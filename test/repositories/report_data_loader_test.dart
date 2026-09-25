// 統計報表資料集(loadReportDataset + ReportAggregator)的回歸測試。
// 最重要的是「對帳」:同一區間下,新引擎的分類/收支總額必須跟既有
// totalsByCategoryWithHierarchy / totalsInRange 完全一致,類別分頁才不會跟
// 改版前的洞察頁數字對不上。

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/data/repositories/transaction_repository.dart';
import 'package:beecount/models/report/report_dataset.dart';
import 'package:beecount/models/report/report_filter.dart';
import 'package:beecount/models/report/report_period.dart';
import 'package:beecount/services/report/report_aggregator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;

  final start = DateTime(2026, 7, 1);
  final end = DateTime(2026, 8, 1);

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
  });

  tearDown(() async => db.close());

  Future<ReportDataset> load([ReportFilter f = ReportFilter.none]) =>
      repo.loadReportDataset(
          ReportQuery(ledgerId: 1, start: start, end: end, filter: f));

  Future<String> syncIdOfCategory(int id) async =>
      (await (db.select(db.categories)..where((c) => c.id.equals(id)))
              .getSingle())
          .syncId!;

  test('對帳:分類階層與收支總額同既有統計方法', () async {
    final life = await repo.createCategory(name: '生活', kind: 'expense');
    final food = await repo.createCategory(
        name: '餐饮', kind: 'expense', parentId: life, level: 2);
    final fun = await repo.createCategory(name: '娱乐', kind: 'expense');
    final salary = await repo.createCategory(name: '薪资', kind: 'income');

    await repo.addTransaction(
        ledgerId: 1,
        type: 'expense',
        amount: 100,
        nativeAmount: 50, // 外幣折算:統計用 native
        currencyCode: 'USD',
        happenedAt: DateTime(2026, 7, 3),
        splits: [
          TransactionSplitInput(categoryId: food, amount: 60),
          TransactionSplitInput(categoryId: fun, amount: 40),
        ]);
    await repo.addTransaction(
        ledgerId: 1,
        type: 'expense',
        amount: 20,
        categoryId: life,
        happenedAt: DateTime(2026, 7, 4));
    await repo.addTransaction(
        ledgerId: 1,
        type: 'expense',
        amount: 999,
        categoryId: fun,
        excludeFromStats: true,
        happenedAt: DateTime(2026, 7, 5));
    await repo.addTransaction(
        ledgerId: 1,
        type: 'expense',
        amount: 7,
        happenedAt: DateTime(2026, 7, 6)); // 未分類
    await repo.addTransaction(
        ledgerId: 1,
        type: 'income',
        amount: 300,
        categoryId: salary,
        happenedAt: DateTime(2026, 7, 7));
    await repo.addTransaction(
        ledgerId: 1,
        type: 'expense',
        amount: 5,
        categoryId: fun,
        happenedAt: DateTime(2026, 8, 1)); // 區間外

    final agg = ReportAggregator(await load());
    final summary = agg.summary();
    final (income, expense) =
        await repo.totalsInRange(ledgerId: 1, start: start, end: end);
    expect(summary.income, closeTo(income, 1e-9));
    expect(summary.expense, closeTo(expense, 1e-9));
    expect(summary.expense, closeTo(50 + 20 + 7, 1e-9));

    final old = await repo.totalsByCategoryWithHierarchy(
        ledgerId: 1, type: 'expense', start: start, end: end);
    final oldById = {for (final r in old) r.id: r.total};
    final rollup = agg.categoryHierarchy('expense');
    final byId = {for (final r in rollup) r.id: r};
    // 生活 = 直接 20 + 子分類餐飲 30(60*0.5)
    expect(byId[life]!.total, closeTo(oldById[life]! + oldById[food]!, 1e-9));
    expect(byId[life]!.total, closeTo(50, 1e-9));
    expect(byId[life]!.subCategories.single.id, food);
    expect(byId[fun]!.total, closeTo(oldById[fun]!, 1e-9));
    expect(byId[null]!.total, closeTo(7, 1e-9));
    expect(rollup.first.id, life, reason: '金額降序');
  });

  test('父分類查不到的二級分類不會被丟掉', () async {
    final orphan = await repo.createCategory(
        name: '孤兒', kind: 'expense', parentId: 9999, level: 2);
    await repo.addTransaction(
        ledgerId: 1,
        type: 'expense',
        amount: 12,
        categoryId: orphan,
        happenedAt: DateTime(2026, 7, 2));
    final rollup = ReportAggregator(await load()).categoryHierarchy('expense');
    expect(rollup.single.id, orphan);
    expect(rollup.single.total, 12);
  });

  test('分類篩選作用在拆帳明細,且一級分類含子分類', () async {
    final life = await repo.createCategory(name: '生活', kind: 'expense');
    final food = await repo.createCategory(
        name: '餐饮', kind: 'expense', parentId: life, level: 2);
    final fun = await repo.createCategory(name: '娱乐', kind: 'expense');
    await repo.addTransaction(
        ledgerId: 1,
        type: 'expense',
        amount: 100,
        happenedAt: DateTime(2026, 7, 3),
        splits: [
          TransactionSplitInput(categoryId: food, amount: 70),
          TransactionSplitInput(categoryId: fun, amount: 30),
        ]);

    final include = await load(ReportFilter(
        categories: KeySetFilter(values: {await syncIdOfCategory(life)})));
    expect(ReportAggregator(include).summary().expense, closeTo(70, 1e-9));

    final exclude = await load(ReportFilter(
        categories: KeySetFilter(
            mode: FilterMode.exclude, values: {await syncIdOfCategory(life)})));
    expect(ReportAggregator(exclude).summary().expense, closeTo(30, 1e-9));
    // 排行/列表把拆帳合回一筆,金額 = 命中的明細
    final ranked = ReportAggregator(exclude).rankedTransactions('expense');
    expect(ranked.single.amount, closeTo(30, 1e-9));
  });

  test('帳戶、標籤、商家、名稱、專案、對象維度與篩選', () async {
    final cash = await repo.createAccount(ledgerId: 1, name: '現金');
    final bank = await repo.createAccount(ledgerId: 1, name: '銀行');
    final tagA = await repo.createTag(name: 'A');
    await repo.createProject(ledgerId: 1, name: '旅行');
    final project = (await db.select(db.projects).get()).single.syncId!;
    await repo.createDebt(
        ledgerId: 1,
        direction: 'payable',
        counterpartyName: '小明',
        principalAmount: 100);
    final debt = (await db.select(db.debts).get()).single.syncId!;

    final t1 = await repo.addTransaction(
        ledgerId: 1,
        type: 'expense',
        amount: 40,
        accountId: cash,
        merchant: ' 全聯 ',
        note: '午餐',
        projectSyncId: project,
        happenedAt: DateTime(2026, 7, 3));
    await repo.addTagsToTransaction(transactionId: t1, tagIds: [tagA]);
    await repo.addTransaction(
        ledgerId: 1,
        type: 'expense',
        amount: 60,
        accountId: bank,
        debtSyncId: debt,
        happenedAt: DateTime(2026, 7, 4));
    await repo.addTransaction(
        ledgerId: 1,
        type: 'transfer',
        amount: 25,
        accountId: bank,
        toAccountId: cash,
        happenedAt: DateTime(2026, 7, 5));

    final agg = ReportAggregator(await load());
    expect(agg.summary().expense, 100, reason: '轉帳不計入收支');
    expect(agg.summary().txCount, 3);

    final accounts = {
      for (final r in agg.byDimension(ReportDimension.account)) r.label: r
    };
    expect(accounts['現金']!.expense, 40);
    expect(accounts['現金']!.transferIn, 25);
    expect(accounts['銀行']!.expense, 60);
    expect(accounts['銀行']!.transferOut, 25);

    final merchants = agg.byDimension(ReportDimension.merchant);
    expect(merchants.firstWhere((r) => r.key == '全聯').expense, 40);
    expect(merchants.firstWhere((r) => r.key == null).expense, 60);
    final tags = agg.byDimension(ReportDimension.tag);
    expect(tags.firstWhere((r) => r.label == 'A').expense, 40);
    expect(
        agg
            .byDimension(ReportDimension.name)
            .firstWhere((r) => r.key == '午餐')
            .expense,
        40);
    expect(
        agg
            .byDimension(ReportDimension.project)
            .firstWhere((r) => r.key == project)
            .label,
        '旅行');
    expect(
        agg
            .byDimension(ReportDimension.counterparty)
            .firstWhere((r) => r.key == '小明')
            .expense,
        60);

    // 帳戶篩選:轉帳只要轉出或轉入其一命中即可
    final cashKey = (await (db.select(db.accounts)
              ..where((a) => a.id.equals(cash)))
            .getSingle())
        .syncId!;
    final onlyCash =
        await load(ReportFilter(accounts: KeySetFilter(values: {cashKey})));
    expect(ReportAggregator(onlyCash).summary().txCount, 2);

    // 標籤「(無)」
    final untagged =
        await load(const ReportFilter(tags: KeySetFilter(includeNone: true)));
    expect(ReportAggregator(untagged).summary().expense, 60);

    // 記錄類型 + 金額範圍
    final noTransfer =
        await load(const ReportFilter(recordTypes: {'expense', 'income'}));
    expect(ReportAggregator(noTransfer).summary().txCount, 2);
    final big = await load(const ReportFilter(minAmount: 50));
    expect(ReportAggregator(big).summary().expense, 60);
  });

  test('趨勢序列:日桶連續、結餘 = 收入 - 支出', () async {
    await repo.addTransaction(
        ledgerId: 1,
        type: 'expense',
        amount: 10,
        happenedAt: DateTime(2026, 7, 2, 9));
    await repo.addTransaction(
        ledgerId: 1,
        type: 'income',
        amount: 30,
        happenedAt: DateTime(2026, 7, 2, 18));
    final agg = ReportAggregator(await load());
    final days = agg.series(
        type: 'expense',
        granularity: ReportGranularity.day,
        start: start,
        end: end);
    expect(days.length, 31);
    expect(days[1].value, 10);
    final bal = agg.series(
        type: 'balance',
        granularity: ReportGranularity.day,
        start: start,
        end: end);
    expect(bal[1].value, 20);
    final months = agg.series(
        type: 'expense',
        granularity: ReportGranularity.month,
        start: DateTime(2026, 1, 1),
        end: DateTime(2027, 1, 1));
    expect(months.length, 12);
  });

  test('超過分段大小的交易量', () async {
    final tag = await repo.createTag(name: 'T');
    for (var i = 0; i < 620; i++) {
      final id = await repo.addTransaction(
          ledgerId: 1,
          type: 'expense',
          amount: 1,
          happenedAt: DateTime(2026, 7, 1 + i % 28));
      await repo.addTagsToTransaction(transactionId: id, tagIds: [tag]);
    }
    final agg = ReportAggregator(await load());
    expect(agg.summary().expense, 620);
    expect(agg.byDimension(ReportDimension.tag).single.expense, 620);
  });
}
