// 自由對話股票工具(2026-10-03,docs/changes/2026-10-03-stock-ai-tools.md)。
//
// 用記憶體 Drift DB + LocalRepository 建真實的明細/報價/帳戶設定/定期定額規則,
// 驗證每個工具:有資料、無資料、多幣別分開、年度/日期篩選、報價缺失/過期、
// 名稱模糊比對、截斷旗標。
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/models/investment_settings.dart';
import 'package:beecount/services/ai/free_chat_stock_tools.dart';
import 'package:beecount/services/ai/free_chat_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  // 固定「現在」:報價新鮮/過期、近 12 個月股利、持有天數都以它為準。
  final now = DateTime(2026, 10, 3, 12);
  const executor = FreeChatToolExecutor();

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency, sync_id) VALUES (1, 'L', 'TWD', 'lg1')");
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, type, currency, sync_id) VALUES "
        "(1, 1, '交割戶', 'bank_card', 'TWD', 'acc_bank'), "
        "(2, 1, '永豐證券', 'investment', 'TWD', 'acc_inv'), "
        "(3, 1, '複委託', 'investment', 'USD', 'acc_us')");
  });

  tearDown(() async => db.close());

  Future<Map<String, dynamic>> run(String tool, [Map<String, dynamic>? params,
          StockPendingDividendsLoader? pending]) =>
      executor.execute(tool, params ?? {},
          repo: repo, ledgerId: 1, now: () => now, pendingDividends: pending);

  Future<int> trade({
    required int account,
    required String type,
    required String market,
    required String symbol,
    String? name,
    required double shares,
    double? price,
    double fee = 0,
    double tax = 0,
    required DateTime date,
    int? settlement = 1,
    double? settlementAmount,
    String? ruleId,
  }) =>
      repo.createStockTrade(
        ledgerId: 1,
        accountId: account,
        tradeType: type,
        market: market,
        symbol: symbol,
        securityName: name,
        shares: shares,
        price: price,
        fee: fee,
        tax: tax,
        tradeDate: date,
        settlementAccountId: settlement,
        settlementAmount: settlementAmount,
        recurringRuleId: ruleId,
      );

  Future<void> quote(String market, String symbol, double price,
      {required DateTime fetchedAt, String? name}) {
    return repo.upsertSecurityQuotes([
      SecurityQuotesCompanion.insert(
        market: market,
        symbol: symbol,
        name: d.Value(name),
        price: d.Value(price),
        quoteTime: d.Value(fetchedAt),
        session: const d.Value('close'),
        source: const d.Value('test'),
        fetchedAt: fetchedAt,
      ),
    ]);
  }

  /// 標準資料集(數字都已手算):
  /// - 2330 台積電:2026-01-10 買 1000@600(手續費 855 → 成本 600,855),
  ///   2026-03-05 賣 400@700(費 399 稅 840 → 淨收入 278,761,已實現 38,419),
  ///   2026-06-11 現金股利 600 股×5−10 = 2,990。
  /// - 0050:2026-02-01 買 100@180(費 25 → 成本 18,025)。
  /// - 2412 中華電(已出清):2025-01-05 買 100@120(費 20),2025-07-01 賣
  ///   100@130(費 18 稅 39 → 淨 12,943,已實現 923)。
  /// - AAPL(複委託 USD,沒有報價):2026-04-01 買 10@150(費 1),
  ///   2026-08-10 現金股利 10×0.27−0.81 = 1.89。
  /// - 報價:2330 = 650(10/3 10:00,新鮮)、0050 = 190(9/20,過期)、AAPL 無。
  Future<void> seed() async {
    await trade(
        account: 2,
        type: 'buy',
        market: 'TW',
        symbol: '2330',
        name: '台積電',
        shares: 1000,
        price: 600,
        fee: 855,
        date: DateTime(2026, 1, 10, 12));
    await trade(
        account: 2,
        type: 'buy',
        market: 'TW',
        symbol: '0050',
        name: '元大台灣50',
        shares: 100,
        price: 180,
        fee: 25,
        date: DateTime(2026, 2, 1, 12));
    await trade(
        account: 2,
        type: 'sell',
        market: 'TW',
        symbol: '2330',
        shares: 400,
        price: 700,
        fee: 399,
        tax: 840,
        date: DateTime(2026, 3, 5, 12));
    await trade(
        account: 2,
        type: 'buy',
        market: 'TW',
        symbol: '2412',
        name: '中華電',
        shares: 100,
        price: 120,
        fee: 20,
        date: DateTime(2025, 1, 5, 12));
    await trade(
        account: 2,
        type: 'sell',
        market: 'TW',
        symbol: '2412',
        shares: 100,
        price: 130,
        fee: 18,
        tax: 39,
        date: DateTime(2025, 7, 1, 12));
    await trade(
        account: 2,
        type: 'cash_dividend',
        market: 'TW',
        symbol: '2330',
        shares: 600,
        price: 5,
        fee: 10,
        date: DateTime(2026, 6, 11, 12));
    await trade(
        account: 3,
        type: 'buy',
        market: 'US',
        symbol: 'AAPL',
        name: 'Apple',
        shares: 10,
        price: 150,
        fee: 1,
        date: DateTime(2026, 4, 1, 12),
        settlementAmount: 4700);
    await trade(
        account: 3,
        type: 'cash_dividend',
        market: 'US',
        symbol: 'AAPL',
        shares: 10,
        price: 0.27,
        tax: 0.81,
        date: DateTime(2026, 8, 10, 12),
        settlement: 3);
    await quote('TW', '2330', 650, fetchedAt: DateTime(2026, 10, 3, 10));
    await quote('TW', '0050', 190, fetchedAt: DateTime(2026, 9, 20, 15));
  }

  Map<String, dynamic> m(dynamic v) => (v as Map).cast<String, dynamic>();
  List<Map<String, dynamic>> ml(dynamic v) =>
      (v as List).map((e) => (e as Map).cast<String, dynamic>()).toList();

  test('所有股票工具都有登記 spec,並被 isFreeChatStockTool 認得', () {
    const expected = {
      'stock_holdings',
      'stock_trades',
      'stock_realized_pnl',
      'stock_dividends',
      'stock_settings',
      'stock_dca_plans',
      'stock_performance',
      'stock_portfolio_analysis',
    };
    final names = freeChatTools.map((t) => t.name).toSet();
    expect(names.containsAll(expected), isTrue);
    for (final n in expected) {
      expect(isFreeChatStockTool(n), isTrue);
    }
    expect(isFreeChatStockTool('get_spending_summary'), isFalse);
    final section = buildFreeChatToolsPromptSection();
    for (final n in expected) {
      expect(section, contains('- $n:'));
    }
  });

  // ==========================================================================
  group('stock_holdings', () {
    test('各幣別分開、數字同持股頁口徑(扣預估賣出成本)', () async {
      await seed();
      final r = await run('stock_holdings');

      expect(r['holdingCount'], 3);
      final positions = ml(r['positions']);
      final tsmc = positions.firstWhere((p) => p['symbol'] == '2330');
      expect(tsmc['name'], '台積電');
      expect(tsmc['account'], '永豐證券');
      expect(tsmc['shares'], 600);
      // 剩餘成本 = 600,855 − 400×600.855
      expect(tsmc['totalCost'], 360513);
      expect(tsmc['marketValue'], 390000);
      // 預估賣出:手續費 555、證交稅 1,170 → 淨值 388,275
      expect(tsmc['estSellFee'], 555);
      expect(tsmc['estSellTax'], 1170);
      expect(tsmc['netValue'], 388275);
      expect(tsmc['unrealizedPnl'], 27762);
      expect(m(tsmc['quote'])['available'], isTrue);
      expect(m(tsmc['quote'])['price'], 650);
      expect(m(tsmc['quote'])['stale'], isFalse);
      expect(m(tsmc['quote'])['fetchedAt'], '2026-10-03 10:00');

      final byCcy = m(r['byCurrency']);
      expect(byCcy.keys.toSet(), {'TWD', 'USD'});
      final twd = m(byCcy['TWD']);
      expect(twd['cost'], 378538);
      expect(twd['marketValue'], 409000);
      expect(twd['valuation'], 407229);
      expect(twd['unrealizedPnl'], 28691);
      expect(twd['pnlBasis'], 'afterEstimatedSellCosts');
      expect(twd['staleQuoteCount'], 1);
      // 已實現含已出清的中華電
      expect(twd['realizedPnl'], 39342);
      expect(twd['dividends'], 2990);
      // USD 沒有報價:不計市值,標 unpricedCount
      final usd = m(byCcy['USD']);
      expect(usd['unpricedCount'], 1);
      expect(usd['marketValue'], 0);
      expect(usd['cost'], 1501);
    });

    test('報價過期(>72 小時)標 stale,缺報價 available=false', () async {
      await seed();
      final r = await run('stock_holdings');
      final positions = ml(r['positions']);
      final etf = positions.firstWhere((p) => p['symbol'] == '0050');
      expect(m(etf['quote'])['stale'], isTrue);
      expect(m(etf['quote'])['ageHours'], greaterThan(72));
      final aapl = positions.firstWhere((p) => p['symbol'] == 'AAPL');
      expect(m(aapl['quote']), {'available': false});
      expect(aapl['marketValue'], isNull);
      expect(aapl['unrealizedPnl'], isNull);
    });

    test('名稱模糊比對「台積電」、代號、陣列', () async {
      await seed();
      var r = await run('stock_holdings', {'symbol': '台積電'});
      expect(ml(r['positions']).map((p) => p['symbol']), ['2330']);
      expect(m(r['filters'])['resolvedSecurities'], ['TW:2330 台積電']);

      r = await run('stock_holdings', {'symbol': 'aapl'});
      expect(ml(r['positions']).map((p) => p['symbol']), ['AAPL']);

      r = await run('stock_holdings', {
        'symbol': ['2330', 'TW:0050']
      });
      expect(ml(r['positions']).map((p) => p['symbol']).toSet(),
          {'2330', '0050'});
    });

    test('帳戶名稱篩選與找不到帳戶', () async {
      await seed();
      var r = await run('stock_holdings', {'account': '複委託'});
      expect(m(r['byCurrency']).keys, ['USD']);

      r = await run('stock_holdings', {'account': '永豐'});
      expect(m(r['byCurrency']).keys, ['TWD']);

      r = await run('stock_holdings', {'account': '不存在證券'});
      expect(r['holdingCount'], 0);
      expect(m(r['filters'])['warning'], contains('找不到名稱相近'));
      expect(r.containsKey('positions'), isFalse);

      r = await run('stock_holdings', {'symbol': '9999'});
      expect(r['holdingCount'], 0);
      expect(m(r['filters'])['warning'], contains('找不到相符的股票'));
    });

    test('includeClosed 才列出已出清的部位', () async {
      await seed();
      var r = await run('stock_holdings');
      expect(ml(r['positions']).any((p) => p['symbol'] == '2412'), isFalse);
      r = await run('stock_holdings', {'includeClosed': true});
      final closed = ml(r['positions']).firstWhere((p) => p['symbol'] == '2412');
      expect(closed['isOpen'], isFalse);
      expect(closed['realizedPnl'], 923);
    });

    test('帳戶設定關閉「扣預估賣出成本」→ 用毛市值算未實現損益', () async {
      await seed();
      await repo.updateAccountInvestmentSettings(
          2, const InvestmentSettings(pnlAfterSellCosts: false));
      final r = await run('stock_holdings', {'symbol': '2330'});
      final tsmc = ml(r['positions']).single;
      expect(tsmc['unrealizedPnl'], 29487); // 390,000 − 360,513
      expect(m(m(r['byCurrency'])['TWD'])['pnlBasis'], 'grossMarketValue');
    });

    test('沒有任何股票資料', () async {
      final r = await run('stock_holdings');
      expect(r['holdingCount'], 0);
      expect(r['note'], contains('沒有任何股票持股'));
      expect(r.containsKey('positions'), isFalse);
    });

    test('持股超過上限時標 truncated,彙總仍涵蓋全部', () async {
      for (var i = 0; i < kStockToolMaxPositions + 3; i++) {
        await trade(
            account: 2,
            type: 'opening',
            market: 'TW',
            symbol: '${1100 + i}',
            shares: 10,
            price: 10,
            date: DateTime(2026, 1, 1, 12));
      }
      final r = await run('stock_holdings');
      expect(r['holdingCount'], kStockToolMaxPositions + 3);
      expect(ml(r['positions']), hasLength(kStockToolMaxPositions));
      expect(r['positionsTruncated'], isTrue);
      expect(m(m(r['byCurrency'])['TWD'])['openPositions'],
          kStockToolMaxPositions + 3);
    });
  });

  // ==========================================================================
  group('stock_trades', () {
    test('全期間彙總:各幣別買進/賣出/手續費/稅分開,股利費用另列', () async {
      await seed();
      final r = await run('stock_trades');
      expect(r['matchedCount'], 8);
      final twd = m(m(r['totalsByCurrency'])['TWD']);
      expect(twd['buyAmount'], 630900); // 600,855 + 18,025 + 12,020
      expect(twd['buyCount'], 3);
      expect(twd['sellAmount'], 291704); // 278,761 + 12,943
      expect(twd['sellCount'], 2);
      expect(twd['feeTotal'], 1317);
      expect(twd['taxTotal'], 879);
      expect(twd['feeAndTaxTotal'], 2196);
      expect(twd['dividendFeeAndTax'], 10);
      final usd = m(m(r['totalsByCurrency'])['USD']);
      expect(usd['buyAmount'], 1501);
      expect(usd['feeTotal'], 1);
      expect(usd['dividendFeeAndTax'], 0.81);
      expect(m(r['countByType'])['buy'], 4);
      expect(m(r['countByType'])['cash_dividend'], 2);
    });

    test('日期區間篩選(含頭含尾)與最近一筆', () async {
      await seed();
      var r = await run('stock_trades',
          {'startDate': '2026-03-01', 'endDate': '2026-03-31'});
      expect(r['matchedCount'], 1);
      expect(m(r['latestTrade'])['type'], 'sell');
      expect(m(r['latestTrade'])['date'], '2026-03-05');

      r = await run('stock_trades', {'endDate': '2026-03-05', 'limit': 1});
      expect(m(r['latestTrade'])['date'], '2026-03-05');
      expect(m(r['sample'])['count'], 1);
      expect(m(r['sample'])['isPartial'], isTrue);
    });

    test('標的 + 類型篩選;sample 新到舊;limit=0 只要彙總', () async {
      await seed();
      var r = await run('stock_trades', {'symbol': '台積電'});
      expect(r['matchedCount'], 3);
      final dates = ml(m(r['sample'])['trades']).map((t) => t['date']).toList();
      expect(dates, ['2026-06-11', '2026-03-05', '2026-01-10']);

      r = await run('stock_trades', {'symbol': '2330', 'tradeType': 'sell'});
      expect(r['matchedCount'], 1);
      expect(ml(m(r['sample'])['trades']).single['shares'], 400);

      r = await run('stock_trades', {'tradeType': 'dividend'});
      expect(r['matchedCount'], 2);

      r = await run('stock_trades', {'limit': 0});
      expect(m(r['sample'])['count'], 0);
      expect(r['matchedCount'], 8);
      expect(m(r['latestTrade'])['date'], '2026-08-10');
    });

    test('帳戶篩選', () async {
      await seed();
      final r = await run('stock_trades', {'account': '複委託'});
      expect(r['matchedCount'], 2);
      expect(m(r['totalsByCurrency']).keys, ['USD']);
    });

    test('無資料、找不到標的、參數錯誤', () async {
      var r = await run('stock_trades');
      expect(r['matchedCount'], 0);
      await seed();
      r = await run('stock_trades', {'symbol': '9999'});
      expect(r['matchedCount'], 0);
      expect(m(r['filters'])['warning'], contains('找不到相符的股票'));
      r = await run('stock_trades', {'startDate': '2030-01-01'});
      expect(r['matchedCount'], 0);

      expect(() => run('stock_trades', {'tradeType': 'gift'}),
          throwsA(isA<FreeChatToolException>()));
      expect(() => run('stock_trades', {'startDate': '昨天'}),
          throwsA(isA<FreeChatToolException>()));
    });
  });

  // ==========================================================================
  group('stock_realized_pnl', () {
    test('年度篩選:2026 / 2025 / 全部,各幣別分開', () async {
      await seed();
      var r = await run('stock_realized_pnl', {'year': 2026});
      var twd = m(m(r['totalsByCurrency'])['TWD']);
      expect(twd['realizedPnl'], 38419);
      expect(twd['dividends'], 2990);
      expect(twd['sellCount'], 1);
      expect(twd['winningSells'], 1);
      // USD 只有股利、沒有賣出
      var usd = m(m(r['totalsByCurrency'])['USD']);
      expect(usd['realizedPnl'], 0);
      expect(usd['dividends'], 1.89);
      expect(r['availableYears'], [2026, 2025]);

      r = await run('stock_realized_pnl', {'year': 2025});
      twd = m(m(r['totalsByCurrency'])['TWD']);
      expect(twd['realizedPnl'], 923);
      expect(twd['dividends'], 0);
      expect(m(r['totalsByCurrency']).containsKey('USD'), isFalse);

      r = await run('stock_realized_pnl');
      twd = m(m(r['totalsByCurrency'])['TWD']);
      expect(twd['realizedPnl'], 39342);
      expect(twd['realizedPnlPlusDividends'], 42332);
      expect(r['symbolCount'], 3);
    });

    test('成本用全部歷史算:篩 2026 時 2330 賣出成本不變', () async {
      await seed();
      final r = await run('stock_realized_pnl', {'year': 2026, 'symbol': '2330'});
      final g = ml(r['groups']).single;
      expect(g['symbol'], '2330');
      final sell = ml(g['sells']).single;
      expect(sell['costBasis'], 240342);
      expect(sell['proceeds'], 278761);
      expect(sell['pnl'], 38419);
    });

    test('標的/帳戶篩選與排序(依損益絕對值)', () async {
      await seed();
      var r = await run('stock_realized_pnl', {'account': '永豐'});
      final syms = ml(r['groups']).map((g) => g['symbol']).toList();
      expect(syms.first, '2330');
      expect(syms, contains('2412'));

      r = await run('stock_realized_pnl', {'symbol': '中華電'});
      expect(ml(r['groups']).single['symbol'], '2412');
    });

    test('無資料 / 沒有符合的年度 / 找不到標的', () async {
      var r = await run('stock_realized_pnl');
      expect(r.containsKey('totalsByCurrency'), isFalse);
      expect(r['note'], isNotNull);

      await seed();
      r = await run('stock_realized_pnl', {'year': 2020});
      expect(r.containsKey('groups'), isFalse);
      expect(r['availableYears'], [2026, 2025]);

      r = await run('stock_realized_pnl', {'symbol': '9999'});
      expect(m(r['filters'])['warning'], contains('找不到相符的股票'));
    });

    test('標的分組超過上限時 truncated', () async {
      for (var i = 0; i < kStockToolMaxGroups + 2; i++) {
        final sym = '${2000 + i}';
        await trade(
            account: 2,
            type: 'opening',
            market: 'TW',
            symbol: sym,
            shares: 10,
            price: 10,
            date: DateTime(2026, 1, 1, 12));
        await trade(
            account: 2,
            type: 'sell',
            market: 'TW',
            symbol: sym,
            shares: 10,
            price: 11,
            date: DateTime(2026, 2, 1, 12));
      }
      final r = await run('stock_realized_pnl');
      expect(ml(r['groups']), hasLength(kStockToolMaxGroups));
      expect(r['groupsTruncated'], isTrue);
      expect(r['symbolCount'], kStockToolMaxGroups + 2);
    });
  });

  // ==========================================================================
  group('stock_dividends', () {
    test('年度篩選、各幣別分開、近 12 個月', () async {
      await seed();
      var r = await run('stock_dividends', {'year': 2026});
      expect(r['matchedCount'], 2);
      final twd = m(m(r['totalsByCurrency'])['TWD']);
      expect(twd['cashDividend'], 2990);
      expect(twd['reinvested'], 0);
      expect(twd['totalDividends'], 2990);
      expect(m(m(r['totalsByCurrency'])['USD'])['cashDividend'], 1.89);
      expect(m(r['trailing12MonthsByCurrency'])['TWD'], 2990);
      expect(m(r['trailing12MonthsByCurrency'])['USD'], 1.89);
      expect(ml(r['bySymbol']).first['symbol'], '2330');

      r = await run('stock_dividends', {'year': 2025});
      expect(r['matchedCount'], 0);
      // 近 12 個月不受年度篩選影響
      expect(m(r['trailing12MonthsByCurrency'])['TWD'], 2990);
    });

    test('股利再投入與配股分開計', () async {
      await seed();
      await trade(
          account: 2,
          type: 'reinvest',
          market: 'TW',
          symbol: '2330',
          shares: 11,
          price: 630,
          fee: 1,
          date: DateTime(2026, 9, 20, 12),
          settlement: null);
      await trade(
          account: 2,
          type: 'stock_dividend',
          market: 'TW',
          symbol: '0050',
          shares: 5,
          date: DateTime(2026, 9, 21, 12),
          settlement: null);
      final r = await run('stock_dividends', {'account': '永豐'});
      final twd = m(m(r['totalsByCurrency'])['TWD']);
      expect(twd['reinvested'], 6931);
      expect(twd['totalDividends'], 2990 + 6931);
      expect(twd['stockDividendShares'], 5);
      expect(r['stockDividendCount'], 1);
    });

    test('待確認股利:沒有 loader 時 available=false', () async {
      await seed();
      final r = await run('stock_dividends');
      expect(m(r['pendingDividends'])['available'], isFalse);
    });

    test('待確認股利:讀 loader、只列 pending、套用標的/帳戶篩選', () async {
      await seed();
      Future<List<Map<String, dynamic>>> loader() async => [
            {
              'accountName': '永豐證券',
              'market': 'TW',
              'symbol': '2330',
              'exDate': '2026-09-18',
              'estNet': 3000.0,
              'status': 'pending',
            },
            {
              'accountName': '永豐證券',
              'market': 'TW',
              'symbol': '0050',
              'exDate': '2026-09-20',
              'estNet': 100.0,
              'status': 'pending',
            },
            {
              'accountName': '永豐證券',
              'market': 'TW',
              'symbol': '2330',
              'exDate': '2026-06-01',
              'status': 'dismissed',
            },
          ];
      var r = await run('stock_dividends', {}, loader);
      expect(m(r['pendingDividends'])['available'], isTrue);
      expect(m(r['pendingDividends'])['count'], 2);

      r = await run('stock_dividends', {'symbol': '台積電'}, loader);
      expect(m(r['pendingDividends'])['count'], 1);
      expect(ml(m(r['pendingDividends'])['items']).single['symbol'], '2330');

      r = await run('stock_dividends', {'account': '複委託'}, loader);
      expect(m(r['pendingDividends'])['count'], 0);
    });

    test('loader 拋例外時降級,不讓整個工具失敗', () async {
      await seed();
      final r = await run('stock_dividends', {},
          () async => throw StateError('boom'));
      expect(m(r['pendingDividends'])['available'], isFalse);
      expect(r['matchedCount'], 2);
    });

    test('無股利資料', () async {
      final r = await run('stock_dividends');
      expect(r['matchedCount'], 0);
      expect(r['note'], contains('沒有已入帳的股利'));
    });
  });

  // ==========================================================================
  group('stock_settings', () {
    test('未自訂:使用市場預設(依帳戶實際交易市場)', () async {
      await seed();
      final r = await run('stock_settings', {'account': '永豐證券'});
      final acc = ml(r['accounts']).single;
      expect(acc['usingAllDefaults'], isTrue);
      expect(acc['effectiveForMarket'], 'TW');
      final eff = m(acc['effective']);
      expect(eff['feeRate'], 0.001425);
      expect(eff['feeMin'], 20);
      expect(eff['sellTaxRate'], 0.003);
      expect(eff['etfSellTaxRate'], 0.001);
      expect(eff['nhiThreshold'], 20000);
      expect(eff['pnlAfterSellCosts'], isTrue);
    });

    test('自訂折扣/最低/交割帳戶/損益開關,並列出 customized', () async {
      await seed();
      await repo.updateAccountInvestmentSettings(
          2,
          const InvestmentSettings(
            feeDiscount: 0.6,
            feeMin: 1,
            pnlAfterSellCosts: false,
            settlementAccountId: 'acc_bank',
          ));
      final r = await run('stock_settings', {'account': '永豐'});
      final acc = ml(r['accounts']).single;
      expect(acc['usingAllDefaults'], isFalse);
      expect(m(acc['customized'])['feeDiscount'], 0.6);
      final eff = m(acc['effective']);
      expect(eff['feeDiscount'], 0.6);
      expect(eff['feeMin'], 1);
      expect(eff['effectiveFeeRate'], closeTo(0.000855, 1e-9));
      expect(eff['pnlAfterSellCosts'], isFalse);
      expect(eff['defaultSettlementAccount'], '交割戶');
    });

    test('多帳戶(美股帳戶用 US 預設)與不篩帳戶', () async {
      await seed();
      final r = await run('stock_settings');
      final accounts = ml(r['accounts']);
      expect(accounts, hasLength(2));
      final us = accounts.firstWhere((a) => a['account'] == '複委託');
      expect(us['effectiveForMarket'], 'US');
      expect(m(us['effective'])['dividendWithholdingRate'], 0.3);
    });

    test('沒有投資帳戶 / 找不到帳戶', () async {
      await db.customStatement("DELETE FROM accounts WHERE type = 'investment'");
      var r = await run('stock_settings');
      expect(r['accounts'], isEmpty);
      expect(r['note'], contains('沒有任何投資理財帳戶'));
      await db.customStatement(
          "INSERT INTO accounts (id, ledger_id, name, type, currency, sync_id) VALUES "
          "(2, 1, '永豐證券', 'investment', 'TWD', 'acc_inv')");
      r = await run('stock_settings', {'account': '不存在'});
      expect(r['accounts'], isEmpty);
      expect(r['note'], contains('找不到'));
    });
  });

  // ==========================================================================
  group('stock_dca_plans', () {
    Future<int> createPlan({
      String symbol = '0050',
      String name = '元大台灣50',
      double amount = 3000,
      double? feeRate,
      double? feeMin,
    }) =>
        repo.createRule(
          ledgerId: 1,
          type: 'transfer',
          amount: amount,
          fromAccountId: 1,
          toAccountId: 2,
          frequency: 'monthly',
          interval: 1,
          nextRunAt: DateTime(2026, 1, 15),
          kind: 'stock_dca',
          market: 'TW',
          symbol: symbol,
          securityName: name,
          stockFeeRate: feeRate,
          stockFeeMin: feeMin,
        );

    test('沒有計畫', () async {
      final r = await run('stock_dca_plans');
      expect(r['planCount'], 0);
      expect(r['note'], contains('沒有任何股票定期定額'));
    });

    test('設定欄位、尚未執行', () async {
      await createPlan(feeRate: 0.0006, feeMin: 1);
      final r = await run('stock_dca_plans');
      expect(r['planCount'], 1);
      final p = ml(r['plans']).single;
      expect(p['symbol'], '0050');
      expect(p['name'], '元大台灣50');
      expect(p['investmentAccount'], '永豐證券');
      expect(p['settlementAccount'], '交割戶');
      expect(p['amountPerPeriod'], 3000);
      expect(p['wholeShares'], isTrue);
      expect(p['frequency'], 'monthly');
      expect(p['executedPeriods'], 0);
      expect(p['totalInvested'], 0);
      expect(p['enabled'], isTrue);
      expect(p['upcomingRunAt'], '2026-01-15');
      expect(m(p['feeOverride']), {'feeRate': 0.0006, 'feeMin': 1.0});
    });

    test('沒覆寫手續費 → 沿用帳戶設定;已執行期數與累計投入', () async {
      final ruleId = await createPlan();
      final rule = (await repo.getRuleById(ruleId))!;
      expect(rule.syncId, isNotNull);
      await quote('TW', '0050', 190, fetchedAt: DateTime(2026, 10, 3, 10));
      await trade(
          account: 2,
          type: 'buy',
          market: 'TW',
          symbol: '0050',
          shares: 15,
          price: 190,
          fee: 20,
          date: DateTime(2026, 8, 15, 12),
          ruleId: rule.syncId);
      await trade(
          account: 2,
          type: 'buy',
          market: 'TW',
          symbol: '0050',
          shares: 15,
          price: 190,
          fee: 20,
          date: DateTime(2026, 9, 15, 12),
          ruleId: rule.syncId);
      // 非定期定額的單筆買進不算期數
      await trade(
          account: 2,
          type: 'buy',
          market: 'TW',
          symbol: '0050',
          shares: 1,
          price: 190,
          fee: 20,
          date: DateTime(2026, 9, 20, 12));

      final p = ml((await run('stock_dca_plans'))['plans']).single;
      expect(p['feeOverride'], 'usesInvestmentAccountSettings');
      expect(p['accountDefaultFeeRate'], 0.001425);
      expect(p['executedPeriods'], 2);
      expect(p['totalInvested'], 5700); // 2 × (15×190)
      expect(p['totalFees'], 40);
      expect(p['lastExecutedDate'], '2026-09-15');
    });

    test('名稱比對規則上的標的名稱、includeDisabled=false 排除停用', () async {
      final id = await createPlan();
      await createPlan(symbol: '00878', name: '國泰永續高股息');
      var r = await run('stock_dca_plans', {'symbol': '台灣50'});
      expect(ml(r['plans']).single['symbol'], '0050');

      await repo.setRuleEnabled(id, false);
      r = await run('stock_dca_plans', {'includeDisabled': false});
      expect(ml(r['plans']).single['symbol'], '00878');
      r = await run('stock_dca_plans');
      expect(r['planCount'], 2);
      expect(r['activeCount'], 1);
    });

    test('一般週期性規則不會被當成定期定額', () async {
      await repo.createRule(
        ledgerId: 1,
        type: 'expense',
        amount: 100,
        accountId: 1,
        frequency: 'monthly',
        nextRunAt: DateTime(2026, 1, 1),
      );
      final r = await run('stock_dca_plans');
      expect(r['planCount'], 0);
    });
  });

  // ==========================================================================
  group('stock_performance', () {
    test('總報酬 = 未實現 + 已實現 + 股利;USD 缺報價不亂算', () async {
      await seed();
      final r = await run('stock_performance');
      final twd = m(m(r['byCurrency'])['TWD']);
      expect(twd['unrealizedPnl'], 28691);
      expect(twd['realizedPnl'], 39342);
      expect(twd['dividends'], 2990);
      expect(twd['totalReturn'], 71023);
      expect(twd['securityCount'], 3);
      // 排名:2330 總報酬最高
      final ranking = ml(twd['ranking']);
      expect(ranking.first['symbol'], '2330');
      expect(ranking.first['totalReturn'], 27762 + 38419 + 2990);
      expect(ranking.last['symbol'], '2412');

      final usd = m(m(r['byCurrency'])['USD']);
      expect(usd['unpricedCount'], 1);
      expect(usd['unrealizedPnl'], 0);
      expect(usd['dividends'], 1.89);
      expect(usd['totalReturn'], 1.89);
      final aapl = ml(usd['ranking']).single;
      expect(aapl['quoteMissing'], isTrue);
      expect(aapl['unrealizedPnl'], isNull);
    });

    test('殖利率估算:近 12 個月股利 ÷ 成本、÷ 市值(只計仍持有的標的)', () async {
      await seed();
      final twd = m(m((await run('stock_performance'))['byCurrency'])['TWD']);
      final y = m(twd['dividendYield']);
      expect(y['trailing12MonthsDividends'], 2990);
      expect(y['yieldOnCostPercent'], 0.79); // 2990 / 378,538
      expect(y['yieldOnMarketValuePercent'], 0.73); // 2990 / 409,000
      expect(y['costBase'], 378538);
    });

    test('單一標的篩選', () async {
      await seed();
      final r = await run('stock_performance', {'symbol': '台積電'});
      final twd = m(m(r['byCurrency'])['TWD']);
      expect(twd['securityCount'], 1);
      expect(twd['totalReturn'], 27762 + 38419 + 2990);
    });

    test('無資料與找不到', () async {
      var r = await run('stock_performance');
      expect(r.containsKey('byCurrency'), isFalse);
      await seed();
      r = await run('stock_performance', {'account': '不存在'});
      expect(r.containsKey('byCurrency'), isFalse);
      expect(m(r['filters'])['warning'], contains('找不到名稱相近'));
    });

    test('ranking 超過 15 檔只列前 8 + 後 7', () async {
      for (var i = 0; i < 18; i++) {
        await trade(
            account: 2,
            type: 'opening',
            market: 'TW',
            symbol: '${3000 + i}',
            shares: 10,
            price: 10,
            date: DateTime(2026, 1, 1, 12));
        await quote('TW', '${3000 + i}', 10.0 + i,
            fetchedAt: DateTime(2026, 10, 3, 10));
      }
      final twd = m(m((await run('stock_performance'))['byCurrency'])['TWD']);
      expect(ml(twd['ranking']), hasLength(15));
      expect(twd['rankingTruncated'], isTrue);
      expect(twd['securityCount'], 18);
    });
  });

  // ==========================================================================
  group('stock_portfolio_analysis', () {
    test('集中度、分布、成本佔比、股利、observations(各幣別分開)', () async {
      await seed();
      final r = await run('stock_portfolio_analysis');
      expect(r['disclaimerRequired'], isTrue);
      expect(r['hasHoldings'], isTrue);
      final twd = m(m(r['byCurrency'])['TWD']);
      expect(twd['openPositions'], 2);
      expect(twd['marketValue'], 409000);
      final conc = m(twd['concentration']);
      expect(conc['topWeightPercent'], 95.4);
      expect(ml(conc['topPositions']).first['key'], 'TW:2330');
      final byKind = m(twd['byKind']);
      expect(m(byKind['stock'])['count'], 1);
      expect(m(byKind['etf'])['count'], 1);
      expect(m(byKind['etf'])['marketValue'], 19000);
      expect(ml(twd['byMarket']).single['market'], 'TW');
      expect(ml(twd['byAccount']).single['account'], '永豐證券');

      final costs = m(twd['costs']);
      expect(costs['buyAmount'], 630900);
      expect(costs['feeTotal'], 1317);
      expect(costs['taxTotal'], 879);
      expect(costs['feeAndTaxPercentOfBuyAmount'], 0.35);
      expect(m(twd['dividends'])['allTimeDividends'], 2990);
      expect(m(twd['dividends'])['yieldOnCostPercent'], 0.79);

      final obs = (twd['observations'] as List).cast<String>();
      expect(obs.any((o) => o.contains('單一標的') && o.contains('集中度偏高')),
          isTrue);
      // 交易成本只佔 0.35%,不該被標成偏高
      expect(obs.any((o) => o.contains('交易成本偏高')), isFalse);

      // USD 沒有報價:不納入占比,observations 要說明
      final usd = m(m(r['byCurrency'])['USD']);
      expect(usd['marketValue'], 0);
      expect(
          (usd['observations'] as List).cast<String>().any((o) => o.contains('沒有報價')),
          isTrue);
    });

    test('長期虧損 / 深度虧損標的', () async {
      await seed();
      // 2025-01-02 買 100@100,現價 50 → 約 -50%,持有 > 365 天
      await trade(
          account: 2,
          type: 'buy',
          market: 'TW',
          symbol: '2603',
          name: '長榮',
          shares: 100,
          price: 100,
          fee: 20,
          date: DateTime(2025, 1, 2, 12));
      await quote('TW', '2603', 50, fetchedAt: DateTime(2026, 10, 3, 10));
      final r = await run('stock_portfolio_analysis');
      final twd = m(m(r['byCurrency'])['TWD']);
      final long = ml(twd['longTermLosers']);
      expect(long.single['symbol'], '2603');
      expect(long.single['holdDays'], greaterThan(365));
      expect(long.single['unrealizedPnlPercent'], lessThan(-30));
      expect(ml(twd['deepLossPositions']).single['symbol'], '2603');
      final obs = (twd['observations'] as List).cast<String>();
      expect(obs.any((o) => o.contains('持有超過 365 天')), isTrue);
    });

    test('交易成本偏高會列入 observations', () async {
      // 買 1,000 元、手續費 20(2%)
      await trade(
          account: 2,
          type: 'buy',
          market: 'TW',
          symbol: '2884',
          shares: 100,
          price: 10,
          fee: 20,
          date: DateTime(2026, 5, 1, 12));
      await quote('TW', '2884', 10, fetchedAt: DateTime(2026, 10, 3, 10));
      final r = await run('stock_portfolio_analysis');
      final twd = m(m(r['byCurrency'])['TWD']);
      final obs = (twd['observations'] as List).cast<String>();
      expect(obs.any((o) => o.contains('交易成本偏高')), isTrue);
      // 只有一檔標的
      expect(obs.any((o) => o.contains('只有一檔標的')), isTrue);
    });

    test('無持股:hasHoldings=false 仍要求免責聲明', () async {
      final r = await run('stock_portfolio_analysis');
      expect(r['hasHoldings'], isFalse);
      expect(r['disclaimerRequired'], isTrue);
      expect(r.containsKey('byCurrency'), isFalse);
    });

    test('帳戶篩選', () async {
      await seed();
      final r = await run('stock_portfolio_analysis', {'account': '複委託'});
      expect(m(r['byCurrency']).keys, ['USD']);
    });
  });
}
