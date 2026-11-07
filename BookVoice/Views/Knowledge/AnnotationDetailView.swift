import SwiftUI

struct AnnotationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AnnotationStore
    @EnvironmentObject private var library: BookLibrary
    @EnvironmentObject private var player: BookSpeechPlayer
    @StateObject private var voicePlayback = VoiceNotePlayback()
    @StateObject private var quotePlayback = QuotePlayback()
    let annotationID: UUID
    @State private var showEditor = false
    @State private var showRecording = false
    @State private var showDelete = false
    @State private var errorText: String?

    private var note: BookAnnotation? { store.annotation(id: annotationID) }
    private var book: Book? { note.flatMap { item in library.books.first { $0.id == item.bookID } } }

    var body: some View {
        Group {
            if let note { content(note) }
            else { Text("Заметка удалена").foregroundStyle(.secondary) }
        }
        .navigationTitle("Заметка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
            Button("Изменить") { showEditor = true }.disabled(note == nil)
        } }
        .sheet(isPresented: $showEditor) {
            if let note {
                AnnotationEditorView(bookID: note.bookID, pageIndex: note.pageIndex, existing: note)
            }
        }
        .sheet(isPresented: $showRecording) {
            if let note {
                VoiceNoteSheet(bookID: note.bookID, pageIndex: note.pageIndex,
                               quote: note.quoteText ?? "", annotationID: note.id)
            }
        }
        .confirmationDialog("Удалить заметку и голосовые записи?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                do { try store.deleteAnnotation(id: annotationID); dismiss() }
                catch { errorText = error.localizedDescription }
            }
        }
        .alert("Ошибка", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("Закрыть") { errorText = nil }
        } message: { Text(errorText ?? "") }
        .onDisappear { voicePlayback.stop(); quotePlayback.stop() }
    }

    private func content(_ note: BookAnnotation) -> some View {
        List {
            bookSection(note)
            quoteSection(note)
            commentSection(note)
            voiceSection(note)
            reviewSection(note)
            Section { Button("Удалить заметку", role: .destructive) { showDelete = true } }
        }
    }

    private func bookSection(_ note: BookAnnotation) -> some View {
        Section {
            HStack {
                Label(book?.title ?? "Книга удалена", systemImage: "book.closed")
                Spacer()
                Text("стр. \(note.pageIndex + 1)").foregroundStyle(.secondary)
            }
            if let book {
                NavigationLink {
                    ReaderView(bookID: book.id, initialPage: note.pageIndex, initialHighlight: note.quoteText)
                } label: {
                    Label("Перейти к странице", systemImage: "arrow.up.right.square")
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    @ViewBuilder
    private func quoteSection(_ note: BookAnnotation) -> some View {
        if let quote = note.quoteText, !quote.isEmpty {
            Section("Цитата") {
                Text(quote).textSelection(.enabled)
                Button {
                    player.stop()
                    voicePlayback.stop()
                    quotePlayback.toggle(text: quote, preferredVoiceID: player.chosenVoiceID, rate: player.rate)
                } label: {
                    Label(quotePlayback.speaking ? "Остановить" : "Прослушать цитату",
                          systemImage: quotePlayback.speaking ? "stop.fill" : "speaker.wave.2")
                }
            }
        }
    }

    private func commentSection(_ note: BookAnnotation) -> some View {
        Section("Моя заметка") {
            Text(note.comment.isEmpty ? "Комментарий ещё не добавлен" : note.comment)
                .foregroundStyle(note.comment.isEmpty ? Color.secondary : Color.primary)
            if !note.tags.isEmpty {
                Text(note.tags.map { "#" + $0 }.joined(separator: "  "))
                    .foregroundStyle(.blue)
            }
            Text(note.createdAt, style: .date)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func voiceSection(_ note: BookAnnotation) -> some View {
        Section("Голос") {
            ForEach(store.bookmarks(for: note.id)) { voice in
                voiceRow(voice)
            }
            Button { voicePlayback.stop(); quotePlayback.stop(); showRecording = true } label: {
                Label("Добавить голосовую заметку", systemImage: "mic")
            }
        }
    }

    private func voiceRow(_ voice: VoiceBookmark) -> some View {
        HStack {
            Button {
                player.stop()
                quotePlayback.stop()
                do { try voicePlayback.toggle(voice, fileURL: store.audioURL(for: voice)) }
                catch { errorText = error.localizedDescription }
            } label: {
                Label(voicePlayback.playingID == voice.id ? "Стоп" : "Слушать · \(Int(voice.duration)) с",
                      systemImage: voicePlayback.playingID == voice.id ? "stop.fill" : "play.circle")
            }
            Spacer()
            Button(role: .destructive) {
                voicePlayback.stop()
                do { try store.deleteVoice(voice) }
                catch { errorText = error.localizedDescription }
            } label: { Image(systemName: "trash") }
        }
    }

    private func reviewSection(_ note: BookAnnotation) -> some View {
        Section("Повторение") {
            if let next = store.nextReviewDate(for: note.id) {
                LabeledContent("Следующее повторение", value: next.formatted(date: .abbreviated, time: .omitted))
            }
            HStack {
                Button("Помню") { review(note, grade: .remembered) }.buttonStyle(.borderedProminent)
                Spacer()
                Button("Позже") { review(note, grade: .later) }.buttonStyle(.bordered)
            }
            Text("Всего повторений: \(store.reviews.filter { $0.annotationID == note.id }.count)")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(store.reviews.filter { $0.annotationID == note.id }
                .sorted { $0.reviewedAt > $1.reviewedAt }.prefix(5))) { event in
                HStack {
                    Text(event.grade.title)
                    Spacer()
                    Text(event.reviewedAt, style: .date).foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    private func review(_ note: BookAnnotation, grade: ReviewGrade) {
        do { try store.review(note.id, grade: grade) }
        catch { errorText = error.localizedDescription }
    }
}
