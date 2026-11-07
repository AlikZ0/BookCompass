import Foundation

/// Minimal standards-compliant ZIP (method 0, uncompressed) for backups made by BookCompass.
/// Deliberately rejects unsupported compression, ZIP64 and unsafe names on import.
/// This avoids a network/package dependency in the offline iOS project.
enum StoredZIP {
    struct Entry {
        var path: String
        var data: Data
    }

    enum Error: LocalizedError {
        case tooLarge, corrupt, unsupported, invalidPath
        var errorDescription: String? {
            switch self {
            case .tooLarge: return "Архив слишком большой. Экспортируй книги по отдельности."
            case .corrupt: return "Повреждённый ZIP-архив или неверная контрольная сумма."
            case .unsupported: return "Поддерживаются ZIP-копии BookCompass без сжатия."
            case .invalidPath: return "Небезопасное имя файла в ZIP-архиве."
            }
        }
    }

    private static let perFileLimit = 90 * 1024 * 1024
    private static let totalLimit = 240 * 1024 * 1024

    static func encode(_ entries: [Entry]) throws -> Data {
        var archive = Data()
        var central = Data()
        var known = Set<String>()
        var rawTotal = 0

        for entry in entries {
            guard validPath(entry.path), known.insert(entry.path).inserted else { throw Error.invalidPath }
            guard entry.data.count <= perFileLimit else { throw Error.tooLarge }
            rawTotal += entry.data.count
            guard rawTotal <= totalLimit, archive.count < Int(UInt32.max) else { throw Error.tooLarge }
            guard let pathData = entry.path.data(using: .utf8), pathData.count < 65_535 else { throw Error.invalidPath }
            let offset = UInt32(archive.count)
            let size = UInt32(entry.data.count)
            let checksum = crc32(entry.data)
            // local file header
            archive.put32(0x04034b50)
            archive.put16(20)
            archive.put16(0x0800)
            archive.put16(0)
            archive.put16(0)
            archive.put16(0)
            archive.put32(checksum)
            archive.put32(size)
            archive.put32(size)
            archive.put16(UInt16(pathData.count))
            archive.put16(0)
            archive.append(pathData)
            archive.append(entry.data)
            // central directory entry
            central.put32(0x02014b50)
            central.put16(20)
            central.put16(20)
            central.put16(0x0800)
            central.put16(0)
            central.put16(0)
            central.put16(0)
            central.put32(checksum)
            central.put32(size)
            central.put32(size)
            central.put16(UInt16(pathData.count))
            central.put16(0)
            central.put16(0)
            central.put16(0)
            central.put16(0)
            central.put32(0)
            central.put32(offset)
            central.append(pathData)
        }
        guard entries.count <= Int(UInt16.max), central.count <= Int(UInt32.max) else { throw Error.tooLarge }
        let centralOffset = UInt32(archive.count)
        archive.append(central)
        archive.put32(0x06054b50)
        archive.put16(0)
        archive.put16(0)
        archive.put16(UInt16(entries.count))
        archive.put16(UInt16(entries.count))
        archive.put32(UInt32(central.count))
        archive.put32(centralOffset)
        archive.put16(0)
        return archive
    }

