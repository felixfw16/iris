# Audit IRIS — 13 September 2026

Pembaruan 0.3.0: model jarak kini YOLO26n-depth ONNX 640×640 tunggal. Dropdown lingkungan dihapus. APK baru berhasil dibangun, 19 tes Flutter lulus; detail dan hash ada di `VALIDATION.md`. Bagian audit awal di bawah merekam kondisi sebelum penggantian depth. Near real-time kontinu dan LLM/VLM masih belum diimplementasikan.

Pembaruan 0.4.0: Qwen3-0.6B INT4 sudah diintegrasikan sebagai tanya jawab suara lokal melalui Whisper dan TTS, dengan switch Thinking dan pembatalan. Model belum diuji langsung di Redmi. Ini belum mengimplementasikan VLM, wake word, atau pemilihan mode otomatis. Audit di bawah merupakan riwayat sebelum integrasi tersebut.

## Posisi implementasi

Proyek sudah berupa aplikasi Flutter/Android dengan inferensi native, bukan hanya mockup. Versi sumber `0.2.0+2`, paket `id.sahabatnetra.app`, target proyek Redmi Note 13 5G RAM 8 GB. Workspace saat audit tidak memiliki metadata Git, sehingga perubahan tidak dapat dibandingkan dengan commit sebelumnya.

| Bagian | Yang tersedia dalam kode | Batas verifikasi |
| --- | --- | --- |
| Kamera | CameraX, frame bersama, pembatalan saat aplikasi tidak aktif | Belum diuji di HP pada audit ini |
| Objek | YOLOv8n Open Images V7 ONNX, 601 kelas, posisi dan narasi hingga 10 objek | Akurasi kelas dan latensi perangkat belum diukur |
| Tulisan/rupiah | ML Kit OCR; nominal rupiah dicocokkan angka dan huruf | Bukan autentikasi uang |
| Keluarga | ML Kit + MobileFaceNet, lima sampel, profil terenkripsi | Threshold belum dikalibrasi, belum ada liveness |
| Jarak | Depth Anything V2 Metric indoor/outdoor, penyaringan konsistensi tiga pembacaan | Perkiraan; belum ada validasi jarak nyata |
| Suara | Whisper tiny offline, rekaman empat detik, pemetaan kata kunci | Masih harus menekan Perintah; tidak ada wake word/VAD kontinu |
| Aksesibilitas | TTS Indonesia offline, semantic labels, panduan, ulangi/berhenti | Memerlukan pengujian TalkBack dan TTS nyata |
| Penjelasan foto | Integrasi layanan online opsional melalui pengaturan | Belum diuji dengan kredensial pada audit ini |
| Otomatisasi | Scan objek kontinu setelah diaktifkan | Belum ada pemilih mode otomatis atau LLM lokal |

Tidak diberikan persentase selesai karena kriteria penerimaan dan hasil uji pengguna belum tersedia. Status yang tepat: prototipe fitur terintegrasi; validasi perangkat dan pengalaman hands-free masih tertunda.

## Kelayakan LLM kecil

LLM lokal memungkinkan untuk memilih fungsi berdasarkan transkrip suara dan ringkasan hasil visual. Qwen3-0.6B adalah kandidat eksperimen, bukan model yang sudah terpasang atau terukur di Redmi. Model ini menerima teks; kamera tetap memerlukan detektor/OCR atau model multimodal tersendiri. Dokumentasi penerbit menyebut dukungan multibahasa, mode non-thinking, dan kompatibilitas llama.cpp. Referensi: [model card Qwen](https://huggingface.co/Qwen/Qwen3-0.6B), [llama.cpp Android](https://github.com/ggml-org/llama.cpp/blob/master/docs/android.md). Alternatif runtime Android: [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM), dengan model dalam format yang didukung.

Usulan awal: kuantisasi 4-bit, konteks pendek, keluaran satu tindakan terstruktur. Anggaran bobot mentah 0,6 miliar parameter × 4 bit sekitar 300 MB; ukuran berkas sebenarnya, buffer runtime, KV cache, dan total RAM akan lebih besar. Angka ini perhitungan kapasitas, bukan benchmark. Uji bersama kamera, YOLO, Whisper, dan depth sebelum memilih model final.

## Rancangan kelanjutan (belum diimplementasikan)

1. Tambahkan sesi otomatis di foreground setelah izin dan pengaturan awal. Kamera menghasilkan observasi objek, probe teks berkala, serta sinyal wajah. Hasil deteksi objek saja tidak cukup untuk menemukan semua teks/wajah.
2. Pengendali memilih satu pekerjaan pada satu waktu: objek sebagai default, baca teks saat teks stabil, baca nominal saat bukti rupiah cocok, kenali keluarga saat wajah cukup jelas. Tambahkan jeda pergantian mode, umur maksimum hasil, dan penekanan narasi berulang.
3. Wake word/VAD mengaktifkan Whisper tanpa tombol. Pisahkan penjadwalan audio dari worker inferensi visual; implementasi sekarang memakai satu worker. Sinkronkan dengan akhir TTS agar aplikasi tidak menafsirkan suaranya sendiri sebagai perintah.
4. LLM menafsirkan maksud lebih bebas, misalnya “ini uang berapa?” menjadi `rupiah`. Validasi keluaran terhadap daftar tindakan; timeout, keluaran tidak valid, atau bukti kurang kembali ke aturan dasar. “Berhenti” harus segera ditangani tanpa menunggu LLM. Tulisan dalam kamera diperlakukan sebagai data, bukan instruksi untuk pengendali.
5. Perintah suara eksplisit mengalahkan tebakan konteks. LLM tidak dapat mengetahui tujuan pengguna secara pasti dari gambar; bila beberapa tujuan sama-sama masuk akal, ajukan pertanyaan suara singkat. Unggahan foto tetap mengikuti pilihan online pengguna.
6. Ukur ketepatan pemilihan tindakan, pergantian mode salah, latency p50/p95, RAM puncak, suhu/baterai, keberhasilan berhenti, dan keberhasilan tugas dengan pengguna tunanetra. Bandingkan pengendali aturan dengan aturan + LLM untuk mengetahui manfaat model tambahan.

Target realistis adalah bebas memilih tombol selama sesi aktif, setelah setup awal. Jangan menyamakan otomatisasi pemilihan fitur dengan navigasi jalan yang terbukti aman. APK hasil audit ini tetap memakai alur manual yang sudah ada.
