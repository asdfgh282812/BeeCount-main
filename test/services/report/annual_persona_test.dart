import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/services/investment/holdings_calculator.dart';
import 'package:beecount/services/investment/stock_annual_report.dart';
import 'package:beecount/services/report/annual_persona.dart';

AnnualPersona decide({
  double income = 100000,
  double expense = 90000,
  int streak = 5,
  double? ratio,
  String? cat,
  double? share,
  StockCurrencyAnnual? stock,
}) =>
    AnnualPersona.decide(
      totalRecords: 120,
      totalDays: 80,
      totalIncome: income,
      totalExpense: expense,
      maxConsecutiveDays: streak,
      weekendWeekdayRatio: ratio,
      topCategoryName: cat,
      topCategoryShare: share,
      stock: stock,
    );

StockCurrencyAnnual stockWith(List<HoldingTrade> trades) =>
    StockAnnualReport.build(trades, year: 2026).primary!;

HoldingTrade tr(String type, double amount, String date, {int i = 0}) =>
    HoldingTrade(
        syncId: 's$i$date$type',
        accountKey: '1',
        market: 'TW',
        symbol: '2330',
        tradeType: type,
        shares: 10,
        price: null,
        fee: 0,
        tax: 0,
        amount: amount,
        tradeDateKey: date);

void main() {
  test('儲蓄率 >= 30% → superSaver,理由含儲蓄率', () {
    final p = decide(income: 100000, expense: 60000);
    expect(p.type, AnnualPersonaType.superSaver);
    expect(p.reasons.first.kind, PersonaReasonKind.savingsRate);
    expect(p.reasons.first.value, closeTo(40, 1e-9));
    expect(p.reasons.length, inInclusiveRange(2, 3));
  });

  test('連續記帳 >= 30 天 → consistentRecorder', () {
    expect(decide(streak: 45).type, AnnualPersonaType.consistentRecorder);
  });

  test('週末日均 >= 1.5 倍平日 → weekendSpender', () {
    final p = decide(ratio: 1.8);
    expect(p.type, AnnualPersonaType.weekendSpender);
    expect(p.reasons.first.kind, PersonaReasonKind.weekendHigh);
  });

  test('單一分類占 >= 40% → focusedSpender,理由含分類名稱', () {
    final p = decide(cat: '餐飲', share: 0.45);
    expect(p.type, AnnualPersonaType.focusedSpender);
    expect(p.reasons.first.label, '餐飲');
  });

  test('入不敷出 → adventurer;沒有收入資料時不算入不敷出', () {
    expect(decide(income: 50000, expense: 60000).type,
        AnnualPersonaType.adventurer);
    expect(decide(income: 0, expense: 1000).type, AnnualPersonaType.steady);
  });

  test('股票風格優先於儲蓄率', () {
    final active = stockWith([
      for (var i = 0; i < 45; i++) tr('buy', 100, '2026-01-02', i: i),
    ]);
    final p = decide(income: 100000, expense: 10000, stock: active);
    expect(p.type, AnnualPersonaType.stockTrader);
    expect(p.reasons.first.kind, PersonaReasonKind.stockStyle);

    final div = stockWith([
      tr('buy', 1000, '2026-01-02'),
      tr('cash_dividend', 300, '2026-07-01'),
      tr('cash_dividend', 300, '2026-10-01', i: 1),
    ]);
    expect(decide(stock: div).type, AnnualPersonaType.dividendCollector);
  });

  test('理由最多 3 個、至少有記帳筆數可補', () {
    final p = decide(income: 0, expense: 1000, streak: 1);
    expect(p.reasons, isNotEmpty);
    expect(p.reasons.length, lessThanOrEqualTo(3));
    expect(p.reasons.any((r) => r.kind == PersonaReasonKind.records), isTrue);
  });
}
