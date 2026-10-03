// 年度報告新增頁面(股票總覽/亮點、年度稱號、跟去年比、消費習慣)的煙霧測試:
// 各種資料組合都能渲染、不會 overflow / 拋例外,多幣別 chip 可切換。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/report/annual_report_extra_pages.dart';
import 'package:beecount/pages/report/annual_report_page.dart';
import 'package:beecount/services/export/share_poster_types.dart';
import 'package:beecount/services/investment/holdings_calculator.dart';
import 'package:beecount/services/investment/stock_annual_report.dart';

int _n = 0;
HoldingTrade t(String type, double amount, String date,
        {String market = 'TW', String symbol = '2330'}) =>
    HoldingTrade(
        syncId: 'x${_n++}',
        accountKey: '1',
        market: market,
        symbol: symbol,
        tradeType: type,
        shares: 10,
        price: null,
        fee: 5,
        tax: 3,
        amount: amount,
        tradeDateKey: date,
        securityName: symbol == '2330' ? '台積電' : null);

Widget host(Widget page, {double width = 360}) => ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', 'TW'),
        home: Scaffold(
          backgroundColor: Colors.teal,
          body: SizedBox(width: width, child: page),
        ),
      ),
    );

AnnualReportData reportData({StockAnnualBundle? stock, bool prev = true}) =>
    AnnualReportData(
      year: 2026,
      totalDays: 120,
      totalRecords: 300,
      totalIncome: 800000,
      totalExpense: 500000,
      netSavings: 300000,
      topExpenseCategories: [
        CategoryTotal(
            id: 1, name: '餐飲', icon: null, total: 250000, percentage: 0.5),
      ],
      monthlyData: [
        for (var m = 1; m <= 12; m++) (month: m, income: 1000, expense: 500),
      ],
      maxConsecutiveDays: 31,
      previousYearIncome: prev ? 700000 : null,
      previousYearExpense: prev ? 520000 : null,
      expenseHourBuckets: const [3, 20, 60, 40, 55],
      weekdayExpense: 300000,
      weekendExpense: 200000,
      weekdayDays: 260,
      weekendDays: 105,
      stock: stock,
    );

void main() {
  final trades = [
    t('buy', 100000, '2026-01-05'),
    t('buy', 50000, '2026-01-06', symbol: '0050'),
    t('sell', 60000, '2026-02-01'),
    t('sell', 20000, '2026-03-01', symbol: '0050'),
    t('cash_dividend', 800, '2026-07-01'),
    t('cash_dividend', 500, '2026-10-01', symbol: '0050'),
    t('buy', 1000, '2026-04-01', market: 'US', symbol: 'AAPL'),
  ];
  final stock = StockAnnualReport.build(trades, year: 2026);

  testWidgets('股票總覽:多幣別 chip 可切換', (tester) async {
    expect(stock.currencies.length, 2);
    final selected = ValueNotifier<int>(0);
    await tester
        .pumpWidget(host(AnnualStockOverviewPage(stock: stock, selected: selected)));
    await tester.pumpAndSettle();
    expect(find.text('股票年度總覽'), findsOneWidget);
    expect(find.text('TWD'), findsOneWidget);
    expect(find.text('USD'), findsOneWidget);
    await tester.tap(find.text('USD'));
    await tester.pumpAndSettle();
    expect(selected.value, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('股票亮點:最賺/勝率/領息王/月柱狀圖', (tester) async {
    await tester.pumpWidget(host(AnnualStockHighlightsPage(
        stock: stock, selected: ValueNotifier<int>(0))));
    await tester.pumpAndSettle();
    expect(find.text('股票亮點'), findsOneWidget);
    expect(find.text('領息王'), findsOneWidget);
    expect(find.text('勝率'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('只有買進(沒賣出)的幣別也能渲染', (tester) async {
    final onlyBuy = StockAnnualReport.build(
        [t('buy', 1000, '2026-01-01')],
        year: 2026);
    final sel = ValueNotifier<int>(0);
    await tester.pumpWidget(
        host(AnnualStockOverviewPage(stock: onlyBuy, selected: sel)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
        host(AnnualStockHighlightsPage(stock: onlyBuy, selected: sel)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('年度稱號 / 跟去年比 / 消費習慣', (tester) async {
    final data = reportData(stock: stock);
    for (final page in <Widget>[
      AnnualPersonaPage(data: data),
      AnnualYoYPage(data: data),
      AnnualHabitsPage(data: data),
    ]) {
      await tester.pumpWidget(host(page));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(data.hasPreviousYear, isTrue);
    expect(data.hasHabits, isTrue);
    expect(data.weekendWeekdayRatio, isNotNull);
    expect(reportData(prev: false).hasPreviousYear, isFalse);
  });

  testWidgets('窄螢幕不 overflow', (tester) async {
    final data = reportData(stock: stock);
    for (final page in <Widget>[
      AnnualStockOverviewPage(stock: stock, selected: ValueNotifier<int>(0)),
      AnnualStockHighlightsPage(stock: stock, selected: ValueNotifier<int>(0)),
      AnnualPersonaPage(data: data),
      AnnualYoYPage(data: data),
      AnnualHabitsPage(data: data),
    ]) {
      await tester.pumpWidget(host(page, width: 320));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
