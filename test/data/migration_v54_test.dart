/// v54 迁移(清理分期計畫已刪但期數/交易引用還在的孤儿):
/// - 根因:分期計畫刪除是一次操作產生 N*2+1 筆獨立 change(每期一筆
///   installment_period:delete + 每期生成交易一筆 transaction:delete + 1 筆
///   installment_plan:delete),推送/拉取之間存在窗口期——如果 plan 的 delete
///   change 先落地,但某些 period/transaction 的 delete change 因為窗口期
///   race 而暫時(或最終)沒有同步過來,就会留下「plan 已刪,但
///   installment_periods.plan_sync_id / transactions.installment_plan_sync_id
///   仍指向這個不存在的 plan」的孤儿(見 docs/changes/2026-09-03-
///   installment-tracking-delete-sync-fixes.md 問題A,及 orphan_scanner.dart
///   的 A11/A12 自救工具)。这类孤儿的 ledgerId 仍然指向現存帳本,v53 那种
///   「ledger 不存在才清」的检查挡不住。
/// - 迁移对齐 orphan_scanner.dart/orphan_cleaner.dart 既有的 A11/A12 语义:
///   period 直接删(纯排程元数据,不影响它产生的真实交易);transaction 只清空
///   引用欄位,交易本身保留。
/// 这里直接执行迁移里的同一段 SQL(仓库既有 migration_v* 测试的惯例是校验
/// 这段额外 SQL 本身在各种既有资料形态下算得对,不驱动真正的 onUpgrade
/// from-version 分支)。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:beecount/data/db.dart';

const _clearOrphanTxPlanRefSql = '''
  UPDATE transactions
  SET installment_plan_sync_id = NULL
  WHERE installment_plan_sync_id IS NOT NULL
    AND installment_plan_sync_id NOT IN (
      SELECT sync_id FROM installment_plans WHERE sync_id IS NOT NULL
    );
''';

const _deleteOrphanPeriodsMissingPlanSql = '''
  DELETE FROM installment_periods
  WHERE plan_sync_id NOT IN (
    SELECT sync_id FROM installment_plans WHERE sync_id IS NOT NULL
  );
''';

Future<void> _runV54Cleanup(BeeDatabase db) async {
  await db.customStatement(_clearOrphanTxPlanRefSql);
  await db.customStatement(_deleteOrphanPeriodsMissingPlanSql);
}

void main() {
  late BeeDatabase db;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
  });

  tearDown(() async => db.close());

  test('schemaVersion >= 54', () {
    expect(db.schemaVersion, greaterThanOrEqualTo(54));
  });

  test('plan_sync_id 找不到对应 plan 的分期期数被删除', () async {
    // plan 已经被删(installment_plans 里没有 sync_id='plan-gone' 的行),但
    // 当年 v53 之前 race 留下的 period 还在,ledgerId 仍指向现存帳本 1。
    await db.customStatement(
        "INSERT INTO installment_periods (id, sync_id, ledger_id, plan_sync_id, period_no, due_at, principal_amount, interest_amount, total_amount) "
        "VALUES (1, 'period-orphan', 1, 'plan-gone', 1, 4102444800000, 1530.0, 0.0, 1530.0)");

    await _runV54Cleanup(db);

    final periods = await db.select(db.installmentPeriods).get();
    expect(periods, isEmpty);
  });

  test('installment_plan_sync_id 找不到对应 plan 的交易只清引用,交易本身保留', () async {
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, currency) VALUES (10, 1, 'A', 'CNY')");
    await db.customStatement(
        "INSERT INTO transactions (id, ledger_id, type, amount, account_id, installment_plan_sync_id) "
        "VALUES (100, 1, 'expense', 500.0, 10, 'plan-gone')");

    await _runV54Cleanup(db);

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(100)))
        .getSingle();
    expect(tx.installmentPlanSyncId, isNull);
    expect(tx.amount, 500.0, reason: '迁移不删交易本身,只清引用欄位');
  });

  test('plan 仍存在时,对应的期数/交易引用不受影响', () async {
    await db.customStatement(
        "INSERT INTO installment_plans (id, sync_id, ledger_id, total_amount, periods, first_period_at, category_id) "
        "VALUES (1, 'plan-live', 1, 1200.0, 12, 0, 1)");
    await db.customStatement(
        "INSERT INTO installment_periods (id, sync_id, ledger_id, plan_sync_id, period_no, due_at, principal_amount, interest_amount, total_amount) "
        "VALUES (1, 'period-live', 1, 'plan-live', 1, 4102444800000, 100.0, 0.0, 100.0)");
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, currency) VALUES (10, 1, 'A', 'CNY')");
    await db.customStatement(
        "INSERT INTO transactions (id, ledger_id, type, amount, account_id, installment_plan_sync_id) "
        "VALUES (100, 1, 'expense', 500.0, 10, 'plan-live')");

    await _runV54Cleanup(db);

    final periods = await db.select(db.installmentPeriods).get();
    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(100)))
        .getSingle();
    expect(periods, hasLength(1));
    expect(tx.installmentPlanSyncId, 'plan-live');
  });
}
