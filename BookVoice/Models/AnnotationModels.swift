import Foundation

struct TextLocator: Codable, Hashable {
    var pageIndex: Int
    var selectedText: String
    var contextBefore: String?
    var contextAfter: String?
}

struct BookAnnotation: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var bookID: UUID
    var pageIndex: Int
    var quoteText: String?
    var comment: String
    var tags: [String]
    var isFavorite: Bool
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var locator: TextLocator?

    var preview: String {
        let text = (quoteText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? (comment.isEmpty ? "Закладка" : comment) : text
    }
}

struct VoiceBookmark: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var annotationID: UUID
    var audioFileName: String
    var duration: TimeInterval
    var createdAt: Date = Date()
}

enum ReviewGrade: String, Codable, CaseIterable {
    case remembered
    case later
    var title: String { self == .remembered ? "Помню" : "Повторить позже" }
}

struct ReviewEvent: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var annotationID: UUID
    var reviewedAt: Date = Date()
    var grade: ReviewGrade
    var nextAt: Date
}

/// Separate from BookVoice/library.json to preserve books on upgrade.
struct AnnotationArchive: Codable {
    var version: Int = 1
    var annotations: [BookAnnotation] = []
    var voiceBookmarks: [VoiceBookmark] = []
    var reviews: [ReviewEvent] = []
}

enum CompassError: LocalizedError {
    case missingAnnotation
    case unreadableArchive
    case unsupportedArchive
    case invalidAudio
    case microphoneDenied
    case invalidPage

    var errorDescription: String? {
        switch self {
        case .missingAnnotation: return "Заметка больше не найдена."
        case .unreadableArchive: return "Не удалось прочитать резервную копию."
        case .unsupportedArchive: return "Неподдерживаемый формат архива."
        case .invalidAudio: return "Не удалось открыть голосовую запись."
        case .microphoneDenied: return "Доступ к микрофону выключен. Разреши его в настройках iPhone."
        case .invalidPage: return "Номер страницы вне диапазона книги."
        }
    }
}
