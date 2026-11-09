import AVFoundation
import CoreGraphics
import Flutter
import Foundation
import UIKit

final class SessionHost: NSObject {
    private let messenger: FlutterBinaryMessenger
    private weak var controller: UIViewController?
    private var sink: FlutterEventSink?
    private let worker = DispatchQueue(label: "id.sahabatnetra.worker")
    private let busy = NSLock()
    private var working = false
    private let frameLock = NSLock()
    private var frame: CGImage?
    private var frameAt: Int = 0
    private var cameras: [CameraView] = []
    private var current: CameraView?
    private var scanning = false
    private var generation = 0
    private var foreground = true
    private var lastAnalysisAt = 0

    private let store = SecureStore()
    private let models = ModelFiles()
    private let metrics = Metrics()
    private lazy var objects = ObjectVision(models: models)
    private lazy var depth = DepthVision(models: models)
    private lazy var faces = FaceVision(models: models, store: store)
    private lazy var speech = SpeechService { [weak self] message in
        self?.emit(["type": "status", "message": message])
    }
    private lazy var gpt = GptService(store: store)
    private lazy var qwen = QwenService(models: models) { [weak self] message in
        self?.emit(["type": "status", "message": message])
    }

    init(messenger: FlutterBinaryMessenger, controller: UIViewController, registrar: FlutterPluginRegistrar) {
        self.messenger = messenger
        self.controller = controller
        super.init()
        registrar.register(CameraFactory(host: self), withId: "id.sahabatnetra/camera")
        FlutterEventChannel(name: "id.sahabatnetra/events", binaryMessenger: messenger).setStreamHandler(self)
        FlutterMethodChannel(name: "id.sahabatnetra/control", binaryMessenger: messenger)
            .setMethodCallHandler { [weak self] call, result in
                self?.handle(call, result) ?? result(FlutterError(code: "operation", message: "Sesi tidak aktif.", details: nil))
            }
        NotificationCenter.default.addObserver(self, selector: #selector(onBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    func emit(_ event: [String: Any?]) {
        DispatchQueue.main.async { [weak self] in
            self?.sink?(event.compactMapValues { $0 })
        }
    }

    func attachCamera(_ view: CameraView) {
        cameras.append(view)
        current = view
    }

    func detachCamera(_ view: CameraView) {
        cameras.removeAll { $0 === view }
        if current === view {
            current = cameras.last
            clearFrame()
            current?.rebind()
        }
    }

    private var cameraAllowed: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "status":
            speech.refreshVoice()
            result([
                "models": models.status(),
                "ttsReady": speech.ready,
                "cameraPermission": cameraAllowed,
                "hasApiKey": !(store.get("api_key") ?? "").isEmpty,
                "gptModel": store.get("gpt_model") ?? "",
            ])
        case "requestCamera":
            if cameraAllowed {
                current?.bind()
                result(true)
                return
            }
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.current?.bind() }
                    result(granted)
                    self?.emit(["type": "ready"])
                }
            }
        case "startScan":
            guard cameraAllowed else {
                result(FlutterError(code: "operation", message: "Izin kamera diperlukan.", details: nil))
                return
            }
            guard objects.available else {
                result(FlutterError(code: "operation", message: "Model objek belum dipasang dalam paket ini.", details: nil))
                return
            }
            generation = arguments["generation"] as? Int ?? generation + 1
            scanning = true
            lastAnalysisAt = 0
            result(nil)
            haptic()
        case "stop":
            scanning = false
            generation = arguments["generation"] as? Int ?? generation + 1
            gpt.cancel()
            qwen.cancel()
            speech.stop()
            result(nil)
        case "speak":
            do {
                try speech.speak(arguments["text"] as? String ?? "")
                result(nil)
            } catch {
                result(failure(error))
            }
        case "readText":
            runTask(result, "ocr") { [weak self] in
                guard let self else { throw SessionError.cancelled }
                return try TextVision.read(try self.snapshot())
            }
        case "recognizeFamily":
            runTask(result, "family") { [weak self] in
                guard let self else { throw SessionError.cancelled }
                return try self.faces.recognize(try self.snapshot())
            }
        case "measureDistance":
            runTask(result, "depth") { [weak self] in
                guard let self else { throw SessionError.cancelled }
                return try self.measureDistance()
            }
        case "describePhoto":
            runTask(result, "gpt") { [weak self] in
                guard let self else { throw SessionError.cancelled }
                return try self.gpt.describe(try self.snapshot(), online: arguments["online"] as? Bool == true)
            }
        case "requestMicrophone":
            if SpeechService.microphoneAllowed {
                result(true)
                return
            }
            SpeechService.authorize { granted in
                DispatchQueue.main.async { result(granted) }
            }
        case "listen":
            guard SpeechService.microphoneAllowed else {
                result(FlutterError(code: "operation", message: "Aktifkan izin mikrofon terlebih dahulu.", details: nil))
                return
            }
            let token = generation
            runTask(result, "speech") { [weak self] in
                guard let self else { throw SessionError.cancelled }
                return try self.speech.listen { token == self.generation }
            }
        case "askQwen":
            guard SpeechService.microphoneAllowed else {
                result(FlutterError(code: "operation", message: "Aktifkan izin mikrofon terlebih dahulu.", details: nil))
                return
            }
            let token = generation
            runTask(result, "qwen") { [weak self] in
                guard let self else { throw SessionError.cancelled }
                let question = try self.speech.listen { token == self.generation }
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return try self.qwen.answer(
                    question: question,
                    thinking: arguments["thinking"] as? Bool == true,
                    tools: { name in try self.runTool(name, token: token) },
                    isCurrent: { token == self.generation })
            }
        case "saveSettings":
            do {
                try saveSettings(arguments)
                result(nil)
            } catch {
                result(failure(error))
            }
        case "deleteApiKey":
            gpt.cancel()
            store.remove("api_key")
            result(nil)
        case "listFamily":
            result(faces.list())
        case "deleteFamily":
            runTask(result, "family_delete") { [weak self] in
                try self?.faces.delete(arguments["id"] as? String ?? "")
                return nil
            }
        case "enrollFace":
            runTask(result, "family_enroll") { [weak self] in
                guard let self else { throw SessionError.cancelled }
                return try self.faces.enroll(try self.snapshot(), name: arguments["name"] as? String ?? "")
            }
        case "cancelEnrollment":
            worker.async { [weak self] in self?.faces.cancelEnrollment() }
            result(nil)
        case "ttsSettings":
            guard let url = URL(string: UIApplication.openSettingsURLString),
                  UIApplication.shared.canOpenURL(url) else {
                result(FlutterError(code: "operation", message: "Pengaturan suara tidak dapat dibuka.", details: nil))
                return
            }
            UIApplication.shared.open(url)
            result(nil)
        case "exportMetrics":
            exportMetrics(result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func saveSettings(_ arguments: [String: Any]) throws {
        let key = arguments["apiKey"] as? String ?? ""
        let model = arguments["model"] as? String ?? ""
        guard model.count <= 150, !model.contains("\n") else {
            throw SessionError.invalid("Model ID tidak valid.")
        }
        if !key.trimmingCharacters(in: .whitespaces).isEmpty {
            guard (20...1024).contains(key.count), !key.contains(where: { $0.isWhitespace }) else {
                throw SessionError.invalid("Format API key tidak valid.")
            }
            try store.put("api_key", key)
        }
        try store.put("gpt_model", model)
    }

    private func runTool(_ name: String, token: Int) throws -> String {
        guard token == generation else { throw SessionError.cancelled }
        emit(["type": "status", "generation": token, "message": "Memeriksa kamera untuk menjawab pertanyaan Anda."])
        var output: [String: Any] = ["tool": name]
        do {
            let image = try snapshot()
            output["capturedAt"] = Int(Date().timeIntervalSince1970 * 1000)
            output["status"] = "ok"
            switch name {
            case "detect_objects":
                let seen = try objects.detect(image).prefix(10)
                output["objects"] = seen.map {
                    [
                        "label": $0.label,
                        "position": VisionMath.position(centerX: Float($0.box.midX) / Float(max(image.width, 1))),
                        "confidence": Double($0.score),
                    ]
                }
                output["distanceMeasured"] = false
            case "read_text":
                output["text"] = String(try TextVision.read(image).prefix(1600))
            default:
                throw SessionError.invalid("Alat tidak dikenal.")
            }
        } catch {
            output["status"] = "unavailable"
            output["message"] = "Pengamatan kamera belum tersedia."
        }
        guard token == generation else { throw SessionError.cancelled }
        let data = try JSONSerialization.data(withJSONObject: output)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func measureDistance() throws -> [String: Any?] {
        let token = generation
        var previous: [SeenObject] = []
        var readings: [[Float?]] = []
        var imageWidth = 1
        for pass in 0..<3 {
            guard token == generation else { throw SessionError.cancelled }
            let image = try snapshot()
            var seen = try objects.detect(image)
            imageWidth = image.width
            if !seen.isEmpty { try depth.measure(image, &seen) }
            if pass == 0 {
                previous = seen
                readings = seen.map { [$0.meters] }
            } else {
                for (index, item) in previous.enumerated() {
                    let matched = seen.filter { $0.label == item.label }
                        .max { overlap(item.box, $0.box) < overlap(item.box, $1.box) }
                    if let matched, overlap(item.box, matched.box) >= 0.5 {
                        readings[index].append(matched.meters)
                        previous[index].box = matched.box
                    } else {
                        readings[index].append(nil)
                    }
                }
            }
        }
        for index in previous.indices {
            previous[index].meters = VisionMath.stableDistance(readings[index])
        }
        return ["items": previous.map { $0.map(width: imageWidth) }]
    }

    private func overlap(_ a: CGRect, _ b: CGRect) -> Float {
        let intersection = a.intersection(b)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let area = intersection.width * intersection.height
        let union = a.width * a.height + b.width * b.height - area
        return Float(area / max(union, 1))
    }

    private func exportMetrics(_ result: @escaping FlutterResult) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("iris-metrics.csv")
        do {
            try metrics.bytes().write(to: url)
        } catch {
            result(FlutterError(code: "export", message: "Ekspor gagal.", details: nil))
            return
        }
        guard let controller else {
            result(FlutterError(code: "export", message: "Ekspor gagal.", details: nil))
            return
        }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, completed, _, _ in
            result(completed ? "Metrik disimpan." : "Ekspor dibatalkan.")
        }
        sheet.popoverPresentationController?.sourceView = controller.view
        controller.present(sheet, animated: true)
    }

    private func failure(_ error: Error) -> FlutterError {
        let session = error as? SessionError
        return FlutterError(code: session?.code ?? "operation",
                            message: error.localizedDescription,
                            details: nil)
    }

    private func runTask(_ result: @escaping FlutterResult, _ task: String, _ action: @escaping () throws -> Any?) {
        scanning = false
        speech.stop()
        busy.lock()
        if working {
            busy.unlock()
            result(FlutterError(code: "busy", message: "Pemrosesan sebelumnya masih berjalan. Tunggu sebentar.", details: nil))
            return
        }
        working = true
        busy.unlock()
        let token = generation
        worker.async { [weak self] in
            let started = Date()
            var success = false
            defer {
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                self?.metrics.record(task: task, elapsedMs: elapsed, success: success)
                self?.busy.lock()
                self?.working = false
                self?.busy.unlock()
            }
            do {
                guard let self, token == self.generation else { throw SessionError.cancelled }
                let value = try action()
                success = true
                DispatchQueue.main.async {
                    if token == self.generation {
                        result(value)
                        self.haptic()
                    } else {
                        result(FlutterError(code: "cancelled", message: "Permintaan dibatalkan.", details: nil))
                    }
                }
            } catch {
                let wrapped = self?.failure(error) ?? FlutterError(code: "processing", message: "Pemrosesan \(task) gagal.", details: nil)
                DispatchQueue.main.async { result(wrapped) }
            }
        }
    }

    func receiveFrame(_ image: CGImage, capturedAt: Int) {
        guard foreground else { return }
        frameLock.lock()
        frame = image
        frameAt = capturedAt
        frameLock.unlock()
        guard scanning, capturedAt - lastAnalysisAt >= 900 else { return }
        busy.lock()
        if working {
            busy.unlock()
            return
        }
        working = true
        busy.unlock()
        lastAnalysisAt = capturedAt
        let token = generation
        worker.async { [weak self] in
            guard let self else { return }
            let started = Date()
            var success = false
            defer {
                self.metrics.record(task: "objects", elapsedMs: Int(Date().timeIntervalSince(started) * 1000), success: success)
                self.busy.lock()
                self.working = false
                self.busy.unlock()
            }
            guard token == self.generation, self.scanning else { return }
            do {
                let seen = try self.objects.detect(image)
                success = true
                if token == self.generation, self.scanning {
                    self.emit([
                        "type": "objects",
                        "generation": token,
                        "capturedAt": capturedAt,
                        "items": seen.map { $0.map(width: image.width) },
                    ])
                }
            } catch {
                self.scanning = false
                self.emit(["type": "error", "message": "Deteksi objek gagal. Periksa paket model dan mulai kembali."])
            }
        }
    }

    private func snapshot() throws -> CGImage {
        for _ in 0..<30 {
            frameLock.lock()
            let now = Int(Date().timeIntervalSince1970 * 1000)
            let candidate = (foreground && now - frameAt <= 2500) ? frame : nil
            frameLock.unlock()
            if let candidate { return candidate }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw SessionError.unavailable("Kamera belum siap. Tunggu sebentar lalu coba lagi.")
    }

    func clearFrame() {
        frameLock.lock()
        frame = nil
        frameAt = 0
        frameLock.unlock()
    }

    private func haptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    @objc private func onForeground() {
        foreground = true
    }

    @objc private func onBackground() {
        foreground = false
        scanning = false
        generation += 1
        speech.stop()
        gpt.cancel()
        qwen.cancel()
        clearFrame()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension SessionHost: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }
}
