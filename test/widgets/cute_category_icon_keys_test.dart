import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/widgets/cute_icons/cute_category_icon_keys.dart';

void main() {
  test(
      'registry covers the original 18, the 111 default-category keys, and '
      'the 159 remaining category_service.dart keys added 2026-09-12 '
      '(288 total, no dupes — full CategoryService.getCategoryIcon coverage)',
      () {
    expect(kCuteCategoryIconKeys.length, 288);
    // A few from the original 18 (Task 3).
    for (final key in ['restaurant', 'home', 'pets', 'trending_up']) {
      expect(kCuteCategoryIconKeys.contains(key), isTrue, reason: key);
    }
    // A few from the first 2026-09-12 default-category expansion.
    for (final key in ['coffee', 'account_balance', 'work', 'star', 'yard']) {
      expect(kCuteCategoryIconKeys.contains(key), isTrue, reason: key);
    }
    // A few from the second 2026-09-12 expansion (full table coverage).
    for (final key in ['train', 'boat', 'category', 'bookmark', 'wifi']) {
      expect(kCuteCategoryIconKeys.contains(key), isTrue, reason: key);
    }
  });

  test(
      'maybeBuild never returns null — unregistered/null keys resolve to the '
      'generic fallback asset instead of falling back to a Material icon',
      () {
    final covered = CuteCategoryIcon.maybeBuild(
        iconKey: 'restaurant', size: 24, lineColor: Colors.black87);
    expect(covered, isA<CuteCategoryIcon>());
    expect((covered as CuteCategoryIcon).iconKey, 'restaurant');

    final uncovered = CuteCategoryIcon.maybeBuild(
        iconKey: 'some_future_icon_key', size: 24, lineColor: Colors.black87);
    expect(uncovered, isA<CuteCategoryIcon>());
    expect((uncovered as CuteCategoryIcon).iconKey, '_fallback');

    final nullKey = CuteCategoryIcon.maybeBuild(
        iconKey: null, size: 24, lineColor: Colors.black87);
    expect(nullKey, isA<CuteCategoryIcon>());
    expect((nullKey as CuteCategoryIcon).iconKey, '_fallback');
  });

  testWidgets(
      'maybeBuild returns a working themed icon for a registered key',
      (tester) async {
    final widget = CuteCategoryIcon.maybeBuild(
        iconKey: 'restaurant', size: 24, lineColor: Colors.black87);

    // This intentionally requires assets/icons/categories_cute/restaurant.svg
    // to actually exist in the checkout — a key registered in
    // kCuteCategoryIconKeys without its file is exactly the bug this test
    // exists to catch, not something to work around.
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'maybeBuild renders the generic _fallback.svg for an uncovered key '
      'without throwing', (tester) async {
    final widget = CuteCategoryIcon.maybeBuild(
        iconKey: 'some_future_icon_key', size: 24, lineColor: Colors.black87);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
