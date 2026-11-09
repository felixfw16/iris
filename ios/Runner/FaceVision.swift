import CoreGraphics
import Foundation
import Vision

final class FaceVision {
    private let store: SecureStore
    private let models: ModelFiles

    init(models: ModelFiles, store: SecureStore) {
        self.models = models
        self.store = store
    }

    private func profiles() -> [[String: Any]] {
        guard let raw = store.get("family_v1"),
              let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return parsed
    }

    private func save(_ value: [[String: Any]]) throws {
        let data = try JSONSerialization.data(withJSONObject: value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SessionError.invalid("Profil wajah tidak dapat disimpan.")
        }
        try store.put("family_v1", text)
    }

    func list() -> [[String: String]] {
        profiles().compactMap { profile in
            guard let id = profile["id"] as? String, let name = profile["name"] as? String else { return nil }
            return ["id": id, "name": name]
        }
    }

    func delete(_ id: String) throws {
        let remaining = profiles().filter { ($0["id"] as? String) != id }
        try save(remaining)
    }

    func detect(_ image: CGImage) throws -> [VNFaceObservation] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return request.results ?? []
    }

    func enroll(_ image: CGImage, name: String) throws -> Int {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else {
            throw SessionError.invalid("Nama panggilan harus 1 sampai 40 karakter.")
        }
        guard models.has("face") else {
            throw SessionError.unavailable("Face Registration belum tersedia pada iOS. Model face embedding belum dipasang untuk platform ini.")
        }
        throw SessionError.unavailable("Face Registration belum tersedia pada iOS. Runtime face embedding belum terhubung.")
    }

    func recognize(_ image: CGImage) throws -> String {
        guard models.has("face") else {
            throw SessionError.unavailable("Face Recognition belum tersedia pada iOS. Model face embedding belum dipasang untuk platform ini.")
        }
        throw SessionError.unavailable("Face Recognition belum tersedia pada iOS. Runtime face embedding belum terhubung.")
    }

    func cancelEnrollment() {
    }

    func close() {
    }
}
