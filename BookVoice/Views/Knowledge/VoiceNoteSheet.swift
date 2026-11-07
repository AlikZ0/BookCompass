import SwiftUI

struct VoiceNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AnnotationStore
    @EnvironmentObject private var player: BookSpeechPlayer
    @StateObject private var recorder = VoiceNoteRecorder()

    let bookID: UUID
    let pageIndex: Int
    let quote: String
    let annotationID: UUID?
    @State private var comment = ""
    @State private var errorMessage: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 68))
                    .foregroundStyle(recorder.isRecording ? .red : .blue)
                    .padding(.top, 34)
                Text(recorder.isRecording ? "Идёт запись" : "Голосовая заметка")
                    .font(.title2.bold())
                Text(recorder.isRecording ? "\(Int(recorder.seconds)) сек" : "Книга · страница \(pageIndex + 1)")
                    .monospacedDigit().foregroundStyle(.secondary)
                TextField("Комментарий к записи (необязательно)", text: $comment, axis: .vertical)
                    .lineLimit(2...4).textFieldStyle(.roundedBorder)
                Button(action: toggleRecording) {
                    Label(recorder.isRecording ? "Остановить и сохранить" : "Начать запись",
                          systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                        .frame(maxWidth: .infinity).padding(14)
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.isRecording ? .red : .blue)
                .disabled(busy)
                Text("Для записи нужен доступ к микрофону. Файл M4A остаётся на iPhone.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
            }
            .padding(.horizontal, 24)
            .navigationTitle("Голосовая заметка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                Button("Закрыть") { dismiss() }
            } }
            .alert("Не удалось сохранить", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Понятно", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .onDisappear { recorder.discard() }
        }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            saveRecording()
        } else {
            busy = true
            player.pauseForRecording()  // Pause book TTS without resetting its page.
            Task { @MainActor in
                do { try await recorder.start(in: store.audioDirectory) }
                catch { errorMessage = error.localizedDescription }
                busy = false
            }
        }
    }

    private func saveRecording() {
        busy = true
        do {
            let existing = annotationID.flatMap { store.annotation(id: $0) }
            var record = existing ?? BookAnnotation(bookID: bookID, pageIndex: pageIndex,
                                                       quoteText: quote.isEmpty ? nil : quote, comment: "",
                                                       tags: [], isFavorite: false, locator: nil)
            if !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                record.comment = [record.comment, comment].filter { !$0.isEmpty }.joined(separator: "\n")
            }
            // Finish first, then persist annotation and audio metadata.
            let voice = try recorder.finish(annotationID: record.id)
            do {
                try store.save(record)
                try store.appendVoice(voice)
                busy = false
                dismiss()
            } catch {
                // No orphan M4A even when the metadata write fails.
                try? FileManager.default.removeItem(at: store.audioURL(for: voice))
                errorMessage = error.localizedDescription
                busy = false
            }
        } catch {
            errorMessage = error.localizedDescription
            busy = false
        }
    }
}
