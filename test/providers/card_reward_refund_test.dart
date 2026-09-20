// 信用卡紅利回饋彙總——退款應該一併取消對應回饋金,不能讓已退款的交易繼續
// 佔用/貢獻回饋額度(2026-09-20 bugfix,見
// lib/providers/card_reward_rule_providers.dart 的 `_summarizeRulePeriod`)。
//
// 覆盖:
// - 全額退款:退款後這筆交易的回饋淨額歸零,totalReward/totalSpend 都要扣除。
// - 部分退款:回饋金按「原始金額 - 已退款金額」的淨額重算,不是整筆清零。

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<int> seedLedger() => repo.createLedger(name: '测试账本');

  test('全額退款後,該筆交易的回饋淨額歸零', () async {
    final lid = await seedLedger();
    final accountId = await repo.createAccount(
      ledgerId: lid,
      name: '信用卡',
      type: 'credit_card',
      syncId: 'acc-1',
    );
    final ruleId = await repo.createCardRewardRule(
      accountId: accountId,
      label: '國外',
      rateType: 'percentage',
      rateValue: 2,
      syncId: 'rule-1',
    );
    final rule = (await repo.getCardRewardRuleById(ruleId))!;

    final now = DateTime.now();
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 2806,
      accountId: accountId,
      happenedAt: now,
      syncId: 'tx-original',
      rewardRuleIds: const ['rule-1'],
    );
    // 退款:类型对调(income)、金额可等于/小于原始金额,refundOfSyncId 指回
    // 原交易——比照 transaction_edit_utils.dart 的 refundTransaction()。
    await repo.addTransaction(
      ledgerId: lid,
      type: 'income',
      amount: 2806,
      accountId: accountId,
      happenedAt: now,
      refundOfSyncId: 'tx-original',
    );

    final summary = await container.read(cardRewardRulePeriodSummaryProvider((
      rule: rule,
      accountId: accountId,
      extraIdsKey: '',
      billingDay: null,
      offset: 0,
    )).future);

    expect(summary.totalReward, 0,
        reason: '原交易已全額退款,回饋應該一併取消,不能繼續累計');
    expect(summary.totalSpend, 0,
        reason: '已退款金額不該繼續算進「消費多少才能拿到最高回饋」的統計');
  });

  test('部分退款後,回饋按淨額(原始金額-已退款金額)重算', () async {
    final lid = await seedLedger();
    final accountId = await repo.createAccount(
      ledgerId: lid,
      name: '信用卡',
      type: 'credit_card',
      syncId: 'acc-2',
    );
    final ruleId = await repo.createCardRewardRule(
      accountId: accountId,
      label: '國內',
      rateType: 'percentage',
      rateValue: 2,
      syncId: 'rule-2',
    );
    final rule = (await repo.getCardRewardRuleById(ruleId))!;

    final now = DateTime.now();
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 1000,
      accountId: accountId,
      happenedAt: now,
      syncId: 'tx-partial',
      rewardRuleIds: const ['rule-2'],
    );
    // 只退款 400,净消费应剩 600。
    await repo.addTransaction(
      ledgerId: lid,
      type: 'income',
      amount: 400,
      accountId: accountId,
      happenedAt: now,
      refundOfSyncId: 'tx-partial',
    );

    final summary = await container.read(cardRewardRulePeriodSummaryProvider((
      rule: rule,
      accountId: accountId,
      extraIdsKey: '',
      billingDay: null,
      offset: 0,
    )).future);

    expect(summary.totalSpend, 600);
    expect(summary.totalReward, closeTo(600 * 0.02, 0.001));
  });
}
