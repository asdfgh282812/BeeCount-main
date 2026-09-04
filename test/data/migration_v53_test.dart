/// v53 迁移(清理分期付款孤儿行):
/// - 根因:deleteLedger() 一直只 cascade transactions/budgets/debts,v49
///   新增的 installment_plans/installment_periods 没跟进——删帳本后
///   ledgerId 指向已经不存在的帳本,首页 getOutstandingPrincipalAllLedgers()
///   当时又不过滤 ledgerId,把这些孤儿本金也加总进「尚有应缴」,但分期列表页
///   按当前 ledgerId 过滤看不到,两边对不上(见使用者回报)。
/// - 迁移按「ledger_id 在 ledgers 表里找不到」删掉孤儿行,并把已有 syncId 的
///   孤儿行登记一条 local_changes delete,让云端也同步清掉。
/// 这里直接执行迁移里的同一段 SQL(仓库既有 migration_v* 测试的惯例是校验
/// 这段额外 SQL 本身在各种既有资料形态下算得对,不驱动真正的 onUpgrade
/// from-version 分支)。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:beecount/data/db.dart';

const _recordOrphanPeriodDeletesSql = '''
  INSERT INTO local_changes
    (entity_type, entity_id, entity_sync_id, ledger_id, action)
  SELECT 'installment_period', id, sync_id, ledger_id, 'delete'
  FROM installment_periods
  WHERE sync_id IS NOT NULL
    AND ledger_id NOT IN (SELECT id FROM ledgers);
''';

const _recordOrphanPlanDeletesSql = '''
  INSERT INTO local_changes
    (entity_type, entity_id, entity_sync_id, ledger_id, action)
  SELECT 'installment_plan', id, sync_id, ledger_id, 'delete'
  FROM installment_plans
  WHERE sync_id IS NOT NULL
    AND ledger_id NOT IN (SELECT id FROM ledgers);
''';

const _deleteOrphanPeriodsSql = '''
  DELETE FROM installment_periods
  WHERE ledger_id NOT IN (SELECT id FROM ledgers);
''';

const _deleteOrphanPlansSql = '''
  DELETE FROM installment_plans
  WHERE ledger_id NOT IN (SELECT id FROM ledgers);
''';

Future<void> _runV53Cleanup(BeeDatabase db) async {
  await db.customStatement(_recordOrphanPeriodDeletesSql);
  await db.customStatement(_recordOrphanPlanDeletesSql);
  await db.customStatement(_deleteOrphanPeriodsSql);
  await db.customStatement(_deleteOrphanPlansSql);
}

void main() {
  late BeeDatabase db;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
  });

  tearDown(() async => db.close());

  test('schemaVersion >= 53', () {
    expect(db.schemaVersion, greaterThanOrEqualTo(53));
  });

  test('ledgerId 已不存在的分期计划/期数被清除', () async {
    // 帳本 999 已经被删掉(ledgers 表里没有对应行),但当年建立的分期计划/
    // 期数因为 v53 之前的 deleteLedger() 漏 cascade 而残留下来。
    await db.customStatement(
        "INSERT INTO installment_plans (id, sync_id, ledger_id, total_amount, periods, first_period_at, category_id) "
        "VALUES (1, 'plan-orphan', 999, 1200.0, 12, 0, 1)");
    await db.customStatement(
        "INSERT INTO installment_periods (id, sync_id, ledger_id, plan_sync_id, period_no, due_at, principal_amount, interest_amount, total_amount) "
        "VALUES (1, 'period-orphan', 999, 'plan-orphan', 1, 4102444800000, 1530.0, 0.0, 1530.0)");

    await _runV53Cleanup(db);

    final plans = await db.select(db.installmentPlans).get();
    final periods = await db.select(db.installmentPeriods).get();
    expect(plans, isEmpty);
    expect(periods, isEmpty);
  });

  test('孤儿行清除时登记 local_changes delete,让云端跟着清', () async {
    await db.customStatement(
        "INSERT INTO installment_plans (id, sync_id, ledger_id, total_amount, periods, first_period_at, category_id) "
        "VALUES (1, 'plan-orphan', 999, 1200.0, 12, 0, 1)");
    await db.customStatement(
        "INSERT INTO installment_periods (id, sync_id, ledger_id, plan_sync_id, period_no, due_at, principal_amount, interest_amount, total_amount) "
        "VALUES (1, 'period-orphan', 999, 'plan-orphan', 1, 4102444800000, 1530.0, 0.0, 1530.0)");

    await _runV53Cleanup(db);

    final changes = await db.select(db.localChanges).get();
    expect(changes, hasLength(2));
    expect(
        changes.any((c) =>
            c.entityType == 'installment_plan' &&
            c.entitySyncId == 'plan-orphan' &&
            c.action == 'delete'),
        isTrue);
    expect(
        changes.any((c) =>
            c.entityType == 'installment_period' &&
            c.entitySyncId == 'period-orphan' &&
            c.action == 'delete'),
        isTrue);
  });

  test('sync_id 为 null 的孤儿行只删不登记 change(从未推送过云端)', () async {
    await db.customStatement(
        "INSERT INTO installment_plans (id, ledger_id, total_amount, periods, first_period_at, category_id) "
        "VALUES (1, 999, 1200.0, 12, 0, 1)");

    await _runV53Cleanup(db);

    final plans = await db.select(db.installmentPlans).get();
    final changes = await db.select(db.localChanges).get();
    expect(plans, isEmpty);
    expect(changes, isEmpty);
  });

  test('ledgerId 仍存在的分期计划/期数不受影响', () async {
    await db.customStatement(
        "INSERT INTO installment_plans (id, sync_id, ledger_id, total_amount, periods, first_period_at, category_id) "
        "VALUES (1, 'plan-live', 1, 1200.0, 12, 0, 1)");
    await db.customStatement(
        "INSERT INTO installment_periods (id, sync_id, ledger_id, plan_sync_id, period_no, due_at, principal_amount, interest_amount, total_amount) "
        "VALUES (1, 'period-live', 1, 'plan-live', 1, 4102444800000, 100.0, 0.0, 100.0)");

    await _runV53Cleanup(db);

    final plans = await db.select(db.installmentPlans).get();
    final periods = await db.select(db.installmentPeriods).get();
    expect(plans, hasLength(1));
    expect(periods, hasLength(1));
  });
}
