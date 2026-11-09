import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahabat_netra/main.dart';
import 'package:sahabat_netra/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeBridge.channel, (call) async {
      if (call.method == 'status')
        return {
          'cameraPermission': false,
          'ttsReady': true,
          'hasApiKey': false,
          'gptModel': '',
          'models': <String, bool>{'depth': true, 'qwen': true}
        };
      if (call.method == 'listFamily') return <Object?>[];
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('id.sahabatnetra/events'), (_) async => null);
  });

  Future<void> expectMeetsGuidelines(WidgetTester tester) async {
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  }

  testWidgets('HomeView meets accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const NetraApp());
    await tester.pumpAndSettle();
    await expectMeetsGuidelines(tester);
    handle.dispose();
  });

  testWidgets('SettingsView meets accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const NetraApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pengaturan dan kesiapan model'));
    await tester.pumpAndSettle();
    await expectMeetsGuidelines(tester);
    handle.dispose();
  });

  testWidgets('FamilyView meets accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const NetraApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Kelola wajah keluarga'), 300);
    await tester.tap(find.text('Kelola wajah keluarga'));
    await tester.pumpAndSettle();
    await expectMeetsGuidelines(tester);
    handle.dispose();
  });
}
