import SwiftUI
import PDFKit
import UniformTypeIdentifiers

private enum BookVoiceStyle {
    static let blue = Color(red: 0.08, green: 0.42, blue: 0.94)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}

struct LibraryView: View {
    @EnvironmentObject private var library: BookLibrary
    @EnvironmentObject private var player: BookSpeechPlayer
    @EnvironmentObject private var annotations: AnnotationStore
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var pendingDeletion: Book?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    titleSection
                    importCard
                    knowledgeLink
                    booksSection
                    privacyLine
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(BookVoiceStyle.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Book.self) { book in
                ReaderView(bookID: book.id)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(player)
                    .presentationDragIndicator(.visible)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
                do {
                    let urls = try result.get()
                    guard let url = urls.first else { return }
                    try library.importPDF(from: url)
                } catch {
                    library.errorText = error.localizedDescription
                }
            }
            .confirmationDialog("Удалить PDF-книгу?", isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ), titleVisibility: .visible) {
                Button("Удалить PDF и все заметки", role: .destructive) { deletePending(deleteNotes: true) }
                Button("Удалить только PDF", role: .destructive) { deletePending(deleteNotes: false) }
                Button("Отмена", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("Можно сохранить заметки отдельно или удалить их вместе с PDF. Остальные книги не затрагиваются.")
            }
            .alert("Ошибка", isPresented: Binding(
                get: { library.errorText != nil },
                set: { if !$0 { library.errorText = nil } }
            )) {
                Button("Понятно", role: .cancel) { library.errorText = nil }
            } message: {
                Text(library.errorText ?? "")
            }
        }
    }

    private var titleSection: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(LinearGradient(colors: [.blue, BookVoiceStyle.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "waveform")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)
            .shadow(color: .blue.opacity(0.19), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 4) {
                Text("BookCompass")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .tracking(-1.0)
                Text("Читай, слушай и сохраняй мысли.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 42, height: 42)
                    .background(BookVoiceStyle.surface, in: Circle())
            }
            .accessibilityLabel("Настройки голоса")
        }
        .foregroundStyle(.primary)
    }

    private var importCard: some View {
        Button { showImporter = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.19))
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Добавить PDF-книгу")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Из приложения «Файлы» · без интернета")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.83))
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [BookVoiceStyle.blue, Color(red: 0.29, green: 0.32, blue: 0.82)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 23, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Открыть выбор PDF из Файлов")
    }

    private var knowledgeLink: some View {
        NavigationLink {
            KnowledgeHubView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.title2).foregroundStyle(.blue).frame(width: 35)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Мои знания").font(.headline)
                    Text("\(annotations.annotations.count) заметок · повторение · карта тем")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(BookVoiceStyle.surface, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func deletePending(deleteNotes: Bool) {
        guard let book = pendingDeletion else { return }
        pendingDeletion = nil
        if player.isCurrentBook(book.id) { player.close() }
        guard library.delete(book) else { return }
        if deleteNotes {
            do { try annotations.deleteAnnotations(for: book.id) }
            catch { library.errorText = "PDF удалён, но заметки остались: \(error.localizedDescription)" }
        }
    }

    private var booksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Моя библиотека")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                Spacer()
                Text("\(library.books.count) книг")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if library.books.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 35, weight: .ultraLight))
                        .foregroundStyle(BookVoiceStyle.blue)
                        .frame(height: 48)
                    Text("Здесь появятся твои книги")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Импортируй PDF, нажми «Слушать» и продолжай с того же места в следующий раз.")
                        .multilineTextAlignment(.center)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(22)
                .frame(maxWidth: .infinity)
                .background(BookVoiceStyle.surface, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            } else {
                LazyVStack(spacing: 11) {
                    ForEach(library.books) { book in
                        NavigationLink(value: book) {
                            BookRow(book: book, fileURL: library.url(for: book),
                                    annotationCount: annotations.annotations(for: book.id).count)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDeletion = book
                            } label: {
                                Label("Удалить книгу", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var privacyLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
            Text("Книги остаются на этом iPhone. Интернет не нужен.")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}

private struct BookRow: View {
    let book: Book
    let fileURL: URL
    let annotationCount: Int

    var body: some View {
        HStack(spacing: 14) {
            PDFCover(fileURL: fileURL)
                .frame(width: 72, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text(book.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text("PDF · \(book.pageCount) стр.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                ProgressView(value: book.progress)
                    .tint(BookVoiceStyle.blue)
                if annotationCount > 0 {
                    Label("\(annotationCount) заметок", systemImage: "bookmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(book.lastPage == 0 ? "Начать чтение" : "Продолжить · стр. \(book.lastPage + 1)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BookVoiceStyle.blue)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(BookVoiceStyle.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct PDFCover: View {
    let fileURL: URL
    @State private var coverImage: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [.gray.opacity(0.22), .gray.opacity(0.12)], startPoint: .top, endPoint: .bottom)
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 27, weight: .ultraLight))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if coverImage == nil, let doc = PDFDocument(url: fileURL), let page = doc.page(at: 0) {
                coverImage = page.thumbnail(of: CGSize(width: 190, height: 260), for: .mediaBox)
            }
        }
    }
}
