import 'package:beecount/widgets/ui/bee_pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  double scaleOf(WidgetTester tester) =>
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

  testWidgets('按下立即進入縮放態,放開還原,且 onTap 照常觸發', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(BeePressable(
      pressedScale: 0.92,
      onTap: () => taps++,
      child: const SizedBox(width: 80, height: 40, child: Text('x')),
    )));

    final g = await tester.startGesture(tester.getCenter(find.text('x')));
    await tester.pump(); // 不等 kPressTimeout,Listener 應已觸發
    expect(scaleOf(tester), 0.92);

    await g.up();
    await tester.pump();
    expect(scaleOf(tester), 1.0);
    expect(taps, 1);
  });

  testWidgets('拖走(tap 被取消)後縮放還原且不觸發 onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(BeePressable(
      onTap: () => taps++,
      child: const SizedBox(width: 80, height: 40, child: Text('x')),
    )));

    final g = await tester.startGesture(tester.getCenter(find.text('x')));
    await tester.pump();
    expect(scaleOf(tester), 0.96);
    await g.moveBy(const Offset(200, 0));
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(scaleOf(tester), 1.0);
    expect(taps, 0);
  });

  testWidgets('長按 start / moveUpdate / end 回呼完整透傳', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(host(BeePressable(
      onTap: () {},
      onLongPressStart: (_) => events.add('start'),
      onLongPressMoveUpdate: (_) => events.add('move'),
      onLongPressEnd: (_) => events.add('end'),
      child: const SizedBox(width: 80, height: 40, child: Text('x')),
    )));

    final g = await tester.startGesture(tester.getCenter(find.text('x')));
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveBy(const Offset(0, -30));
    await g.up();
    await tester.pump();
    expect(events.first, 'start');
    expect(events, contains('move'));
    expect(events.last, 'end');
    expect(scaleOf(tester), 1.0);
  });

  testWidgets('onPressedChanged 在按下與還原時依序回呼', (tester) async {
    final states = <bool>[];
    await tester.pumpWidget(host(BeePressable(
      onTap: () {},
      onPressedChanged: states.add,
      child: const SizedBox(width: 80, height: 40, child: Text('x')),
    )));

    final g = await tester.startGesture(tester.getCenter(find.text('x')));
    await tester.pump();
    expect(states, [true]);
    await g.up();
    await tester.pump();
    expect(states, [true, false]);
  });
}
