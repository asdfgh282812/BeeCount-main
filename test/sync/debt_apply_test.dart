// 借還款(v39 debt,對齐 BeeCount Cloud debt entity)同步 apply 路径测试。
//
// debt 是 ledger-scope 实体,跟 budget/recurring_rule 同款全量 UPSERT 语义
// (不是 partial merge)——见 lib/cloud/sync/entity_serializer.dart::serializeDebt
// 的注释。dueAt/note/closedAt 恒發(同 reconciledAt),这里也测缺鍵時的行為。
//
// 還款交易走既有 _applyTransactionChange 路径,这里也顺带测 transaction
// payload 里新增的 debtId(存 syncId)键能正确落地成 Transactions.debtSyncId。
//
// 用 engine.pull('') 走真实 applyRemoteChange seam(public 入口），
// FakeBeeCountCloudProvider.pushFakeChange 注入远端 change。

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' show Value;

import 'package:beecount/cloud/sync/change_tracker.dart';
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
    engine = SyncEngine(
      db: db,
      provider: provider,
      changeTracker: changeTracker,
      repo: repo,
    );
  });

  tearDown(() async => db.close());

  Future<int> seedLedger({String? syncId}) {
    return db.into(db.ledgers).insert(LedgersCompanion.insert(
          name: '测试账本',
          monthStartDay: const Value(1),
          syncId: Value(syncId),
        ));
  }

  test('(insert) 远端新增欠款 → 本地插入且欄位齊全', () async {
    final lid = await seedLedger(syncId: 'ledger-1');

    provider.pushFakeChange(
      entityType: 'debt',
      entitySyncId: 'debt-1',
      ledgerId: 'ledger-1',
      payload: {
        'syncId': 'debt-1',
        'ledgerSyncId': 'ledger-1',
        'direction': 'payable',
        'counterpartyName': '小明',
        'principalAmount': 1000.0,
        'dueAt': '2026-03-01T00:00:00Z',
        'note': '借車錢',
        'closedAt': null,
      },
    );

    await engine.pull('');

    final debt = await repo.getDebtBySyncId('debt-1');
    expect(debt, isNotNull);
    expect(debt!.ledgerId, lid);
    expect(debt.direction, 'payable');
    expect(debt.counterpartyName, '小明');
    expect(debt.principalAmount, 1000.0);
    expect(debt.dueAt, isNotNull);
    expect(debt.note, '借車錢');
    expect(debt.closedAt, isNull);
  });

  test('(insert) payload 缺 ledgerSyncId 鍵(Cloud web 寫入的真實形狀)→ 仍靠 change.ledgerId 落地',
      () async {
    final lid = await seedLedger(syncId: 'ledger-web');

    provider.pushFakeChange(
      entityType: 'debt',
      entitySyncId: 'debt-web-1',
      ledgerId: 'ledger-web',
      payload: {
        'syncId': 'debt-web-1',
        // 故意不帶 ledgerSyncId 鍵——BeeCount Cloud 的 debt payload(無論
        // create/update 還是 snapshot 重建)都不帶這個鍵，只有 App 自己
        // push 時才會帶。必須 fallback 到 change.ledgerId 才能落地。
        'direction': 'payable',
        'counterpartyName': '易遊網',
        'principalAmount': 2920.0,
      },
    );

    await engine.pull('');

    final debt = await repo.getDebtBySyncId('debt-web-1');
    expect(debt, isNotNull);
    expect(debt!.ledgerId, lid);
    expect(debt.counterpartyName, '易遊網');
    expect(debt.principalAmount, 2920.0);
  });

  test('遠端 upsert 全量覆蓋 → dueAt/note/closedAt 缺鍵時視為清空(非 partial merge)',
      () async {
    final lid = await seedLedger(syncId: 'ledger-2');

    final id = await repo.createDebt(
      ledgerId: lid,
      direction: 'receivable',
      counterpartyName: '舊對象',
      principalAmount: 500,
      dueAt: DateTime(2026, 1, 1),
      note: '舊備註',
    );
    final before = await repo.getDebt(id);
    final syncId = before!.syncId!;

    provider.pushFakeChange(
      entityType: 'debt',
      entitySyncId: syncId,
      ledgerId: 'ledger-2',
      payload: {
        'syncId': syncId,
        'ledgerSyncId': 'ledger-2',
        'direction': 'receivable',
        'counterpartyName': '新對象',
        'principalAmount': 500.0,
        'dueAt': null,
        'note': null,
        'closedAt': null,
      },
    );

    await engine.pull('');

    final debt = await repo.getDebtBySyncId(syncId);
    expect(debt, isNotNull);
    expect(debt!.counterpartyName, '新對象');
    expect(debt.dueAt, isNull);
    expect(debt.note, isNull);
  });

  test('遠端 upsert 帶 closedAt → 本地結案', () async {
    final lid = await seedLedger(syncId: 'ledger-close');
    final id = await repo.createDebt(
      ledgerId: lid,
      direction: 'payable',
      counterpartyName: '對象',
      principalAmount: 200,
    );
    final syncId = (await repo.getDebt(id))!.syncId!;

    provider.pushFakeChange(
      entityType: 'debt',
      entitySyncId: syncId,
      ledgerId: 'ledger-close',
      payload: {
        'syncId': syncId,
        'ledgerSyncId': 'ledger-close',
        'direction': 'payable',
        'counterpartyName': '對象',
        'principalAmount': 200.0,
        'closedAt': '2026-02-01T00:00:00Z',
      },
    );

    await engine.pull('');

    final debt = await repo.getDebtBySyncId(syncId);
    expect(debt!.closedAt, isNotNull);
  });

  test('(delete) 遠端刪除欠款 → 本地對應行被移除', () async {
    final lid = await seedLedger(syncId: 'ledger-3');
    final id = await repo.createDebt(
      ledgerId: lid,
      direction: 'payable',
      counterpartyName: '對象',
      principalAmount: 100,
    );
    final syncId = (await repo.getDebt(id))!.syncId!;

    provider.pushFakeChange(
      entityType: 'debt',
      entitySyncId: syncId,
      ledgerId: 'ledger-3',
      action: 'delete',
    );

    await engine.pull('');

    expect(await repo.getDebtBySyncId(syncId), isNull);
  });

  test('遠端 upsert 帶 excludedFromTotal → 本地欄位正確落地(v42)', () async {
    final lid = await seedLedger(syncId: 'ledger-excl');
    final id = await repo.createDebt(
      ledgerId: lid,
      direction: 'payable',
      counterpartyName: '對象',
      principalAmount: 100,
    );
    final syncId = (await repo.getDebt(id))!.syncId!;
    expect((await repo.getDebt(id))!.excludedFromTotal, isFalse);

    provider.pushFakeChange(
      entityType: 'debt',
      entitySyncId: syncId,
      ledgerId: 'ledger-excl',
      payload: {
        'syncId': syncId,
        'ledgerSyncId': 'ledger-excl',
        'direction': 'payable',
        'counterpartyName': '對象',
        'principalAmount': 100.0,
        'excludedFromTotal': true,
      },
    );

    await engine.pull('');

    final debt = await repo.getDebtBySyncId(syncId);
    expect(debt!.excludedFromTotal, isTrue);
  });

  test('遠端 upsert 缺 excludedFromTotal 鍵 → 視為 false(不是 partial merge)',
      () async {
    final lid = await seedLedger(syncId: 'ledger-excl2');
    final id = await repo.createDebt(
      ledgerId: lid,
      direction: 'payable',
      counterpartyName: '對象',
      principalAmount: 100,
      excludedFromTotal: true,
    );
    final syncId = (await repo.getDebt(id))!.syncId!;
    expect((await repo.getDebt(id))!.excludedFromTotal, isTrue);

    provider.pushFakeChange(
      entityType: 'debt',
      entitySyncId: syncId,
      ledgerId: 'ledger-excl2',
      payload: {
        'syncId': syncId,
        'ledgerSyncId': 'ledger-excl2',
        'direction': 'payable',
        'counterpartyName': '對象',
        'principalAmount': 100.0,
        // 故意不帶 excludedFromTotal 鍵——debt 是全量 upsert 語意,缺鍵視為
        // false,不是保留舊值。
      },
    );

    await engine.pull('');

    final debt = await repo.getDebtBySyncId(syncId);
    expect(debt!.excludedFromTotal, isFalse);
  });

  test('账本本地尚未就緒(ledgerId 對不到)→ 跳過,不建孤兒欠款', () async {
    provider.pushFakeChange(
      entityType: 'debt',
      entitySyncId: 'debt-orphan',
      ledgerId: 'ledger-not-synced-yet',
      payload: {
        'syncId': 'debt-orphan',
        'ledgerSyncId': 'ledger-not-synced-yet',
        'direction': 'payable',
        'counterpartyName': '對象',
        'principalAmount': 10.0,
      },
    );

    await engine.pull('');

    expect(await repo.getDebtBySyncId('debt-orphan'), isNull);
  });

  test('(transaction payload) 遠端還款交易帶 debtId → 正確落地成 debtSyncId', () async {
    await seedLedger(syncId: 'ledger-4');

    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: 'tx-repayment-1',
      ledgerId: 'ledger-4',
      payload: {
        'syncId': 'tx-repayment-1',
        'type': 'expense',
        'amount': 100.0,
        'happenedAt': '2026-02-01T00:00:00Z',
        'ledgerSyncId': 'ledger-4',
        'categoryName': null,
        'categoryKind': null,
        'accountName': '',
        'accountId': '',
        'fromAccountName': '',
        'fromAccountId': '',
        'toAccountName': '',
        'toAccountId': '',
        'debtId': 'debt-xyz',
      },
    );

    await engine.pull('');

    final tx = await (db.select(db.transactions)
          ..where((t) => t.syncId.equals('tx-repayment-1')))
        .getSingle();
    expect(tx.debtSyncId, 'debt-xyz');
  });

  test('(transaction payload) 缺 debtId 鍵 → 不覆蓋本地已有的欠款關聯', () async {
    final lid = await seedLedger(syncId: 'ledger-5');
    final txId = await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 50,
      happenedAt: DateTime(2026, 1, 1),
      debtSyncId: 'debt-keep',
    );
    final tx = await repo.getTransactionById(txId);
    final syncId = tx!.syncId!;

    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: syncId,
      ledgerId: 'ledger-5',
      payload: {
        'syncId': syncId,
        'type': 'expense',
        'amount': 50.0,
        'happenedAt': '2026-01-01T00:00:00Z',
        'ledgerSyncId': 'ledger-5',
        'categoryName': null,
        'categoryKind': null,
        'accountName': '',
        'accountId': '',
        'fromAccountName': '',
        'fromAccountId': '',
        'toAccountName': '',
        'toAccountId': '',
        // 故意不帶 debtId 鍵。
      },
    );

    await engine.pull('');

    final updated = await (db.select(db.transactions)
          ..where((t) => t.syncId.equals(syncId)))
        .getSingle();
    expect(updated.debtSyncId, 'debt-keep');
  });
}
