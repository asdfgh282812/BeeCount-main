import 'holdings_calculator.dart';
import 'markets.dart';
import 'stock_trade_types.dart';

/// 年度記帳報告的「股票年度摘要」純函式(不碰 DB / Riverpod)。
///
/// 口徑與 [RealizedPnlReport]、[InvestmentFlow] 一致:
/// - 年度 = 交易日期 `yyyy`(`HoldingTrade.tradeDateKey` 前 4 碼);
/// - 已實現損益**用全部歷史**依移動平均成本算([HoldingsCalculator.realizedEvents]),
///   再過濾出年度賣出事件——所以去年買、今年賣的成本會正確延續;
/// - 買進金額 = buy 的 `amount`(含手續費)、賣出金額 = sell 的 `amount`(淨額);
///   `reinvest`(股利再投入)算股利,不算買進;
/// - 各幣別分開統計,**不跨幣別加總**。
enum StockStyleTag {
  /// 積極交易者:買賣合計 ≥ 40 筆。
  activeTrader,

  /// 領息獵人:股利 ≥ |已實現損益| 且至少 2 筆股利。
  dividendHunter,

  /// 長期持有者:沒賣出只買進,或買進 ≥ 3 倍賣出。
  longTermHolder,

  /// 波段操作者:其餘有賣出者。
  swingTrader,

  /// 新手上路:其餘(買賣都很少)。
  beginner,
}

/// 單筆賣出的亮點(最賺 / 最賠)。
class StockSellHighlight {
  final String market;
  final String symbol;
  final String? name;

  /// yyyy-MM-dd
  final String date;
  final double pnl;

  /// 報酬率 = pnl / costBasis;成本為 0 時為 null。
  final double? returnRate;

  const StockSellHighlight({
    required this.market,
    required this.symbol,
    required this.name,
    required this.date,
    required this.pnl,
    required this.returnRate,
  });

  String get displayName => (name != null && name!.isNotEmpty) ? name! : symbol;
}

/// 「某檔標的 + 一個數值」(交易次數 / 股利金額)。
class StockSymbolStat {
  final String market;
  final String symbol;
  final String? name;
  final double value;

  const StockSymbolStat({
    required this.market,
    required this.symbol,
    required this.name,
    required this.value,
  });

  String get displayName => (name != null && name!.isNotEmpty) ? name! : symbol;
}

/// 單一幣別的年度摘要。
class StockCurrencyAnnual {
  final String currency;
  final int buyCount;
  final int sellCount;

  /// cash_dividend + reinvest 的筆數。
  final int dividendCount;

  /// 當年有交易(buy/sell/股利)的不同標的數。
  final int symbolCount;
  final double buyAmount;
  final double sellAmount;
  final double fees;
  final double taxes;
  final double dividends;
  final double realizedPnl;
  final int winCount;
  final int lossCount;
  final StockSellHighlight? bestSell;
  final StockSellHighlight? worstSell;

  /// 當年買賣次數最多的標的([StockSymbolStat.value] = 次數)。
  final StockSymbolStat? topSymbolByTrades;

  /// 領股利最多的標的([StockSymbolStat.value] = 金額)。
  final StockSymbolStat? topDividendSymbol;

  /// 長度 12,依賣出日期月份的已實現損益(index 0 = 1 月)。
  final List<double> monthlyRealizedPnl;

  /// 長度 12,依股利日期月份。
  final List<double> monthlyDividends;

  /// market 代碼 → 當年交易筆數(buy + sell + 股利)。
  final Map<String, int> marketBreakdown;
  final StockStyleTag styleTag;

