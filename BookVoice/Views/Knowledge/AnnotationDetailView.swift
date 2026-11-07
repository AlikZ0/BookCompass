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
    @State private var pendingDeleteVoice: VoiceBookmark?
    @State private var errorText: String?

    private var note: BookAnnotation? { store.annotation(id: annotationID) }
    private var book: Book? { note.flatMap { item in library.books.first { $0.id == item.bookID } } }

    var body: some View {
        Group {
            if let note {
                content(note)
            } else {
                ContentUnavailableView("Заметка удалена", systemImage: "note.text.badge.minus")
            }
        }
        .navigationTitle("Заметка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Изменить") { showEditor = true }
                    .disabled(note == nil)
            }
        }
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
                do {
                    try store.deleteAnnotation(id: annotationID)
                    dismiss()
                } catch {
                    errorText = error.localizedDescription
                }
            }
        }
        .confirmationDialog("Удалить голосовую заметку?", isPresented: Binding(
            get: { pendingDeleteVoice != nil },
            set: { if !$0 { pendingDeleteVoice = nil } }
        ), titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                guard let voice = pendingDeleteVoice else { return }
                voicePlayback.stop()
                do {
                    try store.deleteVoice(voice)
                    pendingDeleteVoice = nil
                } catch {
                    errorText = error.localizedDescription
                }
            }
            Button("Отмена", role: .cancel) {
                pendingDeleteVoice = nil
            }
        }
        .alert("Ошибка", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("Закрыть") { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
        .onDisappear {
            voicePlayback.stop()
            quotePlayback.stop()
        }
    }

    private func content(_ note: BookAnnotation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                bookCard(note)
                if let quote = note.quoteText, !quote.isEmpty {
                    quoteCard(quote)
                }
                noteCard(note)
                voiceCard(note)
                reviewCard(note)
                deleteCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func bookCard(_ note: BookAnnotation) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "book.closed")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book?.title ?? "Книга удалена")
                            .font(.headline)
                            .lineLimit(3)
                        Text("Стр. \(note.pageIndex + 1)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if let book {
                    NavigationLink {
                        ReaderView(bookID: book.id, initialPage: note.pageIndex, initialHighlight: note.quoteText)
                    } label: {
                        actionPill(title: "Перейти к странице", systemImage: "arrow.up.right.square", tint: .blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func quoteCard(_ quote: String) -> some View {
        card(header: "Цитата") {
            VStack(alignment: .leading, spacing: 14) {
                Text(quote)
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                Button {
                    player.stop()
                    voicePlayback.stop()
                    quotePlayback.toggle(text: quote, preferredVoiceID: player.chosenVoiceID, rate: player.rate)
                } label: {
                    actionPill(
                        title: quotePlayback.speaking ? "Остановить цитату" : "Прослушать цитату",
                        systemImage: quotePlayback.speaking ? "stop.fill" : "speaker.wave.2.fill",
                        tint: quotePlayback.speaking ? .red : .blue
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func noteCard(_ note: BookAnnotation) -> some View {
        card(header: "Моя заметка") {
            VStack(alignment: .leading, spacing: 12) {
                Text(note.comment.isEmpty ? "Комментарий ещё не добавлен" : note.comment)
                    .font(.body)
                    .foregroundStyle(note.comment.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !note.tags.isEmpty {
                    tagWrap(tags: note.tags)
                }
                HStack {
                    Label("\(note.isFavorite ? "Избранное" : "Заметка")", systemImage: note.isFavorite ? "star.fill" : "note.text")
                        .foregroundStyle(note.isFavorite ? .yellow : .secondary)
                    Spacer()
                    Text(note.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func voiceCard(_ note: BookAnnotation) -> some View {
        card(header: "Голос") {
            VStack(alignment: .leading, spacing: 12) {
                let voices = store.bookmarks(for: note.id)
                if voices.isEmpty {
                    Text("Голосовая заметка ещё не добавлена")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(voices) { voice in
                        voiceRow(voice)
                    }
                }
                Button {
                    voicePlayback.stop()
                    quotePlayback.stop()
                    showRecording = true
                } label: {
                    actionPill(title: voices.isEmpty ? "Добавить голосовую заметку" : "Записать ещё", systemImage: "mic.fill", tint: .blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func voiceRow(_ voice: VoiceBookmark) -> some View {
        let isPlaying = voicePlayback.playingID == voice.id
        return HStack(spacing: 12) {
            Button {
                player.stop()
                quotePlayback.stop()
                do {
                    try voicePlayback.toggle(voice, fileURL: store.audioURL(for: voice))
                } catch {
                    errorText = error.localizedDescription
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill((isPlaying ? Color.red : Color.blue).opacity(0.12))
                            .frame(width: 42, height: 42)
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isPlaying ? .red : .blue)
                            .offset(x: isPlaying ? 0 : 1)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isPlaying ? "Остановить" : "Слушать")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(Int(max(1, round(voice.duration)))) сек")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Menu {
                Button(role: .destructive) {
                    pendingDeleteVoice = voice
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
            }
        }
    }

    private func reviewCard(_ note: BookAnnotation) -> some View {
        let history = store.reviews.filter { $0.annotationID == note.id }
            .sorted { $0.reviewedAt > $1.reviewedAt }
        return card(header: "Повторение") {
            VStack(alignment: .leading, spacing: 14) {
                if let next = store.nextReviewDate(for: note.id) {
                    HStack {
                        Text("Следующее повторение")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(next.formatted(date: .abbreviated, time: .omitted))
                            .fontWeight(.medium)
                    }
                }
                HStack(spacing: 12) {
                    Button("Помню") { review(note, grade: .remembered) }
                        .buttonStyle(.borderedProminent)
                    Button("Позже") { review(note, grade: .later) }
                        .buttonStyle(.bordered)
                }
                Text("Всего повторений: \(history.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !history.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(Array(history.prefix(5))) { event in
                            HStack {
                                Text(event.grade.title)
                                Spacer()
                                Text(event.reviewedAt.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private var deleteCard: some View {
        card {
            Button("Удалить заметку", role: .destructive) {
                showDelete = true
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .font(.headline)
            .padding(.vertical, 2)
        }
    }

    private func tagWrap(tags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    private func card<Content: View>(header: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let header {
                Text(header.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
                    .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func actionPill(title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private func review(_ note: BookAnnotation, grade: ReviewGrade) {
        do {
            try store.review(note.id, grade: grade)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
