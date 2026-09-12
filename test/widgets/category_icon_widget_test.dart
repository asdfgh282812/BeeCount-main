import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/providers/theme_providers.dart';
import 'package:beecount/styles/tokens.dart';
import 'package:beecount/widgets/category_icon.dart';
import 'package:beecount/widgets/cute_icons/cute_category_icon_keys.dart';
import 'package:beecount/widgets/cute_icons/pencil_underline_painter.dart';

Category _fakeCategory({
  required String icon,
  String? color,
  String iconType = 'material',
}) {
  return Category(
    id: 1,
    syncId: 'test-sync-id',
    name: 'test',
    kind: 'expense',
    icon: icon,
    iconType: iconType,
    color: color,
    sortOrder: 0,
    level: 0,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'categoryIconStyle': 'cute'});
  });

  testWidgets(
      'cute style with a registered key renders CuteCategoryIcon + underline',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CategoryIconWidget(
              category: _fakeCategory(icon: 'restaurant', color: '#3F9DA6'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CuteCategoryIcon), findsOneWidget);
    expect(find.byType(CategoryColorUnderline), findsOneWidget);
  });

  testWidgets(
      'cute style with an unregistered key renders the generic fallback '
      'cute icon, not a Material icon', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CategoryIconWidget(
              category: _fakeCategory(icon: 'some_future_icon_key'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 2026-09-12: cute 模式下不再退回 Material 图示,没有专属素材的 key 也
    // 显示手绘风的通用 fallback 图示。
    expect(find.byType(Icon), findsNothing);
    expect(find.byType(CuteCategoryIcon), findsOneWidget);
    expect(find.byType(CategoryColorUnderline), findsOneWidget);
  });

  testWidgets(
      'cute style with no category color falls back to a neutral underline, '
      'not the app-wide primaryColor (2026-09-12: 節日限定金色主題下沒配色的'
      '分類底線曾經誤用 primaryColor,看起來像沒套用分類色)', (tester) async {
    const distinctivePrimary = Color(0xFFAA00FF);
    late Color underlineColor;
    late Color neutralToken;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          primaryColorProvider.overrideWith((ref) => distinctivePrimary),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              neutralToken = BeeTokens.iconCategory(context);
              return CategoryIconWidget(
                category: _fakeCategory(icon: 'restaurant', color: null),
              );
            }),
          ),
        ),
      ),
    );
    await tester.pump();

    underlineColor =
        tester.widget<CategoryColorUnderline>(find.byType(CategoryColorUnderline)).color;
    expect(underlineColor, isNot(distinctivePrimary));
    expect(underlineColor, neutralToken);
  });

  testWidgets(
      'cute style ignores showBackground: true — no circle badge, still an underline',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CategoryIconWidget(
              category: _fakeCategory(icon: 'restaurant', color: '#3F9DA6'),
              showBackground: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Reaching CuteCategoryIcon/CategoryColorUnderline at all proves the cute
    // Column branch ran instead of the showBackground==true circle-Container
    // branch (that branch never builds either of these widgets).
    expect(find.byType(CuteCategoryIcon), findsOneWidget);
    expect(find.byType(CategoryColorUnderline), findsOneWidget);
  });

  testWidgets('material style renders the plain Icon with no underline',
      (tester) async {
    SharedPreferences.setMockInitialValues({'categoryIconStyle': 'material'});
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CategoryIconWidget(
              category: _fakeCategory(icon: 'restaurant'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Icon), findsOneWidget);
    expect(find.byType(CategoryColorUnderline), findsNothing);
  });
}
