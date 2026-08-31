/// v46 迁移(转账手续费/折损,design doc
/// docs/superpowers/specs/2026-08-29-transfer-fee-discount-design.md §2):
/// - transactions 新增 4 个可空列:fee_amount / fee_label / discount_amount /
///   discount_label
/// - 无回填:既有资料这 4 列全部为 NULL,语意上等同「没有手续费/折损」,
///   `_transferOutEffect`/`_transferInEffect` 两个 helper 遇到 NULL 会退化回
///   改动前的行为(见 transfer_fee_discount_balance_test.dart 的回归测试)。
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:beecount/data/db.dart';

void main() {
  late BeeDatabase db;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  test('schemaVersion >= 46', () {
    // 不再断言等于某个固定值——每次新 migration 上线都会推进这个数字,
    // 这份测试只关心 v46 本身的迁移行为,不该因为后续版本号推进而失败
    // (v48 起改用 >= 断言,同步修正 migration_v47_test.dart)。
    expect(db.schemaVersion, greaterThanOrEqualTo(46));
  });

  test('v46 schema:transactions 带 4 个可空的 fee/discount 列', () async {
    final cols =
        await db.customSelect("PRAGMA table_info(transactions)").get();
    final names = cols.map((r) => r.read<String>('name')).toSet();
    expect(names, containsAll(['fee_amount', 'fee_label', 'discount_amount', 'discount_label']));
  });

  test('既有资料(模拟 v45 存量,无这 4 个字段)读回全部为 null', () async {
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, currency) VALUES (10, 1, 'A', 'CNY')");
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, currency) VALUES (11, 1, 'B', 'CNY')");
    // 模拟 v45 时代写入的转账行:不带 fee/discount 任何字段。
    await db.customStatement(
        "INSERT INTO transactions (id, ledger_id, type, amount, account_id, to_account_id) "
        "VALUES (100, 1, 'transfer', 200.0, 10, 11)");

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(100)))
        .getSingle();
    expect(tx.feeAmount, isNull);
    expect(tx.feeLabel, isNull);
    expect(tx.discountAmount, isNull);
    expect(tx.discountLabel, isNull);
  });
}
