/// 信用卡紅利回饋規則(v35 card_reward_rule)— Repository 层 CRUD 测试。
///
/// 覆盖:
/// - `createCardRewardRule` 落值 + 记 user-global change(同步依赖,scope 必须
///   是 ledgerId=0,见 change_tracker.dart 的 scope 契约)。
/// - `updateCardRewardRule`(Companion 覆盖式更新)落值 + 记 change。
/// - `deleteCardRewardRule` 落值 + 记 change。
/// - `getCardRewardRulesForAccount` 按 sortOrder 排序、只返该帐户下的规则。
/// - `updateCardRewardRuleSortOrders` 批量排序。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/cloud/sync/change_tracker.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
  });

  tearDown(() async => db.close());

  Future<int> seedCreditCardAccount(LocalRepository r,
      {String? syncId, String name = '信用卡'}) async {
    final lid = await r.createLedger(name: 'L-$name-$syncId');
    return r.createAccount(
      ledgerId: lid,
      name: name,
      type: 'credit_card',
      syncId: syncId,
    );
  }

  test('createCardRewardRule 落值 + 记 user-global change(ledgerId=0)', () async {
    final tracker = ChangeTracker(db);
    final trackedRepo = LocalRepository(db, changeTracker: tracker);
    final accountId =
        await seedCreditCardAccount(trackedRepo, syncId: 'acc-1');

    final id = await trackedRepo.createCardRewardRule(
      accountId: accountId,
      label: '國內',
      rateType: 'percentage',
      rateValue: 1.5,
      capAmount: 500,
    );

    final rule = await trackedRepo.getCardRewardRuleById(id);
    expect(rule, isNotNull);
    expect(rule!.accountId, accountId);
    expect(rule.label, '國內');
    expect(rule.rateValue, 1.5);
    expect(rule.capAmount, 500);
    expect(rule.rounding, 'round', reason: '未传时应落 server 端同款默认值');
    expect(rule.enabled, true);
    expect(rule.syncId, isNotNull);

    final changes = await (db.select(db.localChanges)
          ..where((c) => c.entityType.equals('card_reward_rule')))
        .get();
    expect(changes, hasLength(1));
    expect(changes.first.ledgerId, 0, reason: 'user-global 必须挂 ledgerId=0');
    expect(changes.first.action, 'create');
  });

  test('updateCardRewardRule(Companion) 覆盖式更新 + 记 change', () async {
    final tracker = ChangeTracker(db);
    final trackedRepo = LocalRepository(db, changeTracker: tracker);
    final accountId =
        await seedCreditCardAccount(trackedRepo, syncId: 'acc-2');
    final id = await trackedRepo.createCardRewardRule(
      accountId: accountId,
      label: '國內',
      rateValue: 1.0,
    );

    await trackedRepo.updateCardRewardRule(
      id,
      const CardRewardRulesCompanion(
        label: Value('國內(改)'),
        rateValue: Value(2.5),
        capAmount: Value(300),
      ),
    );

    final rule = await trackedRepo.getCardRewardRuleById(id);
    expect(rule!.label, '國內(改)');
    expect(rule.rateValue, 2.5);
    expect(rule.capAmount, 300);

    final changes = await (db.select(db.localChanges)
          ..where((c) => c.entityType.equals('card_reward_rule'))
          ..where((c) => c.action.equals('update')))
        .get();
    expect(changes, hasLength(1));
  });

  test('deleteCardRewardRule 删除本地行 + 记 change', () async {
    final tracker = ChangeTracker(db);
    final trackedRepo = LocalRepository(db, changeTracker: tracker);
    final accountId =
        await seedCreditCardAccount(trackedRepo, syncId: 'acc-3');
    final id = await trackedRepo.createCardRewardRule(
      accountId: accountId,
      label: '待刪除',
      rateValue: 1.0,
    );

    await trackedRepo.deleteCardRewardRule(id);

    expect(await trackedRepo.getCardRewardRuleById(id), isNull);
    final deletes = await (db.select(db.localChanges)
          ..where((c) => c.entityType.equals('card_reward_rule'))
          ..where((c) => c.action.equals('delete')))
        .get();
    expect(deletes, hasLength(1));
  });

  test('getCardRewardRulesForAccount 只返该帐户下的规则,按 sortOrder 排序', () async {
    final accountA =
        await seedCreditCardAccount(repo, syncId: 'acc-a', name: '信用卡A');
    final accountB =
        await seedCreditCardAccount(repo, syncId: 'acc-b', name: '信用卡B');

    await repo.createCardRewardRule(
        accountId: accountA, label: 'A-第二', rateValue: 1, sortOrder: 1);
    await repo.createCardRewardRule(
        accountId: accountA, label: 'A-第一', rateValue: 1, sortOrder: 0);
    await repo.createCardRewardRule(
        accountId: accountB, label: 'B-規則', rateValue: 1, sortOrder: 0);

    final rulesA = await repo.getCardRewardRulesForAccount(accountA);
    expect(rulesA.map((r) => r.label), ['A-第一', 'A-第二']);

    final rulesB = await repo.getCardRewardRulesForAccount(accountB);
    expect(rulesB.map((r) => r.label), ['B-規則']);
  });

  test('updateCardRewardRuleSortOrders 批量更新排序', () async {
    final accountId = await seedCreditCardAccount(repo, syncId: 'acc-sort');
    final id1 = await repo.createCardRewardRule(
        accountId: accountId, label: '第一', rateValue: 1, sortOrder: 0);
    final id2 = await repo.createCardRewardRule(
        accountId: accountId, label: '第二', rateValue: 1, sortOrder: 1);

    await repo.updateCardRewardRuleSortOrders([
      (id: id1, sortOrder: 1),
      (id: id2, sortOrder: 0),
    ]);

    final rules = await repo.getCardRewardRulesForAccount(accountId);
    expect(rules.map((r) => r.label), ['第二', '第一']);
  });
}