  const StockCurrencyAnnual({
    required this.currency,
    required this.buyCount,
    required this.sellCount,
    required this.dividendCount,
    required this.symbolCount,
    required this.buyAmount,
    required this.sellAmount,
    required this.fees,
    required this.taxes,
    required this.dividends,
    required this.realizedPnl,
    required this.winCount,
    required this.lossCount,
    required this.bestSell,
    required this.worstSell,
    required this.topSymbolByTrades,
    required this.topDividendSymbol,
    required this.monthlyRealizedPnl,
    required this.monthlyDividends,
    required this.marketBreakdown,
    required this.styleTag,
  });

  /// 買進 + 賣出筆數(不含股利)。
  int get tradeCount => buyCount + sellCount;

  /// 有勝負的賣出筆數(pnl == 0 不計)。
  int get decidedCount => winCount + lossCount;

  /// 勝率 0~1;沒有勝負資料時為 0(UI 以 [decidedCount] > 0 判斷是否顯示)。
  double get winRate => decidedCount == 0 ? 0 : winCount / decidedCount;

  /// 有賣出事件(才有意義顯示已實現損益相關內容)。
  bool get hasSells => sellCount > 0;

  /// 活躍度(排序用):買進 + 賣出金額。
  double get activity => buyAmount + sellAmount;
}

/// 整年(所有幣別)的股票摘要。
class StockAnnualBundle {
  final int year;

  /// 依活躍度由大到小;只含當年有活動的幣別。
  final List<StockCurrencyAnnual> currencies;

  /// 這是使用者第一次買股票的那一年(之前沒有任何 buy / opening)。
  final bool firstBuyThisYear;

  const StockAnnualBundle({
    required this.year,
    required this.currencies,
    required this.firstBuyThisYear,
  });

  bool get isEmpty => currencies.isEmpty;

  StockCurrencyAnnual? get primary =>
      currencies.isEmpty ? null : currencies.first;

  int get totalTradeCount => currencies.fold(0, (a, c) => a + c.tradeCount);
  int get totalDividendCount =>
      currencies.fold(0, (a, c) => a + c.dividendCount);

  /// 任一幣別年度已實現損益為正。
  bool get hasRealizedProfit => currencies.any((c) => c.realizedPnl > 1e-9);

  /// 任一幣別勝率 ≥ 60% 且賣出 ≥ 5 筆。
  bool get hasHighWinRate =>
      currencies.any((c) => c.sellCount >= 5 && c.winRate >= 0.6);

  /// 領息達人:股利合計 ≥ 3 筆。
  bool get isDividendCollector => totalDividendCount >= 3;

  /// 積極交易者:買賣合計 ≥ 40 筆(跟 [StockStyleTag.activeTrader] 同門檻)。
  bool get isActiveTrader =>
      totalTradeCount >= StockAnnualReport.activeThreshold;
}

class StockAnnualReport {
  /// 積極交易者門檻(buy + sell 筆數)。
  static const int activeThreshold = 40;

  static int? _yearOf(String date) =>
      date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null;

  static int? _monthOf(String date) {
    if (date.length < 7) return null;
    final m = int.tryParse(date.substring(5, 7));
    return (m != null && m >= 1 && m <= 12) ? m : null;
  }

  /// 幣別解析:明細自帶幣別 → 市場預設幣別 → 帳戶幣別。
  static String _ccy(String? currency, String market, String? accountCcy) {
    final c = (currency ?? '').toUpperCase();
    if (c.isNotEmpty) return c;
    final m = stockMarketByCode(market)?.currency ?? '';
    if (m.isNotEmpty) return m;
    return (accountCcy ?? '').toUpperCase();
  }

  static bool _isDividend(String type) =>
      type == kStockTradeCashDividend || type == kStockTradeReinvest;

