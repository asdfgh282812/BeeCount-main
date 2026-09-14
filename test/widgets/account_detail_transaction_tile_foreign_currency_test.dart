/// `TransactionTile`(信用卡帳戶詳情頁「一般記錄」清單的每一列)在交易自身
/// 幣別(currencyCode)跟顯示用的帳戶幣別脫鉤時的呈現——2026-09-14 使用者
/// 反饋:台幣信用卡記一筆日圓 600 元消費(≈123.65 台幣),但這裡的金額只顯示
/// 台幣 600(算錯),回報後先修正了金額計算,接著使用者再回饋:應該比照首頁
/// 交易清單先顯示外幣原始金額、再顯示「≈折算金額」小字,但幣別不要用貨幣
/// 符號(¥ 同時是 JPY/CNY 的符號,會混淆),要用幣別縮寫文字(JPY)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart' as db;
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/account/account_detail_page.dart';
import 'package:beecount/providers/database_providers.dart';

db.Transaction _fakeExpense({
  required double amount,
  String? currencyCode,
  double? nativeAmount,
  int? categoryId,
}) {
  return db.Transaction(
    id: 1,
    ledgerId: 1,
    type: 'expense',
    amount: amount,
    categoryId: categoryId,
    accountId: 1,
    happenedAt: DateTime(2026, 9, 14, 12, 44),
    excludeFromStats: false,
    excludeFromBudget: false,
    currencyCode: currencyCode,
    nativeAmount: nativeAmount,
    recurringOccurrenceOverridden: false,
    hasSplits: false,
    needsAccountAssignment: false,
    needsProjectAssignment: false,
  );
}

db.Category _fakeCategory() => db.Category(
      id: 1,
      syncId: 'cat-1',
      name: '交通',
      kind: 'expense',
      icon: 'directions_bus',
      iconType: 'material',
      sortOrder: 0,
      level: 0,
    );

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      // TransactionTile 会 watch 这个拿转账分类图示,测试环境没有真实
      // repository/DB,直接 override 固定值避免打到 repositoryProvider。
      transferCategoryProvider.overrideWith((ref) async => _fakeCategory()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('交易幣別(JPY)跟帳戶幣別(TWD)不同時:顯示原始外幣金額 + 幣別縮寫文字(不是貨幣符號)+ 折算後的 ≈ 金額',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final category = _fakeCategory();
    final tx = _fakeExpense(
      amount: 600,
      currencyCode: 'JPY',
      nativeAmount: 123.65,
      categoryId: category.id,
    );

    await tester.pumpWidget(_wrap(TransactionTile(
      transaction: tx,
      currencyCode: 'TWD',
      primaryColor: Colors.orange,
      ledgers: const [],
      categories: [category],
      onTap: (_) {},
    )));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    // 幣別縮寫文字,不是符號 ¥。
    expect(find.textContaining('JPY'), findsOneWidget);
    expect(find.textContaining('¥'), findsNothing);
    // 原始外幣金額(600)跟折算後金額(123.65)都要顯示。
    expect(find.textContaining('600'), findsOneWidget);
    expect(find.text('≈123.65'), findsOneWidget);
  });

  testWidgets('同幣別(TWD)交易:維持原本單行顯示,不出現幣別縮寫或 ≈ 折算小字', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final category = _fakeCategory();
    final tx = _fakeExpense(
      amount: 150,
      currencyCode: 'TWD',
      nativeAmount: 150,
      categoryId: category.id,
    );

    await tester.pumpWidget(_wrap(TransactionTile(
      transaction: tx,
      currencyCode: 'TWD',
      primaryColor: Colors.orange,
      ledgers: const [],
      categories: [category],
      onTap: (_) {},
    )));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('TWD'), findsNothing);
    expect(find.textContaining('≈'), findsNothing);
    expect(find.textContaining('150'), findsOneWidget);
  });
}
