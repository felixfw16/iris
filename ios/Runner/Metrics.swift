import Foundation

final class Metrics {
    private let header = "timestamp,task,latency_ms,success\n"
    private let lock = NSLock()
    private let url: URL
    private let stamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("metrics.csv")
    }

    private func size() -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }

    func record(task: String, elapsedMs: Int, success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if !FileManager.default.fileExists(atPath: url.path) || size() > 5_000_000 {
            try? Data(header.utf8).write(to: url)
        }
        let line = "\(stamp.string(from: Date())),\(task),\(elapsedMs),\(success)\n"
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    func bytes() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return (try? Data(contentsOf: url)) ?? Data(header.utf8)
    }
}
