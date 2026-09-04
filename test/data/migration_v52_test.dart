/// v52 迁移(修补 base_amount 缺失的历史交易):
/// - 根因:某些历史 SyncChange 的 payload 只带了 feeAmount/discountAmount
///   却漏了 baseAmount 键,「缺键不覆盖」语意下 base_amount 永远停在 null。
/// - 迁移用必然正确的 amount 反推 base_amount(公式对齐
///   lib/utils/amount_calculator.dart computeBaseAmountFromNet),只处理
///   base_amount 为 NULL 且 fee/discount 非 0 的行,不动其余资料。
/// 这里直接执行迁移里的同一段 UPDATE SQL(仓库既有 migration_v* 测试的惯例
/// 是校验 onCreate 后的最终 schema 形态,不驱动真正的 onUpgrade from-version
/// 分支——这条额外验证 SQL 本身在各种既有资料形态下算得对)。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:beecount/data/db.dart';

const _backfillSql = '''
  UPDATE transactions
  SET base_amount = CASE
    WHEN type = 'expense' THEN
      ROUND(amount - COALESCE(fee_amount, 0) + COALESCE(discount_amount, 0), 2)
    ELSE
      ROUND(amount + COALESCE(fee_amount, 0) - COALESCE(discount_amount, 0), 2)
  END
  WHERE base_amount IS NULL
    AND type IN ('expense', 'income')
    AND (COALESCE(fee_amount, 0) != 0 OR COALESCE(discount_amount, 0) != 0);
''';

void main() {
  late BeeDatabase db;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, currency) VALUES (10, 1, 'A', 'CNY')");
  });

  tearDown(() async => db.close());

  test('schemaVersion >= 52', () {
    expect(db.schemaVersion, greaterThanOrEqualTo(52));
  });

  test('支出:fee 已启用但 base_amount 缺失 → 反推补齐', () async {
    await db.customStatement(
        "INSERT INTO transactions (id, ledger_id, type, amount, account_id, fee_amount, discount_amount) "
        "VALUES (100, 1, 'expense', 2691.0, 10, 40.0, 0.0)");
    await db.customStatement(_backfillSql);

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(100)))
        .getSingle();
    expect(tx.baseAmount, 2651.0);
  });

  test('收入:discount 已启用但 base_amount 缺失 → 反推补齐', () async {
    await db.customStatement(
        "INSERT INTO transactions (id, ledger_id, type, amount, account_id, discount_amount) "
        "VALUES (101, 1, 'income', 980.0, 10, 20.0)");
    await db.customStatement(_backfillSql);

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(101)))
        .getSingle();
    expect(tx.baseAmount, 960.0);
  });

  test('fee/discount 均为 0(或缺省)→ 不动 base_amount,保持 null', () async {
    await db.customStatement(
        "INSERT INTO transactions (id, ledger_id, type, amount, account_id) "
        "VALUES (102, 1, 'expense', 100.0, 10)");
    await db.customStatement(_backfillSql);

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(102)))
        .getSingle();
    expect(tx.baseAmount, isNull);
  });

  test('base_amount 已有值 → 不覆盖既有值(即便跟反推结果不同)', () async {
    await db.customStatement(
        "INSERT INTO transactions (id, ledger_id, type, amount, account_id, fee_amount, base_amount) "
        "VALUES (103, 1, 'expense', 2691.0, 10, 40.0, 2600.0)");
    await db.customStatement(_backfillSql);

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(103)))
        .getSingle();
    expect(tx.baseAmount, 2600.0, reason: '迁移只补 NULL,不覆盖既有资料');
  });

  test('转帐(type=transfer)不套用这条公式', () async {
    await db.customStatement(
        "INSERT INTO transactions (id, ledger_id, type, amount, account_id, fee_amount) "
        "VALUES (104, 1, 'transfer', 500.0, 10, 5.0)");
    await db.customStatement(_backfillSql);

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(104)))
        .getSingle();
    expect(tx.baseAmount, isNull);
  });
}
