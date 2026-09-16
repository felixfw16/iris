import 'package:flutter_test/flutter_test.dart';
import 'package:sahabat_netra/domain.dart';

void main() {
  test('narration rejects low confidence and invalid metric distances', () {
    final text = narrateObjects(const [
      Observation(
          label: 'kursi', position: 'kiri', confidence: .9, meters: double.nan),
      Observation(label: 'mobil', position: 'kanan', confidence: .2, meters: 2),
    ], withDistance: true);
    expect(text, contains('kursi di kiri'));
    expect(text, contains('Jarak belum dapat diperkirakan'));
    expect(text, isNot(contains('mobil')));
    expect(text, isNot(contains('NaN')));
  });
  test('distance is explicitly approximate and rounded', () {
    const item = Observation(
        label: 'kursi', position: 'kiri', confidence: .9, meters: 1.7);
    expect(item.description, 'kursi di kiri, perkiraan 1,5 meter');
  });
  test('narration includes ten objects and caps longer lists', () {
    final text = narrateObjects(List.generate(
        12,
        (i) =>
            Observation(label: 'objek$i', position: 'depan', confidence: .9)));
    expect(text, contains('objek3'));
    expect(text, contains('objek9'));
    expect(text, isNot(contains('objek10')));
  });
  test('long narration is not replaced after only a few seconds', () {
    final gate = NarrationGate();
    final text = List.filled(10, 'kursi di depan').join('. ');
    expect(gate.accept(text, 10000, 10000), isTrue);
    expect(gate.accept('pintu di kiri', 15000, 15000), isFalse);
    expect(gate.accept('pintu di kiri', 31000, 31000), isTrue);
  });
  test('stale results and repeated announcements are suppressed', () {
    final gate = NarrationGate();
    expect(gate.accept('kursi', 0, 6000), isFalse);
    expect(gate.accept('kursi', 10000, 10000), isTrue);
    expect(gate.accept('meja', 11000, 11000), isFalse);
    expect(gate.accept('kursi', 15000, 15000), isFalse);
    expect(gate.accept('kursi', 23000, 23000), isTrue);
    gate.reset();
    expect(gate.accept('kursi', 24000, 24000), isTrue);
  });
  test('voice commands use words and give stop precedence', () {
    expect(parseCommand('Tolong baca tulisan.'), VoiceCommand.text);
    expect(parseCommand('luar ruangan'), VoiceCommand.outdoor);
    expect(parseCommand('ukur jarak'), VoiceCommand.distance);
    expect(parseCommand('baca uang rupiah'), VoiceCommand.rupiah);
    expect(parseCommand('berhenti baca rupiah'), VoiceCommand.stop);
    expect(parseCommand('berhenti pindai'), VoiceCommand.stop);
    expect(parseCommand('keluarganya'), VoiceCommand.unknown);
    expect(parseCommand(''), VoiceCommand.unknown);
  });
}
