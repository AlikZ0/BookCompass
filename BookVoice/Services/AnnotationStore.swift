import Foundation
import Combine

@MainActor
final class AnnotationStore: ObservableObject {
    @Published private(set) var archive = AnnotationArchive()
    @Published var errorText: String?
    @Published private(set) var isReadOnly = false

    let root: URL
    let audioDirectory: URL
    private let annotationsFile: URL
    private let fm = FileManager.default

    init(rootOverride: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = rootOverride ?? support.appendingPathComponent("BookVoice", isDirectory: true)
        audioDirectory = root.appendingPathComponent("VoiceNotes", isDirectory: true)
        annotationsFile = root.appendingPathComponent("annotations.json")
        do {
            try fm.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
            if fm.fileExists(atPath: annotationsFile.path) {
                let data = try Data(contentsOf: annotationsFile)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                archive = try decoder.decode(AnnotationArchive.self, from: data)
                guard archive.version == 1 else { throw CompassError.unsupportedArchive }
            }
        } catch {
            isReadOnly = true
            errorText = "Заметки не открылись. Данные не будут перезаписаны: \(error.localizedDescription)"
        }
    }

    var annotations: [BookAnnotation] { archive.annotations }
    var bookmarks: [VoiceBookmark] { archive.voiceBookmarks }
    var reviews: [ReviewEvent] { archive.reviews }

