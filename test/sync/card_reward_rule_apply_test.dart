// 信用卡紅利回饋規則(v35 card_reward_rule)同步 apply 路径测试。
//
// card_reward_rule 是 user-global 实体,generic sync push 走
// `projection.upsert_card_reward_rule` 的全量 UPSERT 语义(不是 partial
// merge,见 lib/cloud/sync/entity_serializer.dart::serializeCardRewardRule
// 的注释)——App 自己 push 时永远带出全部字段当前真值,所以这里测的是
// full-replace upsert 行为,不是 partial-update 缺键保留(那是
// account/transaction 那类走 `_merge_from_spec` 的 entity 才有的语义)。
//
// 这条用 engine.pull('') 走真实 applyRemoteChange seam(public 入口),
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

  Future<int> seedLedger() {
    return db.into(db.ledgers).insert(LedgersCompanion.insert(
          name: '测试账本',
          monthStartDay: const Value(1),
        ));
  }

  Future<Account> getAccountBySyncId(String syncId) => (db.select(db.accounts)
        ..where((a) => a.syncId.equals(syncId)))
      .getSingle();

  test('(insert) 远端新增紅利回饋規則 → 本地插入且欄位齊全', () async {
    final lid = await seedLedger();
    const accountSyncId = 'acc-cc-1';
    const ruleSyncId = 'rule-1';

    final accountId = await repo.createAccount(
      ledgerId: lid,
      name: '信用卡A',
      type: 'credit_card',
      currency: 'TWD',
      syncId: accountSyncId,
    );

    provider.pushFakeChange(
      entityType: 'card_reward_rule',
      entitySyncId: ruleSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': ruleSyncId,
        'accountId': accountSyncId,
        'label': '影音網購加碼',
        'categoryIds': <String>[],
        'rateType': 'percentage',
        'rateValue': 3.0,
        'rounding': 'round',
        'totalRounding': 'round',
        'calcBasis': 'transaction_date',
        'interval': 'billing_cycle',
        'minSpendThreshold': null,
        'minTxAmount': null,
        'capAmount': 300.0,
        'capSharedKey': null,
        'startsAt': '2025-01-01T00:00:00Z',
        'endsAt': '2027-12-31T00:00:00Z',
        'settlementType': 'period_end',
        'settlementDays': null,
        'settlementMonthOffset': 0,
        'settlementDayOfMonth': 15,
        'rewardAccountId': null,
        'note': null,
        'enabled': true,
      },
    );

    await engine.pull('');

    final rule = await repo.getCardRewardRuleBySyncId(ruleSyncId);
    expect(rule, isNotNull);
    expect(rule!.accountId, accountId);
    expect(rule.label, '影音網購加碼');
    expect(rule.rateValue, 3.0);
    expect(rule.capAmount, 300.0);
    expect(rule.settlementType, 'period_end');
    expect(rule.settlementDayOfMonth, 15);
    expect(rule.enabled, true);
  });

  test('遠端 upsert 全量覆蓋 → 本地欄位跟隨最新 payload(full-replace,非 partial merge)',
      () async {
    final lid = await seedLedger();
    const accountSyncId = 'acc-cc-2';
    const ruleSyncId = 'rule-2';

    await repo.createAccount(
      ledgerId: lid,
      name: '信用卡B',
      type: 'credit_card',
      currency: 'TWD',
      syncId: accountSyncId,
    );

    // 本地先建一条規則,capAmount=300、note='舊備註'。
    await repo.createCardRewardRule(
      accountId: (await getAccountBySyncId(accountSyncId)).id,
      label: '國內',
      rateValue: 1.0,
      capAmount: 300.0,
      note: '舊備註',
      syncId: ruleSyncId,
    );

    // 遠端推同 syncId 的 upsert,capAmount/note 都沒帶(對照 server 端
    // upsert_card_reward_rule 的全量替換語義,缺鍵會被當成清空,不是保留)。
    provider.pushFakeChange(
      entityType: 'card_reward_rule',
      entitySyncId: ruleSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': ruleSyncId,
        'accountId': accountSyncId,
        'label': '國內(更新)',
        'rateType': 'percentage',
        'rateValue': 2.0,
        'rounding': 'round',
        'totalRounding': 'round',
        'calcBasis': 'transaction_date',
        'interval': 'billing_cycle',
        'settlementType': 'manual',
        'enabled': true,
        // 注意:故意省略 capAmount / note,驗證 full-replace 語義下這些欄位
        // 會被清空,不是「缺鍵保留」。
      },
    );

    await engine.pull('');

    final rule = await repo.getCardRewardRuleBySyncId(ruleSyncId);
    expect(rule, isNotNull);
    expect(rule!.label, '國內(更新)');
    expect(rule.rateValue, 2.0);
    expect(rule.capAmount, isNull, reason: 'full-replace 語義下缺鍵視為清空');
    expect(rule.note, isNull, reason: 'full-replace 語義下缺鍵視為清空');
  });

  test('(delete) 遠端刪除規則 → 本地對應行被移除', () async {
    final lid = await seedLedger();
    const accountSyncId = 'acc-cc-3';
    const ruleSyncId = 'rule-3';

    await repo.createAccount(
      ledgerId: lid,
      name: '信用卡C',
      type: 'credit_card',
      currency: 'TWD',
      syncId: accountSyncId,
    );
    await repo.createCardRewardRule(
      accountId: (await getAccountBySyncId(accountSyncId)).id,
      label: '待刪除',
      rateValue: 1.0,
      syncId: ruleSyncId,
    );

    provider.pushFakeChange(
      entityType: 'card_reward_rule',
      entitySyncId: ruleSyncId,
      ledgerId: '$lid',
      action: 'delete',
    );

    await engine.pull('');

    final rule = await repo.getCardRewardRuleBySyncId(ruleSyncId);
    expect(rule, isNull);
  });

  test('綁定帳戶本地尚未就緒(accountId 對不到)→ 跳過,不建孤兒行', () async {
    const ruleSyncId = 'rule-4';

    provider.pushFakeChange(
      entityType: 'card_reward_rule',
      entitySyncId: ruleSyncId,
      ledgerId: '999',
      payload: {
        'syncId': ruleSyncId,
        'accountId': 'acc-not-synced-yet',
        'label': '孤兒規則',
        'rateType': 'percentage',
        'rateValue': 1.0,
        'enabled': true,
      },
    );

    await engine.pull('');

    final rule = await repo.getCardRewardRuleBySyncId(ruleSyncId);
    expect(rule, isNull, reason: '帳戶本地不存在時應該跳過,不建立孤兒規則');
  });
}
