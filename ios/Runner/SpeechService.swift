import AVFoundation
import Foundation
import Speech

final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private let notify: (String) -> Void
    private var voice: AVSpeechSynthesisVoice?
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var epoch = 0
    private let lock = NSLock()

    var ready: Bool { voice != nil }

    init(notify: @escaping (String) -> Void) {
        self.notify = notify
        refreshVoice()
        if voice == nil {
            notify("Suara Bahasa Indonesia belum tersedia. Pasang suara Indonesia pada Pengaturan iOS.")
        }
    }

    func refreshVoice() {
        let indonesian = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("id") }
        voice = indonesian.first { $0.quality == .premium }
            ?? indonesian.first { $0.quality == .enhanced }
            ?? indonesian.first
    }

    func speak(_ text: String) throws {
        guard let voice else {
            throw SessionError.unavailable("Suara Bahasa Indonesia belum siap. Hasil tetap tersedia di layar.")
        }
        guard !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }

    func stop() {
        lock.lock()
        epoch += 1
        lock.unlock()
        synthesizer.stopSpeaking(at: .immediate)
        task?.cancel()
        task = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
    }

    static func authorize(_ completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            guard granted else {
                completion(false)
                return
            }
            SFSpeechRecognizer.requestAuthorization { status in
                completion(status == .authorized)
            }
        }
    }

    static var microphoneAllowed: Bool {
        AVAudioSession.sharedInstance().recordPermission == .granted
            && SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func listen(isCurrent: @escaping () -> Bool) throws -> String {
        guard SpeechService.microphoneAllowed else {
            throw SessionError.invalid("Aktifkan izin mikrofon dan pengenalan suara terlebih dahulu.")
        }
        lock.lock()
        let token = epoch
        lock.unlock()

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "id-ID"))
        guard let recognizer, recognizer.isAvailable else {
            throw SessionError.unavailable("Pengenalan suara Bahasa Indonesia belum tersedia pada perangkat ini.")
        }
        self.recognizer = recognizer

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()
        notify("Mikrofon siap. Silakan bicara; rekaman berhenti otomatis setelah Anda selesai.")

        let semaphore = DispatchSemaphore(value: 0)
        var transcript = ""
        var failure: Error?
        task = recognizer.recognitionTask(with: request) { result, error in
            if let result, result.isFinal {
                transcript = result.bestTranscription.formattedString
                semaphore.signal()
                return
            }
            if let error {
                failure = error
                semaphore.signal()
            }
        }

        let deadline = DispatchTime.now() + .seconds(32)
        var expired = false
        while semaphore.wait(timeout: .now() + .milliseconds(200)) == .timedOut {
            if DispatchTime.now() > deadline {
                expired = true
                break
            }
            lock.lock()
            let current = epoch
            lock.unlock()
            if current != token || !isCurrent() {
                expired = true
                break
            }
        }

        request.endAudio()
        engine.stop()
        input.removeTap(onBus: 0)
        task?.finish()
        task = nil
        try? session.setActive(false, options: .notifyOthersOnDeactivation)

        lock.lock()
        let current = epoch
        lock.unlock()
        if current != token || !isCurrent() { return "" }
        if expired && transcript.isEmpty { return "" }
        if let failure, transcript.isEmpty {
            throw SessionError.unavailable("Ucapan belum terbaca. Coba lagi di tempat yang lebih tenang. (\(failure.localizedDescription))")
        }
        notify("Memahami ucapan Anda.")
        return transcript
    }

    func close() {
        stop()
    }
}
