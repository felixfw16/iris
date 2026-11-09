# Models and inference contracts

Every model is a pretrained baseline. Versions and hashes are recorded in `models.lock.json`; no accuracy target has been demonstrated on the Redmi.

| Function | Model/runtime | Contract |
| --- | --- | --- |
| Objects | YOLOv8n Open Images V7, ONNX Runtime | RGB 640×640 float32 /255, letterbox RGB 114; NCHW 1×3×640×640; output 1×605×8400 (xywh plus 601 scores), threshold 0.4, cross-class NMS IoU 0.5, at most 10 objects |
| Faces | ML Kit plus MobileFaceNet | Two-eye alignment, RGB 112×112 float32 `(pixel−128)/128`; 192-dimension embedding, L2 normalized |
| Distance | YOLO26n-depth, ONNX Runtime CPU | RGB /255, letterbox RGB 114 at 640×640; ONNX input NCHW 1×3×640×640, output 1×1×640×640 in metres |
| Text | ML Kit Text Recognition Latin, bundled | Upright photo, printed Latin text |
| Rupiah | ML Kit OCR plus text matching rules | BANK INDONESIA and RUPIAH must be present, along with a single matching numeric and spelled-out denomination; this is not a banknote classification or authentication model |
| Commands | Whisper tiny multilingual, whisper.cpp v1.8.3 | PCM mono 16 kHz, energy-based endpointing, 30 seconds maximum, language `id`, no-context, at most 4 CPU threads |
| Speech | Android TTS | An Indonesian voice that needs no network and carries no not-yet-installed marker |
| Online photo | OpenAI Responses API | JPEG with a long side <=1024 px; `store=false`, output capped at 600 tokens; model and key come from the settings |

## Local Qwen voice (0.5.0)

Qwen3.5-0.8B uses the LiteRT community dynamic INT8 conversion, a 2048 context, and the LiteRT-LM Android 0.17.0 CPU runtime. The repacked asset is 1,159,760,881 bytes, SHA-256 `49a077c27d63945da44289d8d8054cd231dfaaf5192167bff22f47ab9a258fc2`. The GabrieleConte conversion source is pinned to revision `766ec4afaaeeda64da162c458bac1efc0d27cf9e` in `models.lock.json`, with Apache-2.0 license metadata. The repack script adds hybrid attention state metadata and a conversation template; the hash of every weight shard is compared before and after the repack.

The input is a Whisper transcript, not pixels. Although the bundle ships a visual encoder and adapter, the application does not send images to Qwen. Every model question opens a new conversation; the engine is reused. The switch passes `enable_thinking` to the template and selects between a 128-token and a 512-token sampling and output budget. Text marked `<think>` is filtered before TTS; reasoning that does not finish produces a message suggesting another attempt with Thinking off.

Explicit camera questions route straight to `detect_objects` or `read_text`. A tool request from the model is accepted only for those two names. Camera results are narrated directly, with no further generation pass. This is tool selection driven by the question, not a hands-free mode or automatic navigation.

Earlier desktop experiment logs show inconsistent and repetitive general answers. A successful runtime load is not evidence of answer quality, Bahasa Indonesia comprehension, or Thinking behaviour. There is no on-device benchmark. The Qwen3-0.6B INT4 model from 0.4.0 is no longer an active asset.

## Depth and family

The YOLO26n-depth **metric depth** map is used directly, including the calibration built into the weights; there is no per-image scale alignment against ground truth. RGB is normalized /255. The letterbox preserves the image aspect and pads with RGB 114. ROI coordinates use the same scale and padding. One model serves both indoors and outdoors. The official export branch includes a 4× bilinear upsample back to the input size. The experimental 640 resolution differs from the weights' 768 training resolution and its accuracy needs testing. The current runtime is two-thread CPU, not GPU or NPU.

The ROI is the middle 40% of the bounding box. At least 70% of samples must fall within 0.5-5 m; the median absolute deviation must be <=max(0.25 m, 20% of the median). Three readings are matched by class and IoU >=0.5. Accept when all are available and each differs from the median by <=max(0.5 m, 20% of the median); speak the estimate rounded to 0.5 m. This is camera-axis depth, not a calibrated sensor. The fixed resolution and the letterbox need separate testing.

Family: five samples per profile, 20 profiles maximum. Matching averages the three highest cosine similarities. The initial 0.72 threshold and 0.08 candidate margin are **not calibrated**. Registration rejects multiple faces, faces that are too small, extreme angles, poor lighting, and poses too similar to an existing sample. The system is not authentication and has no liveness detection. Names are chosen by the user.

## Sources and licenses

- [Ultralytics Open Images V7](https://docs.ultralytics.com/datasets/detect/open-images-v7/): YOLOv8n, 601 classes, official assets v8.2.0 weights, source SHA-256 in `models.lock.json`, exporter 8.2.82, AGPL-3.0. The 601 label translations are in `scripts/object_labels_id.json`. Hierarchical classes can overlap; cross-class NMS reduces duplication, but it can also suppress distinct objects that overlap heavily. Per-class accuracy and speed on the Redmi have not been measured for the new model.
- [YOLO26n-depth](https://docs.ultralytics.com/tasks/depth): official Ultralytics assets `v8.4.0` weights, SHA-256 `befed1b8561d8b2eaa66274b070cdfc9c44853bda6d6d62a04759f9383af74e9`; exporter `ultralytics==8.4.150`, AGPL-3.0. The ONNX export was checked and compared against PyTorch on three synthetic inputs. That validates the export, not distance accuracy. It replaced two Depth Anything V2 models in 0.3.0; the old binaries are kept at `.models/previous-depth_*.onnx` on the migration machine.
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp): v1.8.3, revision `2eeeba56e9edd762b4b38467bab96c2517163158`, MIT. The tiny multilingual model comes from the ggerganov conversion repository at a pinned revision.
- [MobileFaceNet example](https://github.com/estebanuri/face_recognition): revision `dbf9732725cf1ab6e06b412651bb4858b5dfe0df`. The example repository carried no license metadata when checked; the weight license and the dataset origin are unverified. Readiness for public redistribution has not been established; the current prototype is for private demonstration.
- ML Kit and the Android SDK follow their publishers' terms. No OpenAI credentials are present in the assets.

Hashes are verified again during extraction on the device. Hugging Face models are compared against the publisher's LFS SHA-256; TFLite binaries are pinned by version and revision, and the downloaded hash is recorded. ONNX/PyTorch agreement on synthetic inputs is an export test, not evidence of real-world accuracy.
