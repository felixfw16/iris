import CoreGraphics
import Foundation
import Vision

enum TextVision {
    static func read(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["id-ID", "en-US"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Tulisan belum terbaca. Dekatkan kamera, tahan stabil, dan pastikan cahaya cukup."
        }
        return String(text.prefix(4000))
    }
}
