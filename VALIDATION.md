# Catatan validasi

## Qwen suara / versi 0.4.0 — 13 September 2026

- APK final berhasil: `build/app/outputs/flutter-apk/app-release.apk`, 667.515.735 byte (636,6 MiB), versi `0.4.0` (4), paket `id.sahabatnetra.app`, minimum API 26, target API 36. Log `build/apk-build-qwen.log`; Gradle sekitar 38,2 detik.
- SHA-256 APK: `570d6bb00d72fbffb6d1b168982ce085b09d41373174bbfa02c0a4d7379a9e8b`.
- `flutter analyze`: tanpa masalah. `flutter test`: 21 tes lulus; log `build/qwen-tests.log`. Tes baru memverifikasi switch Thinking diteruskan ke native, jawaban diteruskan ke TTS, Thinking awal mati, dan jawaban terlambat setelah Berhenti tidak dibacakan. Kanal native memakai mock; inferensi model tidak diuji oleh tes Flutter.
- Kompilasi release Kotlin dan integrasi LiteRT-LM 0.17.0 lulus. Kotlin 2.4.0 diperlukan oleh metadata pustaka. Flutter masih memberi peringatan migrasi Built-in Kotlin untuk versi mendatang.
- `apksigner verify --verbose` lulus signature v2; signing tetap debug key untuk demo. Semua checksum model dalam APK sesuai manifest, runtime LiteRT-LM tersedia, dan tidak ada folder potongan unduhan `.parts` dalam paket. Audit dapat diulang dengan `python scripts/verify_qwen_apk.py`.
- Header model yang dipaketkan memuat template `enable_thinking` serta kanal `thought`. Runtime mengirim switch tersebut, membatasi keluaran menjadi 128/512 token, dan hanya meneruskan konten jawaban ke TTS; markup reasoning tambahan disaring.
- Tombol Berhenti/onPause/onDestroy meminta pembatalan inferensi native. Pemuatan model pertama tidak dapat langsung dibatalkan; pemeriksaan generation mencegah inferensi berikutnya dan hasil lama dibacakan.

APK belum dipasang atau diuji di HP. Kecepatan, konsumsi RAM, mutu jawaban Indonesia, perilaku Thinking, dan pembatalan native masih perlu pengujian perangkat. Qwen menerima transkrip teks; belum ada pemahaman gambar Qwen, wake word, atau pemilihan fitur otomatis. Versi ini mempertahankan YOLO26n-depth dan detektor objek sebelumnya.

## YOLO26n-depth / versi 0.3.0 — 13 September 2026

- Dua model Depth Anything V2 diganti dengan satu YOLO26n-depth ONNX; input RGB /255, letterbox 640×640 RGB 114, output `[1,1,640,640]` meter. Android memakai ONNX Runtime CPU dua thread. Pilihan profil indoor/outdoor dihapus; detektor objek 601 kelas tetap.
- Bobot resmi SHA-256 diverifikasi terhadap digest GitHub release. ONNX checker lulus; keluaran ONNX dibandingkan PyTorch pada input random, abu-abu, dan hitam dengan toleransi rtol/atol 0,005. Selisih absolut maksimum 0,0002594. Ini validasi numerik ekspor, bukan akurasi pengukuran nyata.
- Model ONNX baru: 20.740.729 byte. Model depth lama disimpan di `.models/previous-depth_*.onnx` dan tidak ikut APK.
- `flutter analyze`: tanpa masalah. `flutter test`: 19 tes lulus, termasuk status kesiapan model depth tunggal. Tes native Android tidak dijalankan ulang pada tahap ini; Kotlin release berhasil dikompilasi dalam build APK.
- APK: `build/app/outputs/flutter-apk/app-release.apk`, 274.169.584 byte (261,5 MiB), versi `0.3.0` (3), paket `id.sahabatnetra.app`, min SDK 26, target SDK 36.
- SHA-256 APK: `c65cf0e1c8cf9cd0376423a55375152f27d14c0ace38acb7cff17dc7a559adaa`.
- `apksigner verify --verbose` lulus, signature v2 dengan debug signing demo. Semua hash model dalam arsip APK cocok dengan manifest; kedua aset depth lama tidak ada.
- Log: `build/depth-export.log`, `build/apk-build-yolo-depth.log`. Gradle release selesai sekitar 71,5 detik.

Belum diuji di Redmi: latensi, akurasi meter, konsumsi baterai, dan suhu. Latensi ONNX desktop pada tiga input sintetis sekitar 333–419 ms, bukan benchmark HP. Alur ukur masih tiga pembacaan berurutan dan narasi dibulatkan 0,5 m; versi ini belum mengimplementasikan depth kontinu near real-time. Model baru belum dikalibrasi memakai pengukuran jarak nyata. Tidak ada LLM/VLM baru dalam APK.

## Audit dan build ulang versi 0.2.0 — 13 September 2026

