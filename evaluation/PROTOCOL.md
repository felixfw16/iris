# Protokol pengujian Redmi Note 13 5G

Target penelitian bukan hasil yang telah dicapai. Semua kolom CSV dimulai kosong. Isi hanya dari percobaan nyata, gunakan ID samaran untuk orang, dan jangan simpan wajah dalam CSV.

## Persiapan

- Catat versi Android/HyperOS, RAM fisik, versi APK, `models.lock.json`, TTS engine/voice, kondisi baterai, dan suhu awal. Gunakan APK release untuk pengukuran performa.
- Unduh suara Indonesia offline, lalu uji ulang dengan mode pesawat dan Wi-Fi mati. Buka kembali aplikasi setelah force-stop untuk menguji cold start.
- Pisahkan sesi kalibrasi ambang dari sesi pengujian. Jangan mengubah ambang berdasarkan data uji. Ambang wajah awal 0,72 dengan margin 0,08 adalah baseline yang belum dikalibrasi.
- Uji TalkBack dengan layar tidak dilihat: pilih mode, mulai/berhenti, ulangi, perintah suara, dan perpindahan profil indoor/outdoor. Hindari pengumuman TTS yang bertabrakan dengan TalkBack.

## Objek

20 kelas fokus: orang, kursi, sofa, meja makan, tempat tidur, botol, cangkir, buku, ponsel, laptop, televisi, tas ransel, payung, kucing, anjing, sepeda, sepeda motor, mobil, bus, bangku. Pilih label yang sesuai dari model COCO; detektor tidak mencakup semua objek atau bahaya jalan.

Untuk setiap kelas, ambil minimal 20 adegan uji terpisah, pencahayaan terang/redup, oklusi ringan, dan latar berbeda. Hitung TP/FP/FN terhadap anotasi dengan IoU >= 0,5. Gunakan keluaran tampilan/top-3 secara konsisten jika mengevaluasi pengalaman aplikasi, jangan menyamakannya dengan mAP seluruh detektor. Target awal precision >= 85%, recall >= 75%.

## Jarak

Letakkan objek pada 0,5; 1; 1,5; 2; 3; 4; 5 meter. Minimal 5 pengulangan per jarak untuk indoor dan outdoor, kamera diam saat pengukuran tiga frame. Ukur kedalaman arah sumbu kamera ke permukaan objek dengan meteran; jangan mencampur jarak miring dengan optical-axis depth. Mulai dari objek dekat pusat gambar.

Isi estimate_m kosong jika aplikasi menolak hasil. Laporkan MAE pada hasil tersedia DAN coverage pada seluruh percobaan, per lingkungan/jarak/kelas. Target awal MAE <= 0,5 m; jangan menyimpulkan akurasi dari hasil yang dibulatkan tanpa menyebut pembulatan. Model Small dan letterbox perlu divalidasi di kamera perangkat ini. Tidak ada kalibrasi kamera otomatis atau sensor depth.

## Wajah

Daftarkan 5 sudut per orang bersama pendamping. Ambil data uji pada sesi lain, bukan lima foto pendaftaran. Gunakan minimal 5 profil jika tersedia serta orang yang tidak terdaftar. Catat `unknown` untuk orang tidak dikenal atau penolakan aplikasi. Target known accuracy >= 90%, false accept <= 1%; gunakan cukup percobaan negatif dan laporkan jumlahnya, bukan persentase tanpa ukuran sampel. Sistem bukan autentikasi; tidak ada liveness detection.

## Tulisan dan perintah suara

OCR: minimal 30 contoh teks cetak Latin, panjang/jarak/cahaya bervariasi; bandingkan teks verbatim lewat character error rate, target <= 10%. Tulisan tangan tidak dijanjikan.

Suara: uji 10 perintah (pindai, tulisan, keluarga, jelaskan foto, ulangi, berhenti, indoor, outdoor, jarak, perintah tidak dikenal), masing-masing 10 kali pada kondisi tenang dan bising. Rekaman aktif 4 detik setelah tombol mikrofon, bukan wake word. Target keberhasilan kondisi tenang >= 90%.

## Performa dan kegagalan

Ekspor runtime CSV dari Pengaturan. Hitung median/p95 per operasi, bedakan cold/warm start; latensi detektor native tidak sama dengan waktu end-to-end sampai suara. Ukur waktu end-to-end secara terpisah. Target awal objek <= 2 detik, jarak/OCR/suara <= 5 detik setelah masukan tersedia; jarak memakai tiga inferensi sehingga bisa lebih lambat. Laporkan nilai aktual tanpa mengganti target diam-diam.

Uji 20 menit: suhu, baterai, frame tertunda, penggunaan RAM, izin ditolak, kamera dipakai aplikasi lain, aplikasi masuk latar, hasil lama setelah berhenti, model rusak, keluarga belum didaftarkan, suara Indonesia belum terpasang, jaringan putus, API key salah, kuota habis, serta pembatalan permintaan GPT.

Jalankan `python scripts/evaluate.py evaluation` untuk agregasi CSV. Data kosong menghasilkan null, bukan angka keberhasilan.
