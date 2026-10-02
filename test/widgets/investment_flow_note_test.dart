// 股票報表一致性的 UI 元件(docs/changes/2026-10-03-stock-report-consistency.md):
//   - InvestmentFlowNote:期間內有股票買賣時顯示「投資淨投入」補充資訊,沒有時不佔空間
//   - StockNetWorthNote:淨資產卡下的說明,沒記過股票交易時不顯示
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers.dart';
import 'package:beecount/services/currency/rate_math.dart';
import 'package:beecount/widgets/biz/investment_flow_note.dart';

StockTrade trade(String type, double amount, DateTime date,
        {double fee = 0, double tax = 0, int id = 1}) =>
    StockTrade(
      id: id,
      syncId: 's$id',
      ledgerId: 1,
      accountId: 2,
      market: 'TW',
      symbol: '2330',
      tradeType: type,
      shares: 100,
      fee: fee,
      tax: tax,
      amount: amount,
      currency: 'TWD',
      tradeDate: date,
      createdAt: date,
      updatedAt: date,
    );

Widget host(Widget child, List<StockTrade> trades) => ProviderScope(
      overrides: [
        stockTradesProvider.overrideWith((ref) => Stream.value(trades)),
        securityQuotesProvider
            .overrideWith((ref) => Stream.value(const <String, SecurityQuote>{})),
        currentLedgerProvider.overrideWith((ref) => Stream.value(Ledger(
              id: 1,
              name: 'L',
              currency: 'TWD',
              type: 'personal',
              createdAt: DateTime(2026),
              myRole: 'owner',
              memberCount: 1,
              isShared: false,
              monthStartDay: 1,
            ))),
        effectiveRatesProvider
            .overrideWith((ref) async => <String, EffectiveRate>{}),
        allAccountsStreamProvider
            .overrideWith((ref) => Stream.value(const <Account>[])),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  final oct = DateTime(2026, 10, 1);
  final nov = DateTime(2026, 11, 1);

  testWidgets('期間內有買賣:顯示淨投入、買賣明細、手續費稅(註明不計入收支)', (tester) async {
    await tester.pumpWidget(host(
      InvestmentFlowNote(start: oct, end: nov, ledgerId: 1),
      [
        trade('buy', 10000, DateTime(2026, 10, 5), fee: 14, id: 1),
        trade('sell', 4000, DateTime(2026, 10, 9), fee: 6, tax: 12, id: 2),
        trade('cash_dividend', 300, DateTime(2026, 10, 12), id: 3),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Net invested in stocks +NT\$6,000'), findsOneWidget);
    expect(find.textContaining('not counted as income or expense'), findsOneWidget);
    expect(find.textContaining('Fees & transaction tax NT\$32'), findsOneWidget);
    expect(find.textContaining('Dividend income NT\$300'), findsOneWidget);
  });

  testWidgets('期間內沒有股票買賣/股利:完全不顯示', (tester) async {
    await tester.pumpWidget(host(
      InvestmentFlowNote(start: nov, end: DateTime(2026, 12, 1), ledgerId: 1),
      [trade('buy', 10000, DateTime(2026, 10, 5), id: 1)],
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Net invested'), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('compact 模式只顯示主行與第一行說明', (tester) async {
    await tester.pumpWidget(host(
      InvestmentFlowNote(start: oct, end: nov, ledgerId: 1, compact: true),
      [trade('buy', 10000, DateTime(2026, 10, 5), fee: 14, id: 1)],
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Net invested in stocks'), findsOneWidget);
    expect(find.textContaining('not counted as income or expense'), findsOneWidget);
    expect(find.textContaining('Fees & transaction tax'), findsNothing);
  });

  testWidgets('StockNetWorthNote:沒記過股票交易時不顯示', (tester) async {
    await tester.pumpWidget(host(const StockNetWorthNote(), const []));
    await tester.pumpAndSettle();
    expect(find.textContaining('Investment accounts are excluded'), findsNothing);
    expect(find.textContaining('Excludes investment accounts'), findsNothing);
  });

  testWidgets('StockNetWorthNote:有股票交易但全部缺報價,不寫「約 \$0」', (tester) async {
    await tester.pumpWidget(host(const StockNetWorthNote(),
        [trade('buy', 10000, DateTime(2026, 10, 5), id: 1)]));
    await tester.pumpAndSettle();
    expect(find.textContaining('Investment accounts are excluded'), findsOneWidget);
    expect(find.textContaining('about'), findsNothing);
  });
}
