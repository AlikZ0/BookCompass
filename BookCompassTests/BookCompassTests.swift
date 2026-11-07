import Foundation
import XCTest
@testable import BookVoice

final class BookCompassTests: XCTestCase {
    func testZipRoundTripAndUnicode() throws {
        let entries = [
            StoredZIP.Entry(path: "annotations.json", data: Data("\"Привет Հայերեն\"".utf8)),
            StoredZIP.Entry(path: "audio/00000000-0000-4000-8000-000000000001.m4a", data: Data([0, 1, 2, 255]))
        ]
        let zip = try StoredZIP.encode(entries)
        let result = try StoredZIP.decode(zip)
        XCTAssertEqual(result["annotations.json"], entries[0].data)
        XCTAssertEqual(result[entries[1].path], entries[1].data)
    }

    func testArchiveRejectsCorruptedPayload() throws {
        let original = try StoredZIP.encode([.init(path: "annotations.json", data: Data("hello".utf8))])
        var tampered = original
        let offset = 30 + "annotations.json".utf8.count
        tampered[offset] ^= 1
        XCTAssertThrowsError(try StoredZIP.decode(tampered))
    }

    func testCannotExportTraversalPaths() {
        XCTAssertThrowsError(try StoredZIP.encode([.init(path: "../../library.json", data: Data())]))
    }

    func testAnnotationModelSerialization() throws {
        let id = UUID()
        let note = BookAnnotation(bookID: id, pageIndex: 4, quoteText: "Կարդալ", comment: "Заметка",
                                  tags: ["учёба"], isFavorite: true,
                                  locator: TextLocator(pageIndex: 4, selectedText: "Կարդալ"))
        let archive = AnnotationArchive(annotations: [note])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(AnnotationArchive.self, from: encoder.encode(archive))
        XCTAssertEqual(restored.annotations.first?.bookID, id)
        XCTAssertEqual(restored.annotations.first?.locator?.selectedText, "Կարդալ")
    }

    @MainActor
    func testStoreKeepsNotesAfterReopening() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let bookID = UUID()
        let first = AnnotationStore(rootOverride: temp)
        try first.save(BookAnnotation(bookID: bookID, pageIndex: 2, quoteText: "Important",
                                      comment: "My thought", tags: ["memory"], isFavorite: false))
        let restored = AnnotationStore(rootOverride: temp)
        XCTAssertEqual(restored.annotations(for: bookID).count, 1)
        XCTAssertEqual(restored.annotations(for: bookID).first?.pageIndex, 2)
    }

    @MainActor
    func testReviewSchedule() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = AnnotationStore(rootOverride: temp)
        let note = BookAnnotation(bookID: UUID(), pageIndex: 0, quoteText: "A", comment: "", tags: [], isFavorite: true)
        try store.save(note)
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        try store.review(note.id, grade: .later, now: day)
        XCTAssertEqual(store.reviews.count, 1)
        XCTAssertTrue(store.reviews[0].nextAt > day)
    }
}
