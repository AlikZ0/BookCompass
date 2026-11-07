import Foundation

struct Book: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    let fileName: String
    let addedAt: Date
    let pageCount: Int
    var lastPage: Int

    var progress: Double {
        guard pageCount > 0 else { return 0 }
        return min(Double(lastPage) / Double(pageCount), 1)
    }
}
