import 'package:beecount/widgets/biz/pin_entry_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({
    required ValueChanged<String> onNumber,
    bool showBiometric = false,
  }) =>
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: NumberPad(
                onNumberTap: onNumber,
                onDelete: () {},
                showBiometric: showBiometric,
                onBiometric: () {},
              ),
            ),
          ),
        ),
      );

  Finder scaleOfKey(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(AnimatedScale),
      );

  testWidgets('點擊數字鍵:觸發 onNumberTap 與輕觸覺回饋', (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final taps = <String>[];
    await tester.pumpWidget(host(onNumber: taps.add));
    await tester.tap(find.text('5'));
    await tester.pump();

    expect(taps, ['5']);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('按下數字鍵立即縮放 0.92,放開後還原', (tester) async {
    await tester.pumpWidget(host(onNumber: (_) {}));
    final f = scaleOfKey('7');
    expect(tester.widget<AnimatedScale>(f).scale, 1.0);

    final g = await tester.startGesture(tester.getCenter(find.text('7')));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(f).scale, 0.92);

    await g.up();
    await tester.pump();
    expect(tester.widget<AnimatedScale>(f).scale, 1.0);
  });

  testWidgets('未啟用生物辨識的佔位鍵不可點、不縮放', (tester) async {
    await tester.pumpWidget(host(onNumber: (_) {}));
    // 數字 0~9 + 刪除鍵共 11 個可點鍵,佔位鍵不應有 AnimatedScale
    expect(find.byType(AnimatedScale), findsNWidgets(11));
  });

  testWidgets('啟用生物辨識時指紋鍵可按壓', (tester) async {
    await tester.pumpWidget(host(onNumber: (_) {}, showBiometric: true));
    expect(find.byType(AnimatedScale), findsNWidgets(12));
  });
}
