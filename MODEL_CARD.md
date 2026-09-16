# Model dan kontrak inferensi

Seluruh model adalah baseline pretrained. Versi dan hash dicatat di `models.lock.json`; target akurasi belum dibuktikan pada Redmi.

| Fungsi | Model/runtime | Kontrak |
| --- | --- | --- |
| Objek | YOLOv8n Open Images V7, ONNX Runtime | RGB 640×640 float32 /255, letterbox RGB 114; NCHW 1×3×640×640; output 1×605×8400 (xywh + 601 skor), threshold 0,4, NMS lintas kelas IoU 0,5, maksimal 10 objek |
| Wajah | ML Kit + MobileFaceNet | Alignment dua mata, RGB 112×112 float32 `(pixel−128)/128`; embedding 192 dimensi, normalisasi L2 |
| Jarak | YOLO26n-depth, ONNX Runtime CPU | RGB /255, letterbox RGB 114 pada 640×640; ONNX input NCHW 1×3×640×640, output 1×1×640×640 dalam meter |
| Tulisan | ML Kit Text Recognition Latin bundled | Foto upright, teks cetak Latin |
| Rupiah | OCR ML Kit + aturan pencocokan tulisan | Harus ada BANK INDONESIA, RUPIAH, serta nominal angka dan huruf yang cocok dan tunggal; bukan model klasifikasi uang atau autentikasi |
| Perintah | Whisper tiny multilingual, whisper.cpp v1.8.3 | PCM mono 16 kHz, endpoint berbasis energi, maksimum 30 detik, bahasa `id`, no-context, CPU maksimal 4 thread |
| Suara | Android TTS | Voice Indonesia tanpa kebutuhan jaringan dan tanpa penanda voice belum terpasang |
| Foto online | OpenAI Responses API | JPEG sisi panjang <=1024 px; `store=false`, output maksimum 600 token; model/key dari pengaturan |

## Qwen suara lokal (0.5.0)

Qwen3.5-0.8B memakai konversi komunitas LiteRT dynamic INT8, konteks 2048, dan runtime LiteRT-LM Android 0.17.0 CPU. Aset hasil repack berukuran 1.159.760.881 byte, SHA-256 `49a077c27d63945da44289d8d8054cd231dfaaf5192167bff22f47ab9a258fc2`. Sumber konversi GabrieleConte dipatok revisi `766ec4afaaeeda64da162c458bac1efc0d27cf9e` dalam `models.lock.json`, dengan metadata lisensi Apache-2.0. Skrip repack menambahkan metadata state hybrid attention dan template percakapan; hash setiap bagian bobot dibandingkan sebelum dan sesudah repack.

Input berasal dari transkrip Whisper, bukan piksel. Meskipun bundle menyertakan encoder/adapter visual, aplikasi tidak mengirim gambar langsung ke Qwen. Setiap pertanyaan model membuat percakapan baru; engine dipakai ulang. Switch mengirim `enable_thinking` ke template dan membedakan sampling/anggaran keluaran 128 atau 512 token. Teks bertanda `<think>` disaring sebelum TTS; penalaran yang tidak selesai menghasilkan pesan untuk mencoba tanpa Thinking.

Pertanyaan kamera eksplisit diteruskan langsung ke `detect_objects` atau `read_text`. Permintaan alat dari model hanya menerima dua nama tersebut. Hasil kamera dinarasikan langsung tanpa putaran generasi tambahan. Ini pemilihan alat berdasarkan pertanyaan, bukan mode hands-free atau navigasi otomatis.

Log eksperimen desktop sebelumnya menunjukkan jawaban umum yang tidak konsisten dan berulang. Keberhasilan pemuatan runtime bukan bukti kualitas jawaban, pemahaman Bahasa Indonesia, atau Thinking. Belum ada benchmark HP. Model Qwen3-0.6B INT4 versi 0.4.0 tidak lagi menjadi aset aktif.

## Kedalaman dan keluarga

