/// v51 迁移(支出/收入手续费/折扣,对齐 BeeCount Cloud
/// `read_tx_projection.base_amount`,`0039_tx_fee_discount.py`):
/// - transactions 新增 1 个可空列:base_amount
/// - 无回填:既有资料这一列为 NULL,语意上等同「没有使用手续费/折扣」,
///   `computeFeeDiscountNetAmount` 不会被调用,amount 维持既有值。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:beecount/data/db.dart';

void main() {
  late BeeDatabase db;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  test('schemaVersion >= 51', () {
    expect(db.schemaVersion, greaterThanOrEqualTo(51));
  });

  test('v51 schema:transactions 带 1 个可空的 base_amount 列', () async {
    final cols = await db.customSelect("PRAGMA table_info(transactions)").get();
    final names = cols.map((r) => r.read<String>('name')).toSet();
    expect(names, contains('base_amount'));
  });

  test('既有资料(模拟 v50 存量,无 base_amount 字段)读回为 null', () async {
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, currency) VALUES (10, 1, 'A', 'CNY')");
    // 模拟 v50 时代写入的支出行:不带 base_amount 字段。
    await db.customStatement(
        "INSERT INTO transactions (id, ledger_id, type, amount, account_id) "
        "VALUES (100, 1, 'expense', 200.0, 10)");

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(100)))
        .getSingle();
    expect(tx.baseAmount, isNull);
  });
}
