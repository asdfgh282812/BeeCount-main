// 信用卡帳單口徑「已刷卡金額」(getCreditCardChargedAsOf)要用入帳歸屬日
// (COALESCE(deferredPostingAt, happenedAt))做帳期截斷,不能用原始交易日
// happenedAt——否则一笔已標記「延後入帳」到下一期的交易,会在这期的
// charged 里被重复计入,跟「新增花費」等已经用歸屬日過濾的口径对不上
// (2026-08-18 使用者实测:一笔 140 元延後入帳交易导致「已繳金額」倒推出
// 异常负数,详见 docs/changes/2026-08-18-credit-card-payment-server-parity-fixes.md)。

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

  Future<int> seedAccount(int ledgerId) {
    return db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: ledgerId,
          name: '信用卡',
          type: const Value('credit_card'),
          syncId: const Value('acc-1'),
        ));
  }

  test('延後入帳的交易不计入原帳期的 charged,改计入延後後的日期所在帳期',
      () async {
    final lid = await seedLedger();
    final aid = await seedAccount(lid);

    // 原始消费发生在(原帳期结束日之前),但被延後入帳到下一期——两个日期
    // 都取实际系统时间之前(避免撞上 getCreditCardChargedAsOf 的
    // 「asOf 晚于现在一律 clamp 到现在」防呆逻辑,那是另一个独立行为)。
    final txId = await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 140,
      accountId: aid,
      happenedAt: DateTime(2020, 8, 5),
    );
    await repo.setTransactionDeferredPosting(
      id: txId,
      deferredPostingAt: DateTime(2020, 9, 10),
    );
    // 这期本来就有的一笔正常消费,没有延後。
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 7337,
      accountId: aid,
      happenedAt: DateTime(2020, 7, 20),
    );

    final chargedAtOldCycleEnd = await repo.getCreditCardChargedAsOf(
      aid,
      asOf: DateTime(2020, 8, 5, 23, 59, 59),
    );
    // 140 元那笔已经延後到 9/10,不该算进 8/5 结束的这期。
    expect(chargedAtOldCycleEnd, 7337);

    final chargedAtNewCycleEnd = await repo.getCreditCardChargedAsOf(
      aid,
      asOf: DateTime(2020, 9, 30),
    );
    // 延後後的日期(9/10)落在这个更晚的截斷点之前,应该算进去。
    expect(chargedAtNewCycleEnd, 7477);
  });

  test('没有延後入帳时,charged 仍照原始交易日截斷(行为不变)', () async {
    final lid = await seedLedger();
    final aid = await seedAccount(lid);

    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      accountId: aid,
      happenedAt: DateTime(2020, 8, 1),
    );
    await repo.addTransaction(
      ledgerId: lid,
      type: 'income',
      amount: 20,
      accountId: aid,
      happenedAt: DateTime(2020, 8, 2),
    );

    final charged = await repo.getCreditCardChargedAsOf(
      aid,
      asOf: DateTime(2020, 8, 5),
    );
    // Σexpense − Σincome = 100 − 20 = 80
    expect(charged, 80);
  });
}
