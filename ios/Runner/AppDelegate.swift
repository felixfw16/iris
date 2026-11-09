import Flutter
import Foundation
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var host: SessionHost?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        if let controller = window?.rootViewController as? FlutterViewController,
           let registrar = registrar(forPlugin: "IrisSessionHost") {
            host = SessionHost(messenger: controller.binaryMessenger,
                               controller: controller,
                               registrar: registrar)
        }
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
