# Redmi Note 13 5G test protocol

The research targets are not results already achieved. Every CSV column starts empty. Fill them only from real trials, use pseudonymous IDs for people, and never store faces in a CSV.

## Preparation

- Record the Android/HyperOS version, physical RAM, APK version, `models.lock.json`, TTS engine and voice, battery condition, and starting temperature. Use a release APK for performance measurement.
- Download the offline Indonesian voice, then retest with airplane mode on and Wi-Fi off. Reopen the application after a force-stop to test cold start.
- Keep threshold calibration sessions separate from test sessions. Do not change a threshold based on test data. The initial face threshold of 0.72 with a 0.08 margin is an uncalibrated baseline.
- Test TalkBack without looking at the screen: choosing a mode, start and stop, repeat, and voice commands. The indoor and outdoor commands no longer switch a profile and return a fixed statement, so test that reply rather than a profile change. Avoid TTS announcements that collide with TalkBack.

## Objects

20 focus classes: orang, kursi, sofa, meja makan, tempat tidur, botol, cangkir, buku, ponsel, laptop, televisi, ransel, payung, kucing, anjing, sepeda, sepeda motor, mobil, bus, bangku. These are the Indonesian label strings the application narrates, so they are left untranslated; match each one against the label values in `object_classes.json` before scoring. Pick the matching label from the Open Images V7 model; the detector does not cover every object or road hazard.

For each class, capture at least 20 separate test scenes, bright and dim lighting, light occlusion, and different backgrounds. Count TP/FP/FN against the annotations at IoU >= 0.5. Use the narrated output, which the decoder caps at 10 objects, consistently when evaluating the application experience, and do not equate it with whole-detector mAP. Initial targets: precision >= 85%, recall >= 75%.

## Distance

Place the object at 0.5, 1, 1.5, 2, 3, 4, and 5 metres. At least 5 repetitions per distance for indoor and outdoor, with the camera still during the three-frame measurement. Measure depth along the camera axis to the object surface with a tape measure, and do not mix slant range with optical-axis depth. Start with objects near the centre of the frame.

Leave estimate_m empty when the application rejects a result. Report MAE over the available results AND coverage over all trials, per environment, distance, and class. Initial target MAE <= 0.5 m. Do not conclude accuracy from rounded results without stating the rounding. The YOLO26n-depth model and the letterbox still need validation on this device's camera. There is no automatic camera calibration and no depth sensor.

## Faces

Register 5 angles per person together with a helper. Capture the test data in a separate session, not the five registration photos. Use at least 5 profiles where available, plus people who are not registered. Record `unknown` for an unrecognised person or an application refusal. Targets: known accuracy >= 90%, false accept <= 1%. Use enough negative trials and report their count, not a percentage without a sample size. The system is not authentication and has no liveness detection.

## Text and voice commands

OCR: at least 30 printed Latin text samples, with varying length, distance, and light. Compare verbatim text through character error rate, target <= 10%. Handwriting is not promised.

Voice: test 11 commands (pindai, tulisan, keluarga, jelaskan foto, ulangi, berhenti, indoor, outdoor, jarak, rupiah, and an unrecognised command), each 10 times in quiet and in noisy conditions. Recording starts after the microphone button, ends after a pause of about one second, waits up to eight seconds without speech, and is capped at 30 seconds. It is not a wake word. Test utterances longer than four seconds, a pause mid-sentence, silence, impulse sounds, and continuous noise. Target success in quiet conditions >= 90%.

Qwen: separate general questions, object requests, and OCR requests. Record tool-selection correctness, whether the answer matches the camera result, repeated answers, Thinking on and off, and cancellation during loading and during generation. Report failures and time-to-TTS separately from interface test successes.

## Performance and failures

Export the runtime CSV from Pengaturan. Compute median and p95 per operation, and distinguish cold from warm start. Native detector latency is not the same as end-to-end time to speech. Measure end-to-end time separately. Initial targets: objects <= 2 seconds, distance, OCR, and voice <= 5 seconds once the input is available. Distance uses three inferences, so it can be slower. Report the actual values without quietly replacing a target.

20 minute test: temperature, battery, delayed frames, RAM use, denied permission, camera held by another application, application backgrounded, stale results after a stop, a corrupt model, family not yet registered, the Indonesian voice not installed, network loss, a wrong API key, exhausted quota, and cancelling a GPT request.

Run `python scripts/evaluate.py evaluation` to aggregate the CSVs. Empty data yields null, not a success figure.
