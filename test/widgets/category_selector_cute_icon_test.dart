/// 「支出/收入」單獨進入的分類選擇格(`CategorySelector` 的 `_CategoryItem`)
/// 在 Cute 圖示主題下的呈現——2026-09-12 使用者反饋:這個分類選擇格自己包了
/// 一層色底 `Container`(不是走 `CategoryIconWidget` 的 `showBackground` 路徑),
/// 跟先前處理的「建議」格是同一類問題,cute 模式下也要拿掉色底、改用底線。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/widgets/category/category_selector.dart';
import 'package:beecount/widgets/cute_icons/pencil_underline_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    await db.customStatement("INSERT INTO categories "
        "(id, name, kind, icon, icon_type, color, sort_order, level, sync_id) "
        "VALUES (1, '餐飲', 'expense', 'restaurant', 'material', '#3F9DA6', 0, 1, 'c1')");
  });

  tearDown(() async => db.close());

  Widget host() {
    return ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: CategorySelector(kind: 'expense', onCategorySelected: (_) {}),
        ),
      ),
    );
  }

  testWidgets('material style keeps the colored circular badge, no underline',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.byType(CategoryColorUnderline), findsNothing);
    final circles = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).shape == BoxShape.circle &&
            (c.decoration as BoxDecoration).color == const Color(0xFF3F9DA6));
    expect(circles, isNotEmpty);
  });

  testWidgets('cute style drops the colored circle and shows an underline',
      (tester) async {
    SharedPreferences.setMockInitialValues({'categoryIconStyle': 'cute'});
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.byType(CategoryColorUnderline), findsOneWidget);
    final circles = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).shape == BoxShape.circle &&
            (c.decoration as BoxDecoration).color == const Color(0xFF3F9DA6));
    expect(circles, isEmpty);
  });
}
