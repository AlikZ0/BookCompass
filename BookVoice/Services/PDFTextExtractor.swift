import Foundation
import PDFKit
import Vision
import UIKit

struct PDFTextExtractor {
    /// First uses the text layer. If it is missing, runs Apple's on-device OCR.
    static func text(on page: PDFPage, bookID: UUID, pageIndex: Int) async -> String {
        let direct = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty { return normalize(direct) }

        if let cached = OCRTextCache.read(bookID: bookID, page: pageIndex) { return cached }

        // Render the scanned page in PDFKit. No image data is uploaded anywhere.
        let image = page.thumbnail(of: CGSize(width: 1700, height: 2200), for: .mediaBox)
        guard let cgImage = image.cgImage else { return "" }

        let recognized = await Task.detached(priority: .userInitiated) { () -> String in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                let lines = (request.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                return Self.normalize(lines.joined(separator: "\n"))
            } catch {
                return ""
            }
        }.value
        // Cache successfully-recognized pages to avoid repeated OCR.
        if !recognized.isEmpty { OCRTextCache.write(recognized, bookID: bookID, page: pageIndex) }
        return recognized
    }

    private static func normalize(_ input: String) -> String {
        input.replacingOccurrences(of: "-\\n", with: "")
            .replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
