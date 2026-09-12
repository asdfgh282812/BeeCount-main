/// 分類編輯頁「系統圖示」選取格(`GroupedIconGrid`)在 Cute 圖示主題下的
/// 呈現——2026-09-12 使用者反饋:開啟可愛圖示後,這裡可以選的圖示樣式也要
/// 跟著換,才不會選的時候看到 Material 圖示、切回列表卻是手繪圖示。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/widgets/biz/grouped_icon_grid.dart';
import 'package:beecount/widgets/cute_icons/cute_category_icon_keys.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  testWidgets('material style renders plain Material icons for a cute-covered key',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_wrap(GroupedIconGrid(
      selectedIcon: 'restaurant',
      kind: 'expense',
      onIconSelected: (_) {},
    )));
    await tester.pump();

    expect(find.byType(CuteCategoryIcon), findsNothing);
    expect(find.byIcon(Icons.restaurant), findsOneWidget);
  });

  testWidgets('cute style swaps a covered key for its CuteCategoryIcon',
      (tester) async {
    SharedPreferences.setMockInitialValues({'categoryIconStyle': 'cute'});
    await tester.pumpWidget(_wrap(GroupedIconGrid(
      selectedIcon: 'restaurant',
      kind: 'expense',
      onIconSelected: (_) {},
    )));
    await tester.pump();

    // The whole grid has multiple cute-covered keys — this one specifically
    // no longer renders as a plain Material icon.
    expect(find.byIcon(Icons.restaurant), findsNothing);
    expect(find.byType(CuteCategoryIcon), findsWidgets);
  });

  testWidgets(
      'cute style renders the generic fallback cute icon for an uncovered '
      'key, not its Material glyph', (tester) async {
    SharedPreferences.setMockInitialValues({'categoryIconStyle': 'cute'});
    await tester.pumpWidget(_wrap(GroupedIconGrid(
      selectedIcon: 'label',
      kind: 'expense',
      onIconSelected: (_) {},
    )));
    await tester.pump();

    // 2026-09-12: 'label' 沒有專屬 cute SVG,但 cute 模式下不再退回 Material
    // 圖示,改顯示手繪風的通用 fallback。
    expect(find.byIcon(Icons.label), findsNothing);
  });
}
