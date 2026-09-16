# Progres IRIS 0.5.0

Dokumen ini menggantikan audit 0.2.0–0.4.0 yang belum mencerminkan implementasi terbaru. Versi sumber: `0.5.0+5`, paket `id.sahabatnetra.app`.

## Implementasi tersedia

| Bagian | Status versi 0.5.0 |
| --- | --- |
| Kamera | CameraX, frame bersama, penghentian saat aplikasi masuk latar |
| Objek | YOLOv8n Open Images V7, 601 kelas, pemindaian kontinu setelah tombol diaktifkan |
| Tulisan dan rupiah | OCR ML Kit; validasi nominal angka dan huruf |
| Keluarga | Lima sampel/profil, MobileFaceNet, penyimpanan terenkripsi |
| Jarak | YOLO26n-depth tunggal; konsistensi tiga pembacaan |
| Suara | Whisper tiny dan endpoint berbasis energi; jeda akhir sekitar satu detik, batas 30 detik |
| Qwen lokal | Qwen3.5-0.8B INT8, LiteRT-LM 0.17.0 CPU, Thinking dan pembatalan |
| Alat kamera Qwen | `detect_objects` dan `read_text`; permintaan eksplisit diarahkan langsung, JSON dari model divalidasi terhadap dua alat tersebut |
| Narasi kamera | Hasil alat dibacakan langsung agar model tidak menambahkan objek atau jarak |
| Aksesibilitas | TTS Indonesia offline, TalkBack, panduan, Ulangi/Berhenti |
| Foto online | Integrasi opsional yang memerlukan pengaturan dan kredensial pengguna |

## Penyelesaian rilis

- [x] Selaraskan README dan model card dengan kode 0.5.0.
- [x] Periksa analisis statis dan 21 tes Flutter.
- [x] Jalankan 5 skenario endpoint suara dan 6 skenario perutean alat kamera.
- [x] Build APK 0.5.0 dan audit signature, metadata, runtime ARM64, serta checksum model; hasil di VALIDATION.md.

## Pekerjaan yang memerlukan pengujian lanjutan

- Uji APK di Redmi: izin, kamera, TalkBack, suara Indonesia, penggunaan RAM, suhu, latensi, dan penghentian inferensi.
- Ukur akurasi objek, OCR, wajah, jarak, dan suara menggunakan data nyata dalam `evaluation/`.
- Evaluasi jawaban Qwen dan Thinking. Log eksperimen desktop sebelumnya menunjukkan jawaban tidak konsisten dan pengulangan teks; keberhasilan memuat model belum membuktikan kualitas jawaban.
- Lengkapi otomatisasi penyiapan sumber/template Qwen pada checkout baru.

## Cakupan lanjutan yang belum diimplementasikan

Wake word, sesi hands-free kontinu, pemilihan otomatis semua mode berdasarkan konteks, pengukuran depth kontinu, dan input gambar langsung ke Qwen belum tersedia. Pemilihan dua alat kamera berdasarkan pertanyaan suara sudah tersedia, tetapi bukan pengendali otomatis seluruh aplikasi.

Tidak diberikan persentase selesai tanpa kriteria penerimaan dan data pengguna. Status saat ini adalah prototipe terintegrasi untuk validasi perangkat; hasil build dan tes bukan hasil eksperimen akurasi.