Peta **metric depth** YOLO26n-depth dipakai langsung, termasuk kalibrasi bawaan bobot; tidak ada penyelarasan skala per gambar terhadap ground truth. RGB dinormalisasi /255. Letterbox mempertahankan aspek gambar dan diisi RGB 114. Koordinat ROI memakai skala/padding yang sama. Satu model dipakai untuk dalam dan luar ruangan. Export branch resmi menyertakan upsampling bilinear 4× menjadi ukuran input. Resolusi eksperimen 640 berbeda dari resolusi training bobot 768 dan perlu diuji akurasinya. Runtime saat ini CPU dua thread, belum GPU/NPU.

ROI adalah 40% tengah bounding box. Minimal 70% sampel berada di 0,5–5 m; median absolute deviation <=max(0,25 m, 20% median). Tiga pembacaan dicocokkan menurut kelas/IoU >=0,5. Terima jika semuanya tersedia dan selisih dari median <=max(0,5 m, 20% median); ucapkan perkiraan dibulatkan 0,5 m. Ini kedalaman sumbu kamera, bukan sensor terkalibrasi. Fixed resolution dan letterbox harus diuji tersendiri.

Keluarga: lima sampel/profil, maksimum 20 profil. Matching memakai rata-rata tiga cosine similarity tertinggi. Threshold awal 0,72 dan margin kandidat 0,08 **belum dikalibrasi**. Pendaftaran menolak wajah ganda, terlalu kecil, sudut ekstrem, cahaya buruk, dan pose terlalu mirip. Sistem bukan autentikasi dan tidak memiliki liveness detection. Nama ditentukan pengguna.

## Sumber dan lisensi

- [Ultralytics Open Images V7](https://docs.ultralytics.com/datasets/detect/open-images-v7/): YOLOv8n 601 kelas, bobot resmi assets v8.2.0, SHA-256 sumber di `models.lock.json`, exporter 8.2.82, AGPL-3.0. Terjemahan 601 label ada di `scripts/object_labels_id.json`. Kelas berjenjang dapat berimpit; NMS lintas kelas mengurangi duplikasi, tetapi juga bisa menekan benda berbeda yang sangat berimpit. Akurasi per kelas dan kecepatan di Redmi belum diukur untuk model baru.
- [YOLO26n-depth](https://docs.ultralytics.com/tasks/depth): bobot resmi Ultralytics assets `v8.4.0`, SHA-256 `befed1b8561d8b2eaa66274b070cdfc9c44853bda6d6d62a04759f9383af74e9`; exporter `ultralytics==8.4.150`, AGPL-3.0. ONNX diperiksa dan dibandingkan dengan PyTorch pada tiga input sintetis. Ini validasi ekspor, bukan pengujian akurasi jarak. Menggantikan dua model Depth Anything V2 sejak 0.3.0; biner lama disimpan di `.models/previous-depth_*.onnx` pada komputer migrasi.
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp): v1.8.3, revisi `2eeeba56e9edd762b4b38467bab96c2517163158`, MIT. Model tiny multilingual dari repositori konversi ggerganov dipatok revisinya.
- [Contoh MobileFaceNet](https://github.com/estebanuri/face_recognition): revisi `dbf9732725cf1ab6e06b412651bb4858b5dfe0df`. Repositori contoh tidak mencantumkan metadata lisensi saat diperiksa; lisensi bobot dan asal dataset belum terverifikasi. Kesiapan redistribusi publik belum dinyatakan; prototipe saat ini untuk demo pribadi.
- ML Kit/Android SDK mengikuti ketentuan penerbit. Tidak ada kredensial OpenAI dalam aset.

Hash diverifikasi kembali saat ekstraksi di HP. Model Hugging Face dibandingkan dengan SHA-256 LFS penerbit; biner TFLite dipatok versi/revisi dan hash hasil unduhan dicatat. Kesamaan ONNX/PyTorch pada input sintetis adalah uji ekspor, bukan bukti akurasi dunia nyata.
