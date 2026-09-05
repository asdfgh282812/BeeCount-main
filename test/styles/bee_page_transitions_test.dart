import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/styles/bee_page_transitions.dart';

void main() {
  const builder = BeePageTransitionsBuilder();

  Widget wrap(bool disableAnimations, Widget child) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    );
  }

  testWidgets('减少动画时只输出 FadeTransition，没有滑动/视差', (tester) async {
    final route = MaterialPageRoute<void>(builder: (_) => const SizedBox());
    await tester.pumpWidget(wrap(
      true,
      Builder(
        builder: (context) => builder.buildTransitions<void>(
          route,
          context,
          const AlwaysStoppedAnimation(0.5),
          const AlwaysStoppedAnimation(0.0),
          const SizedBox(),
        ),
      ),
    ));
    expect(find.byType(FadeTransition), findsOneWidget);
    expect(find.byType(SlideTransition), findsNothing);
  });

  testWidgets('正常状态下有滑动位移叠层', (tester) async {
    final route = MaterialPageRoute<void>(builder: (_) => const SizedBox());
    await tester.pumpWidget(wrap(
      false,
      Builder(
        builder: (context) => builder.buildTransitions<void>(
          route,
          context,
          const AlwaysStoppedAnimation(0.5),
          const AlwaysStoppedAnimation(0.0),
          const SizedBox(),
        ),
      ),
    ));
    expect(find.byType(SlideTransition), findsWidgets);
  });
}
