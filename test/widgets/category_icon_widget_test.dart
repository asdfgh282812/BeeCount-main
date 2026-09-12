import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:beecount/data/db.dart';
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

  testWidgets('cute style with an unregistered key falls back to Material icon',
      (tester) async {
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

    expect(find.byType(Icon), findsOneWidget);
    expect(find.byType(CuteCategoryIcon), findsNothing);
    // Color-coding still shows even when the glyph itself falls back.
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
