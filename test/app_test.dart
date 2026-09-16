import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahabat_netra/main.dart';
import 'package:sahabat_netra/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  Completer<String>? listening;
  Completer<String>? qwenAnswer;
  bool speechFails = false;
  setUp(() {
    calls.clear();
    listening = null;
    qwenAnswer = null;
    speechFails = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeBridge.channel, (call) async {
      calls.add(call);
      if (call.method == 'requestMicrophone') return true;
      if (call.method == 'listen') return listening?.future ?? '';
      if (call.method == 'askQwen')
        return qwenAnswer?.future ?? 'Jawaban Qwen lokal.';
      if (call.method == 'speak' && speechFails) {
        throw PlatformException(code: 'tts', message: 'Suara belum siap.');
      }
      if (call.method == 'status')
        return {
          'cameraPermission': false,
          'ttsReady': true,
          'models': <String, bool>{'depth': true, 'qwen': true}
        };
      if (call.method == 'listFamily') return [];
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('id.sahabatnetra/events'), (_) async => null);
  });
  testWidgets('stopping Qwen suppresses late speech and defaults thinking off',
      (tester) async {
    qwenAnswer = Completer<String>();
    await tester.pumpWidget(const NetraApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Tanya Qwen dengan suara'), 300);
    await tester.tap(find.text('Tanya Qwen dengan suara'));
    await tester.pump();
    await tester.pump();
    expect(calls.lastWhere((c) => c.method == 'askQwen').arguments['thinking'],
        isFalse);
    await tester.scrollUntilVisible(find.text('Berhenti'), 300);
    await tester.tap(find.text('Berhenti'));
    await tester.pumpAndSettle();
    qwenAnswer!.complete('Jawaban terlambat.');
    await tester.pumpAndSettle();
    expect(
        calls
            .where((c) => c.method == 'speak')
            .any((c) => c.arguments['text'] == 'Jawaban terlambat.'),
        isFalse);
  });

  testWidgets('opens offline with accessible actions and no upload',
      (tester) async {
    await tester.pumpWidget(const NetraApp());
    await tester.pumpAndSettle();
    expect(find.text('IRIS'), findsOneWidget);
    expect(find.text('OFFLINE · DIPROSES DI PERANGKAT'), findsOneWidget);
    expect(find.text('Mulai pindai'), findsOneWidget);
    expect(calls.any((call) => call.method == 'describePhoto'), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('GPT action is blocked before native image upload when offline',
      (tester) async {
    await tester.pumpWidget(const NetraApp());
    await tester.pumpAndSettle();
    final button = find.text('Jelaskan foto dengan GPT');
    await tester.scrollUntilVisible(button, 400);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(calls.any((call) => call.method == 'describePhoto'), isFalse);
    expect(calls.where((c) => c.method == 'speak').last.arguments['text'],
        contains('Mode offline aktif'));
  });
  testWidgets('settings reports the unified depth model as available',
      (tester) async {
    await tester.pumpWidget(const NetraApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pengaturan dan kesiapan model'));
    await tester.pumpAndSettle();
    final tile = find.ancestor(
        of: find.text('Perkiraan jarak (YOLO26n-depth)'),
        matching: find.byType(ListTile));
    expect(tile, findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('Model tersedia')),
        findsOneWidget);
    expect(find.text('Jarak dalam ruangan'), findsNothing);
    expect(find.text('Jarak luar ruangan'), findsNothing);
  });
  testWidgets('mode change stops previous processing', (tester) async {
    await tester.pumpWidget(const NetraApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tulisan'));
    await tester.pumpAndSettle();
    expect(find.text('Baca tulisan'), findsOneWidget);
    expect(calls.any((c) => c.method == 'stop'), isTrue);
  });
  testWidgets('Qwen voice button passes thinking switch and speaks its answer',
      (tester) async {
    await tester.pumpWidget(const NetraApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Thinking Qwen'), 300);
    await tester.tap(find.text('Thinking Qwen'));
    await tester.pump();
    await tester.tap(find.text('Tanya Qwen dengan suara'));
    await tester.pumpAndSettle();
    final qwen = calls.lastWhere((call) => call.method == 'askQwen');
    expect(qwen.arguments['thinking'], isTrue);
    expect(calls.lastWhere((call) => call.method == 'speak').arguments['text'],
        'Jawaban Qwen lokal.');
  });
  testWidgets('phone layout with larger text does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const NetraApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('guide stops processing and preserves the last narration',
      (tester) async {
    await tester.pumpWidget(const NetraApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tulisan'));
    await tester.pumpAndSettle();
    final previous =
        calls.lastWhere((c) => c.method == 'speak').arguments['text'];
    await tester.tap(find.byTooltip('Panduan penggunaan'));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'stop');
    await tester.tap(find.text('Bacakan panduan'));
    await tester.pumpAndSettle();
    expect(calls.last.arguments['text'], contains('berhenti otomatis'));
    await tester.tap(find.text('Tutup panduan'));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'stop');
    await tester.scrollUntilVisible(find.text('Ulangi'), 300);
    await tester.tap(find.text('Ulangi'));
    await tester.pumpAndSettle();
    expect(calls.last.arguments['text'], previous);
  });

  testWidgets('repeat is disabled during recording and recovers after stop',
      (tester) async {
    listening = Completer<String>();
    await tester.pumpWidget(const NetraApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Perintah'), 300);
    await tester.tap(find.text('Perintah'));
    await tester.pump();
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Ulangi'), 200);
    final repeat = find.widgetWithText(TextButton, 'Ulangi');
    expect(tester.widget<TextButton>(repeat).onPressed, isNull);
    await tester.tap(find.text('Berhenti'));
    await tester.pump();
    listening!.complete('pindai');
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(repeat).onPressed, isNotNull);
    expect(calls.any((c) => c.method == 'startScan'), isFalse);
  });

  testWidgets('TalkBack announcement is enabled when device speech fails',
      (tester) async {
    await tester.pumpWidget(const NetraApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tulisan'));
    await tester.pumpAndSettle();
    Finder result() => find
        .ancestor(
            of: find.textContaining('Mode tulisan.'),
            matching: find.byType(Semantics))
        .first;
    await tester.scrollUntilVisible(find.text('Ulangi'), 300);
    expect(tester.widget<Semantics>(result()).properties.liveRegion, isFalse);
    speechFails = true;
    await tester.tap(find.text('Ulangi'));
    await tester.pumpAndSettle();
    expect(tester.widget<Semantics>(result()).properties.liveRegion, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guide supports large text on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const NetraApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Panduan penggunaan'));
    await tester.pumpAndSettle();
    expect(find.text('Tutup panduan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
