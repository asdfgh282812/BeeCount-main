/// v62 迁移(回填既有跨幣別轉帳的 native_amount 快照,見
/// docs/changes/2026-09-18-transfer-direction-display-and-rate-fix.md):
/// - 純資料回填,不改 schema——轉帳(type='transfer')且 to_amount 非空、
///   轉入帳戶幣別剛好等於帳本本位幣時,native_amount 直接等於 to_amount
///   (免查表、保證精確)。
/// - 轉入帳戶幣別不是本位幣的情況缺乏「當時匯率」可回溯,維持原樣不動。
///
/// 這裡不走 onUpgrade 觸發路徑(schema 沒變,fresh install 也是同一份
/// schema,無法用「有沒有這個欄位」反推是否跑過遷移)——直接對 v62 這段
/// UPDATE SQL 本身的邏輯做驗證,確保 SQL 語法(相關子查詢 EXISTS、UPPER()
/// 幣別比對、ABS() 誤差容忍)在 SQLite 下如預期運作。
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:beecount/data/db.dart';

const _v62BackfillSql = '''
  UPDATE transactions
  SET native_amount = to_amount
  WHERE type = 'transfer'
    AND to_amount IS NOT NULL
    AND to_account_id IS NOT NULL
    AND (native_amount IS NULL OR ABS(native_amount - to_amount) > 0.0001)
    AND EXISTS (
      SELECT 1 FROM accounts a
      JOIN ledgers l ON l.id = transactions.ledger_id
      WHERE a.id = transactions.to_account_id
        AND UPPER(a.currency) = UPPER(l.currency)
    )
''';

void main() {
  late BeeDatabase db;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'TWD')");
  });

  tearDown(() async => db.close());

  test('schemaVersion >= 62', () {
    // 不断言等于固定值——这份测试只关心 v62 本身的迁移行为,不该因为
    // 后续版本号推进而失败。
    expect(db.schemaVersion, greaterThanOrEqualTo(62));
  });

  test('轉入帳戶幣別 = 帳本本位幣:native_amount 回填成 to_amount(使用者回報案例)',
      () async {
    // 玉山外幣戶(JPY)→ 玉山台幣戶(TWD),帳本本位幣也是 TWD。
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, type, currency) "
        "VALUES (10, 1, '玉山外幣戶', 'bank_card', 'JPY')");
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, type, currency) "
        "VALUES (11, 1, '玉山台幣戶', 'bank_card', 'TWD')");
    await db.customStatement('''
      INSERT INTO transactions
        (ledger_id, type, amount, account_id, to_account_id, happened_at,
         sync_id, currency_code, native_amount, to_amount)
      VALUES
        (1, 'transfer', 9016, 10, 11, 1700000000000,
         'tx-1', 'JPY', 1841.92, 1828)
    ''');

    await db.customStatement(_v62BackfillSql);

    final tx = await (db.select(db.transactions)
          ..where((t) => t.syncId.equals('tx-1')))
        .getSingle();
    expect(tx.nativeAmount, 1828);
  });

  test('轉入帳戶幣別不是帳本本位幣:native_amount 維持原樣不動', () async {
    // 轉入帳戶是 USD,帳本本位幣是 TWD——缺乏「當時匯率」可回溯,不處理。
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, type, currency) "
        "VALUES (20, 1, 'JPY戶', 'bank_card', 'JPY')");
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, type, currency) "
        "VALUES (21, 1, 'USD戶', 'bank_card', 'USD')");
    await db.customStatement('''
      INSERT INTO transactions
        (ledger_id, type, amount, account_id, to_account_id, happened_at,
         sync_id, currency_code, native_amount, to_amount)
      VALUES
        (1, 'transfer', 9016, 20, 21, 1700000000000,
         'tx-2', 'JPY', 1841.92, 60)
    ''');

    await db.customStatement(_v62BackfillSql);

    final tx = await (db.select(db.transactions)
          ..where((t) => t.syncId.equals('tx-2')))
        .getSingle();
    expect(tx.nativeAmount, 1841.92);
  });

  test('non-transfer 交易不受影響', () async {
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, type, currency) "
        "VALUES (30, 1, '台幣戶', 'bank_card', 'TWD')");
    await db.customStatement('''
      INSERT INTO transactions
        (ledger_id, type, amount, account_id, happened_at,
         sync_id, currency_code, native_amount)
      VALUES
        (1, 'expense', 100, 30, 1700000000000, 'tx-3', 'TWD', 100)
    ''');

    await db.customStatement(_v62BackfillSql);

    final tx = await (db.select(db.transactions)
          ..where((t) => t.syncId.equals('tx-3')))
        .getSingle();
    expect(tx.nativeAmount, 100);
  });

  test('已經是正確值時不重複觸發(冪等)', () async {
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, type, currency) "
        "VALUES (40, 1, 'JPY戶', 'bank_card', 'JPY')");
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, type, currency) "
        "VALUES (41, 1, 'TWD戶', 'bank_card', 'TWD')");
    await db.customStatement('''
      INSERT INTO transactions
        (ledger_id, type, amount, account_id, to_account_id, happened_at,
         sync_id, currency_code, native_amount, to_amount)
      VALUES
        (1, 'transfer', 9016, 40, 41, 1700000000000,
         'tx-4', 'JPY', 1828, 1828)
    ''');

    await db.customStatement(_v62BackfillSql);
    await db.customStatement(_v62BackfillSql); // 再跑一次,確認冪等

    final tx = await (db.select(db.transactions)
          ..where((t) => t.syncId.equals('tx-4')))
        .getSingle();
    expect(tx.nativeAmount, 1828);
  });
}
