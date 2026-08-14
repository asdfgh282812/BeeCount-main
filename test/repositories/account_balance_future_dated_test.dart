// 账户余额不该把「还没发生」的交易算进去(2026-08-15 实测反馈:资产管理页
// 把周期性交易预生成的未来账单也计入了信用卡欠款/余额)。
//
// 跟 BeeCount-Cloud/src/routers/read/workspace.py 的 `happened_at <= now`
// 口径对齐(该处注释记录了同一个使用者反馈 #1:信用卡显示的消费金额不该
// 连未来的都算进去)——周期性交易可以预先生成未来日期的记录(例如下个月
// 才扣款的订阅),在它真正发生前不该计入当前余额。

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

  Future<int> seedAccount(int ledgerId, {String type = 'credit_card'}) {
    return db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: ledgerId,
          name: '信用卡',
          type: Value(type),
          syncId: const Value('acc-1'),
        ));
  }

  test('getAccountBalance 排除未来日期的交易(周期性预生成账单)', () async {
    final lid = await seedLedger();
    final aid = await seedAccount(lid);
    final now = DateTime.now();

    // 已发生的消费 100
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      accountId: aid,
      happenedAt: now.subtract(const Duration(days: 1)),
    );
    // 周期性规则预生成的下个月账单 500,还没发生
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 500,
      accountId: aid,
      happenedAt: now.add(const Duration(days: 30)),
    );

    final balance = await repo.getAccountBalance(aid);

    // 只扣已发生的 100,未来的 500 不该算进当前欠款
    expect(balance, -100.0);
  });

  test('getAccountBalance 当天发生的交易仍计入', () async {
    final lid = await seedLedger();
    final aid = await seedAccount(lid);
    final now = DateTime.now();

    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 50,
      accountId: aid,
      happenedAt: now,
    );

    final balance = await repo.getAccountBalance(aid);
    expect(balance, -50.0);
  });

  test('getAccountBalanceInLedger 同样排除未来日期的交易', () async {
    final lid = await seedLedger();
    final aid = await seedAccount(lid);
    final now = DateTime.now();

    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      accountId: aid,
      happenedAt: now.subtract(const Duration(days: 1)),
    );
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 500,
      accountId: aid,
      happenedAt: now.add(const Duration(days: 30)),
    );

    final balance = await repo.getAccountBalanceInLedger(aid, lid);
    expect(balance, -100.0);
  });
}
