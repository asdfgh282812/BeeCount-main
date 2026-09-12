/// v61 迁移(帳戶頁面單帳戶金額隱藏,對齊 BeeCount Cloud `accounts.
/// hide_amount`,見 docs/superpowers/specs/
/// 2026-09-13-account-hide-amount-design.md):
/// - accounts 新增 1 个列:hide_amount(NOT NULL DEFAULT 0)
/// - 既有资料该列落 false,语意上等同「金額不隱藏」,不影响既有数据。
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';

import 'package:beecount/data/db.dart';

void main() {
  late BeeDatabase db;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  test('schemaVersion >= 61', () {
    // 不断言等于固定值——这份测试只关心 v61 本身的迁移行为,不该因为
    // 后续版本号推进而失败。
    expect(db.schemaVersion, greaterThanOrEqualTo(61));
  });

  test('v61 schema:accounts 带 hide_amount 列', () async {
    final cols = await db.customSelect("PRAGMA table_info(accounts)").get();
    final names = cols.map((r) => r.read<String>('name')).toSet();
    expect(names, contains('hide_amount'));
  });

  test('既有账户(模拟 v60 存量,无该字段)读回为 false', () async {
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, type, currency) "
        "VALUES (10, 1, '銀行卡', 'bank_card', 'TWD')");

    final acc = await (db.select(db.accounts)..where((a) => a.id.equals(10)))
        .getSingle();
    expect(acc.hideAmount, isFalse);
  });

  test('写入并读回 hide_amount', () async {
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    final id = await db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: 1,
          name: '私房錢',
          type: const d.Value('cash'),
          hideAmount: const d.Value(true),
        ));
    final acc = await (db.select(db.accounts)..where((a) => a.id.equals(id)))
        .getSingle();
    expect(acc.hideAmount, isTrue);
  });
}
