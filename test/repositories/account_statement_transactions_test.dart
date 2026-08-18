// getAccountStatementTransactions(對帳清單查詢)必須跟 BeeCount Cloud
// `get_account_statement` 的篩選/歸屬口徑逐筆一致——純日期窗口過濾
// (COALESCE(deferred_posting_at, happened_at)),不做任何「這筆繳款實際
// 沖銷哪一期舊欠款」的 FIFO 重新歸屬。這裡用「星展信用卡」的真實資料
// (2026-08-18 直接查 BeeCount Cloud 正式資料庫
// `postgresql://temp_user@10.0.4.20:5431/beecount` 核對過,詳見
// docs/changes/2026-08-18-credit-card-reconciliation-cloud-parity-fix.md)
// 逐筆重建成測試 fixture,鎖定這個行為,避免以後又被改回自創的期別歸屬
// 演算法。

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
          name: '测试账本',
          monthStartDay: const Value(1),
        ));
  }

  test('星展信用卡三期帳單:對帳清單筆數/金額跟 Cloud 正式資料庫核對一致', () async {
    final lid = await seedLedger();
    final groupId = await db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: lid,
          name: '星展信用卡',
          type: const Value('account_group'),
          syncId: const Value('acc_group'),
          billingDay: const Value(11),
          paymentDueDay: const Value(27),
        ));
    final ecoId = await db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: lid,
          name: '星展eco卡',
          type: const Value('credit_card'),
          syncId: const Value('acc_eco'),
          parentAccountId: const Value('acc_group'),
        ));
    final heroId = await db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: lid,
          name: '星展英雄聯盟卡',
          type: const Value('credit_card'),
          syncId: const Value('acc_hero'),
          parentAccountId: const Value('acc_group'),
        ));

    Future<void> expense(int accountId, double amount, DateTime happenedAt) =>
        repo
            .addTransaction(
              ledgerId: lid,
              type: 'expense',
              amount: amount,
              accountId: accountId,
              happenedAt: happenedAt,
            )
            .then((_) {});

    Future<void> income(int accountId, double amount, DateTime happenedAt) =>
        repo
            .addTransaction(
              ledgerId: lid,
              type: 'income',
              amount: amount,
              accountId: accountId,
              happenedAt: happenedAt,
            )
            .then((_) {});

    Future<void> deferredExpense(
      int accountId,
      double amount,
      DateTime happenedAt,
      DateTime deferredTo,
    ) async {
      final id = await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: amount,
        accountId: accountId,
        happenedAt: happenedAt,
      );
      await repo.setTransactionDeferredPosting(
          id: id, deferredPostingAt: deferredTo);
    }

    Future<void> transferIn(int toAccountId, double amount, DateTime at) => repo
        .addTransaction(
          ledgerId: lid,
          type: 'transfer',
          amount: amount,
          toAccountId: toAccountId,
          happenedAt: at,
        )
        .then((_) {});

    // 期一 2020/06/11–2020/07/11:6 筆一般消費,無繳款。
    await expense(heroId, 930, DateTime(2020, 7, 6, 16, 32));
    await expense(heroId, 398, DateTime(2020, 7, 6, 16, 33));
    await expense(heroId, 264, DateTime(2020, 7, 6, 16, 34));
    await expense(heroId, 420, DateTime(2020, 7, 7, 15, 5));
    await expense(heroId, 145, DateTime(2020, 7, 8, 15, 16));
    await expense(heroId, 147, DateTime(2020, 7, 11, 15, 3));

    // 期二 2020/07/11–2020/08/11:9 筆消費 + 1 筆回饋收入,無繳款。
    await expense(heroId, 1350, DateTime(2020, 7, 17, 16, 5));
    await expense(heroId, 486, DateTime(2020, 7, 19, 15, 3));
    await expense(heroId, 31, DateTime(2020, 7, 23, 11, 12));
    await income(heroId, 900, DateTime(2020, 7, 24, 18, 20));
    await expense(ecoId, 819, DateTime(2020, 7, 25, 1, 19));
    await expense(heroId, 91, DateTime(2020, 7, 27, 1, 24));
    await expense(heroId, 120, DateTime(2020, 8, 1, 7, 25));
    await expense(heroId, 2166, DateTime(2020, 8, 1, 8, 35));
    await expense(heroId, 66, DateTime(2020, 8, 2, 12, 21));
    await expense(heroId, 30, DateTime(2020, 8, 8, 1, 28));

    // 期三 2020/08/11–2020/09/11:4 筆延後入帳的消費(原始發生在期二窗口内,
    // 延後到 08/12)+ 1 筆回饋收入 + 2 筆一般消費 + 2 筆繳款轉入。
    await deferredExpense(
        heroId, 1197, DateTime(2020, 8, 8, 10, 7), DateTime(2020, 8, 12));
    await deferredExpense(
        heroId, 1554, DateTime(2020, 8, 8, 14, 2), DateTime(2020, 8, 12));
    await deferredExpense(
        heroId, 307, DateTime(2020, 8, 9, 16, 30), DateTime(2020, 8, 12));
    await deferredExpense(
        heroId, 54, DateTime(2020, 8, 10, 9, 33), DateTime(2020, 8, 12));
    await transferIn(ecoId, 819, DateTime(2020, 8, 12, 13, 7));
    await transferIn(heroId, 5744, DateTime(2020, 8, 12, 13, 7));
    await income(heroId, 300, DateTime(2020, 8, 12, 14, 11));
    await expense(ecoId, 969, DateTime(2020, 8, 25, 1, 19));
    await expense(heroId, 30, DateTime(2020, 9, 8, 15, 18));

    double statementTotal(List<Transaction> txs) {
      var total = 0.0;
      for (final t in txs) {
        if (t.type == 'transfer') continue;
        total += t.type == 'expense' ? t.amount : -t.amount;
      }
      return total;
    }

    // [cycleStart] 比照 `card_reward_period.dart::billingCyclePeriod` 的
    // 實際語意傳「上次結帳日隔天」(不是結帳日本身)——查詢邊界是
    // inclusive-both([cycleStart], [cycleEnd]),跟 Cloud
    // `attr_date > cycle_start_dt(結帳日 23:59:59)` 換算成隔天 00:00 的
    // 起點等價,呼叫端(`account_detail_page.dart`/
    // `account_reconciliation_page.dart`)一律用 [billingCyclePeriod] 算出
    // 這個值,不會直接傳結帳日本身。
    final period1 = await repo.getAccountStatementTransactions(
      accountId: groupId,
      extraAccountIds: [ecoId, heroId],
      cycleStart: DateTime(2020, 6, 12),
      cycleEnd: DateTime(2020, 7, 11),
    );
    expect(period1.length, 6);
    expect(statementTotal(period1), 2304);
    expect(period1.any((t) => t.type == 'transfer'), isFalse);

    final period2 = await repo.getAccountStatementTransactions(
      accountId: groupId,
      extraAccountIds: [ecoId, heroId],
      cycleStart: DateTime(2020, 7, 12),
      cycleEnd: DateTime(2020, 8, 11),
    );
    expect(period2.length, 10);
    expect(statementTotal(period2), 4259);
    expect(period2.any((t) => t.type == 'transfer'), isFalse);

    // 期三是這次修正的核心案例:兩筆繳款轉入(819/5744)必須依它們自己的
    // 入帳歸屬日(08/12)出現在這一期的清單裡——不是被 FIFO 模擬「歸屬」到
    // 已經結清的期一/期二。
    final period3 = await repo.getAccountStatementTransactions(
      accountId: groupId,
      extraAccountIds: [ecoId, heroId],
      cycleStart: DateTime(2020, 8, 12),
      cycleEnd: DateTime(2020, 9, 11),
    );
    expect(period3.length, 9);
    final transfersInPeriod3 = period3
        .where((t) => t.type == 'transfer')
        .map((t) => t.amount)
        .toList()
      ..sort();
    expect(transfersInPeriod3, [819, 5744]);
    // 新增花費(statement_total)口徑刻意排除轉帳,只算 expense/income——
    // 4 筆延後入帳消費(1197+1554+307+54)+ 2 筆一般消費(969+30)- 回饋 300。
    expect(statementTotal(period3), 3811);
  });
}
