import SwiftUI
import PDFKit

struct OCRQuotePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let document: PDFDocument
    let bookID: UUID
    let pageIndex: Int
    let onSave: (String) -> Void
    @State private var pageText = ""
    @State private var selectionText = ""
    @State private var loading = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Распознанный текст") {
                    if loading { ProgressView("Распознаём страницу…") }
                    else if pageText.isEmpty { Text("Текст не распознан. Цитату можно написать вручную.").foregroundStyle(.secondary) }
                    else { Text(pageText).textSelection(.enabled) }
                }
                Section("Цитата для сохранения") {
                    TextEditor(text: $selectionText).frame(minHeight: 110)
                    if !pageText.isEmpty {
                        Button("Вставить весь текст страницы") { selectionText = pageText }
                    }
                    Text("Можно скопировать нужные строки из блока выше или ввести текст вручную.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Цитата из скана")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        onSave(selectionText.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(selectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                guard let page = document.page(at: pageIndex) else { loading = false; return }
                pageText = await PDFTextExtractor.text(on: page, bookID: bookID, pageIndex: pageIndex)
                loading = false
            }
        }
    }
}
