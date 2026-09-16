/// Reads printed text only; this is not banknote detection or authentication.
String narrateRupiah(String text) {
  final words = text
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9\s.,]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  const unclear = 'Nominal rupiah belum terbaca dengan cukup jelas. '
      'Arahkan satu lembar uang ke kamera, ratakan, dan pastikan tulisan BANK INDONESIA serta nominal terlihat.';
  // A price tag, receipt, serial number or an arbitrary number is not a banknote.
  if (!words.contains('BANK INDONESIA') ||
      !RegExp(r'\bRUPIAH\b').hasMatch(words)) return unclear;
  const denominations = <int, String>{
    1000: 'seribu',
    2000: 'dua ribu',
    5000: 'lima ribu',
    10000: 'sepuluh ribu',
    20000: 'dua puluh ribu',
    50000: 'lima puluh ribu',
    75000: 'tujuh puluh lima ribu',
    100000: 'seratus ribu',
  };
  final numeric = <int>{};
  for (final match in RegExp(r'\b\d+(?:[.,]\d+)*\b').allMatches(words)) {
    final raw = match.group(0)!;
    // Only plain digits or a correctly grouped thousands separator are accepted.
    if (!RegExp(r'^\d+$|^\d{1,3}[.,]\d{3}$').hasMatch(raw)) continue;
    final value = int.tryParse(raw.replaceAll(RegExp(r'[.,]'), ''));
    if (denominations.containsKey(value)) numeric.add(value!);
  }
  final spelled = <int>{};
  final phrases = denominations.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  final pattern = RegExp(
      '\\b(${phrases.map((e) => e.value.toUpperCase()).join('|')}) RUPIAH\\b');
  for (final match in pattern.allMatches(words)) {
    spelled.add(
        phrases.firstWhere((e) => e.value.toUpperCase() == match.group(1)).key);
  }
  final candidates = {...numeric, ...spelled};
  if (candidates.length > 1) {
    return 'Terbaca lebih dari satu nominal atau hasil tidak konsisten. '
        'Pisahkan uang dan baca satu lembar lagi.';
  }
  // Require agreement between digits and written denomination to limit OCR guesses.
  if (numeric.length != 1 ||
      spelled.length != 1 ||
      numeric.single != spelled.single) {
    return unclear;
  }
  return 'Tulisan nominal terbaca ${denominations[numeric.single]} rupiah. '
      'Ini pembacaan tulisan, bukan pemeriksaan keaslian uang. Ulangi untuk memastikan.';
}
