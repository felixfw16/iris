import CoreGraphics
import Foundation

final class DepthVision {
    private let models: ModelFiles

    init(models: ModelFiles) {
        self.models = models
    }

    var available: Bool { models.has("depth") }

    func measure(_ image: CGImage, _ objects: inout [SeenObject]) throws {
        throw SessionError.unavailable("Distance Estimation belum tersedia pada iOS. Runtime monocular depth belum terhubung pada paket ini.")
    }

    func close() {
    }
}
