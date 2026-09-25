import 'package:beecount/widgets/ui/bee_tab_drag_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 500 寬 → 每格 100,膠囊寬 64,第 i 格置中時 left = 100*i + 18。
class _Harness extends StatefulWidget {
  const _Harness({required this.onSelected, required this.onTap});
  final ValueChanged<int> onSelected;
  final ValueChanged<int> onTap;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int current = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 500,
            height: 56,
            child: BeeTabDragScope(
              currentIndex: current,
              tabCount: 5,
              primaryColor: Colors.amber,
              onSelected: (i) {
                widget.onSelected(i);
                setState(() => current = i);
              },
              builder: (context, activeIndex, indicator) => Stack(children: [
                Positioned.fill(child: indicator),
                Row(children: [
                  for (var i = 0; i < 5; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          widget.onTap(i);
                          setState(() => current = i);
                        },
                        child: Center(
                            child: Text(i == activeIndex ? 'on$i' : 'off$i')),
                      ),
                    ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  // 量排版位置(AnimatedScale 之外那層),不受拖曳時「浮起」放大影響
  double capsuleLeft(WidgetTester tester) {
    final origin = tester.getTopLeft(find.byType(BeeTabDragScope)).dx;
    return tester.getTopLeft(find.byType(AnimatedScale)).dx - origin;
  }

  testWidgets('點按:膠囊以彈簧滑到新分頁', (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(_Harness(onSelected: (_) {}, onTap: taps.add));
    expect(capsuleLeft(tester), 18);

    await tester.tap(find.text('off3'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final mid = capsuleLeft(tester);
    expect(mid, greaterThan(18));
    expect(mid, lessThan(318));

    await tester.pumpAndSettle();
    expect(taps, [3]);
    expect(capsuleLeft(tester), moreOrLessEquals(318, epsilon: 0.5));
  });

  testWidgets('拖曳:膠囊跟手、經過的分頁亮起、放開吸附並切頁', (tester) async {
    final selected = <int>[];
    final taps = <int>[];
    var haptics = 0;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics++;
      return null;
    });

    await tester.pumpWidget(_Harness(onSelected: selected.add, onTap: taps.add));
    final origin = tester.getTopLeft(find.byType(BeeTabDragScope));
    final gesture =
        await tester.startGesture(origin + const Offset(50, 28)); // 第 0 格
    await gesture.moveBy(const Offset(30, 0)); // 超過 slop,判給拖曳
    await tester.pump();
    await gesture.moveTo(origin + const Offset(250, 28)); // 第 2 格中央
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('on2'), findsOneWidget);
    expect(find.text('on0'), findsNothing);
    // 膠囊中心跟手指:250 − 32
    expect(capsuleLeft(tester), moreOrLessEquals(218, epsilon: 0.5));
    // 浮起放大
    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, greaterThan(1));
    expect(haptics, greaterThan(0));

    await gesture.moveTo(origin + const Offset(330, 28)); // 第 3 格偏左
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, [3]);
    expect(taps, isEmpty); // 拖曳不會觸發點按
    expect(find.text('on3'), findsOneWidget);
    expect(capsuleLeft(tester), moreOrLessEquals(318, epsilon: 0.5));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });

  testWidgets('拖曳超出兩端時膠囊停在第一/最後一格', (tester) async {
    await tester.pumpWidget(_Harness(onSelected: (_) {}, onTap: (_) {}));
    final origin = tester.getTopLeft(find.byType(BeeTabDragScope));
    final gesture = await tester.startGesture(origin + const Offset(50, 28));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveTo(origin + const Offset(620, 28));
    await tester.pumpAndSettle();
    expect(capsuleLeft(tester), moreOrLessEquals(418, epsilon: 0.5));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('on4'), findsOneWidget);
  });
}
