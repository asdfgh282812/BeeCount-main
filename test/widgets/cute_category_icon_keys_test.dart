import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/widgets/cute_icons/cute_category_icon_keys.dart';

void main() {
  test('registry has exactly the 18 confirmed real icon keys', () {
    const expectedKeys = [
      'restaurant',
      'bakery_dining',
      'directions_bus',
      'shopping_bag',
      'shopping_cart',
      'home',
      'flash_on',
      'sports_esports',
      'local_hospital',
      'menu_book',
      'smartphone',
      'checkroom',
      'card_travel',
      'laptop',
      'pets',
      'fitness_center',
      'account_balance_wallet',
      'trending_up',
    ];
    expect(kCuteCategoryIconKeys, expectedKeys.toSet());
  });

  test('maybeBuild returns null for an unregistered or null key', () {
    expect(
      CuteCategoryIcon.maybeBuild(
          iconKey: 'some_future_icon_key', size: 24, lineColor: Colors.black87),
      isNull,
    );
    expect(
      CuteCategoryIcon.maybeBuild(
          iconKey: null, size: 24, lineColor: Colors.black87),
      isNull,
    );
  });

  testWidgets('maybeBuild returns a working themed icon for a registered key',
      (tester) async {
    final widget = CuteCategoryIcon.maybeBuild(
        iconKey: 'restaurant', size: 24, lineColor: Colors.black87);
    expect(widget, isA<CuteCategoryIcon>());

    // This intentionally requires assets/icons/categories_cute/restaurant.svg
    // to actually exist in the checkout (Step 1) — a key registered in
    // kCuteCategoryIconKeys without its file is exactly the bug this test
    // exists to catch, not something to work around.
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget!)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