- `flutter analyze`: lulus tanpa masalah.
- `flutter test`: seluruh 18 tes lulus. Tes Flutter memakai mock kanal native.
- Tes native `:app:testDebugUnitTest` belum berhasil dijalankan: percobaan online tertahan pada jaringan dan dihentikan; percobaan offline mengidentifikasi artefak Flutter `arm64_v8a_debug` dan `x86_64_debug` revisi engine `0e228ec8c8d2abc9fcf1d053e8a40665bb859ec7` belum ada di cache. Log: `build/android-tests-offline.log`. Ini kegagalan resolusi dependensi sebelum eksekusi tes, bukan hasil assertion. Konfigurasi saat ini hanya menyediakan task unit test debug; `testReleaseUnitTest` tidak tersedia.
- Build release dari sumber saat ini berhasil: `build/app/outputs/flutter-apk/app-release.apk`.
- Log build terbaru: `build/apk-build-current.log`; waktu Gradle sekitar 73,7 detik.
- Ukuran: 449.043.109 byte (428,2 MiB).
- Metadata diperiksa dengan `aapt`: paket `id.sahabatnetra.app`, versi `0.2.0` (2), min SDK 26, target SDK 36.
- `apksigner verify --verbose` lulus, signature v2; masih debug signing untuk demo.
- SHA-256: `467c3ffd684124d9dae2b9e1e0109a3cb16cf95db520b84e1546b5448000b252`.
- Aset YOLO 601 kelas, label, MobileFaceNet, Whisper, kedua model depth, dan manifest ada di APK. Aset EfficientDet lama juga masih ikut terpaket. Task release memverifikasi checksum aset wajib.
- Target Flutter ARM64; inspeksi arsip masih menemukan native libraries ARMv7/x86_64 juga. Jangan menganggap ini dukungan aplikasi untuk ABI tersebut.
- Build mengeluarkan peringatan migrasi Kotlin Gradle Plugin/built-in Kotlin; tidak menggagalkan build ini.

Lingkungan build memerlukan `GRADLE_USER_HOME=C:/Users/felix/.gradle` karena default proses sempat mengarah ke `C:/.gradle`. SDK Flutter memakai pengecualian ownership Git khusus proses, dengan path slash `/`. Tidak ada perubahan konfigurasi Git global.

```powershell
$env:GIT_CONFIG_COUNT='1'
$env:GIT_CONFIG_KEY_0='safe.directory'
$env:GIT_CONFIG_VALUE_0='C:/Users/felix/OneDrive/Desktop/prototype-skripsi/.tools/flutter'
$env:GRADLE_USER_HOME='C:/Users/felix/.gradle'
& .\.tools\flutter\bin\flutter.bat build apk --release --target-platform android-arm64
```

APK belum dipasang atau diuji di HP pada audit ini. LLM lokal, pemilihan mode otomatis, dan wake word belum diimplementasikan. Audit fitur dan rancangan kelanjutan ada di `PROGRESS.md`. Bagian berikut merupakan riwayat validasi versi sebelumnya.

## Build APK — 13 September 2026

APK release berhasil dibangun di `build/app/outputs/flutter-apk/app-release.apk` dengan perintah `flutter build apk --release --target-platform android-arm64`. Log: `build/apk-build.log` (Gradle `BUILD SUCCESSFUL`). Ukuran berkas 457.924.327 byte, sekitar 436,7 MiB.

- Memperbaiki referensi `MessageDigest` pada skrip Gradle melalui import eksplisit; pemeriksaan checksum kelima model tetap dijalankan dan lulus.
- `apksigner verify --verbose` lulus dengan signature v2. Signing masih memakai debug key sesuai konfigurasi demo proyek.
- Metadata APK: `id.sahabatnetra.app`, versi `0.1.0` (1), minimum Android API 26, target API 36.
- Isi APK diverifikasi mencakup kelima model, manifest model, serta `libapp.so`, `libflutter.so`, dan `libnetra_whisper.so` ARM64. Paket juga mengandung pustaka ABI lain dari konfigurasi build; ini bukan APK yang seluruh isinya hanya ARM64.
- SHA-256: `33bd671f48db8776044999d204759bceb1d2b85dc13de85744fae01237d12c3e`.

APK belum dipasang atau diuji langsung di HP pada tahap ini.

## Kelanjutan aksesibilitas — 13 September 2026

Konsep yang ditemukan dalam kode: antarmuka Flutter dengan CameraX dan pemrosesan AI Android untuk objek, OCR, keluarga, metric depth, Whisper, serta TTS Indonesia. Mode awal offline; penjelasan foto online diaktifkan secara eksplisit melalui pengaturan.

Pemeriksaan statis `flutter analyze` lulus tanpa masalah.

Perubahan pada tahap ini:

- Panduan penggunaan yang dapat dibacakan, termasuk cara menggunakan mode dan perintah suara. Proses aktif dihentikan saat panduan dibuka; menutup panduan menghentikan pembacaannya. Panduan tidak mengganti hasil terakhir.
- Status halaman utama menggunakan semantic live region. Hasil yang dikirim ke TTS tidak meminta pengumuman live region tambahan; ketika pemanggilan TTS gagal, pengumuman TalkBack diaktifkan sebagai cadangan.
- Tombol Ulangi dinonaktifkan selama perekaman dan pemrosesan.

Verifikasi otomatis: 13 tes Flutter lulus, termasuk empat tes baru untuk panduan, hasil terakhir, pembatalan rekaman, fallback semantic live region, dan tampilan panduan pada layar 360 × 800 dengan skala teks 2. Tes menggunakan mock kanal Android; hasil ini tidak membuktikan operasi kamera, kualitas pengenalan AI, atau keluaran suara pada perangkat.

APK baru belum dibangun pada tahap ini. Uji langsung berikutnya: TalkBack dengan layar tidak dilihat, TTS Indonesia tersedia/tidak tersedia, pembacaan panduan dan penghentiannya, serta perintah suara pada Redmi. Akurasi dan latensi model belum diukur.

Lingkungan verifikasi memakai `.tools/flutter/bin/flutter.bat` langsung karena kebijakan PowerShell memblokir skrip pembungkus. Pengecualian Git `safe.directory` untuk folder SDK diberikan hanya melalui variabel lingkungan proses; konfigurasi Git global tidak diubah.
