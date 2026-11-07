import Foundation

enum OCRTextCache {
    private static func folder(for bookID: UUID) -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("BookVoiceOCR", isDirectory: true)
            .appendingPathComponent(bookID.uuidString, isDirectory: true)
    }

    static func read(bookID: UUID, page: Int) -> String? {
        let path = folder(for: bookID).appendingPathComponent("\(page).txt")
        return try? String(contentsOf: path, encoding: .utf8)
    }

    static func write(_ text: String, bookID: UUID, page: Int) {
        let directory = folder(for: bookID)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? text.write(to: directory.appendingPathComponent("\(page).txt"), atomically: true, encoding: .utf8)
    }

    static func delete(bookID: UUID) {
        try? FileManager.default.removeItem(at: folder(for: bookID))
    }
}
