/// v58 迁移(信用卡到期自動扣繳,對齊 BeeCount Cloud `accounts.
/// auto_pay_enabled` + `accounts.auto_pay_from_account_id`,見
/// docs/changes/2026-09-07-credit-card-auto-pay-fields.md):
/// - accounts 新增 2 个列:auto_pay_enabled(NOT NULL DEFAULT 0)、
///   auto_pay_from_account_id(可空)
/// - 既有资料该两列分别落 false / NULL,语意上等同「未開自動扣繳」。
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

  test('schemaVersion >= 58', () {
    // 不断言等于固定值——这份测试只关心 v58 本身的迁移行为,不该因为
    // 后续版本号推进而失败。
    expect(db.schemaVersion, greaterThanOrEqualTo(58));
  });

  test('v58 schema:accounts 带 auto_pay_enabled / auto_pay_from_account_id 列',
      () async {
    final cols = await db.customSelect("PRAGMA table_info(accounts)").get();
    final names = cols.map((r) => r.read<String>('name')).toSet();
    expect(names, contains('auto_pay_enabled'));
    expect(names, contains('auto_pay_from_account_id'));
  });

  test('既有账户(模拟 v57 存量,无该字段)读回为 false / null', () async {
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, type, currency) "
        "VALUES (10, 1, '大戶信用卡', 'credit_card', 'TWD')");

    final acc = await (db.select(db.accounts)..where((a) => a.id.equals(10)))
        .getSingle();
    expect(acc.autoPayEnabled, isFalse);
    expect(acc.autoPayFromAccountId, isNull);
  });

  test('写入并读回 auto_pay_enabled / auto_pay_from_account_id', () async {
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    final sourceId = await db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: 1,
          name: '遠銀',
          type: const d.Value('bank_card'),
          syncId: const d.Value('src-sync-id'),
        ));
    final cardId = await db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: 1,
          name: '大戶信用卡',
          type: const d.Value('credit_card'),
          autoPayEnabled: const d.Value(true),
          autoPayFromAccountId: const d.Value('src-sync-id'),
        ));
    final acc = await (db.select(db.accounts)
          ..where((a) => a.id.equals(cardId)))
        .getSingle();
    expect(acc.autoPayEnabled, isTrue);
    expect(acc.autoPayFromAccountId, 'src-sync-id');

    final source = await (db.select(db.accounts)
          ..where((a) => a.id.equals(sourceId)))
        .getSingle();
    expect(source.syncId, 'src-sync-id');
  });
}
