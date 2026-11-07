import SwiftUI

struct AnnotationsListView: View {
    @EnvironmentObject private var library: BookLibrary
    @EnvironmentObject private var store: AnnotationStore
    let bookID: UUID?
    @State private var query = ""
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Все", text = "Текст", voice = "Голос", favorites = "Избранное"
        var id: Self { self }
    }

    private var filtered: [BookAnnotation] {
        let base = store.annotations.filter { bookID == nil || $0.bookID == bookID }
        return base.filter { annotation in
            switch filter {
            case .all: break
            case .text: if annotation.quoteText?.isEmpty != false { return false }
            case .voice: if store.bookmarks(for: annotation.id).isEmpty { return false }
            case .favorites: if !annotation.isFavorite { return false }
            }
            guard !query.isEmpty else { return true }
            let haystack = ([annotation.quoteText ?? "", annotation.comment] + annotation.tags).joined(separator: " ")
            return haystack.localizedStandardContains(query)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                ContentUnavailableAnnotationView(query: query)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(filtered) { note in
                    NavigationLink {
                        AnnotationDetailView(annotationID: note.id)
                    } label: {
                        AnnotationRow(note: note, title: library.books.first(where: { $0.id == note.bookID })?.title)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Поиск по цитатам, заметкам, тегам")
        .safeAreaInset(edge: .top) {
            Picker("Тип заметок", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.regularMaterial)
        }
        .navigationTitle(bookID == nil ? "Все заметки" : "Заметки книги")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AnnotationRow: View {
    let note: BookAnnotation
    let title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title ?? "Книга удалена")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("стр. \(note.pageIndex + 1)")
                    .font(.caption).foregroundStyle(.secondary)
                if note.isFavorite { Image(systemName: "star.fill").foregroundStyle(.orange) }
            }
            Text(note.preview).font(.body).lineLimit(3)
            if !note.tags.isEmpty {
                Text(note.tags.map { "#" + $0 }.joined(separator: "  "))
                    .font(.caption).foregroundStyle(.blue).lineLimit(2)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct ContentUnavailableAnnotationView: View {
    let query: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.book.closed")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(query.isEmpty ? "Пока нет заметок" : "Ничего не найдено")
                .font(.headline)
            Text("Сохрани цитату во время чтения PDF, чтобы вернуться к ней позже.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
