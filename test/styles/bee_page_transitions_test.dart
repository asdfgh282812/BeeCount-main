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

  // 回归:iOS 曾套用 BeePageTransitionsBuilder,导致整个 App 失去从左缘右滑返回。
  testWidgets('iOS 上从左缘右滑可以返回上一页', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        platform: TargetPlatform.iOS,
        pageTransitionsTheme: kBeePageTransitionsTheme,
      ),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('第二页')),
          )),
          child: const Text('第一页'),
        ),
      ),
    ));
    await tester.tap(find.text('第一页'));
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsOneWidget);

    final gesture = await tester.startGesture(const Offset(5, 300));
    await gesture.moveBy(const Offset(400, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('第二页'), findsNothing);
    expect(find.text('第一页'), findsOneWidget);
  });
}
