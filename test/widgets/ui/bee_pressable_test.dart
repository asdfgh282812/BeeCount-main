import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/widgets/ui/bee_pressable.dart';

void main() {
  testWidgets('按下时缩小、放开后弹回、onTap 触发', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: BeePressable(
        onTap: () => tapped = true,
        child: const SizedBox(width: 100, height: 40, key: Key('child')),
      ),
    ));

    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);

    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('child'))));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 0.96);

    await gesture.up();
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);
    expect(tapped, true);
  });

  testWidgets('减少动画时 AnimatedScale duration 归零', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: BeePressable(onTap: () {}, child: const SizedBox()),
      ),
    ));
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
      Duration.zero,
    );
  });
}
