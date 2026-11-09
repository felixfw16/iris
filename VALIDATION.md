# Validation notes

## Release 0.5.0, 16 September 2026

- The ARM64 release build succeeded with the project Flutter SDK and `--no-pub`; Gradle finished in about 91.6 seconds. Local log: `build/apk-build-0.5.0.log`.
- APK: `build/app/outputs/flutter-apk/app-release.apk`, **1,482,839,112 bytes** (about 1.48 GB, or 1,414.1 MiB).
- SHA-256: `591d500726ddbd93d5788b873e8229639593bf89a384a5dc001cf8669040836b`.
- `aapt` metadata: package `id.sahabatnetra.app`, version `0.5.0` (5), minimum API 26, target API 36.
- `apksigner verify --verbose`: v2 signature passed; signing still uses the debug key for demos.
- `flutter analyze --no-pub`: no issues. `flutter test --no-pub`: **21 tests passed**. The Android channels are mocked in the Flutter tests.
- Native Java checks: **5 VoiceEndpoint scenarios** and **6 AssistantToolRouter scenarios** passed, compiled and run with JBR 21.
- The Android `:app:testDebugUnitTest` suite did not reach its assertions: the offline attempt failed because the `arm64_v8a_debug` and `x86_64_debug` Flutter artifacts were missing from the cache. The online attempt stalled on dependency resolution and was stopped. Log: `build/native-tests-0.5.0.log`. This does not invalidate the successful release build, but the Kotlin distance and detector tests have not been reverified.
- `python scripts/verify_qwen_apk.py`: all six required assets match the manifest and `models.lock.json`; the LiteRT-LM, Flutter, application, and Whisper ARM64 runtimes are present; the Thinking template was checked against the model inside the APK rather than the workspace copy. No `.parts` download fragments are present in the APK.
- Active Qwen: `qwen35_0_8b_iris.litertlm`, SHA-256 `49a077c27d63945da44289d8d8054cd231dfaaf5192167bff22f47ab9a258fc2`.
- The APK targets ARM64, but dependency libraries also carry ARMv7 and x86_64 ABIs. Their presence is not evidence that the application supports those devices.
- The build still emits Kotlin Gradle Plugin migration warnings for future Flutter versions; the current build succeeds.

The APK was not installed or tested on a phone in this session. Accuracy, latency, RAM, real TalkBack and TTS behaviour, Qwen and Thinking quality, and inference cancellation all need on-device testing. Earlier desktop Qwen experiment logs showed repetitive and inconsistent answers. No claim is made that interface tests demonstrate model quality.

The APK binary stays in the gitignored build directory; the commit covers the sources, the documentation, and the verification audit.


## Qwen voice / version 0.4.0, 13 September 2026

- The final APK succeeded: `build/app/outputs/flutter-apk/app-release.apk`, 667,515,735 bytes (636.6 MiB), version `0.4.0` (4), package `id.sahabatnetra.app`, minimum API 26, target API 36. Log `build/apk-build-qwen.log`; Gradle about 38.2 seconds.
- APK SHA-256: `570d6bb00d72fbffb6d1b168982ce085b09d41373174bbfa02c0a4d7379a9e8b`.
- `flutter analyze`: no issues. `flutter test`: 21 tests passed; log `build/qwen-tests.log`. The new tests verify that the Thinking switch reaches the native side, that answers reach TTS, that Thinking starts off, and that a late answer arriving after Berhenti is not spoken. The native channels are mocked; model inference is not exercised by the Flutter tests.
- The Kotlin release compile and the LiteRT-LM 0.17.0 integration passed. Kotlin 2.4.0 is required by the library metadata. Flutter still emits built-in Kotlin migration warnings for future versions.
- `apksigner verify --verbose` passed with a v2 signature; signing remains the debug key for demos. Every model checksum in the APK matches the manifest, the LiteRT-LM runtime is present, and there is no `.parts` download fragment directory in the package. The audit can be repeated with `python scripts/verify_qwen_apk.py`.
- The bundled model header carries the `enable_thinking` template and the `thought` channel. The runtime sends that switch, caps output at 128 or 512 tokens, and forwards only answer content to TTS; extra reasoning markup is filtered out.
- The Berhenti button, `onPause`, and `onDestroy` all request native inference cancellation. The first model load cannot be cancelled directly; a generation check prevents the next inference, and a stale result is still read out.

