import Foundation
import PDFKit
import Combine

@MainActor
final class BookLibrary: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published var errorText: String?

    private let fileManager = FileManager.default
    private let root: URL
    private let libraryFile: URL
    private let booksFolder: URL

    init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("BookVoice", isDirectory: true)
        libraryFile = root.appendingPathComponent("library.json")
        booksFolder = root.appendingPathComponent("Books", isDirectory: true)

        do {
            try fileManager.createDirectory(at: booksFolder, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: libraryFile.path) {
                books = try JSONDecoder().decode([Book].self, from: Data(contentsOf: libraryFile))
            }
        } catch {
            errorText = "Не удалось открыть библиотеку: \(error.localizedDescription)"
        }
    }

    func url(for book: Book) -> URL {
        booksFolder.appendingPathComponent(book.fileName)
    }

    func importPDF(from externalURL: URL) throws {
        #if os(iOS)
        let canAccess = externalURL.startAccessingSecurityScopedResource()
        defer { if canAccess { externalURL.stopAccessingSecurityScopedResource() } }
        #endif

        guard let input = PDFDocument(url: externalURL), input.pageCount > 0 else {
            throw BookError.invalidPDF
        }
        guard !input.isLocked else { throw BookError.lockedPDF }

        let newID = UUID()
        let fileName = "\(newID.uuidString).pdf"
        let destination = booksFolder.appendingPathComponent(fileName)
        try fileManager.copyItem(at: externalURL, to: destination)
        do {
            let title = externalURL.deletingPathExtension().lastPathComponent
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let book = Book(id: newID, title: name.isEmpty ? "Книга без названия" : name,
                            fileName: fileName, addedAt: Date(), pageCount: input.pageCount, lastPage: 0)
            books.insert(book, at: 0)
            try save()
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    func updatePosition(bookID: UUID, page: Int) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        let clamped = min(max(0, page), max(0, books[index].pageCount - 1))
        guard books[index].lastPage != clamped else { return }
        books[index].lastPage = clamped
        do { try save() }
        catch { errorText = "Не удалось сохранить позицию: \(error.localizedDescription)" }
    }

    @discardableResult
    func delete(_ book: Book) -> Bool {
        let original = books
        books.removeAll { $0.id == book.id }
        do {
            try save()
            try? fileManager.removeItem(at: url(for: book))
            OCRTextCache.delete(bookID: book.id)
            return true
        } catch {
            books = original
            errorText = "Не удалось удалить книгу: \(error.localizedDescription)"
            return false
        }
    }

    /// Restore only explicitly selected PDFs from a backup. Preserve the existing
    /// library index, all old filenames, IDs and positions. Map conflicting UUIDs.
    func restoreBooks(_ incoming: [Book], pdfData: [UUID: Data]) throws -> [UUID: UUID] {
        let previous = books
        var newPaths: [URL] = []
        var mapping: [UUID: UUID] = [:]
        do {
            for original in incoming {
                guard let bytes = pdfData[original.id] else { continue }
                guard let pdf = PDFDocument(data: bytes), pdf.pageCount > 0, !pdf.isLocked else {
                    throw BookError.invalidPDF
                }
                if let existing = books.first(where: { $0.id == original.id }),
                   let currentBytes = try? Data(contentsOf: url(for: existing)), currentBytes == bytes {
                    mapping[original.id] = existing.id
                    continue
                }
                let id = books.contains(where: { $0.id == original.id }) ? UUID() : original.id
                let fileName = "\(id.uuidString).pdf"
                let target = booksFolder.appendingPathComponent(fileName)
                guard !fileManager.fileExists(atPath: target.path) else { throw BookError.invalidPDF }
                try bytes.write(to: target, options: [.atomic, .completeFileProtectionUnlessOpen])
                newPaths.append(target)
                let restored = Book(id: id, title: original.title, fileName: fileName,
                                    addedAt: original.addedAt, pageCount: pdf.pageCount,
                                    lastPage: min(max(0, original.lastPage), pdf.pageCount - 1))
                books.append(restored)
                mapping[original.id] = id
            }
            try save()
            return mapping
        } catch {
            books = previous
            for path in newPaths { try? fileManager.removeItem(at: path) }
            throw error
        }
    }

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(books)
        try data.write(to: libraryFile, options: .atomic)
    }
}

enum BookError: LocalizedError {
    case invalidPDF
    case lockedPDF

    var errorDescription: String? {
        switch self {
        case .invalidPDF: return "Не удалось открыть PDF. Проверь файл."
        case .lockedPDF: return "PDF защищён паролем. Сначала сними защиту в другом приложении."
        }
    }
}
