import Foundation

struct CompassBackup {
    let metadata: AnnotationArchive
    let books: [Book]
    let audioFiles: [String: Data]
    let pdfFiles: [UUID: Data]
}

enum BackupService {
    private static func readCapped(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 90 * 1024 * 1024 else { throw StoredZIP.Error.tooLarge }
        return try Data(contentsOf: url)
    }

    static func create(
        metadata: AnnotationArchive,
        books: [Book],
        root: URL,
        includePDF: Bool
    ) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var entries: [StoredZIP.Entry] = [
            .init(path: "annotations.json", data: try encoder.encode(metadata)),
            .init(path: "books.json", data: try JSONEncoder().encode(books))
        ]
        for voice in metadata.voiceBookmarks {
            let name = voice.audioFileName
            guard name == "\(voice.id.uuidString).m4a" else { continue }
            let url = root.appendingPathComponent("VoiceNotes", isDirectory: true).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                entries.append(.init(path: "audio/" + name, data: try readCapped(url)))
            }
        }
        if includePDF {
            for book in books {
                let url = root.appendingPathComponent("Books", isDirectory: true).appendingPathComponent(book.fileName)
                if FileManager.default.fileExists(atPath: url.path) {
                    entries.append(.init(path: "books/\(book.id.uuidString).pdf", data: try readCapped(url)))
                }
            }
        }
        let data = try StoredZIP.encode(entries)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("BookCompass-\(UUID().uuidString).zip")
        try data.write(to: output, options: .atomic)
        return output
    }

    static func open(_ file: URL) throws -> CompassBackup {
        #if os(iOS)
        let access = file.startAccessingSecurityScopedResource()
        defer { if access { file.stopAccessingSecurityScopedResource() } }
        #endif
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 243 * 1024 * 1024 else { throw StoredZIP.Error.tooLarge }
        let entries = try StoredZIP.decode(Data(contentsOf: file))
        guard let metadataData = entries["annotations.json"] else { throw CompassError.unreadableArchive }
        let metadataDecoder = JSONDecoder()
        metadataDecoder.dateDecodingStrategy = .iso8601
        let metadata = try metadataDecoder.decode(AnnotationArchive.self, from: metadataData)
        guard metadata.version == 1 else { throw CompassError.unsupportedArchive }
        let books = try entries["books.json"].map { try JSONDecoder().decode([Book].self, from: $0) } ?? []
        var pdfFiles: [UUID: Data] = [:]
        for book in books {
            let name = "books/\(book.id.uuidString).pdf"
            if let pdf = entries[name] { pdfFiles[book.id] = pdf }
        }
        let audio = entries.filter { $0.key.hasPrefix("audio/") }
        return CompassBackup(metadata: metadata, books: books, audioFiles: audio, pdfFiles: pdfFiles)
    }
}
