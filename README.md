# IRIS

A Flutter and Android visual assistant built as a research prototype for an undergraduate thesis. IRIS recognises objects, reads printed text and rupiah denominations, recognises family faces, and estimates distance, with Bahasa Indonesia speech output.

**Version:** `0.5.0+5` · **Package:** `id.sahabatnetra.app` · **Platform:** Android 8.0+ (API 26), ARM64.

Test target: Redmi Note 13 5G, 8 GB RAM. The application starts in offline mode. On-device accuracy, latency, and accessibility testing is still required; see the [validation notes](VALIDATION.md).

## Features

| Feature | Implementation |
| --- | --- |
| Object scan | YOLOv8n Open Images V7, 601 classes; narrates up to 10 objects with left/front/right direction |
| Text reading | ML Kit OCR for Latin text |
| Rupiah reading | Matches the numeric and spelled-out denomination from OCR, not a banknote authenticity check |
| Family | MobileFaceNet; five face samples per profile, encrypted storage |
| Distance estimation | YOLO26n-depth; three consistent readings across a 0.5-5 m range |
| Voice command | Whisper tiny offline; recording ends after a pause in speech |
| Ask Qwen | Local Qwen3.5-0.8B INT8, optional Thinking, plus object detection and OCR tools |
| Photo description | Optional online service with a user-supplied API key and model |
| Accessibility | Offline Bahasa Indonesia TTS, TalkBack labels, spoken guide, Ulangi, and Berhenti |

Qwen receives a text transcript. Camera questions draw on detector and OCR results; the application does not yet send pixels directly to Qwen. The quality of Qwen's general answers is still experimental. There is no wake word, and no automatic session that reaches every feature without a button.

## Installing and using

1. Install the APK `build/app/outputs/flutter-apk/app-release.apk` on an ARM64 device. Models ship inside the APK and are copied to internal storage on use; allow several GB of free space for the installation and those copies.
2. Grant camera access and, when using voice, the microphone. Install an **offline Bahasa Indonesia** voice in the Android TTS settings. Check model and voice readiness through the application's Pengaturan (settings) screen.
3. Choose **Objek → Mulai pindai**, **Tulisan → Baca tulisan**, or **Keluarga → Kenali wajah**. Register family members through **Kelola wajah keluarga**, with a companion present.
4. For **Ukur jarak** (measure distance), hold the camera steady across three readings. The result is an estimate; one model serves both indoors and outdoors.
5. For **Baca rupiah** (read rupiah), aim at a single banknote so that the words BANK INDONESIA, the numeric denomination, and the spelled-out denomination are legible. Unclear or non-matching results are rejected. Coins are not read.
6. Press **Perintah** (command), wait for the microphone-ready status, then say: `pindai`, `tulisan`, `keluarga`, `jarak`, `rupiah`, `jelaskan foto`, `ulangi`, or `berhenti`. Recording ends after a pause of about one second, waits up to eight seconds if no speech has started, and is capped at 30 seconds.
7. Press **Tanya dengan suara** (ask by voice) to ask Qwen a question locally. Examples: "Di depan saya ada apa?" or "Bacakan tulisan ini". Thinking is off by default; the output budget is 128 tokens, or 512 when it is on.
8. **Berhenti** (stop) cancels processing and speech. An initial model load may still have to finish. **Ulangi** (repeat) speaks the last result again; **Panduan penggunaan** (usage guide) provides instructions that can be read aloud.

For online photo description, fill in an API key and an image-capable model in Pengaturan, enable online mode, then press **Jelaskan foto**. One photo is sent to the service; narration still uses the device TTS.

## Building the APK

The project environment uses Flutter **3.47.4**, Dart **3.13.3**, JDK 17+ (the build machine uses JBR 21), Android SDK 36, NDK 28.2.13676358, CMake 3.22.1, and Gradle 9.3.1. The project-local Flutter SDK lives in `.tools/flutter`.

