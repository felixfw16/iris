# IRIS 0.5.0 progress

This document supersedes the 0.2.0-0.4.0 audits, which no longer reflect the current implementation. Source version: `0.5.0+5`, package `id.sahabatnetra.app`.

## Implemented

| Area | Status at 0.5.0 |
| --- | --- |
| Camera | CameraX, shared frames, stops when the application goes to the background |
| Objects | YOLOv8n Open Images V7, 601 classes, continuous scanning once the button is enabled |
| Text and rupiah | ML Kit OCR; numeric and spelled-out denominations validated against each other |
| Family | Five samples per profile, MobileFaceNet, encrypted storage |
| Distance | A single YOLO26n-depth model; three readings for consistency |
| Voice | Whisper tiny with energy-based endpointing; about a one-second trailing pause, 30-second cap |
| Local Qwen | Qwen3.5-0.8B INT8, LiteRT-LM 0.17.0 CPU, Thinking and cancellation |
| Qwen camera tools | `detect_objects` and `read_text`; explicit requests route directly, and JSON from the model is validated against those two tools |
| Camera narration | Tool results are read out directly, so the model cannot add objects or distances of its own |
| Accessibility | Offline Bahasa Indonesia TTS, TalkBack, guide, Ulangi/Berhenti |
| Online photo | An optional integration requiring user settings and credentials |

## Release completion

- [x] Align the README and the model card with the 0.5.0 code.
- [x] Check static analysis and the 21 Flutter tests.
- [x] Run the 5 voice endpoint scenarios and the 6 camera tool routing scenarios.
- [x] Build the 0.5.0 APK and audit the signature, metadata, ARM64 runtime, and model checksums; results in VALIDATION.md.

## Work that needs further testing

- Test the APK on the Redmi: permissions, camera, TalkBack, the Indonesian voice, RAM use, temperature, latency, and inference cancellation.
- Measure object, OCR, face, distance, and voice accuracy against real data in `evaluation/`.
- Evaluate Qwen's answers and Thinking. Earlier desktop experiment logs show inconsistent answers and repeated text; loading the model successfully is not evidence of answer quality.
- Finish automating Qwen source and template preparation on a fresh checkout.

## Scope not yet implemented

A wake word, a continuous hands-free session, automatic context-driven selection across every mode, continuous depth measurement, and direct image input to Qwen are all unavailable. Selecting between two camera tools from a spoken question does work, but it is not an automatic controller for the whole application.

No completion percentage is given without acceptance criteria and user data. The current state is an integrated prototype awaiting on-device validation; build and test results are not accuracy experiment results.
