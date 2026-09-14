/// `TransactionListItem`(首頁交易清單的每一列)外幣交易的顯示——2026-09-14
/// 使用者反饋:台幣信用卡記一筆日圓 600 元消費(≈120 台幣),首頁清單原本用
/// 貨幣符號 `¥` 標示外幣(`showCurrency: _isForeign(ref)`,見 v30 多币种
/// 註解),但 `¥` 同時是 JPY/CNY 共用的符號,容易誤導使用者以為這筆錢的原始
/// 幣別是人民幣;改成用幣別縮寫文字(例如 JPY)取代符號。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/widgets/biz/transaction_list_item.dart';

Category _fakeCategory() {
  return Category(
    id: 1,
    syncId: 'test-sync-id',
    name: '交通',
    kind: 'expense',
    icon: 'directions_bus',
    iconType: 'material',
    sortOrder: 0,
    level: 0,
  );
}

Ledger _twdLedger() => Ledger(
      id: 1,
      name: '我的帳本',
      currency: 'TWD',
      type: 'personal',
      createdAt: DateTime(2026, 1, 1),
      myRole: 'owner',
      memberCount: 1,
      isShared: false,
      monthStartDay: 1,
    );

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      categoriesProvider.overrideWith((ref) async => [_fakeCategory()]),
      currentLedgerProvider
          .overrideWith((ref) => Stream<Ledger?>.value(_twdLedger())),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('交易幣別(JPY)跟帳本本位幣(TWD)不同時:顯示幣別縮寫文字(不是貨幣符號 ¥)+ ≈折算金額',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(_wrap(TransactionListItem(
      icon: Icons.directions_bus,
      category: _fakeCategory(),
      title: '手扶梯',
      amount: 600,
      currencyCode: 'JPY',
      nativeAmount: 120,
      isExpense: true,
      categoryName: '交通',
    )));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('JPY'), findsOneWidget);
    expect(find.textContaining('¥'), findsNothing);
    expect(find.textContaining('600'), findsOneWidget);
    expect(find.text('≈120.00'), findsOneWidget);
  });

  testWidgets('同幣別交易:不顯示幣別縮寫文字,也不顯示 ≈ 折算小字', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(_wrap(TransactionListItem(
      icon: Icons.directions_bus,
      category: _fakeCategory(),
      title: '公車',
      amount: 30,
      isExpense: true,
      categoryName: '交通',
    )));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('≈'), findsNothing);
    expect(find.textContaining('30'), findsOneWidget);
  });
}
