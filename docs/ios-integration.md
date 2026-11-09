# iOS integration

Status as of 9 November 2026. This document covers the initial iOS integration only. The
app has never been compiled or run on iOS.

> Xcode, the Flutter SDK, and CocoaPods were all absent from the machine where this was
> written. No file here has been compiled against the iOS SDK, and no behaviour described
> below has been observed on a device or simulator.

## What exists

The authored half of the integration: the Swift side of the platform channel, written to
match the Android contract in `android/app/src/main/kotlin/id/sahabatnetra/app/`. These are
the files `flutter create` never generates.

| File | Role | Android counterpart |
| --- | --- | --- |
| `ios/Runner/AppDelegate.swift` | Registers `SessionHost` on launch | `MainActivity.configureFlutterEngine` |
| `ios/Runner/SessionHost.swift` | Method and event channel host, all 20 methods | `MainActivity.kt` |
| `ios/Runner/CameraView.swift` | `UiKitView` platform view, `AVCaptureSession` frame pump | `CameraView.kt` |
| `ios/Runner/SpeechService.swift` | `AVSpeechSynthesizer` output, `SFSpeechRecognizer` input | `SpeechService.kt` |
| `ios/Runner/TextVision.swift` | OCR via Apple Vision | ML Kit call inside `MainActivity.kt` |
| `ios/Runner/GptService.swift` | Online Mode request | `GptService.kt` |
| `ios/Runner/SecureStore.swift` | Keychain, device-only, after-first-unlock | `SecureStore.kt` |
| `ios/Runner/ModelFiles.swift` | Bundled model lookup | `ModelFiles.kt` |
| `ios/Runner/Metrics.swift` | Latency CSV | `Metrics.kt` |
| `ios/Runner/VisionMath.swift` | Thresholds and distance stability | `VisionMath.kt` |
| `ios/Runner/ObjectVision.swift` | Detection types, runtime not connected | `ObjectVision.kt` |
| `ios/Runner/DepthVision.swift` | Not connected | `DepthVision.kt` |
| `ios/Runner/FaceVision.swift` | Face rectangles only, embedding not connected | `FaceVision.kt` |
| `ios/Runner/QwenService.swift` | Not connected | `QwenService.kt` |
| `ios/Runner/SessionError.swift` | Error codes shared across the Swift side | error mapping in `runTask` |
| `ios/Runner/Info.plist` | Camera, microphone, speech usage strings | `AndroidManifest.xml` |
| `ios/Podfile` | Deployment target 13.0 | `build.gradle.kts` |

`lib/main.dart` had `AndroidView` hardcoded at two call sites, which would have rendered
nothing on iOS. Both now go through one `CameraPreview` widget that selects `AndroidView`,
`UiKitView`, or a message for other platforms. The channel names, method names, argument
keys, and return shapes are identical across platforms, so the Dart layer needs no other
platform branching.

Both platform view branches are wrapped in `ExcludeSemantics`, added by the accessibility
pass in session iris-3. A camera preview carries nothing a screen reader can use, and as a
focus stop it costs a swipe for no payoff. `CameraPreviewView` in `CameraView.swift`
therefore sets `isAccessibilityElement = false`, matching `CameraView.kt`, which declares no
accessibility properties at all. Whether the Dart-side exclusion alone would suppress the
native view is untested: a `UiKitView` puts a real `UIView` into the UIKit hierarchy, and
which layer governs VoiceOver there needs a device to settle. Setting both sides to agree
avoids depending on the answer. `docs/UI_RULES.md` rule 9 carries this as a general rule for
any embedded platform view; this section records only the decision for this integration and
the question left open.

## Feature parity

Every channel method answers on iOS. Four features answer with a stated reason rather than a
result, because their runtimes are not wired for this platform.

| Feature | Android | iOS now | Gap |
| --- | --- | --- | --- |
| Voice output | Android TTS, offline `id` voice | `AVSpeechSynthesizer`, `id` voice | none in design |
| Text Recognition | ML Kit Latin, on device | Apple Vision, on device | none in design |
| Voice Command input | whisper.cpp, on device | `SFSpeechRecognizer` `id-ID` | different engine, see below |
| Online Mode | `GptService` | `GptService` | none in design |
| API key storage | Keystore AES-GCM | Keychain, device-only | none in design |
| Camera preview and frames | CameraX, RGBA, upright | `AVCaptureSession`, BGRA, `.right` oriented | rotation handling unverified |
| Object Recognition | ONNX Runtime | throws, stated reason | no ONNX runtime or model in the iOS bundle |
| Distance Estimation | ONNX depth model | throws, stated reason | same |
| Face Registration / Recognition | TFLite MobileFaceNet | detection only, enrol and match throw | no TFLite runtime or model in the iOS bundle |
| Free-form questions, Fallback Mode | LiteRT SLM | throws, stated reason | no LiteRT runtime or model in the iOS bundle |

