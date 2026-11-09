import Foundation

final class QwenService {
    private let models: ModelFiles
    private let notify: (String) -> Void

    init(models: ModelFiles, notify: @escaping (String) -> Void) {
        self.models = models
        self.notify = notify
    }

    var available: Bool { models.has("qwen") }

    func cancel() {
    }

    func answer(question: String, thinking: Bool, tools: (String) throws -> String, isCurrent: () -> Bool) throws -> String {
        throw SessionError.unavailable("Pertanyaan bebas pada Fallback Mode belum tersedia pada iOS. Runtime Small Language Model belum terhubung pada paket ini.")
    }

    func close() {
    }
}
