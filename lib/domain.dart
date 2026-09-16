enum ScanMode { objects, text, family }

const usageGuide = 'Selamat datang di IRIS. '
    'Aplikasi dimulai dalam mode offline.\n\n'
    'Pilih Objek, lalu Mulai pindai untuk mendengar objek di kiri, depan, atau kanan. '
    'Hingga sepuluh objek dibacakan. Gerakkan kamera perlahan.\n\n'
    'Pilih Tulisan, arahkan kamera ke teks, lalu tekan Baca tulisan. '
    'Pilih Keluarga, lalu Kenali wajah untuk mengenali orang yang sudah didaftarkan. '
    'Pendamping dapat mendaftarkan wajah melalui Kelola wajah keluarga.\n\n'
    'Baca rupiah membaca tulisan nominal satu lembar uang. Arahkan sisi dengan tulisan '
    'BANK INDONESIA, angka nominal, dan nominal dalam huruf ke kamera. '
    'Fitur ini tidak memeriksa keaslian uang.\n\n'
    'Untuk Ukur jarak, tahan kamera stabil selama tiga pembacaan. '
    'Model yang sama digunakan untuk dalam dan luar ruangan. '
    'Hasilnya perkiraan dan tidak menggantikan alat bantu mobilitas.\n\n'
    'Tekan Perintah untuk menggunakan mikrofon. Tunggu status mendengarkan, '
    'lalu ucapkan satu perintah: pindai, tulisan, keluarga, '
    'jarak, rupiah, jelaskan foto, ulangi, atau berhenti. '
    'Rekaman berhenti otomatis setelah jeda sekitar satu detik. '
    'Anda dapat berbicara hingga tiga puluh detik; bila belum bicara, mikrofon menunggu delapan detik.\n\n'
    'Tanya Qwen dengan suara merekam pertanyaan, memprosesnya sepenuhnya di perangkat, '
    'lalu membacakan jawaban. Tanyakan di depan saya ada apa untuk memeriksa objek melalui kamera, '
    'atau bacakan tulisan untuk membaca teks. Aktifkan Thinking untuk pertanyaan yang membutuhkan penalaran; '
    'matikan agar jawaban lebih cepat dan singkat.\n\n'
    'Ulangi membacakan hasil terakhir. Berhenti menghentikan pemindaian, '
    'rekaman, dan pembacaan suara.\n\n'
    'Jelaskan foto dengan GPT memerlukan pengaturan online dan mengirim satu foto. '
    'Periksa kesiapan model dan suara offline Bahasa Indonesia di Pengaturan. '
    'Dengan TalkBack, geser untuk berpindah kontrol dan ketuk dua kali untuk memilih.';

enum VoiceCommand {
  objects,
  text,
  family,
  describe,
  repeat,
  stop,
  indoor,
  outdoor,
  distance,
  rupiah,
  unknown
}

VoiceCommand parseCommand(String speech) {
  final s = speech.toLowerCase().replaceAll(RegExp(r'[^a-z\s]'), ' ').trim();
  final words = s.split(RegExp(r'\s+')).toSet();
  if (words.contains('berhenti') || words.contains('stop'))
    return VoiceCommand.stop;
  if (words.contains('ulangi')) return VoiceCommand.repeat;
  if (words.contains('rupiah') || words.contains('uang'))
    return VoiceCommand.rupiah;
  if (words.contains('jarak')) return VoiceCommand.distance;
  if (words.contains('tulisan') || words.contains('teks'))
    return VoiceCommand.text;
  if (words.contains('keluarga') || words.contains('wajah'))
    return VoiceCommand.family;
  if (words.contains('jelaskan') || words.contains('deskripsi'))
    return VoiceCommand.describe;
  if (words.contains('outdoor') || s.contains('luar ruangan'))
    return VoiceCommand.outdoor;
  if (words.contains('indoor') || s.contains('dalam ruangan'))
    return VoiceCommand.indoor;
  if (words.contains('pindai') || words.contains('objek'))
    return VoiceCommand.objects;
  return VoiceCommand.unknown;
}

class Observation {
  const Observation(
      {required this.label,
      required this.position,
      required this.confidence,
      this.meters});
  final String label;
  final String position;
  final double confidence;
  final double? meters;

  factory Observation.fromMap(Map<Object?, Object?> map) => Observation(
        label: map['label'] as String? ?? 'objek',
        position: map['position'] as String? ?? 'depan',
        confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
        meters: (map['meters'] as num?)?.toDouble(),
      );

  String get description {
    final distance = meters;
    if (distance == null ||
        !distance.isFinite ||
        distance < .5 ||
        distance > 5) {
      return '$label di $position';
    }
    final rounded = (distance * 2).round() / 2;
    return '$label di $position, perkiraan ${rounded.toStringAsFixed(1).replaceAll('.', ',')} meter';
  }
}

String narrateObjects(List<Observation> items, {bool withDistance = false}) {
  final reliable = items
      .where((item) =>
          item.confidence.isFinite &&
          item.confidence >= .4 &&
          item.confidence <= 1)
      .take(10)
      .toList();
  if (reliable.isEmpty)
    return 'Belum ada objek yang dikenali. Arahkan kamera perlahan.';
  var text = '${reliable.map((item) => item.description).join('. ')}.';
  if (withDistance &&
      !reliable.any((item) =>
          item.meters != null &&
          item.meters!.isFinite &&
          item.meters! >= .5 &&
          item.meters! <= 5)) {
    text += ' Jarak belum dapat diperkirakan.';
  }
  return text;
}

/// Uses capture timestamps, never replays queued or obsolete camera results.
class NarrationGate {
  String _last = '';
  int _lastSpokenAt = -100000;
  int _nextSpokenAt = -100000;
  bool accept(String text, int capturedAt, int now) {
    if (now - capturedAt > 5000 || capturedAt > now + 1000) return false;
    if (now < _nextSpokenAt) return false;
    if (text == _last && now - _lastSpokenAt < 12000) return false;
    _last = text;
    _lastSpokenAt = now;
    // Allow longer lists to finish at the configured, deliberately slow speech rate.
    final speechDuration = text.split(RegExp(r'\s+')).length * 600 + 1000;
    _nextSpokenAt = now + (speechDuration > 3500 ? speechDuration : 3500);
    return true;
  }

  void reset() {
    _last = '';
    _lastSpokenAt = -100000;
    _nextSpokenAt = -100000;
  }
}
