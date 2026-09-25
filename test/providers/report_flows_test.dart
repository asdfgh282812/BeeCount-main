// 統計報表的支出/收入/轉帳/回饋金切換(docs/changes/2026-09-25-report-flows-and-colors.md):
// - 維度下鑽只列目前 flow 的 legs(在支出頁點進去不會混進收入)
// - 轉帳金額按維度歸屬,帳戶 = 轉入 + 轉出
// - 回饋金用跟回饋明細頁同一份估算(含 capAmount 累積扣減)

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/models/report/report_dataset.dart';
import 'package:beecount/models/report/report_filter.dart';
import 'package:beecount/providers.dart';
import 'package:beecount/services/report/report_aggregator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;
  late ProviderContainer container;
  late int lid;

  final now = DateTime.now();
  // 固定在今天 00:10 之後,不會因為剛過午夜落到上個月
  final today = DateTime(now.year, now.month, now.day, 0, 10);
  final start = DateTime(now.year, now.month, 1);
  final end = DateTime(now.year, now.month + 1, 1);
  ReportQuery query() => ReportQuery(
      ledgerId: lid, start: start, end: end, filter: ReportFilter.none);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
    ]);
    lid = await repo.createLedger(name: '帳本');
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('專案下鑽只列目前 flow 的交易', () async {
    await repo.createProject(ledgerId: lid, name: '投資理財');
    final project = (await db.select(db.projects).get()).single.syncId!;
    final cash = await repo.createAccount(ledgerId: lid, name: '現金');
    final bank = await repo.createAccount(ledgerId: lid, name: '銀行');
    await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 72,
        projectSyncId: project,
        accountId: bank,
        happenedAt: start.add(const Duration(days: 3)));
    await repo.addTransaction(
        ledgerId: lid,
        type: 'income',
        amount: 500,
        projectSyncId: project,
        accountId: bank,
        happenedAt: start.add(const Duration(days: 4)));
    await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 1000,
        projectSyncId: project,
        accountId: bank,
        toAccountId: cash,
        happenedAt: start.add(const Duration(days: 5)));

    final agg = ReportAggregator(await repo.loadReportDataset(query()));
    final row = agg
        .byDimension(ReportDimension.project)
        .firstWhere((r) => r.key == project);
    expect(row.expense, 72);
    expect(row.income, 500);
    expect(row.amountFor(ReportFlow.transfer), 1000);

    List<String> typesFor(String flow) => agg
        .transactions(agg.dimensionPredicate(ReportDimension.project, project,
            flow: flow))
        .map((v) => v.t.type)
        .toList();
    expect(typesFor(ReportFlow.expense), ['expense']);
    expect(typesFor(ReportFlow.income), ['income']);
    expect(typesFor(ReportFlow.transfer), ['transfer']);

    // 帳戶的轉帳 = 轉入 + 轉出,兩邊都列得到這筆
    final accounts = {
      for (final r in agg.byDimension(ReportDimension.account)) r.label: r
    };
    expect(accounts['銀行']!.amountFor(ReportFlow.transfer), 1000);
    expect(accounts['現金']!.amountFor(ReportFlow.transfer), 1000);
    final cashKey = accounts['現金']!.key;
    expect(
        agg
            .transactions(agg.dimensionPredicate(
                ReportDimension.account, cashKey,
                flow: ReportFlow.transfer))
            .single
            .t
            .type,
        'transfer');
    expect(
        agg.transactions(agg.dimensionPredicate(
            ReportDimension.account, cashKey,
            flow: ReportFlow.expense)),
        isEmpty);
    expect(agg.summary().transfer, 1000);
  });

  test('回饋金:按規則估算、套用上限、分到各維度', () async {
    await repo.createProject(ledgerId: lid, name: '生活開銷');
    final project = (await db.select(db.projects).get()).single.syncId!;
    final card = await repo.createAccount(
        ledgerId: lid, name: '快樂卡', type: 'credit_card', syncId: 'acc-card');
    await repo.createCardRewardRule(
        accountId: card,
        label: '3%',
        rateValue: 3,
        capAmount: 50,
        syncId: 'rule-1');
    await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 1000,
        accountId: card,
        projectSyncId: project,
        merchant: '全聯',
        rewardRuleIds: const ['rule-1'],
        happenedAt: today);
    await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 1000,
        accountId: card,
        merchant: '好市多',
        rewardRuleIds: const ['rule-1'],
        happenedAt: today.add(const Duration(minutes: 1)));
    await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 300,
        accountId: card,
        happenedAt: today.add(const Duration(minutes: 2)));

    final rewards = await container.read(reportRewardsProvider(query()).future);
    // 3% × 1000 = 30;第二筆只剩上限 50 − 30 = 20
    expect(rewards.values.toList()..sort(), [20.0, 30.0]);

    final agg = ReportAggregator(await repo.loadReportDataset(query()));
    expect(agg.rewardTotal(rewards), 50);
    final merchants = {
      for (final r
          in agg.byDimension(ReportDimension.merchant, rewards: rewards))
        r.key: r
    };
    expect(merchants['全聯']!.reward, 30);
    expect(merchants['好市多']!.reward, 20);
    expect(merchants['全聯']!.countFor(ReportFlow.reward), 1);
    final proj = agg
        .byDimension(ReportDimension.project, rewards: rewards)
        .firstWhere((r) => r.key == project);
    expect(proj.amountFor(ReportFlow.reward), 30);

    final ranked = agg.rankedTransactions(ReportFlow.reward, rewards: rewards);
    expect(ranked.map((r) => r.amount).toList(), [30, 20]);
    expect(
        agg
            .transactions(agg.dimensionPredicate(ReportDimension.merchant, '全聯',
                flow: ReportFlow.reward, rewards: rewards))
            .length,
        1);
  });
}
