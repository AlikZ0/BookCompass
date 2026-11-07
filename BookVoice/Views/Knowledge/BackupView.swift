import SwiftUI
import UniformTypeIdentifiers

struct BackupView: View {
    @EnvironmentObject private var store: AnnotationStore
    @EnvironmentObject private var library: BookLibrary
    @State private var includePDF = false
    @State private var backupURL: URL?
    @State private var showImporter = false
    @State private var busy = false
    @State private var message: String?
    @State private var showImportConfirmation = false
    @State private var selectedImport: CompassBackup?

    var body: some View {
        Form {
            Section("Экспорт") {
                Toggle("Включить сами PDF-книги", isOn: $includePDF)
                Text("Без переключателя ZIP содержит цитаты, заметки, историю повторений и голосовые файлы. PDF никогда не включаются автоматически.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Создать ZIP", action: export)
                    .disabled(busy)
                if let backupURL {
                    ShareLink(item: backupURL) {
                        Label("Поделиться резервной копией", systemImage: "square.and.arrow.up")
                    }
                }
            }
            Section("Импорт") {
                Button("Выбрать ZIP-файл") { showImporter = true }.disabled(busy)
                Text("Импорт добавляет данные и не удаляет старые книги или заметки. Совпадения UUID обрабатываются отдельно.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if busy { ProgressView("Обработка архива…") }
            if let message {
                Section("Результат") { Text(message).font(.footnote) }
            }
        }
        .navigationTitle("Экспорт и импорт")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let first = urls.first else { return }
                busy = true
                Task {
                    do {
                        let copy = try await Task.detached(priority: .userInitiated) {
                            try BackupService.open(first)
                        }.value
                        selectedImport = copy
                        showImportConfirmation = true
                    } catch { message = error.localizedDescription }
                    busy = false
                }
            case .failure(let error): message = error.localizedDescription
            }
        }
        .confirmationDialog("Импортировать заметки и книги из ZIP?", isPresented: $showImportConfirmation, titleVisibility: .visible) {
            Button("Импортировать") { importSelected() }
            Button("Отмена", role: .cancel) { selectedImport = nil }
        } message: { Text("Старые данные останутся на месте. Новые PDF будут добавлены только если они включены в архив.") }
    }

    private func export() {
        busy = true
        message = nil
        backupURL = nil
        let snapshot = store.exportSnapshot()
        let books = library.books
        let root = store.root
        let include = includePDF
        Task {
            do {
                backupURL = try await Task.detached(priority: .userInitiated) {
                    try BackupService.create(metadata: snapshot, books: books, root: root, includePDF: include)
                }.value
                message = "ZIP готов. Нажми «Поделиться», чтобы сохранить его в «Файлы»."
            } catch { message = error.localizedDescription }
            busy = false
        }
    }

    private func importSelected() {
        guard let incoming = selectedImport else { return }
        selectedImport = nil
        do {
            let mapping = try library.restoreBooks(incoming.books, pdfData: incoming.pdfFiles)
            try store.importArchive(incoming.metadata, audioPayloads: incoming.audioFiles, bookIDMapping: mapping)
            message = "Импорт завершён: заметки объединены, существующие книги сохранены."
        } catch { message = "Импорт прерван: \(error.localizedDescription). Проверь библиотеку перед повтором." }
    }
}
