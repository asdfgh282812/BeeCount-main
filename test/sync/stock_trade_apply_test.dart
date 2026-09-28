// v63 股票持股 — sync 路徑:
//   - pull 下來的 stock_trade upsert/delete 正確落地(帳戶 syncId → 本地 id)
//   - account 的 investmentSettings 缺鍵保留、帶鍵覆蓋
//   - serializeStockTrade 的 wire key 對齊 Cloud _LEDGER_MERGE_SPECS["stock_trade"]
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' show Value;

import 'package:beecount/cloud/sync/change_tracker.dart';
import 'package:beecount/cloud/sync/entity_serializer.dart';
import 'package:beecount/cloud/sync/sync_engine.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

import '../cloud/sync/_fakes/fake_beecount_cloud_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late ChangeTracker changeTracker;
  late LocalRepository repo;
  late FakeBeeCountCloudProvider provider;
  late SyncEngine engine;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    changeTracker = ChangeTracker(db);
    repo = LocalRepository(db, changeTracker: changeTracker);
    provider = FakeBeeCountCloudProvider();
    engine = SyncEngine(db: db, provider: provider, changeTracker: changeTracker, repo: repo);
  });

  tearDown(() async => db.close());

  Future<int> seedLedger() => db.into(db.ledgers).insert(LedgersCompanion.insert(
        name: '帳本',
        syncId: const Value('lg-stock'),
        monthStartDay: const Value(1),
      ));

  Map<String, dynamic> tradePayload({String note = '第一筆'}) => {
        'syncId': 'stk-1',
        'accountId': 'acc-inv',
        'market': 'TW',
        'symbol': '2330',
        'securityName': '台積電',
        'tradeType': 'buy',
        'shares': 1000,
        'price': 600,
        'fee': 855,
        'tax': 0,
        'amount': 600855,
        'currency': 'TWD',
        'tradeDate': '2026-09-01T02:00:00+00:00',
        'txId': 'tx-1',
        'note': note,
      };

  test('pull upsert → 本地明細(帳戶 syncId 解析成本地 id);delete → 移除', () async {
    final lid = await seedLedger();
    final accId = await repo.createAccount(ledgerId: lid, name: '證券', type: 'investment', syncId: 'acc-inv');

    provider.pushFakeChange(entityType: 'stock_trade', entitySyncId: 'stk-1', ledgerId: 'lg-stock',
        payload: tradePayload());
    await engine.pull('');
    final row = await (db.select(db.stockTrades)..where((t) => t.syncId.equals('stk-1'))).getSingle();
    expect(row.ledgerId, lid);
    expect(row.accountId, accId);
    expect(row.shares, 1000);
    expect(row.txSyncId, 'tx-1');
    expect(row.tradeDate.toUtc(), DateTime.utc(2026, 9, 1, 2));

    provider.pushFakeChange(entityType: 'stock_trade', entitySyncId: 'stk-1', ledgerId: 'lg-stock',
        payload: tradePayload(note: '改備註'));
    await engine.pull('');
    final updated = await (db.select(db.stockTrades)..where((t) => t.syncId.equals('stk-1'))).get();
    expect(updated.single.note, '改備註');

    provider.pushFakeChange(entityType: 'stock_trade', entitySyncId: 'stk-1', ledgerId: 'lg-stock',
        payload: const {}, action: 'delete');
    await engine.pull('');
    expect(await db.select(db.stockTrades).get(), isEmpty);
  });

  test('account investmentSettings:帶鍵覆蓋、缺鍵保留', () async {
    final lid = await seedLedger();
    await repo.createAccount(ledgerId: lid, name: '證券', type: 'investment', syncId: 'acc-inv');
    provider.pushFakeChange(entityType: 'account', entitySyncId: 'acc-inv', ledgerId: '$lid', payload: {
      'syncId': 'acc-inv',
      'name': '證券',
      'type': 'investment',
      'investmentSettings': {'feeDiscount': 0.6},
    });
    await engine.pull('');
    var acc = await (db.select(db.accounts)..where((a) => a.syncId.equals('acc-inv'))).getSingle();
    expect(jsonDecode(acc.investmentSettingsJson!), {'feeDiscount': 0.6});

    provider.pushFakeChange(entityType: 'account', entitySyncId: 'acc-inv', ledgerId: '$lid', payload: {
      'syncId': 'acc-inv',
      'name': '證券改名',
    });
    await engine.pull('');
    acc = await (db.select(db.accounts)..where((a) => a.syncId.equals('acc-inv'))).getSingle();
    expect(acc.name, '證券改名');
    expect(jsonDecode(acc.investmentSettingsJson!), {'feeDiscount': 0.6});
  });

  test('serializeStockTrade wire keys 對齊 Cloud merge spec', () async {
    final lid = await seedLedger();
    final id = await db.into(db.stockTrades).insert(StockTradesCompanion.insert(
          syncId: const Value('stk-9'),
          ledgerId: lid,
          market: 'TW',
          symbol: '2330',
          tradeType: 'buy',
          shares: 1,
          tradeDate: DateTime.utc(2026, 9, 1),
        ));
    final trade = await (db.select(db.stockTrades)..where((t) => t.id.equals(id))).getSingle();
    final payload = EntitySerializer.serializeStockTrade(trade, accountSyncId: 'acc-inv');
    // 跟 BeeCount-Cloud src/sync_applier.py _LEDGER_MERGE_SPECS["stock_trade"] 的 payload key 一致
    const cloudKeys = {
      'syncId', 'accountId', 'market', 'symbol', 'securityName', 'tradeType', 'shares', 'price',
      'fee', 'tax', 'amount', 'currency', 'tradeDate', 'txId', 'dividendEventRef', 'note',
    };
    expect(payload.keys.toSet(), cloudKeys);
    expect(payload['tradeDate'], '2026-09-01T00:00:00.000Z');
  });
}
