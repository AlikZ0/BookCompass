import SwiftUI

struct AnnotationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AnnotationStore
    let bookID: UUID
    let pageIndex: Int
    let existing: BookAnnotation?
    let selectedText: String

    @State private var quoteText: String
    @State private var comment: String
    @State private var tagsText: String
    @State private var isFavorite: Bool
    @State private var alertText: String?

    init(bookID: UUID, pageIndex: Int, existing: BookAnnotation? = nil, selectedText: String = "") {
        self.bookID = bookID
        self.pageIndex = pageIndex
        self.existing = existing
        self.selectedText = selectedText
        _quoteText = State(initialValue: existing?.quoteText ?? selectedText)
        _comment = State(initialValue: existing?.comment ?? "")
        _tagsText = State(initialValue: existing?.tags.joined(separator: ", ") ?? "")
        _isFavorite = State(initialValue: existing?.isFavorite ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Фрагмент книги") {
                    Text("Страница \((existing?.pageIndex ?? pageIndex) + 1)")
                        .foregroundStyle(.secondary)
                    TextEditor(text: $quoteText)
                        .frame(minHeight: 95)
                        .accessibilityLabel("Текст цитаты")
                    Text("Для сканированного PDF можно вставить распознанный текст вручную.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Моя заметка") {
                    TextEditor(text: $comment)
                        .frame(minHeight: 105)
                    TextField("Теги через запятую", text: $tagsText)
                        .textInputAutocapitalization(.never)
                    Toggle("В избранном", isOn: $isFavorite)
                }
            }
            .navigationTitle(existing == nil ? "Новая заметка" : "Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить", action: save)
                        .fontWeight(.semibold)
                        .disabled(quoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Ошибка", isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
                Button("Закрыть", role: .cancel) { alertText = nil }
            } message: { Text(alertText ?? "") }
        }
    }

    private func save() {
        let cleanedQuote = quoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTags = tagsText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        let uniqueTags = cleanedTags.filter { seen.insert($0.localizedLowercase).inserted }
        let position = existing?.pageIndex ?? pageIndex
        let locator = cleanedQuote.isEmpty ? nil : TextLocator(pageIndex: position, selectedText: cleanedQuote,
                                                                 contextBefore: nil, contextAfter: nil)
        var value = existing ?? BookAnnotation(bookID: bookID, pageIndex: position, quoteText: nil,
                                              comment: "", tags: [], isFavorite: false, locator: nil)
        value.quoteText = cleanedQuote.isEmpty ? nil : cleanedQuote
        value.comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        value.tags = uniqueTags
        value.isFavorite = isFavorite
        value.locator = locator
        do { try store.save(value); dismiss() }
        catch { alertText = error.localizedDescription }
    }
}
