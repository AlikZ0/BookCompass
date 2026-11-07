import SwiftUI

struct KnowledgeHubView: View {
    @EnvironmentObject private var store: AnnotationStore
    @EnvironmentObject private var library: BookLibrary

    var body: some View {
        List {
            if let error = store.errorText {
                Section("Ошибка данных") { Text(error).foregroundStyle(.red) }
            }
            Section {
                NavigationLink {
                    AnnotationsListView(bookID: nil)
                } label: {
                    hubRow("Цитаты и заметки", icon: "text.book.closed", count: store.annotations.count)
                }
                NavigationLink {
                    ReviewView()
                } label: {
                    hubRow("Повторение", icon: "checkmark.circle", count: dueCount)
                }
                NavigationLink {
                    TopicsView()
                } label: {
                    hubRow("Карта тем", icon: "circle.hexagongrid", count: store.uniqueTopics().count)
                }
            } header: { Text("Мои знания") }
            Section("Книги") {
                ForEach(library.books) { book in
                    NavigationLink {
                        AnnotationsListView(bookID: book.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(book.title).lineLimit(2)
                                Text("\(store.annotations(for: book.id).count) заметок")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
                if library.books.isEmpty { Text("Добавь PDF в библиотеку").foregroundStyle(.secondary) }
            }
            Section {
                NavigationLink("Резервные копии") { BackupView() }
            }
        }
        .navigationTitle("Знания")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dueCount: Int {
        store.annotations.filter { $0.isFavorite && (store.nextReviewDate(for: $0.id) ?? .distantFuture) <= Date() }.count
    }

    private func hubRow(_ title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.blue).frame(width: 24)
            Text(title)
            Spacer()
            Text("\(count)").foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ReviewView: View {
    @EnvironmentObject private var store: AnnotationStore
    @EnvironmentObject private var library: BookLibrary
    @State private var showAll = false
    @State private var errorText: String?

    private var due: [BookAnnotation] {
        store.annotations.filter { note in
            guard note.isFavorite else { return false }
            return showAll || (store.nextReviewDate(for: note.id) ?? .distantFuture) <= Date()
        }.sorted { (store.nextReviewDate(for: $0.id) ?? .distantPast) < (store.nextReviewDate(for: $1.id) ?? .distantPast) }
    }

    var body: some View {
        List {
            Toggle("Показать все избранные", isOn: $showAll)
            if due.isEmpty {
                Text("Нет фрагментов для повторения. Добавь цитату в избранное.")
                    .foregroundStyle(.secondary)
            }
            ForEach(due) { note in
                VStack(alignment: .leading, spacing: 10) {
                    Text(library.books.first(where: { $0.id == note.bookID })?.title ?? "Книга удалена")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(note.preview).lineLimit(5)
                    HStack {
                        Button("Помню") { mark(note, .remembered) }.buttonStyle(.borderedProminent)
                        Button("Повторить позже") { mark(note, .later) }.buttonStyle(.bordered)
                        Spacer(minLength: 0)
                        NavigationLink("Открыть") { AnnotationDetailView(annotationID: note.id) }
                            .font(.footnote)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Повторение")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Ошибка", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("Закрыть") { errorText = nil }
        } message: { Text(errorText ?? "") }
    }

    private func mark(_ note: BookAnnotation, _ grade: ReviewGrade) {
        do { try store.review(note.id, grade: grade) }
        catch { errorText = error.localizedDescription }
    }
}

struct TopicsView: View {
    @EnvironmentObject private var store: AnnotationStore
    @EnvironmentObject private var library: BookLibrary

    var body: some View {
        List {
            if store.uniqueTopics().isEmpty {
                Text("Темы появятся после добавления тегов к заметкам.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.uniqueTopics(), id: \.self) { tag in
                Section("#\(tag)") {
                    ForEach(store.annotations.filter { $0.tags.contains(tag) }) { note in
                        NavigationLink {
                            AnnotationDetailView(annotationID: note.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.preview).lineLimit(2)
                                Text(library.books.first(where: { $0.id == note.bookID })?.title ?? "Книга удалена")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Карта тем")
        .navigationBarTitleDisplayMode(.inline)
    }
}
