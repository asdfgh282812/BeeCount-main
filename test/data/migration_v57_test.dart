/// v57 迁移(修补分期期数缺失 sync_id 并补推云端):
/// - 根因:LocalInstallmentRepository.createInstallmentPlan() 逐期
///   insert installment_periods 时(建表以来)一直漏帶 syncId(同一迴圈里的
///   transaction insert 反而有明确带 `syncId: d.Value(_uuid.v4())`)——导致
///   LocalRepository.createInstallmentPlan() 登记 ChangeTracker 那段
///   `if (p.syncId == null) continue;` 恒为真,这些期数从未被记进
///   local_changes,自然也从未推送到云端。手机建立的分期计画因此在本机显示
///   正常(有完整期数),但 Web 端「期数明细」永远是空的。
/// - 迁移把 sync_id 为 null(且帳本仍存在)的期数补上 UUID,并登记一笔
///   local_changes upsert 让它们在下次同步时补推上云;已经有 sync_id 的期数
///   (本来就同步过的)不应该被重新登记。
/// 这里直接执行迁移里的同一段 SQL(仓库既有 migration_v* 测试的惯例是校验
/// 这段额外 SQL 本身在各种既有资料形态下算得对,不驱动真正的 onUpgrade
/// from-version 分支)。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:beecount/data/db.dart';

const _createTempTableSql = '''
  CREATE TEMP TABLE _v57_periods_to_fix AS
  SELECT id FROM installment_periods
  WHERE sync_id IS NULL
    AND ledger_id IN (SELECT id FROM ledgers);
''';

const _backfillSyncIdSql = '''
  UPDATE installment_periods
  SET sync_id = lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' ||
    substr(hex(randomblob(2)), 2) || '-' ||
    substr('89ab', abs(random()) % 4 + 1, 1) ||
    substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6)))
  WHERE id IN (SELECT id FROM _v57_periods_to_fix);
''';

const _recordBackfilledChangesSql = '''
  INSERT INTO local_changes
    (entity_type, entity_id, entity_sync_id, ledger_id, action)
  SELECT 'installment_period', id, sync_id, ledger_id, 'upsert'
  FROM installment_periods
  WHERE id IN (SELECT id FROM _v57_periods_to_fix);
''';

const _dropTempTableSql = 'DROP TABLE _v57_periods_to_fix;';

Future<void> _runV57Backfill(BeeDatabase db) async {
  await db.customStatement(_createTempTableSql);
  await db.customStatement(_backfillSyncIdSql);
  await db.customStatement(_recordBackfilledChangesSql);
  await db.customStatement(_dropTempTableSql);
}

void main() {
  late BeeDatabase db;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
  });

  tearDown(() async => db.close());

  test('schemaVersion >= 57', () {
    expect(db.schemaVersion, greaterThanOrEqualTo(57));
  });

  test('sync_id 为 null 的期数被补上 UUID', () async {
    await db.customStatement(
        "INSERT INTO installment_plans (id, sync_id, ledger_id, total_amount, periods, first_period_at, category_id) "
        "VALUES (1, 'plan-1', 1, 1200.0, 6, 0, 1)");
    await db.customStatement(
        "INSERT INTO installment_periods (id, ledger_id, plan_sync_id, period_no, due_at, principal_amount, interest_amount, total_amount) "
        "VALUES (1, 1, 'plan-1', 1, 4102444800000, 200.0, 0.0, 200.0)");

    await _runV57Backfill(db);

    final periods = await db.select(db.installmentPeriods).get();
    expect(periods, hasLength(1));
    expect(periods.single.syncId, isNotNull);
    expect(periods.single.syncId, isNotEmpty);
  });

  test('补上 sync_id 的期数登记一笔 local_changes upsert', () async {
    await db.customStatement(
        "INSERT INTO installment_plans (id, sync_id, ledger_id, total_amount, periods, first_period_at, category_id) "
        "VALUES (1, 'plan-1', 1, 1200.0, 6, 0, 1)");
    await db.customStatement(
        "INSERT INTO installment_periods (id, ledger_id, plan_sync_id, period_no, due_at, principal_amount, interest_amount, total_amount) "
        "VALUES (1, 1, 'plan-1', 1, 4102444800000, 200.0, 0.0, 200.0)");

    await _runV57Backfill(db);

    final periods = await db.select(db.installmentPeriods).get();
    final changes = await db.select(db.localChanges).get();
    expect(changes, hasLength(1));
    expect(changes.single.entityType, 'installment_period');
    expect(changes.single.entitySyncId, periods.single.syncId);
    expect(changes.single.action, 'upsert');
  });

  test('已经有 sync_id 的期数不受影响,也不会被重新登记 change', () async {
    await db.customStatement(
        "INSERT INTO installment_plans (id, sync_id, ledger_id, total_amount, periods, first_period_at, category_id) "
        "VALUES (1, 'plan-1', 1, 1200.0, 6, 0, 1)");
    await db.customStatement(
        "INSERT INTO installment_periods (id, sync_id, ledger_id, plan_sync_id, period_no, due_at, principal_amount, interest_amount, total_amount) "
        "VALUES (1, 'period-already-synced', 1, 'plan-1', 1, 4102444800000, 200.0, 0.0, 200.0)");

    await _runV57Backfill(db);

    final periods = await db.select(db.installmentPeriods).get();
    final changes = await db.select(db.localChanges).get();
    expect(periods.single.syncId, 'period-already-synced');
    expect(changes, isEmpty);
  });

  test('ledgerId 已不存在的孤儿期数不处理(留给既有 v53/v54 清理逻辑)',
      () async {
    await db.customStatement(
        "INSERT INTO installment_plans (id, sync_id, ledger_id, total_amount, periods, first_period_at, category_id) "
        "VALUES (1, 'plan-orphan', 999, 1200.0, 6, 0, 1)");
    await db.customStatement(
        "INSERT INTO installment_periods (id, ledger_id, plan_sync_id, period_no, due_at, principal_amount, interest_amount, total_amount) "
        "VALUES (1, 999, 'plan-orphan', 1, 4102444800000, 200.0, 0.0, 200.0)");

    await _runV57Backfill(db);

    final periods = await db.select(db.installmentPeriods).get();
    final changes = await db.select(db.localChanges).get();
    expect(periods.single.syncId, isNull);
    expect(changes, isEmpty);
  });

  test('一个计划多期时,每一期都各自补上不同的 sync_id', () async {
    await db.customStatement(
        "INSERT INTO installment_plans (id, sync_id, ledger_id, total_amount, periods, first_period_at, category_id) "
        "VALUES (1, 'plan-1', 1, 3933.0, 6, 0, 1)");
    for (var i = 1; i <= 6; i++) {
      await db.customStatement(
          "INSERT INTO installment_periods (id, ledger_id, plan_sync_id, period_no, due_at, principal_amount, interest_amount, total_amount) "
          "VALUES ($i, 1, 'plan-1', $i, 4102444800000, 3933.0, 0.0, 3933.0)");
    }

    await _runV57Backfill(db);

    final periods = await db.select(db.installmentPeriods).get();
    final syncIds = periods.map((p) => p.syncId).toSet();
    expect(periods, hasLength(6));
    expect(syncIds, everyElement(isNotNull));
    expect(syncIds, hasLength(6)); // 六个都不重复

    final changes = await db.select(db.localChanges).get();
    expect(changes, hasLength(6));
    expect(changes.every((c) => c.entityType == 'installment_period'), isTrue);
    expect(changes.every((c) => c.action == 'upsert'), isTrue);
  });
}
