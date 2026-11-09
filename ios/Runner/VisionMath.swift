import Foundation

enum VisionMath {
    static func normalize(_ vector: [Float]) throws -> [Float] {
        let norm = sqrt(vector.reduce(Double(0)) { $0 + Double($1 * $1) })
        guard norm.isFinite, norm > 1e-6 else {
            throw SessionError.invalid("Embedding wajah tidak valid.")
        }
        return vector.map { $0 / Float(norm) }
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        return Float(zip(a, b).reduce(Double(0)) { $0 + Double($1.0 * $1.1) })
    }

    static func identity(_ scores: [(String, Float)], threshold: Float = 0.72, margin: Float = 0.08) -> String? {
        let sorted = scores.sorted { $0.1 > $1.1 }
        guard let best = sorted.first, best.1.isFinite, best.1 >= threshold else { return nil }
        if sorted.count > 1, best.1 - sorted[1].1 < margin { return nil }
        return best.0
    }

    static func median(_ values: [Float]) -> Float? {
        let sorted = values.filter { $0.isFinite }.sorted()
        guard !sorted.isEmpty else { return nil }
        if sorted.count % 2 == 0 {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }
        return sorted[sorted.count / 2]
    }

    static func reliableDepth(_ values: [Float]) -> Float? {
        let valid = values.filter { $0.isFinite && $0 >= 0.5 && $0 <= 5 }
        guard !values.isEmpty, Double(valid.count) >= Double(values.count) * 0.7 else { return nil }
        guard let center = median(valid) else { return nil }
        guard let deviation = median(valid.map { abs($0 - center) }) else { return nil }
        return deviation <= max(0.25, center * 0.2) ? center : nil
    }

    static func position(centerX: Float) -> String {
        if centerX < 0.35 { return "kiri" }
        if centerX > 0.65 { return "kanan" }
        return "depan"
    }

    static func stableDistance(_ readings: [Float?]) -> Float? {
        guard readings.count >= 3, !readings.contains(where: { $0 == nil || !$0!.isFinite }) else { return nil }
        let valid = readings.compactMap { $0 }
        guard let center = median(valid) else { return nil }
        return valid.allSatisfy { abs($0 - center) <= max(0.5, center * 0.2) } ? center : nil
    }
}