The APK was not installed or tested on a phone. Speed, RAM consumption, Indonesian answer quality, Thinking behaviour, and native cancellation still need device testing. Qwen receives a text transcript; there is no Qwen image understanding, wake word, or automatic feature selection. This version keeps YOLO26n-depth and the previous object detector.

## YOLO26n-depth / version 0.3.0, 13 September 2026

- Two Depth Anything V2 models were replaced by a single YOLO26n-depth ONNX model; RGB input /255, letterbox 640×640 RGB 114, output `[1,1,640,640]` in metres. Android uses ONNX Runtime CPU with two threads. The indoor/outdoor profile choice was removed; the 601-class object detector stays.
- The official weights' SHA-256 was verified against the GitHub release digest. The ONNX checker passed; ONNX output was compared against PyTorch on random, grey, and black inputs with an rtol/atol tolerance of 0.005. The maximum absolute difference was 0.0002594. This validates the export numerically, not real measurement accuracy.
- The new ONNX model is 20,740,729 bytes. The old depth models are kept at `.models/previous-depth_*.onnx` and are not in the APK.
- `flutter analyze`: no issues. `flutter test`: 19 tests passed, including the single depth model readiness status. The native Android tests were not rerun at this stage; the Kotlin release compiled successfully within the APK build.
- APK: `build/app/outputs/flutter-apk/app-release.apk`, 274,169,584 bytes (261.5 MiB), version `0.3.0` (3), package `id.sahabatnetra.app`, min SDK 26, target SDK 36.
- APK SHA-256: `c65cf0e1c8cf9cd0376423a55375152f27d14c0ace38acb7cff17dc7a559adaa`.
- `apksigner verify --verbose` passed, v2 signature with the debug demo signing. Every model hash in the APK archive matches the manifest; neither old depth asset is present.
- Logs: `build/depth-export.log`, `build/apk-build-yolo-depth.log`. The Gradle release finished in about 71.5 seconds.

Not yet tested on the Redmi: latency, metre accuracy, battery consumption, and temperature. Desktop ONNX latency on three synthetic inputs was about 333-419 ms, which is not a phone benchmark. The measurement flow is still three sequential readings with narration rounded to 0.5 m; this version does not implement near real-time continuous depth. The new model has not been calibrated against real distance measurements. There is no new LLM or VLM in the APK.

## Version 0.2.0 audit and rebuild, 13 September 2026

- `flutter analyze`: passed with no issues.
- `flutter test`: all 18 tests passed. The Flutter tests mock the native channels.
- The native `:app:testDebugUnitTest` run did not succeed: the online attempt stalled on the network and was stopped; the offline attempt identified that the `arm64_v8a_debug` and `x86_64_debug` Flutter artifacts for engine revision `0e228ec8c8d2abc9fcf1d053e8a40665bb859ec7` were missing from the cache. Log: `build/android-tests-offline.log`. This is a dependency resolution failure before test execution, not an assertion result. The current configuration provides only the debug unit test task; `testReleaseUnitTest` is unavailable.
- The release build from the current sources succeeded: `build/app/outputs/flutter-apk/app-release.apk`.
- Latest build log: `build/apk-build-current.log`; Gradle time about 73.7 seconds.
- Size: 449,043,109 bytes (428.2 MiB).
- Metadata checked with `aapt`: package `id.sahabatnetra.app`, version `0.2.0` (2), min SDK 26, target SDK 36.
- `apksigner verify --verbose` passed, v2 signature; still debug signing for demos.
- SHA-256: `467c3ffd684124d9dae2b9e1e0109a3cb16cf95db520b84e1546b5448000b252`.
- The 601-class YOLO assets, labels, MobileFaceNet, Whisper, both depth models, and the manifest are present in the APK. The old EfficientDet asset is also still packaged. The release task verifies the required asset checksums.
- The Flutter target is ARM64; archive inspection still finds ARMv7 and x86_64 native libraries too. Do not read that as application support for those ABIs.
- The build emits Kotlin Gradle Plugin and built-in Kotlin migration warnings; they did not fail this build.

