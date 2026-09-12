/// 「建議」分頁類別格(`SuggestedCategoryGrid`)在 Cute 圖示主題下的呈現——
/// 2026-09-12 使用者反饋:圓形色底徽章太搶眼,Cute 模式下要拿掉色底,顏色
/// 改用底線呈現(跟列表頁的 `CategoryIconWidget` 一致);Material 模式維持
/// 原本圓形色底徽章不變。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/widgets/biz/suggested_category_grid.dart';
import 'package:beecount/widgets/cute_icons/pencil_underline_painter.dart';

Category _fakeCategory({required String icon, String? color}) {
  return Category(
    id: 1,
    syncId: 'test-sync-id',
    name: 'test',
    kind: 'expense',
    icon: icon,
    iconType: 'material',
    color: color,
    sortOrder: 0,
    level: 0,
  );
}

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('material style keeps the colored circular badge, no underline',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_wrap(SuggestedCategoryGrid(
      categories: [_fakeCategory(icon: 'restaurant', color: '#3F9DA6')],
      onCategorySelected: (_) {},
    )));
    await tester.pump();

    expect(find.byType(CategoryColorUnderline), findsNothing);
    final decoratedBoxes = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).shape == BoxShape.circle);
    expect(decoratedBoxes, isNotEmpty);
  });

  testWidgets('cute style drops the colored circle and shows an underline',
      (tester) async {
    SharedPreferences.setMockInitialValues({'categoryIconStyle': 'cute'});
    await tester.pumpWidget(_wrap(SuggestedCategoryGrid(
      categories: [_fakeCategory(icon: 'restaurant', color: '#3F9DA6')],
      onCategorySelected: (_) {},
    )));
    await tester.pump();

    expect(find.byType(CategoryColorUnderline), findsOneWidget);
  });
}
