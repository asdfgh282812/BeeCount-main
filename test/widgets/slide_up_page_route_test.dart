import 'package:beecount/styles/tokens.dart';
import 'package:beecount/widgets/ui/slide_up_page_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BeeSpringCurve', () {
    const curve = BeeSpringCurve();

    test('端點固定為 0 與 1', () {
      expect(curve.transform(0), 0);
      expect(curve.transform(1), 1);
    });

    test('微回弹:峰值略超過 1 但不超過 3%', () {
      var peak = 0.0;
      for (var i = 0; i <= 1000; i++) {
        final v = curve.transform(i / 1000);
        if (v > peak) peak = v;
      }
      expect(peak, greaterThan(1.0));
      expect(peak, lessThan(1.03));
    });

    test('非線性:前段位移明顯快於線性', () {
      expect(curve.transform(0.3), greaterThan(0.5));
    });
  });

  group('SlideUpPageRoute', () {
    Future<NavigatorState> pumpHost(WidgetTester tester) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('home')),
      ));
      return navKey.currentState!;
    }

    double pageTop(WidgetTester tester) => tester
        // 第一幀整頁在螢幕外,預設 finder 會當成 offstage 略過
        .getTopLeft(find.byKey(const Key('sheet'), skipOffstage: false))
        .dy;

    testWidgets('由下往上滑入,減速曲線,300ms 結束', (tester) async {
      final nav = await pumpHost(tester);
      final screenH =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;

      nav.push(SlideUpPageRoute<void>(
        builder: (_) => const Scaffold(key: Key('sheet'), body: Text('sheet')),
      ));
      // 首幀 Navigator 會以完成態 offstage 建構新路由(量測 Hero 用),
      // 起點位置改用 30ms 驗證:easeOutCubic(0.1) ≈ 0.271 → 還在下方 72.9%
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(pageTop(tester), moreOrLessEquals(screenH * 0.729, epsilon: 5));

      await tester.pump(const Duration(milliseconds: 120));
      // easeOutCubic(0.5) = 0.875 → 只剩 12.5% 高度沒滑上來
      expect(pageTop(tester), moreOrLessEquals(screenH * 0.125, epsilon: 1));

      await tester.pumpAndSettle();
      expect(pageTop(tester), 0);
      // 動畫結束後底層頁面被 offstage 且 Ticker 停掉(opaque 生效),
      // 首頁動態皮膚不會在記帳頁背後持續重繪
      expect(find.text('home'), findsNothing);
      final homeTicker = TickerMode.valuesOf(
          tester.element(find.text('home', skipOffstage: false)));
      expect(homeTicker.enabled, isFalse);
    });

    testWidgets('遮罩隨動畫淡入,關閉時往下收回並淡出', (tester) async {
      final nav = await pumpHost(tester);
      nav.push(SlideUpPageRoute<void>(
        builder: (_) => const Scaffold(key: Key('sheet'), body: Text('sheet')),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // 動畫中底層頁面仍可見,遮罩為半透明黑且透明度介於 0 與 54% 之間
      expect(find.text('home'), findsOneWidget);
      final barrier = tester
          .widget<AnimatedModalBarrier>(find.byType(AnimatedModalBarrier).last);
      final color = barrier.color.value!;
      expect(color.a, greaterThan(0));
      expect(color.a, lessThan(Colors.black54.a));

      await tester.pumpAndSettle();
      nav.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final screenH =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      // 反向同曲線 = 先慢後快:一半時間只往下收了 12.5%
      expect(pageTop(tester), moreOrLessEquals(screenH * 0.125, epsilon: 1));

      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sheet')), findsNothing);
    });
  });

  group('SlideUpPageRoute 下滑關閉', () {
    Future<(NavigatorState, double)> pushSheet(
        WidgetTester tester, Widget page) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('home')),
      ));
      navKey.currentState!.push(SlideUpPageRoute<void>(builder: (_) => page));
      await tester.pumpAndSettle();
      final h = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      return (navKey.currentState!, h);
    }

    double top(WidgetTester tester) => tester
        .getTopLeft(find.byKey(const Key('sheet'), skipOffstage: false))
        .dy;

    const plainPage = Scaffold(
      key: Key('sheet'),
      body: Column(children: [
        SizedBox(height: 100, child: Center(child: Text('header'))),
        Expanded(child: SizedBox.expand()),
      ]),
    );

    testWidgets('空白處往下拖:頁面 1:1 跟手、遮罩變淡,過門檻放開即關閉', (tester) async {
      final (_, h) = await pushSheet(tester, plainPage);
      final g = await tester.startGesture(const Offset(200, 300));
      await g.moveBy(const Offset(0, 20)); // 過 slop
      await tester.pump();
      await g.moveBy(const Offset(0, 100));
      await tester.pump();
      // 過 slop 那段之後的位移 1:1(線性映射,不受 easeOutCubic 壓扁)
      final dragged = top(tester);
      expect(dragged, greaterThan(100));
      expect(dragged, lessThanOrEqualTo(120));
      // 拖曳中底層頁面重新露出在遮罩後面
      expect(find.text('home'), findsOneWidget);

      await g.moveBy(Offset(0, h * 0.3));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sheet')), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('拖一小段放開(沒甩):彈回原位', (tester) async {
      await pushSheet(tester, plainPage);
      final g = await tester.startGesture(const Offset(200, 300));
      for (var i = 0; i < 8; i++) {
        await g.moveBy(const Offset(0, 10));
        await tester.pump(const Duration(milliseconds: 100)); // 慢拖
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(top(tester), 0);
      expect(find.text('home'), findsNothing); // 回到不透明、底層 offstage
    });

    testWidgets('往下快甩:短距離也關閉', (tester) async {
      await pushSheet(tester, plainPage);
      await tester.flingFrom(
          const Offset(200, 300), const Offset(0, 120), 1500);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sheet')), findsNothing);
    });

    testWidgets('先往上拉不會啟動(保留給拉到底送出)', (tester) async {
      await pushSheet(tester, plainPage);
      final g = await tester.startGesture(const Offset(200, 400));
      await g.moveBy(const Offset(0, -40));
      await tester.pump();
      await g.moveBy(const Offset(0, 200)); // 同一次拖曳再往下也不接手
      await tester.pump();
      expect(top(tester), 0);
      await g.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sheet')), findsOneWidget);
    });

    testWidgets('捲動區:內容未到頂先捲內容,到頂後再往下拉才拖頁面', (tester) async {
      final controller = ScrollController(initialScrollOffset: 100);
      addTearDown(controller.dispose);
      final (_, h) = await pushSheet(
        tester,
        Scaffold(
          key: const Key('sheet'),
          body: ListView(
            controller: controller,
            children: [
              for (var i = 0; i < 40; i++)
                SizedBox(height: 60, child: Text('row $i')),
            ],
          ),
        ),
      );

      final g = await tester.startGesture(const Offset(200, 300));
      await g.moveBy(const Offset(0, 20));
      await tester.pump();
      await g.moveBy(const Offset(0, 60)); // 內容還剩 ~20 才到頂
      await tester.pump();
      expect(top(tester), 0);
      expect(controller.offset, moreOrLessEquals(20, epsilon: 20));

      for (var i = 0; i < 6; i++) {
        await g.moveBy(Offset(0, h * 0.08)); // 到頂後繼續往下
        await tester.pump();
      }
      expect(controller.offset, 0); // 頂端不回彈、內容凍結
      expect(top(tester), greaterThan(h * 0.3));

      await g.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sheet')), findsNothing);
    });

    testWidgets('頁面有 PopScope(canPop: false) 時手勢停用', (tester) async {
      await pushSheet(
        tester,
        const PopScope(canPop: false, child: plainPage),
      );
      final g = await tester.startGesture(const Offset(200, 300));
      await g.moveBy(const Offset(0, 20));
      await tester.pump();
      await g.moveBy(const Offset(0, 400));
      await tester.pump();
      expect(top(tester), 0);
      await g.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sheet')), findsOneWidget);
    });
  });
}
