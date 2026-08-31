/// v47 迁移(SwipeSmart 信用卡对照,design doc
/// docs/superpowers/specs/2026-08-30-swipesmart-integration-design.md §3.1):
/// - accounts 新增 1 个可空列:swipesmart_card_id
/// - 无回填:既有资料该列为 NULL,语意上等同「尚未對照」。
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

  test('schemaVersion >= 47', () {
    // 不断言等于固定值——这份测试只关心 v47 本身的迁移行为,不该因为
    // 后续版本号推进(如 v48)而失败。
    expect(db.schemaVersion, greaterThanOrEqualTo(47));
  });

  test('v47 schema:accounts 带 swipesmart_card_id 可空列', () async {
    final cols = await db.customSelect("PRAGMA table_info(accounts)").get();
    final names = cols.map((r) => r.read<String>('name')).toSet();
    expect(names, contains('swipesmart_card_id'));
  });

  test('既有账户(模拟 v46 存量,无该字段)读回为 null', () async {
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, type, currency) "
        "VALUES (10, 1, '大戶信用卡', 'credit_card', 'TWD')");

    final acc = await (db.select(db.accounts)
          ..where((a) => a.id.equals(10)))
        .getSingle();
    expect(acc.swipesmartCardId, isNull);
  });

  test('写入并读回 swipesmart_card_id', () async {
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    final id = await db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: 1,
          name: '大戶信用卡',
          type: const d.Value('credit_card'),
          swipesmartCardId: const d.Value('sw-card-123'),
        ));
    final acc =
        await (db.select(db.accounts)..where((a) => a.id.equals(id)))
            .getSingle();
    expect(acc.swipesmartCardId, 'sw-card-123');
  });
}
