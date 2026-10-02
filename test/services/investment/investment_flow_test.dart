import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/l10n/app_localizations_en.dart';
import 'package:beecount/services/investment/investment_flow.dart';
import 'package:beecount/widgets/biz/investment_flow_note.dart';

InvestmentFlowTrade t(String type, double amount, String date,
        {double fee = 0,
        double tax = 0,
        String currency = 'TWD',
        int ledger = 1,
        String market = 'TW'}) =>
    InvestmentFlowTrade(
      tradeType: type,
      amount: amount,
      fee: fee,
      tax: tax,
      currency: currency,
      market: market,
      tradeDate: DateTime.parse(date),
      ledgerId: ledger,
    );

void main() {
  final trades = [
    // 買進 4,878(價金 4,872 + 手續費 6)
    t('buy', 4878, '2026-10-02', fee: 6),
    // 賣出 淨收入 1,000(價金 1,030 − 手續費 9 − 稅 21)
    t('sell', 1000, '2026-10-10', fee: 9, tax: 21),
    // 股利:現金 200、再投入 300
    t('cash_dividend', 200, '2026-10-15', fee: 10),
    t('reinvest', 300, '2026-10-16'),
    // 沒有現金流的類型,全部忽略
    t('opening', 5000, '2026-10-01'),
    t('stock_dividend', 0, '2026-10-05'),
    t('split', 0, '2026-10-06'),
  ];

  test('買進/賣出/淨投入/手續費稅/股利各自獨立,無現金流的類型被忽略', () {
    final f = InvestmentFlow.compute(trades);
    final c = f.byCurrency['TWD']!;
    expect(c.buy, 4878);
    expect(c.sell, 1000);
    expect(c.netInvested, 3878);
    // 手續費稅只算 buy/sell(6 + 9 + 21),股利的手續費不算進來
    expect(c.feesAndTax, 36);
    // 股利 = 現金 + 再投入
    expect(c.dividends, 500);
    expect(c.buyCount, 1);
    expect(c.sellCount, 1);
    expect(f.hasTrades, isTrue);
    expect(f.hasDividends, isTrue);
    expect(f.hasFees, isTrue);
  });

  test('再投入股利不進淨投入(它是收入直接入投資帳戶,不是從交割戶掏錢)', () {
    final f = InvestmentFlow.compute([t('reinvest', 300, '2026-10-16')]);
    final c = f.byCurrency['TWD']!;
    expect(c.netInvested, 0);
    expect(c.dividends, 300);
    expect(f.hasTrades, isFalse);
  });

  test('期間是半開區間 [start, end),並可依帳本篩選', () {
    final all = [
      t('buy', 100, '2026-10-01'),
      t('buy', 200, '2026-10-31T23:59:59'),
      t('buy', 400, '2026-11-01'),
      t('buy', 800, '2026-10-05', ledger: 2),
    ];
    final oct = InvestmentFlow.compute(all,
        start: DateTime(2026, 10, 1), end: DateTime(2026, 11, 1), ledgerId: 1);
    expect(oct.byCurrency['TWD']!.buy, 300);
    final noLedgerFilter = InvestmentFlow.compute(all,
        start: DateTime(2026, 10, 1), end: DateTime(2026, 11, 1));
    expect(noLedgerFilter.byCurrency['TWD']!.buy, 1100);
  });

  test('沒有任何買賣/股利時 isEmpty', () {
    expect(InvestmentFlow.compute([t('opening', 5000, '2026-10-01')]).isEmpty,
        isTrue);
    expect(InvestmentFlow.empty.isEmpty, isTrue);
  });

  test('幣別缺省時用市場預設幣別', () {
    final f = InvestmentFlow.compute([
      InvestmentFlowTrade(
          tradeType: 'buy',
          amount: 100,
          market: 'US',
          tradeDate: DateTime(2026, 10, 1),
          ledgerId: 1),
    ]);
    expect(f.byCurrency.keys, ['USD']);
  });

  test('多幣別分開統計,convertTo 帶匯率換算並剔除缺匯率的幣別', () {
    final f = InvestmentFlow.compute([
      t('buy', 10000, '2026-10-01', fee: 20),
      t('buy', 100, '2026-10-02', currency: 'USD', fee: 1, market: 'US'),
      t('sell', 50, '2026-10-03', currency: 'JPY', market: 'JP'),
    ]);
    expect(f.byCurrency.keys.toSet(), {'TWD', 'USD', 'JPY'});
    // 換成 TWD:USD 1 = 30,JPY 沒匯率
    final conv = f.convertTo('TWD', (c) => c == 'USD' ? 30.0 : null);
    expect(conv.currency, 'TWD');
    expect(conv.total.buy, 10000 + 3000);
    expect(conv.total.feesAndTax, 20 + 30);
    expect(conv.total.sell, 0);
    expect(conv.missingCurrencies, ['JPY']);
  });

  test('crossRate:同幣別 1.0,經主幣別中轉,缺匯率回 null', () {
    // 以 TWD 為主幣別:USD=30,CNY=4
    double? toBase(String c) => {'TWD': 1.0, 'USD': 30.0, 'CNY': 4.0}[c];
    expect(InvestmentFlow.crossRate('CNY', 'cny', toBase), 1.0);
    expect(InvestmentFlow.crossRate('USD', 'CNY', toBase), 7.5);
    expect(InvestmentFlow.crossRate('JPY', 'CNY', toBase), isNull);
    expect(InvestmentFlow.crossRate('USD', 'JPY', toBase), isNull);
  });

  group('InvestmentFlowLines 文案', () {
    final l10n = AppLocalizationsEn();

    test('有買賣:主行 + 買賣明細(註明未計入收支)+ 手續費稅(註明不計入支出)+ 股利(註明已計入收入)',
        () {
      final conv = InvestmentFlow.compute(trades)
          .convertTo('TWD', (_) => null);
      final lines = InvestmentFlowLines.build(l10n, conv);
      expect(lines.title, contains('Net invested in stocks'));
      expect(lines.title, contains('+NT\$3,878'));
      expect(lines.details[0], contains('not counted as income or expense'));
      expect(lines.details[1], contains('not counted as expense'));
      expect(lines.details[2], contains('already included in income'));
      expect(lines.warningIndex, isNull);
    });

    test('只有股利:沒有主行', () {
      final conv = InvestmentFlow.compute([t('cash_dividend', 200, '2026-10-15')])
          .convertTo('TWD', (_) => null);
      final lines = InvestmentFlowLines.build(l10n, conv);
      expect(lines.title, isNull);
      expect(lines.details.single, contains('already included in income'));
    });

    test('缺匯率那行標警示,隱藏金額模式不顯示數字', () {
      final conv = InvestmentFlow.compute([
        t('buy', 100, '2026-10-01'),
        t('buy', 100, '2026-10-02', currency: 'USD', market: 'US'),
      ]).convertTo('TWD', (_) => null);
      final lines = InvestmentFlowLines.build(l10n, conv, hide: true);
      expect(lines.title, contains('****'));
      expect(lines.warningIndex, isNotNull);
      expect(lines.details[lines.warningIndex!], contains('USD'));
    });
  });
}
