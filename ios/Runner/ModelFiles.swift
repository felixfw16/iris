import Foundation

final class ModelFiles {
    static let names: [(id: String, file: String)] = [
        ("objects", "objects_oiv7.onnx"),
        ("objectLabels", "objects_labels.json"),
        ("face", "mobilefacenet.tflite"),
        ("depth", "depth_yolo26n.onnx"),
        ("speech", "ggml-tiny.bin"),
        ("qwen", "qwen35_0_8b_iris.litertlm"),
    ]

    private lazy var folder: URL? = Bundle.main.url(forResource: "Models", withExtension: nil)

    private lazy var available: Set<String> = {
        guard let folder else { return [] }
        let items = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        return Set(items ?? [])
    }()

    func status() -> [String: Bool] {
        let complete = available.contains("manifest.json")
        var result: [String: Bool] = [:]
        for entry in ModelFiles.names {
            result[entry.id] = complete && available.contains(entry.file)
        }
        return result
    }

    func has(_ id: String) -> Bool {
        status()[id] == true
    }

    func file(_ id: String) throws -> URL {
        guard let name = ModelFiles.names.first(where: { $0.id == id })?.file else {
            throw SessionError.invalid("Model tidak dikenal.")
        }
        guard let folder, available.contains(name), available.contains("manifest.json") else {
            throw SessionError.unavailable("Model \(id) belum dipasang pada paket iOS ini.")
        }
        return folder.appendingPathComponent(name)
    }
}