The build environment requires `GRADLE_USER_HOME=C:/Users/felix/.gradle`, because the process default pointed at `C:/.gradle` for a time. The Flutter SDK uses a process-scoped Git ownership exception with `/` separators in the path. No global Git configuration was changed.

```powershell
$env:GIT_CONFIG_COUNT='1'
$env:GIT_CONFIG_KEY_0='safe.directory'
$env:GIT_CONFIG_VALUE_0='C:/Users/felix/OneDrive/Desktop/prototype-skripsi/.tools/flutter'
$env:GRADLE_USER_HOME='C:/Users/felix/.gradle'
& .\.tools\flutter\bin\flutter.bat build apk --release --target-platform android-arm64
```

The APK was not installed or tested on a phone during this audit. The local LLM, automatic mode selection, and the wake word are not implemented. The feature audit and the plan for later work are in `PROGRESS.md`. The sections below are the validation history of earlier versions.

## APK build, 13 September 2026

The release APK built successfully at `build/app/outputs/flutter-apk/app-release.apk` with `flutter build apk --release --target-platform android-arm64`. Log: `build/apk-build.log` (Gradle `BUILD SUCCESSFUL`). File size 457,924,327 bytes, about 436.7 MiB.

- Fixed the `MessageDigest` reference in the Gradle script with an explicit import; the checksum check across all five models still runs and passed.
- `apksigner verify --verbose` passed with a v2 signature. Signing still uses the debug key, per the project's demo configuration.
- APK metadata: `id.sahabatnetra.app`, version `0.1.0` (1), minimum Android API 26, target API 36.
- The APK contents were verified to include all five models, the model manifest, and the ARM64 `libapp.so`, `libflutter.so`, and `libnetra_whisper.so`. The package also contains other ABI libraries from the build configuration; this is not an APK whose contents are exclusively ARM64.
- SHA-256: `33bd671f48db8776044999d204759bceb1d2b85dc13de85744fae01237d12c3e`.

The APK was not installed or tested directly on a phone at this stage.

## Accessibility follow-up, 13 September 2026

The concept found in the code: a Flutter interface with CameraX and Android AI processing for objects, OCR, family, metric depth, Whisper, and Indonesian TTS. The initial mode is offline; online photo description is enabled explicitly through the settings.

Static analysis with `flutter analyze` passed with no issues.

Changes at this stage:

- A usage guide that can be read aloud, covering how to use the modes and the voice commands. An active process stops when the guide opens; closing the guide stops it being read. The guide does not replace the last result.
- The home screen status uses a semantic live region. Results sent to TTS do not request an additional live region announcement; when the TTS call fails, a TalkBack announcement is enabled as a fallback.
- The Ulangi button is disabled during recording and processing.

Automated verification: 13 Flutter tests passed, including four new tests for the guide, the last result, recording cancellation, the semantic live region fallback, and the guide's appearance on a 360 × 800 screen at text scale 2. The tests mock the Android channels; these results do not demonstrate camera operation, AI recognition quality, or speech output on a device.

No new APK was built at this stage. The next direct tests: TalkBack without looking at the screen, Indonesian TTS present and absent, reading the guide and stopping it, and the voice commands on the Redmi. Model accuracy and latency have not been measured.

The verification environment calls `.tools/flutter/bin/flutter.bat` directly, because the PowerShell policy blocks the wrapper script. The Git `safe.directory` exception for the SDK folder is granted only through process environment variables; the global Git configuration was not changed.
