import 'package:beecount/styles/tokens.dart';
import 'package:beecount/widgets/ui/bee_overlays.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sheetKey = Key('sheet');
  const dialogKey = Key('dialog');

  late BuildContext ctx;

  Future<void> pumpHost(WidgetTester tester, {bool reduce = false}) {
    return tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.expand();
        }),
      ),
    ));
  }

  Future<void> openSheet(WidgetTester tester,
      {bool reduce = false, AnimationStyle? style}) async {
    await pumpHost(tester, reduce: reduce);
    showBeeBottomSheet<void>(
      context: ctx,
      animationStyle: style,
      builder: (_) => const SizedBox(key: sheetKey, height: 200),
    );
  }

  Future<void> openDialog(WidgetTester tester, {bool reduce = false}) async {
    await pumpHost(tester, reduce: reduce);
    showBeeDialog<void>(
      context: ctx,
      builder: (_) => const Dialog(
        child: SizedBox(key: dialogKey, width: 200, height: 100),
      ),
    );
  }

  double sheetTop(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(sheetKey, skipOffstage: false)).dy;

  group('showBeeBottomSheet', () {
    testWidgets('進場過程位置不越過終點(無 overshoot),280ms 內結束', (tester) async {
      await openSheet(tester);
      await tester.pump();
      var minTop = double.infinity;
      for (var i = 0; i < 29; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        if (find.byKey(sheetKey, skipOffstage: false).evaluate().isNotEmpty) {
          minTop = minTop < sheetTop(tester) ? minTop : sheetTop(tester);
        }
      }
      await tester.pump(const Duration(milliseconds: 10));
      final finalTop = sheetTop(tester);
      expect(minTop, greaterThanOrEqualTo(finalTop - 0.01));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('離場 210ms 內結束,且一開始就明顯位移', (tester) async {
      await openSheet(tester);
      await tester.pumpAndSettle();
      final finalTop = sheetTop(tester);

      Navigator.of(tester.element(find.byKey(sheetKey))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(sheetTop(tester), greaterThan(finalTop + 20));

      await tester.pump(const Duration(milliseconds: 160));
      expect(find.byKey(sheetKey), findsNothing);
    });

    testWidgets('減少動畫:不留下進行中的動畫', (tester) async {
      await openSheet(tester, reduce: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byKey(sheetKey), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('animationStyle 逐欄位覆寫預設', (tester) async {
      await openSheet(tester,
          style: const AnimationStyle(duration: Duration(seconds: 1)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
    });
  });

  group('showBeeDialog', () {
    double scaleOf(WidgetTester tester) {
      final t = tester.widget<ScaleTransition>(find
          .ancestor(
              of: find.byKey(dialogKey), matching: find.byType(ScaleTransition))
          .first);
      return t.scale.value;
    }

    testWidgets('起始縮放約 0.96,中途介於 0.96~1,180ms 內到 1', (tester) async {
      await openDialog(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(scaleOf(tester), closeTo(0.96, 0.01));

      await tester.pump(const Duration(milliseconds: 60));
      final mid = scaleOf(tester);
      expect(mid, greaterThan(0.96));
      expect(mid, lessThan(1.0));

      await tester.pump(const Duration(milliseconds: 130));
      expect(scaleOf(tester), 1.0);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('離場 120ms 內結束', (tester) async {
      await openDialog(tester);
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byKey(dialogKey))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      expect(find.byKey(dialogKey), findsNothing);
    });

    testWidgets('減少動畫:無過渡', (tester) async {
      await openDialog(tester, reduce: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byKey(dialogKey), findsOneWidget);
      expect(scaleOf(tester), 1.0);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('點遮罩可關閉', (tester) async {
      await openDialog(tester);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byKey(dialogKey), findsNothing);
    });
  });

  test('令牌:sheet 進場用 BeeMotion.medium(280ms)', () {
    expect(BeeMotion.medium, const Duration(milliseconds: 280));
  });
}
