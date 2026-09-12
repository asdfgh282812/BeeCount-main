/// `TransactionListItem`(明細列表列)在 Cute 圖示主題下的呈現——
/// 2026-09-12 使用者反饋:這裡的分類圖示格是寫死 32x32 的圓形色底
/// `Container`,套上 Cute 模式「圖示+底線」的直向排版後,size=18 算出來的
/// 實際高度(18*1.25 + 間距 + 底線 ≈ 32.4)比固定的 32 高一點點,導致
/// `RenderFlex overflowed by 0.4 pixels`——第一次修正只拿掉了色底、卻仍把
/// 高度寫死在 32(不管是 Container 還是 SizedBox 都是同樣的「緊約束」),
/// 沒真的解決溢出,使用者截圖裡警告依舊在。真正的修正是只固定寬度、不設
/// 高度上限,讓 Column 依內容自然撐開。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/widgets/biz/transaction_list_item.dart';
import 'package:beecount/widgets/cute_icons/pencil_underline_painter.dart';

Category _fakeCategory({required String icon, String? color}) {
  return Category(
    id: 1,
    syncId: 'test-sync-id',
    name: '餐飲',
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
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets(
      'cute style: category icon cell does not overflow (regression for '
      'the 0.4px RenderFlex overflow reported 2026-09-12) and shows the '
      'color underline instead of a circle badge', (tester) async {
    SharedPreferences.setMockInitialValues({'categoryIconStyle': 'cute'});

    await tester.pumpWidget(_wrap(TransactionListItem(
      icon: Icons.restaurant,
      category: _fakeCategory(icon: 'restaurant', color: '#FF9800'),
      title: '午餐',
      amount: 120,
      isExpense: true,
      categoryName: '餐飲',
    )));
    await tester.pump();

    // 核心回归断言:不再有 RenderFlex overflow 之类的渲染异常。
    expect(tester.takeException(), isNull);
    expect(find.byType(CategoryColorUnderline), findsOneWidget);

    // 圆形色底徽章已拿掉——找不到任何 BoxDecoration(shape: circle) 的
    // Container 包着分类图示区。
    final circleContainers = find
        .byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle)
        .evaluate();
    expect(circleContainers, isEmpty);
  });

  testWidgets('material style: still shows the circle badge, no underline',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(_wrap(TransactionListItem(
      icon: Icons.restaurant,
      category: _fakeCategory(icon: 'restaurant', color: '#FF9800'),
      title: '午餐',
      amount: 120,
      isExpense: true,
      categoryName: '餐飲',
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CategoryColorUnderline), findsNothing);
    final circleContainers = find
        .byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle)
        .evaluate();
    expect(circleContainers, isNotEmpty);
  });
}
