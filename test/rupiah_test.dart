import 'package:flutter_test/flutter_test.dart';
import 'package:sahabat_netra/rupiah.dart';

void main() {
  test('reads matching digits and printed Indonesian denomination', () {
    const names = {
      '1000': 'SERIBU',
      '2000': 'DUA RIBU',
      '5000': 'LIMA RIBU',
      '10.000': 'SEPULUH RIBU',
      '20000': 'DUA PULUH RIBU',
      '50.000': 'LIMA PULUH RIBU',
      '75000': 'TUJUH PULUH LIMA RIBU',
      '100000': 'SERATUS RIBU',
    };
    for (final entry in names.entries) {
      expect(
          narrateRupiah('BANK INDONESIA\n${entry.key}\n${entry.value} RUPIAH'),
          contains(
              'Tulisan nominal terbaca ${entry.value.toLowerCase()} rupiah'));
    }
  });
  test('does not claim arbitrary prices or foreign currency as rupiah notes',
      () {
    for (final text in [
      '',
      'TOTAL RP 100000',
      'RUPIAH 50000',
      'BANK INDONESIA 100000',
      '100 US DOLLARS',
      'BANK INDONESIA RUPIAH ABC100000XYZ',
      'BANK INDONESIA SERATUS RIBU RUPIAH 100.00',
      'BANK INDONESIA 100000 RUPIAH',
      'BANK INDONESIA 50000 SERATUS RIBU RUPIAH',
    ]) {
      expect(narrateRupiah(text), isNot(contains('Tulisan nominal terbaca')));
    }
  });
  test('rejects mixed notes instead of guessing or summing their values', () {
    expect(
        narrateRupiah('BANK INDONESIA 10000 SEPULUH RIBU RUPIAH '
            '50000 LIMA PULUH RIBU RUPIAH'),
        contains('lebih dari satu nominal'));
  });
  test('repeated text for one denomination remains one result', () {
    expect(narrateRupiah('BANK INDONESIA 20000 20000 DUA PULUH RIBU RUPIAH'),
        contains('Tulisan nominal terbaca dua puluh ribu rupiah'));
  });
}
