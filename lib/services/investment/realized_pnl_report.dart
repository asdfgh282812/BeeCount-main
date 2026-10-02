import 'holdings_calculator.dart';
import 'markets.dart';
import 'stock_trade_types.dart';

/// 已實現損益報表的篩選條件(null = 不篩)。
class RealizedFilter {
  final int? year;
  final String? accountKey;

  /// [securityKey] 格式(`TW:2330`)。
  final String? symbolKey;

  const RealizedFilter({this.year, this.accountKey, this.symbolKey});
}

/// 單一幣別的彙總(各幣別分開,不跨幣別加總)。
class RealizedCurrencyTotal {
  double pnl = 0;
  double dividends = 0;
}

/// 一檔標的(market + symbol,跨帳戶合併)在篩選範圍內的賣出事件與股利。
class RealizedSymbolGroup {
  final String market;
  final String symbol;
  final String? securityName;
  final String currency;

  /// 日期新到舊。
  final List<RealizedPnlEvent> events;
  final double pnl;
  final double proceeds;
  final double costBasis;
  final double dividends;

  const RealizedSymbolGroup({
    required this.market,
    required this.symbol,
    required this.securityName,
    required this.currency,
    required this.events,
    required this.pnl,
    required this.proceeds,
    required this.costBasis,
    required this.dividends,
  });

  String get key => securityKey(market, symbol);
}

class RealizedReport {
  /// 幣別 → 彙總。
  final Map<String, RealizedCurrencyTotal> totals;
  final List<RealizedSymbolGroup> groups;

  const RealizedReport({required this.totals, required this.groups});

  bool get isEmpty => groups.isEmpty;
}

/// 已實現損益報表的純函式(不碰 DB):從全部 stock_trade 明細即時算。
///
/// 成本一律用「全部明細」依移動平均成本算([HoldingsCalculator]),篩選只
/// 影響顯示的範圍——所以篩年度不會改變單筆賣出的成本。累計股利 =
/// cash_dividend + reinvest 的 amount(同持股頁 Holding.dividends 口徑),
/// 依該筆明細日期/帳戶/標的套用同一組篩選。
class RealizedPnlReport {
  static String _currencyOf(String? currency, String market) {
    final c = (currency ?? '').toUpperCase();
    if (c.isNotEmpty) return c;
    return stockMarketByCode(market)?.currency ?? '';
  }

  static int? _yearOf(String date) =>
      date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null;

  static bool _matches(RealizedFilter f, String? accountKey, String market,
      String symbol, String date) {
    if (f.year != null && _yearOf(date) != f.year) return false;
    if (f.accountKey != null && accountKey != f.accountKey) return false;
    if (f.symbolKey != null && securityKey(market, symbol) != f.symbolKey) {
      return false;
    }
    return true;
  }

  /// 有賣出或股利紀錄的年度(新到舊),給年度篩選用。
  static List<int> availableYears(Iterable<HoldingTrade> trades) {
    final years = <int>{};
    for (final t in trades) {
      if (t.tradeType == kStockTradeSell ||
          t.tradeType == kStockTradeCashDividend ||
          t.tradeType == kStockTradeReinvest) {
        final y = _yearOf(t.tradeDateKey);
        if (y != null) years.add(y);
      }
    }
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  static RealizedReport build(
    Iterable<HoldingTrade> trades, {
    RealizedFilter filter = const RealizedFilter(),
  }) {
    final all = trades.toList();
    final events = HoldingsCalculator.realizedEvents(all);

    final groupEvents = <String, List<RealizedPnlEvent>>{};
    final groupDividends = <String, double>{};
    final groupNames = <String, String?>{};
    final groupCurrency = <String, String>{};
    final totals = <String, RealizedCurrencyTotal>{};

    for (final e in events) {
      if (!_matches(filter, e.accountKey, e.market, e.symbol, e.date)) continue;
      final key = securityKey(e.market, e.symbol);
      final ccy = _currencyOf(e.currency, e.market);
      groupEvents.putIfAbsent(key, () => []).add(e);
      groupCurrency[key] = ccy;
      if (e.securityName != null && e.securityName!.isNotEmpty) {
        groupNames[key] = e.securityName;
      }
      totals.putIfAbsent(ccy, RealizedCurrencyTotal.new).pnl += e.pnl;
    }

    for (final t in all) {
      if (t.tradeType != kStockTradeCashDividend &&
          t.tradeType != kStockTradeReinvest) {
        continue;
      }
      if (!_matches(
          filter, t.accountKey, t.market, t.symbol, t.tradeDateKey)) {
        continue;
      }
      final key = securityKey(t.market, t.symbol);
      final ccy = _currencyOf(t.currency, t.market);
      groupDividends.update(key, (v) => v + t.amount, ifAbsent: () => t.amount);
      groupCurrency.putIfAbsent(key, () => ccy);
      if (t.securityName != null && t.securityName!.isNotEmpty) {
        groupNames.putIfAbsent(key, () => t.securityName);
      }
      totals.putIfAbsent(ccy, RealizedCurrencyTotal.new).dividends += t.amount;
    }

    final keys = {...groupEvents.keys, ...groupDividends.keys};
    final groups = <RealizedSymbolGroup>[];
    for (final key in keys) {
      final evs = (groupEvents[key] ?? const <RealizedPnlEvent>[]).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      final sample = key.split(':');
      final market = sample.first;
      final symbol = sample.sublist(1).join(':');
      groups.add(RealizedSymbolGroup(
        market: market,
        symbol: symbol,
        securityName: groupNames[key],
        currency: groupCurrency[key] ?? '',
        events: evs,
        pnl: evs.fold<double>(0, (a, e) => a + e.pnl),
        proceeds: evs.fold<double>(0, (a, e) => a + e.proceeds),
        costBasis: evs.fold<double>(0, (a, e) => a + e.costBasis),
        dividends: groupDividends[key] ?? 0,
      ));
    }
    // 最近有賣出/股利的標的排前面;沒有事件的(只有股利)排在後面。
    groups.sort((a, b) {
      final ad = a.events.isEmpty ? '' : a.events.first.date;
      final bd = b.events.isEmpty ? '' : b.events.first.date;
      final c = bd.compareTo(ad);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
    return RealizedReport(totals: totals, groups: groups);
  }
}
