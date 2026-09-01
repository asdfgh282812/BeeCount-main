/// [PullToSubmitScrollView] 手勢偵測邏輯——2026-09-01 真機回報「往下拉沒有
/// 反應」修正後的行為覆蓋。v2 改用 [Listener] 直接看原始指標事件,核心要
/// 保證的行為:
/// - 手指壓在固定不滾動的 [PullToSubmitScrollView.bottomBar] 區域拖曳一樣算數
///   (這正是原本 bug 的根因——舊版只認 [SingleChildScrollView] 本體範圍)。
/// - 拉過門檻放開才送出,拉不夠或往回收手都不送出。
/// - `canSubmit:false` 時即使拉滿門檻也不送出。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/widgets/biz/pull_to_submit_scroll_view.dart';

void main() {
  Widget host({
    required VoidCallback onSubmit,
    bool canSubmit = true,
    Widget? bottomBar,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // 用 zh_TW 而非 zh:pullToSubmitHint/Release 是新 key,app_zh.arb 依專案
      // 政策不再維護,只有 app_zh_TW.arb 有正確譯文,選用有維護譯文的 zh_TW
      // 避免測試被無關的 l10n 落差誤判。
      locale: const Locale('zh', 'TW'),
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: PullToSubmitScrollView(
            canSubmit: canSubmit,
            isSubmitting: false,
            onSubmit: onSubmit,
            bottomBar: bottomBar,
            child: const SizedBox(
              key: Key('content'),
              height: 100,
              child: Text('x'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('内容不足以撐滿版面時,任何地方往上拉過門檻放開就送出', (tester) async {
    var submitted = false;
    await tester.pumpWidget(host(onSubmit: () => submitted = true));

    final center = tester.getCenter(find.byKey(const Key('content')));
    final gesture = await tester.startGesture(center);
    // 門檻是 72px,分段移動確保產生多個 PointerMoveEvent。
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(submitted, true);
  });

  testWidgets('固定在下方、不隨滾動的 bottomBar 區域拖曳一樣能觸發送出(修正前的 bug 場景)', (tester) async {
    var submitted = false;
    await tester.pumpWidget(host(
      onSubmit: () => submitted = true,
      bottomBar: const SizedBox(
        key: Key('bottomBar'),
        height: 80,
        child: Text('bottom bar'),
      ),
    ));

    final center = tester.getCenter(find.byKey(const Key('bottomBar')));
    final gesture = await tester.startGesture(center);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(submitted, true);
  });

  testWidgets('拉的距離不夠門檻,放開不送出', (tester) async {
    var submitted = false;
    await tester.pumpWidget(host(onSubmit: () => submitted = true));

    final center = tester.getCenter(find.byKey(const Key('content')));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(submitted, false);
  });

  testWidgets('拉過門檻後又往回收手,視為取消,不送出', (tester) async {
    var submitted = false;
    await tester.pumpWidget(host(onSubmit: () => submitted = true));

    final center = tester.getCenter(find.byKey(const Key('content')));
    final gesture = await tester.startGesture(center);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump();
    }
    // 往回收手到起點以下,取消武裝狀態。
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(submitted, false);
  });

  testWidgets('canSubmit:false 時即使拉滿門檻放開也不送出', (tester) async {
    var submitted = false;
    await tester
        .pumpWidget(host(onSubmit: () => submitted = true, canSubmit: false));

    final center = tester.getCenter(find.byKey(const Key('content')));
    final gesture = await tester.startGesture(center);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(submitted, false);
  });
}