  /// 依規則決定投資風格(順序即優先序,取第一個符合者)。
  static StockStyleTag styleOf({
    required int buyCount,
    required int sellCount,
    required int dividendCount,
    required double dividends,
    required double realizedPnl,
  }) {
    if (buyCount + sellCount >= activeThreshold) {
      return StockStyleTag.activeTrader;
    }
    if (dividends > 0 && dividends >= realizedPnl.abs() && dividendCount >= 2) {
      return StockStyleTag.dividendHunter;
    }
    // 沒買進(只有股利/只有賣出)不算長期持有者。
    if (buyCount > 0 && (sellCount == 0 || buyCount >= 3 * sellCount)) {
      return StockStyleTag.longTermHolder;
    }
    // 與 Cloud `services/securities/annual.py::_style_tag` 同序:交易不到 5 筆算新手。
    if (buyCount + sellCount < 5) return StockStyleTag.beginner;
    return StockStyleTag.swingTrader;
  }

  /// 這一年是不是使用者第一次買股票:[year] 內有 buy,且之前沒有任何 buy/opening。
  static bool isFirstBuyYear(Iterable<HoldingTrade> trades, int year) {
    var buyInYear = false;
    for (final t in trades) {
      final y = _yearOf(t.tradeDateKey);
      if (y == null) continue;
      final isBuyLike =
          t.tradeType == kStockTradeBuy || t.tradeType == kStockTradeOpening;
      if (!isBuyLike) continue;
      if (y < year) return false;
      if (y == year && t.tradeType == kStockTradeBuy) buyInYear = true;
    }
    return buyInYear;
  }

