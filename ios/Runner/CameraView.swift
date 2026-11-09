import AVFoundation
import CoreImage
import Flutter
import Foundation
import UIKit

final class CameraFactory: NSObject, FlutterPlatformViewFactory {
    private weak var host: SessionHost?

    init(host: SessionHost) {
        self.host = host
        super.init()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        CameraView(frame: frame, host: host)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

final class CameraPreviewView: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
        backgroundColor = UIColor(red: 0.09, green: 0.16, blue: 0.19, alpha: 1)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

final class CameraView: NSObject, FlutterPlatformView, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let container: CameraPreviewView
    private weak var host: SessionHost?
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "id.sahabatnetra.camera")
    private var disposed = false
    private var lastFrameAt: Double = 0

    init(frame: CGRect, host: SessionHost?) {
        container = CameraPreviewView(frame: frame)
        self.host = host
        super.init()
        container.previewLayer.session = session
        host?.attachCamera(self)
        bind()
    }

    func view() -> UIView {
        container
    }

    var allowed: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    func bind() {
        guard !disposed, allowed, !session.isRunning else { return }
        queue.async { [weak self] in
            guard let self, !self.disposed else { return }
            self.configure()
            guard !self.session.inputs.isEmpty else { return }
            self.session.startRunning()
        }
    }

    private func configure() {
        guard session.inputs.isEmpty else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            host?.emit(["type": "error", "message": "Kamera tidak tersedia. Tutup aplikasi lain yang menggunakan kamera."])
            return
        }
        session.addInput(input)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()
    }

    func rebind() {
        queue.async { [weak self] in
            guard let self, !self.disposed else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
        bind()
    }

    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date().timeIntervalSince1970 * 1000
        guard now - lastFrameAt >= 180 else { return }
        lastFrameAt = now
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: buffer).oriented(.right)
        guard let rendered = CameraView.renderer.createCGImage(image, from: image.extent) else {
            host?.emit(["type": "error", "message": "Frame kamera tidak dapat dibaca."])
            return
        }
        host?.receiveFrame(rendered, capturedAt: Int(now))
    }

    private static let renderer = CIContext(options: [.useSoftwareRenderer: false])

    func dispose() {
        disposed = true
        output.setSampleBufferDelegate(nil, queue: nil)
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
        host?.detachCamera(self)
    }
}
