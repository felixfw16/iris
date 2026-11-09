import CoreGraphics
import Foundation

struct SeenObject {
    let label: String
    let score: Float
    var box: CGRect
    var meters: Float?

    func map(width: Int) -> [String: Any?] {
        [
            "label": label,
            "confidence": Double(score),
            "position": VisionMath.position(centerX: Float(box.midX) / Float(max(width, 1))),
            "meters": meters.map { Double($0) },
            "box": [Double(box.minX), Double(box.minY), Double(box.maxX), Double(box.maxY)],
        ]
    }
}

final class ObjectVision {
    private let models: ModelFiles

    init(models: ModelFiles) {
        self.models = models
    }

    var available: Bool { models.has("objects") && models.has("objectLabels") }

    func detect(_ image: CGImage) throws -> [SeenObject] {
        throw SessionError.unavailable("Object Recognition belum tersedia pada iOS. Runtime object detection belum terhubung pada paket ini.")
    }

    func close() {
    }
}
