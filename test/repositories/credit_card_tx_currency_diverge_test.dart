// 單一信用卡帳戶(非合併帳單群組)場景下,交易自身幣別(currencyCode)可以
// 跟帳戶自身幣別脫鉤(例如台幣信用卡記一筆日圓消費,見
// transaction_entry_form.dart 對應註解,對齐 Cloud 網頁端行為)。
//
// 2026-09-14 使用者反饋:台幣信用卡記一筆日圓 600 元的消費(≈123.65
// 台幣),但信用卡帳戶頁的「剩餘帳款」/「一般記錄」明細卻把這筆消費當成
// 台幣 600 元計入,而非折算後的 123.65——因為 [getAccountBalance]/
// [getCreditCardChargedAsOf] 原本不管交易自己的 currencyCode 是什麼,單一
// 帳戶(非群組)場景一律直接加減 `amount`(交易自己幣別下的原始數字),這個
// 假設在交易幣別可以跟帳戶脫鉤之後不再成立。
//
// 修法:只有在這筆交易自己的 currencyCode 跟帳戶自身幣別不同時,才改用
// `nativeAmount ?? amount`(記帳當下折算到帳本本位幣的快照,帳戶自身幣別
// 這裡等於帳本本位幣,兩者相等);同幣別的既有場景完全不受影響。

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

void main() {
  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
  });

  tearDown(() async => db.close());

  Future<int> seedLedger() {
    return db.into(db.ledgers).insert(LedgersCompanion.insert(
          name: '台幣帳本',
          currency: const Value('TWD'),
          monthStartDay: const Value(1),
        ));
  }

  Future<int> seedCreditCard(int ledgerId, String name) {
    return db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: ledgerId,
          name: name,
          type: const Value('credit_card'),
          currency: const Value('TWD'),
          syncId: Value(name),
        ));
  }

  test('getCreditCardChargedAsOf: 台幣信用卡記一筆日圓消費,charged 要用折算後的台幣金額,不是日圓原始數字',
      () async {
    final lid = await seedLedger();
    final cardId = await seedCreditCard(lid, 'uniopen聯名卡');

    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 600,
      currencyCode: 'JPY',
      nativeAmount: 123.65,
      accountId: cardId,
      happenedAt: DateTime(2026, 9, 14),
    );

    final charged = await repo.getCreditCardChargedAsOf(cardId);
    expect(charged, closeTo(123.65, 0.001));
  });

  test('getAccountBalance: 同一筆日圓消費,帳戶餘額也要用折算後的台幣金額計入', () async {
    final lid = await seedLedger();
    final cardId = await seedCreditCard(lid, 'uniopen聯名卡');

    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 600,
      currencyCode: 'JPY',
      nativeAmount: 123.65,
      accountId: cardId,
      happenedAt: DateTime(2026, 9, 14),
    );

    final balance = await repo.getAccountBalance(cardId);
    expect(balance, closeTo(-123.65, 0.001));
  });

  test('同幣別(TWD)消費不受影響,charged/balance 維持用原始 amount', () async {
    final lid = await seedLedger();
    final cardId = await seedCreditCard(lid, '台幣信用卡');

    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 150,
      currencyCode: 'TWD',
      nativeAmount: 150,
      accountId: cardId,
      happenedAt: DateTime(2026, 9, 14),
    );

    final charged = await repo.getCreditCardChargedAsOf(cardId);
    expect(charged, 150);
    final balance = await repo.getAccountBalance(cardId);
    expect(balance, -150);
  });
}