    static func decode(_ archive: Data) throws -> [String: Data] {
        guard archive.count >= 22, archive.count <= totalLimit + 3_000_000 else { throw Error.tooLarge }
        let first = max(0, archive.count - 65_557)
        guard let footer = stride(from: archive.count - 22, through: first, by: -1)
            .first(where: { archive.word32(at: $0) == 0x06054b50 }) else { throw Error.corrupt }
        guard let count = archive.word16(at: footer + 10),
              let centralSize = archive.word32(at: footer + 12),
              let centralOffset = archive.word32(at: footer + 16),
              let commentLength = archive.word16(at: footer + 20),
              footer + 22 + Int(commentLength) == archive.count else { throw Error.corrupt }
        let centralStart = Int(centralOffset)
        let centralEnd = centralStart + Int(centralSize)
        guard centralStart <= footer, centralEnd <= footer else { throw Error.corrupt }
        var cursor = centralStart
        var found: [String: Data] = [:]
        var total = 0
        for _ in 0..<Int(count) {
            guard archive.word32(at: cursor) == 0x02014b50,
                  let flags = archive.word16(at: cursor + 8), flags & 0x0001 == 0,
                  let method = archive.word16(at: cursor + 10), method == 0,
                  let crc = archive.word32(at: cursor + 16),
                  let compressed = archive.word32(at: cursor + 20),
                  let uncompressed = archive.word32(at: cursor + 24), compressed == uncompressed,
                  let nameSize = archive.word16(at: cursor + 28),
                  let extraSize = archive.word16(at: cursor + 30),
                  let commentSize = archive.word16(at: cursor + 32),
                  let localOffset = archive.word32(at: cursor + 42) else { throw Error.unsupported }
            let nameStart = cursor + 46
            guard nameStart + Int(nameSize) <= centralEnd,
                  let name = String(data: archive.subdata(in: nameStart..<(nameStart + Int(nameSize))), encoding: .utf8),
                  validPath(name), found[name] == nil else { throw Error.invalidPath }
            cursor = nameStart + Int(nameSize) + Int(extraSize) + Int(commentSize)
            guard cursor <= centralEnd, Int(uncompressed) <= perFileLimit else { throw Error.tooLarge }
            total += Int(uncompressed)
            guard total <= totalLimit else { throw Error.tooLarge }
            let local = Int(localOffset)
            guard archive.word32(at: local) == 0x04034b50,
                  let localNameSize = archive.word16(at: local + 26),
                  let localExtraSize = archive.word16(at: local + 28) else { throw Error.corrupt }
            let dataStart = local + 30 + Int(localNameSize) + Int(localExtraSize)
            let dataEnd = dataStart + Int(uncompressed)
            guard dataStart >= 0, dataEnd <= centralStart else { throw Error.corrupt }
            let payload = archive.subdata(in: dataStart..<dataEnd)
            guard crc32(payload) == crc else { throw Error.corrupt }
            found[name] = payload
        }
        guard cursor == centralEnd else { throw Error.corrupt }
        return found
    }

    private static func validPath(_ path: String) -> Bool {
        if path == "annotations.json" || path == "books.json" { return true }
        let components = path.split(separator: "/")
        guard components.count == 2, let folder = components.first, let filename = components.last else { return false }
        let extensionName: String
        if folder == "audio" { extensionName = ".m4a" }
        else if folder == "books" { extensionName = ".pdf" }
        else { return false }
        guard filename.hasSuffix(extensionName) else { return false }
        return UUID(uuidString: String(filename.dropLast(extensionName.count))) != nil
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            var next = (crc ^ UInt32(byte)) & 0xff
            for _ in 0..<8 { next = (next & 1) == 1 ? (next >> 1) ^ 0xedb88320 : (next >> 1) }
            crc = (crc >> 8) ^ next
        }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func put16(_ number: UInt16) {
        append(UInt8(truncatingIfNeeded: number))
        append(UInt8(truncatingIfNeeded: number >> 8))
    }
    mutating func put32(_ number: UInt32) {
        put16(UInt16(truncatingIfNeeded: number))
        put16(UInt16(truncatingIfNeeded: number >> 16))
    }
    func word16(at index: Int) -> UInt16? {
        guard index >= 0, index <= count - 2 else { return nil }
        return UInt16(self[self.startIndex + index]) | (UInt16(self[self.startIndex + index + 1]) << 8)
    }
    func word32(at index: Int) -> UInt32? {
        guard let a = word16(at: index), let b = word16(at: index + 2) else { return nil }
        return UInt32(a) | (UInt32(b) << 16)
    }
}