    func annotations(for bookID: UUID) -> [BookAnnotation] {
        archive.annotations.filter { $0.bookID == bookID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func annotation(id: UUID) -> BookAnnotation? {
        archive.annotations.first { $0.id == id }
    }

    func bookmarks(for annotationID: UUID) -> [VoiceBookmark] {
        archive.voiceBookmarks.filter { $0.annotationID == annotationID }
    }

    func save(_ annotation: BookAnnotation) throws {
        try change { snapshot in
            var item = annotation
            item.updatedAt = Date()
            if let index = snapshot.annotations.firstIndex(where: { $0.id == item.id }) {
                item.createdAt = snapshot.annotations[index].createdAt
                snapshot.annotations[index] = item
            } else {
                snapshot.annotations.append(item)
            }
        }
    }

    func deleteAnnotation(id: UUID) throws {
        let files = archive.voiceBookmarks.filter { $0.annotationID == id }.map(\.audioFileName)
        try change { snapshot in
            snapshot.annotations.removeAll { $0.id == id }
            snapshot.voiceBookmarks.removeAll { $0.annotationID == id }
            snapshot.reviews.removeAll { $0.annotationID == id }
        }
        // Delete audio only after metadata is safely saved.
        for file in files { try? fm.removeItem(at: audioDirectory.appendingPathComponent(file)) }
    }

    func deleteAnnotations(for bookID: UUID) throws {
        let ids = Set(archive.annotations.filter { $0.bookID == bookID }.map(\.id))
        let audioFiles = archive.voiceBookmarks.filter { ids.contains($0.annotationID) }.map(\.audioFileName)
        try change { snapshot in
            snapshot.annotations.removeAll { ids.contains($0.id) }
            snapshot.voiceBookmarks.removeAll { ids.contains($0.annotationID) }
            snapshot.reviews.removeAll { ids.contains($0.annotationID) }
        }
        for file in audioFiles { try? fm.removeItem(at: audioDirectory.appendingPathComponent(file)) }
    }

    func appendVoice(_ note: VoiceBookmark) throws {
        guard annotation(id: note.annotationID) != nil else { throw CompassError.missingAnnotation }
        guard note.audioFileName == "\(note.id.uuidString).m4a" else { throw CompassError.invalidAudio }
        guard fm.fileExists(atPath: audioURL(for: note).path) else { throw CompassError.invalidAudio }
        try change { $0.voiceBookmarks.append(note) }
    }

    func deleteVoice(_ note: VoiceBookmark) throws {
        try change { $0.voiceBookmarks.removeAll { $0.id == note.id } }
        try? fm.removeItem(at: audioURL(for: note))
    }

    func audioURL(for note: VoiceBookmark) -> URL {
        audioDirectory.appendingPathComponent(note.audioFileName)
    }

    func nextReviewDate(for annotationID: UUID) -> Date? {
        guard let last = archive.reviews.filter({ $0.annotationID == annotationID }).max(by: { $0.reviewedAt < $1.reviewedAt }) else {
            return annotation(id: annotationID)?.createdAt
        }
        return last.nextAt
    }

    func review(_ annotationID: UUID, grade: ReviewGrade, now: Date = Date()) throws {
        guard annotation(id: annotationID) != nil else { throw CompassError.missingAnnotation }
        let rememberedStreak = archive.reviews.filter { $0.annotationID == annotationID }
            .sorted { $0.reviewedAt < $1.reviewedAt }
            .reversed().prefix { $0.grade == .remembered }.count
        let days = grade == .later ? 1 : min(30, [1, 3, 7, 14, 30][min(rememberedStreak, 4)])
        let event = ReviewEvent(annotationID: annotationID, reviewedAt: now, grade: grade,
                                nextAt: Calendar.current.date(byAdding: .day, value: days, to: now) ?? now)
        try change { $0.reviews.append(event) }
    }

    func uniqueTopics() -> [String] {
        Array(Set(archive.annotations.flatMap(\.tags))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Persistent, atomic replace; publish state only once the write succeeds.
    private func change(_ operation: (inout AnnotationArchive) throws -> Void) throws {
        var updated = archive
        try operation(&updated)
        try persist(updated)
        archive = updated
    }

    private func persist(_ snapshot: AnnotationArchive) throws {
        guard !isReadOnly else { throw CompassError.unreadableArchive }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: annotationsFile, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    func exportSnapshot() -> AnnotationArchive { archive }

    /// Merge without overwriting existing annotations/audio or assuming old PDFs are present.
    /// Audio bytes are written under a new UUID when the incoming identifier conflicts.
    func importArchive(
        _ incoming: AnnotationArchive,
        audioPayloads: [String: Data],
        bookIDMapping: [UUID: UUID] = [:]
    ) throws {
        guard incoming.version == 1 else { throw CompassError.unsupportedArchive }
        var updated = archive
        var idMapping: [UUID: UUID] = [:]
        var createdAudio: [URL] = []

        do {
            for original in incoming.annotations {
                var mapped = original
                mapped.bookID = bookIDMapping[original.bookID] ?? original.bookID
                // Logical deduplication also handles backups previously imported under a remapped UUID.
                if let equivalent = updated.annotations.first(where: {
                    $0.bookID == mapped.bookID && $0.pageIndex == mapped.pageIndex &&
                    $0.quoteText == mapped.quoteText && $0.comment == mapped.comment &&
                    $0.createdAt.timeIntervalSince1970.rounded() == mapped.createdAt.timeIntervalSince1970.rounded()
                }) {
                    idMapping[original.id] = equivalent.id
                    continue
                }
                if let existing = updated.annotations.first(where: { $0.id == mapped.id }) {
                    if existing == mapped {
                        idMapping[original.id] = existing.id
                        continue
                    }
                    mapped.id = UUID()
                }
                idMapping[original.id] = mapped.id
                updated.annotations.append(mapped)
            }
            for original in incoming.voiceBookmarks {
                guard let targetAnnotation = idMapping[original.annotationID] else { continue }
                let sourcePath = "audio/" + original.audioFileName
                guard let audio = audioPayloads[sourcePath], !audio.isEmpty else { continue }
                var mapped = original
                mapped.annotationID = targetAnnotation
                if updated.voiceBookmarks.contains(where: {
                    $0.annotationID == mapped.annotationID &&
                    $0.createdAt.timeIntervalSince1970.rounded() == mapped.createdAt.timeIntervalSince1970.rounded() &&
                    $0.duration == mapped.duration &&
                    (try? Data(contentsOf: audioURL(for: $0))) == audio
                }) { continue }
                if let existing = updated.voiceBookmarks.first(where: { $0.id == mapped.id }),
                   existing.annotationID == mapped.annotationID,
                   existing.duration == mapped.duration,
                   fm.fileExists(atPath: audioURL(for: existing).path) {
                    continue
                }
                if updated.voiceBookmarks.contains(where: { $0.id == mapped.id }) ||
                   fm.fileExists(atPath: audioDirectory.appendingPathComponent(mapped.audioFileName).path) {
                    mapped.id = UUID()
                }
                mapped.audioFileName = "\(mapped.id.uuidString).m4a"
                let path = audioURL(for: mapped)
                try audio.write(to: path, options: .atomic)
                createdAudio.append(path)
                updated.voiceBookmarks.append(mapped)
            }
            for original in incoming.reviews {
                guard let targetAnnotation = idMapping[original.annotationID] else { continue }
                var mapped = original
                mapped.annotationID = targetAnnotation
                if updated.reviews.contains(where: {
                    $0.annotationID == mapped.annotationID &&
                    $0.grade == mapped.grade &&
                    $0.reviewedAt.timeIntervalSince1970.rounded() == mapped.reviewedAt.timeIntervalSince1970.rounded()
                }) { continue }
                if let existing = updated.reviews.first(where: { $0.id == mapped.id }) {
                    if existing == mapped { continue }
                    mapped.id = UUID()
                }
                updated.reviews.append(mapped)
            }
            try persist(updated)
            archive = updated
        } catch {
            for file in createdAudio { try? fm.removeItem(at: file) }
            throw error
        }
    }

    /// Export/import uses ISO 8601 dates; old BookVoice files remain untouched.
    func encodeArchive(_ value: AnnotationArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    func decodeArchive(_ data: Data) throws -> AnnotationArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AnnotationArchive.self, from: data)
    }
}