The four gaps share one cause: Android ships the model files in
`android/app/src/main/assets/models/` with a `manifest.json` and SHA-256 verification, and
loads them through ONNX Runtime, TFLite, and LiteRT. None of those runtimes are iOS
dependencies yet, and no model is in the iOS bundle. `ModelFiles.swift` already looks for a
`Models` bundle directory and reports each model as absent, so the failure is a stated
message rather than a crash.

> `SFSpeechRecognizer` is not equivalent to whisper.cpp on privacy. Android transcribes
> entirely on device. On iOS we set `requiresOnDeviceRecognition` from
> `supportsOnDeviceRecognition`, so when the device or locale lacks on-device `id-ID`
> support, that flag is false and audio goes to Apple for transcription. Confirm this on
> target hardware before any claim that Iris transcribes only on device.

## What you run once Xcode is installed

The generated half is missing: `Runner.xcodeproj`, `Runner.xcworkspace`,
`ios/Flutter/*.xcconfig`, `Base.lproj/Main.storyboard`, `Base.lproj/LaunchScreen.storyboard`,
`Assets.xcassets`, `Runner-Bridging-Header.h`, and `GeneratedPluginRegistrant`. `Info.plist`
references the two storyboards, and `AppDelegate.swift` references
`GeneratedPluginRegistrant`, so neither compiles until these exist.

`flutter create` overwrites `AppDelegate.swift` and `Info.plist` with its own templates.
Commit the authored files first so the overwrite is recoverable:

```bash
cd /Users/arjunaandio/skripsi/iris
git add ios docs/ios-integration.md lib/main.dart pubspec.yaml
git commit -m "Add initial iOS platform channel integration"

flutter create --platforms=ios .
git checkout -- ios/Runner/AppDelegate.swift ios/Runner/Info.plist

cd ios && pod install && cd ..
flutter build ios --debug --no-codesign
```

Then open `ios/Runner.xcworkspace` and add every `ios/Runner/*.swift` file to the Runner
target. `flutter create` registers only the files its own template knows about, so the
authored Swift files compile only once they are in the target's Compile Sources.

Set the bundle identifier to `id.sahabatnetra.app` to match `applicationId` on Android.

## Expected first failures

These are predictions, not observations.

- Camera frame orientation. `CameraView.swift` applies `.right` to match the upright bitmap
  Android produces through its rotation matrix. Device orientation handling on iOS differs
  from CameraX, so the preview may be correct while the analysed frame is rotated, which
  would move Object Recognition positions between kiri, depan, and kanan.
- `CIContext.createCGImage` per frame at 180 ms intervals is heavier than Android's direct
  buffer copy. Expect to revisit this once frames feed a real detector.
- `SpeechService.listen` blocks its worker thread on a semaphore to keep the Android
  synchronous contract. It is correct on a background queue and would deadlock if ever
  called on the main thread.
- No iOS unit tests exist. `android/app/src/test/` has `ObjectDecoderTest` and
  `VisionMathTest`; `VisionMath.swift` is a direct port and is the first thing worth a
  `RunnerTests` target.

## Verification actually performed

`swiftc -typecheck` against the macOS SDK, using the Swift 6.3.2 toolchain from Command Line
Tools, passes with no errors or warnings on the files that depend only on Foundation,
Security, CoreGraphics, and Vision: `SessionError`, `VisionMath`, `SecureStore`, `Metrics`,
`ModelFiles`, `TextVision`, `FaceVision`, `ObjectVision`, `DepthVision`, `GptService`,
`QwenService`.

`plutil -lint ios/Runner/Info.plist` reports OK.

`SpeechService.swift`, `CameraView.swift`, `SessionHost.swift`, and `AppDelegate.swift` are
unchecked. The first needs `AVAudioSession`, which is unavailable in the macOS SDK; the other
three need `Flutter.framework` and the iOS SDK. Syntax and API errors in these four are
possible and should be expected on the first build.

The Dart change is also unchecked, since `flutter analyze` could not run.