  /// 建立 [year] 年的股票摘要。[accountCurrency]:accountKey → 帳戶幣別,
  /// 只在明細沒有幣別、市場也查不到預設幣別時當後備。
  static StockAnnualBundle build(
    Iterable<HoldingTrade> trades, {
    required int year,
    Map<String, String> accountCurrency = const {},
  }) {
    final all = trades.toList();
    final accum = <String, _Accum>{};
    _Accum of(String ccy) => accum.putIfAbsent(ccy, _Accum.new);

    for (final t in all) {
      if (_yearOf(t.tradeDateKey) != year) continue;
      final isBuy = t.tradeType == kStockTradeBuy;
      final isSell = t.tradeType == kStockTradeSell;
      final isDiv = _isDividend(t.tradeType);
      if (!isBuy && !isSell && !isDiv) continue;
      final ccy = _ccy(t.currency, t.market, accountCurrency[t.accountKey]);
      final a = of(ccy);
      final key = securityKey(t.market, t.symbol);
      a.markets.update(t.market.toUpperCase(), (v) => v + 1, ifAbsent: () => 1);
      a.symbols.add(key);
      if (t.securityName != null && t.securityName!.isNotEmpty) {
        a.names[key] = t.securityName!;
      }
      if (isBuy) {
        a.buyCount++;
        a.buyAmount += t.amount;
        a.fees += t.fee;
        a.taxes += t.tax;
        a.tradesBySymbol.update(key, (v) => v + 1, ifAbsent: () => 1);
      } else if (isSell) {
        a.sellCount++;
        a.sellAmount += t.amount;
        a.fees += t.fee;
        a.taxes += t.tax;
        a.tradesBySymbol.update(key, (v) => v + 1, ifAbsent: () => 1);
      } else {
        a.dividendCount++;
        a.dividends += t.amount;
        a.dividendsBySymbol
            .update(key, (v) => v + t.amount, ifAbsent: () => t.amount);
        final m = _monthOf(t.tradeDateKey);
        if (m != null) a.monthlyDividends[m - 1] += t.amount;
      }
    }

    // 已實現損益:一定要用全部歷史算成本,再過濾年度。
    for (final e in HoldingsCalculator.realizedEvents(all)) {
      if (_yearOf(e.date) != year) continue;
      final ccy = _ccy(e.currency, e.market, accountCurrency[e.accountKey]);
      final a = of(ccy);
      a.realizedPnl += e.pnl;
      if (e.pnl > 1e-9) {
        a.winCount++;
      } else if (e.pnl < -1e-9) {
        a.lossCount++;
      }
      final m = _monthOf(e.date);
      if (m != null) a.monthlyPnl[m - 1] += e.pnl;
      final hl = StockSellHighlight(
        market: e.market,
        symbol: e.symbol,
        name: e.securityName,
        date: e.date,
        pnl: e.pnl,
        returnRate: e.costBasis > 1e-9 ? e.pnl / e.costBasis : null,
      );
      if (a.best == null || hl.pnl > a.best!.pnl) a.best = hl;
      if (a.worst == null || hl.pnl < a.worst!.pnl) a.worst = hl;
    }

    final out = <StockCurrencyAnnual>[];
    for (final entry in accum.entries) {
      final a = entry.value;
      // 沒有任何活動(理論上不會發生)就略過。
      if (a.buyCount + a.sellCount + a.dividendCount == 0) continue;
      StockSymbolStat? statOf(String key, double value) {
        final parts = key.split(':');
        final market = parts.first;
        final symbol = parts.sublist(1).join(':');
        return StockSymbolStat(
            market: market, symbol: symbol, name: a.names[key], value: value);
      }

      // 取數值最大者;同值時取 key 字典序較小者(結果可重現)。
      String? topKey(Map<String, num> m) {
        String? best;
        num bestV = 0;
        final keys = m.keys.toList()..sort();
        for (final k in keys) {
          if (m[k]! > bestV) {
            best = k;
            bestV = m[k]!;
          }
        }
        return best;
      }

      final topTrade = topKey(a.tradesBySymbol);
      final topDiv = topKey(a.dividendsBySymbol);
      out.add(StockCurrencyAnnual(
        currency: entry.key,
        buyCount: a.buyCount,
        sellCount: a.sellCount,
        dividendCount: a.dividendCount,
        symbolCount: a.symbols.length,
        buyAmount: a.buyAmount,
        sellAmount: a.sellAmount,
        fees: a.fees,
        taxes: a.taxes,
        dividends: a.dividends,
        realizedPnl: a.realizedPnl,
        winCount: a.winCount,
        lossCount: a.lossCount,
        bestSell: a.best,
        worstSell: a.worst,
        topSymbolByTrades: topTrade == null
            ? null
            : statOf(topTrade, a.tradesBySymbol[topTrade]!.toDouble()),
        topDividendSymbol: topDiv == null
            ? null
            : statOf(topDiv, a.dividendsBySymbol[topDiv]!),
        monthlyRealizedPnl: List.unmodifiable(a.monthlyPnl),
        monthlyDividends: List.unmodifiable(a.monthlyDividends),
        marketBreakdown: Map.unmodifiable(a.markets),
        styleTag: styleOf(
          buyCount: a.buyCount,
          sellCount: a.sellCount,
          dividendCount: a.dividendCount,
          dividends: a.dividends,
          realizedPnl: a.realizedPnl,
        ),
      ));
    }
    out.sort((a, b) {
      final c = b.activity.compareTo(a.activity);
      if (c != 0) return c;
      final d = b.dividends.compareTo(a.dividends);
      return d != 0 ? d : a.currency.compareTo(b.currency);
    });
    return StockAnnualBundle(
      year: year,
      currencies: out,
      firstBuyThisYear: isFirstBuyYear(all, year),
    );
  }
}

class _Accum {
  int buyCount = 0;
  int sellCount = 0;
  int dividendCount = 0;
  double buyAmount = 0;
  double sellAmount = 0;
  double fees = 0;
  double taxes = 0;
  double dividends = 0;
  double realizedPnl = 0;
  int winCount = 0;
  int lossCount = 0;
  StockSellHighlight? best;
  StockSellHighlight? worst;
  final Set<String> symbols = {};
  final Map<String, String> names = {};
  final Map<String, int> tradesBySymbol = {};
  final Map<String, double> dividendsBySymbol = {};
  final Map<String, int> markets = {};
  final List<double> monthlyPnl = List.filled(12, 0);
  final List<double> monthlyDividends = List.filled(12, 0);
}