Once the SDK, the Whisper sources, and every model asset are available:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/flutter.ps1 pub get
powershell -ExecutionPolicy Bypass -File scripts/flutter.ps1 analyze --no-pub
powershell -ExecutionPolicy Bypass -File scripts/flutter.ps1 test --no-pub
powershell -ExecutionPolicy Bypass -File scripts/flutter.ps1 build apk --release --target-platform android-arm64 --no-pub
python scripts/verify_qwen_apk.py
```

**Result:** `build/app/outputs/flutter-apk/app-release.apk`. The APK uses a debug signing key for demos. APK binaries, models, SDKs, caches, and credentials are not committed to Git.

If Git reports different ownership for the SDK, apply an exception for that terminal process:

```powershell
$env:GIT_CONFIG_COUNT = '1'
$env:GIT_CONFIG_KEY_0 = 'safe.directory'
$env:GIT_CONFIG_VALUE_0 = "$($PWD.Path.Replace('\', '/'))/.tools/flutter"
```

If the Gradle cache sits under a different user profile from the build process, point `GRADLE_USER_HOME` at the matching cache directory. On this development machine: `C:/Users/felix/.gradle`.

## Preparing assets from source

Large models and vendor runtimes are gitignored. Cloning the repository is not enough for a complete build.

```powershell
git -c core.longpaths=true clone --depth 1 --branch 3.47.4 https://github.com/flutter/flutter.git .tools/flutter
git -c core.longpaths=true clone --depth 1 --branch v1.8.3 https://github.com/ggml-org/whisper.cpp.git android/app/src/main/cpp/whisper.cpp
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r scripts/model-requirements.txt --extra-index-url https://download.pytorch.org/whl/cpu
.\.venv\Scripts\python.exe -m pip install --no-deps --target .tools/depth-python ultralytics==8.4.150 filelock==3.20.3
.\.venv\Scripts\python.exe scripts/prepare_models.py
```

`prepare_models.py` prepares the base models, the object detector, and depth. The object exporter uses Ultralytics 8.2.82; the depth exporter uses a separate 8.4.150 installation. The ONNX/PyTorch checks confirm export consistency, not on-device accuracy.

**Qwen 0.5.0 requires extra steps.** `scripts/prepare_qwen35_bundle.py` uses the `litert-lm-builder==0.17.0` package, the `.models/qwen35_mm_q8_ekv2048.litertlm` source, and `.models/qwen35-tokenizer-config.json`. Model sources and checksums are in [models.lock.json](models.lock.json); the script verifies the template checksum. All three prerequisites must be present before running:

```powershell
python -m pip install --target .tools/litert-validation/python litert-lm-builder==0.17.0
python scripts/prepare_qwen35_bundle.py
```

The script updates the runtime and template metadata, confirms the weights are unchanged, then writes the assets and the manifest. Preparing Qwen from a fresh checkout is not yet a single download command. Do not use `prepare_qwen.py` for a 0.5.0 build: that script prepares the older Qwen3 model. Do not run `prepare_models.py --legacy-depth` for the current runtime.

Every asset is SHA-256 verified during a release build and during extraction on the device. Model details, preprocessing, sources, and license limits are in [MODEL_CARD.md](MODEL_CARD.md).

## Project structure

```text
lib/                         Flutter interface, narration, and command mapping
android/app/src/main/kotlin/  Native camera, inference, speech, and storage
android/app/src/main/cpp/     Whisper JNI and CMake
test/                        Flutter tests and native Java checks
scripts/                     Model preparation, build, and APK audit
evaluation/                  Protocols, tool schemas, and research CSVs
models.lock.json             Model versions, sources, and checksums
```

- [PROGRESS.md](PROGRESS.md): implementation status and follow-up work.
- [VALIDATION.md](VALIDATION.md): test results, builds, and APK checksums.
- [evaluation/PROTOCOL.md](evaluation/PROTOCOL.md): the data collection procedure. Run `python scripts/evaluate.py evaluation` to aggregate the CSVs; empty data does not count as a pass.

## Privacy and usage limits

Offline mode does not call the online photo service. Family profiles are stored encrypted with the Android Keystore; camera photos are not saved to the gallery and application backup is disabled. The runtime CSV records the operation, time, latency, and success status.

Accuracy and performance on the Redmi have not been measured. Face recognition has no liveness detection and is not authentication. A rupiah reading does not prove a banknote is genuine. Distance estimates and object detection do not replace a mobility aid and do not guarantee a safe path. Each model's license status is listed in the model card; this project is a research and demo prototype.
