// 退款沖銷口徑(docs/changes/2026-09-25-refund-netting.md)的回歸測試:
// 退款單記成反方向的負值、分類扣回原交易的分類,且 LocalStatisticsRepository
// 各方法與統計報表引擎(loadReportDataset + ReportAggregator)數字一致。

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/data/repositories/transaction_repository.dart';
import 'package:beecount/models/report/report_dataset.dart';
import 'package:beecount/models/report/report_filter.dart';
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

  Future<String> syncIdOf(int txId) async =>
      (await (db.select(db.transactions)..where((t) => t.id.equals(txId)))
              .getSingle())
          .syncId!;

  Future<ReportAggregator> report() async => ReportAggregator(
      await repo.loadReportDataset(ReportQuery(
          ledgerId: 1, start: start, end: end, filter: ReportFilter.none)));

  Future<Map<int?, double>> oldByCategory(String type) async => {
        for (final r in await repo.totalsByCategoryWithHierarchy(
            ledgerId: 1, type: type, start: start, end: end))
          r.id: r.total
      };

  test('收入型退款扣回原交易的支出分類,不算收入', () async {
    final food = await repo.createCategory(name: '餐饮', kind: 'expense');
    final refundCat = await repo.createCategory(name: '退款', kind: 'income');
    final orig = await repo.addTransaction(
        ledgerId: 1,
        type: 'expense',
        amount: 100,
        categoryId: food,
        happenedAt: DateTime(2026, 7, 3));
    await repo.addTransaction(
        ledgerId: 1,
        type: 'income',
        amount: 30,
        categoryId: refundCat,
        refundOfSyncId: await syncIdOf(orig),
        happenedAt: DateTime(2026, 7, 10));

    final (income, expense) =
        await repo.totalsInRange(ledgerId: 1, start: start, end: end);
    expect(income, 0);
    expect(expense, 70);
    expect(await repo.monthlyTotals(ledgerId: 1, month: DateTime(2026, 7)),
        (0.0, 70.0));

    final old = await oldByCategory('expense');
    expect(old[food], 70);
    expect(old.containsKey(refundCat), isFalse, reason: '不以退款單分類成列');
    expect(await oldByCategory('income'), isEmpty);

    final agg = await report();
    final s = agg.summary();
    expect(s.expense, 70);
    expect(s.income, 0);
    expect(s.expenseCount, 1, reason: '退款單不算支出筆數');
    expect(s.incomeCount, 0);
    final cats = agg.categoryHierarchy('expense');
    expect(cats.single.id, food);
    expect(cats.single.total, 70);
    expect(agg.rankedTransactions('expense').single.amount, 100,
        reason: '排行只列原交易');
    expect(agg.categoryHierarchy('income'), isEmpty);

    final days = await repo.totalsByDay(
        ledgerId: 1, type: 'expense', start: start, end: end);
    expect(days[2].total, 100);
    expect(days[9].total, -30);
    final months =
        await repo.totalsByMonth(ledgerId: 1, type: 'expense', year: 2026);
    expect(months[6].total, 70);
  });

  test('原交易拆帳:退款按明細比例分攤', () async {
    final food = await repo.createCategory(name: '餐饮', kind: 'expense');
    final fun = await repo.createCategory(name: '娱乐', kind: 'expense');
    final orig = await repo.addTransaction(
        ledgerId: 1,
        type: 'expense',
        amount: 100,
        happenedAt: DateTime(2026, 7, 3),
        splits: [
          TransactionSplitInput(categoryId: food, amount: 60),
          TransactionSplitInput(categoryId: fun, amount: 40),
        ]);
    await repo.addTransaction(
        ledgerId: 1,
        type: 'income',
        amount: 50,
        refundOfSyncId: await syncIdOf(orig),
        happenedAt: DateTime(2026, 7, 4));

    final old = await oldByCategory('expense');
    expect(old[food], closeTo(30, 1e-9));
    expect(old[fun], closeTo(20, 1e-9));
    final byId = {
      for (final c in (await report()).categoryHierarchy('expense')) c.id: c
    };
    expect(byId[food]!.total, closeTo(30, 1e-9));
    expect(byId[fun]!.total, closeTo(20, 1e-9));
  });

  test('原交易在上一期:退款算在退款當期、扣原分類', () async {
    final food = await repo.createCategory(name: '餐饮', kind: 'expense');
    final orig = await repo.addTransaction(
        ledgerId: 1,
        type: 'expense',
        amount: 80,
        categoryId: food,
        happenedAt: DateTime(2026, 6, 28));
    await repo.addTransaction(
        ledgerId: 1,
        type: 'income',
        amount: 80,
        refundOfSyncId: await syncIdOf(orig),
        happenedAt: DateTime(2026, 7, 2));

    expect((await repo.totalsInRange(ledgerId: 1, start: start, end: end)).$2,
        -80);
    expect((await oldByCategory('expense'))[food], -80);
    final agg = await report();
    expect(agg.summary().expense, -80);
    expect(agg.categoryHierarchy('expense').single.id, food);
  });

  test('原交易不計入統計 → 退款也不計入', () async {
    final food = await repo.createCategory(name: '餐饮', kind: 'expense');
    final orig = await repo.addTransaction(
        ledgerId: 1,
        type: 'expense',
        amount: 100,
        categoryId: food,
        excludeFromStats: true,
        happenedAt: DateTime(2026, 7, 3));
    await repo.addTransaction(
        ledgerId: 1,
        type: 'income',
        amount: 100,
        refundOfSyncId: await syncIdOf(orig),
        happenedAt: DateTime(2026, 7, 4));

    expect(await repo.totalsInRange(ledgerId: 1, start: start, end: end),
        (0.0, 0.0));
    expect(await oldByCategory('expense'), isEmpty);
    expect((await report()).summary().expense, 0);
  });

  test('找不到原交易:用退款單自己的分類', () async {
    final refundCat = await repo.createCategory(name: '退款', kind: 'income');
    await repo.addTransaction(
        ledgerId: 1,
        type: 'income',
        amount: 20,
        categoryId: refundCat,
        refundOfSyncId: 'gone',
        happenedAt: DateTime(2026, 7, 4));
    expect((await repo.totalsInRange(ledgerId: 1, start: start, end: end)).$2,
        -20);
    expect((await oldByCategory('expense'))[refundCat], -20);
    expect((await report()).categoryHierarchy('expense').single.id, refundCat);
  });

  test('支出型退款(回饋金沖銷)扣回收入', () async {
    final reward = await repo.createCategory(name: '回饋', kind: 'income');
    final refundCat = await repo.createCategory(name: '退款', kind: 'expense');
    final payout = await repo.addTransaction(
        ledgerId: 1,
        type: 'income',
        amount: 15,
        categoryId: reward,
        happenedAt: DateTime(2026, 7, 5));
    await repo.addTransaction(
        ledgerId: 1,
        type: 'expense',
        amount: 15,
        categoryId: refundCat,
        refundOfSyncId: await syncIdOf(payout),
        happenedAt: DateTime(2026, 7, 20));

    expect(await repo.totalsInRange(ledgerId: 1, start: start, end: end),
        (0.0, 0.0));
    expect((await oldByCategory('income'))[reward], 0);
    expect(await oldByCategory('expense'), isEmpty);
    final agg = await report();
    expect(agg.summary().income, 0);
    expect(agg.summary().expense, 0);
    expect(
        (await repo.totalsByCategory(
                ledgerId: 1, type: 'income', start: start, end: end))
            .single
            .total,
        0);
  });

  test('退款沿用原交易的專案/商家做維度歸屬', () async {
    await repo.createProject(ledgerId: 1, name: '旅行');
    final project = (await db.select(db.projects).get()).single.syncId!;
    final orig = await repo.addTransaction(
        ledgerId: 1,
        type: 'expense',
        amount: 100,
        merchant: '全聯',
        projectSyncId: project,
        happenedAt: DateTime(2026, 7, 3));
    await repo.addTransaction(
        ledgerId: 1,
        type: 'income',
        amount: 40,
        refundOfSyncId: await syncIdOf(orig),
        happenedAt: DateTime(2026, 7, 4));
    final agg = await report();
    expect(
        agg
            .byDimension(ReportDimension.project)
            .firstWhere((r) => r.key == project)
            .expense,
        60);
    expect(
        agg
            .byDimension(ReportDimension.merchant)
            .firstWhere((r) => r.key == '全聯')
            .expense,
        60);
  });
}
