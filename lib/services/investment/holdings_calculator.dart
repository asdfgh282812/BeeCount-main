import 'stock_trade_types.dart';

/// 由 stock_trade 明細即時彙總持股(移動平均成本法,台灣券商慣例)。
///
/// 純函式、不碰 DB/Riverpod。BeeCount Cloud `src/services/securities/
/// holdings.py` 是同一套算法,兩邊共用 test/fixtures/stock_holdings_vectors.json
/// 測試向量——兩邊算出不同數字時 App 跟 Web 會顯示不同的平均成本/損益,改
/// 算法時兩邊一起改、一起更新向量。
///
/// 規則:
/// - 排序:tradeDate(取日期)升冪 → 同一天依類型(opening, buy, reinvest,
///   stock_dividend, cash_dividend, sell)→ syncId。
/// - opening/buy:股數 += s,成本 += amount(amount ≤ 0 時退回 s×price+fee)。
/// - reinvest:股數 += s,成本 += amount,同時計入累計股利。
/// - stock_dividend(配股):股數 += s,成本不變。
/// - cash_dividend:只計入累計股利。
/// - sell:依賣出當下平均成本扣除成本,已實現損益 += amount − 扣除成本;
///   賣超時只扣掉持有的部分,股數歸零。
class HoldingTrade {
  final String syncId;
  final String? accountKey;
  final String market;
  final String symbol;
  final String tradeType;
  final double shares;
  final double? price;
  final double fee;
  final double tax;
  final double amount;

  /// ISO 日期字串或 DateTime 皆可,只取前 10 碼(YYYY-MM-DD)排序。
  final String tradeDateKey;
  final String? securityName;
  final String? currency;

  const HoldingTrade({
    required this.syncId,
    required this.accountKey,
    required this.market,
    required this.symbol,
    required this.tradeType,
    required this.shares,
    required this.price,
    required this.fee,
    required this.tax,
    required this.amount,
    required this.tradeDateKey,
    this.securityName,
    this.currency,
  });

  static String dateKey(DateTime d) {
    // 用 UTC 日期,跟 Cloud 端 `isoformat()[:10]`(存的是 UTC)一致。
    final u = d.toUtc();
    return '${u.year.toString().padLeft(4, '0')}-'
        '${u.month.toString().padLeft(2, '0')}-'
        '${u.day.toString().padLeft(2, '0')}';
  }

  /// wire/snapshot camelCase map → HoldingTrade(測試向量用)。
  factory HoldingTrade.fromWire(Map<String, dynamic> json) {
    double f(String k) => (json[k] as num?)?.toDouble() ?? 0.0;
    final rawDate = json['tradeDate'];
    final dateKey = rawDate == null
        ? ''
        : (rawDate is DateTime
            ? HoldingTrade.dateKey(rawDate)
            : rawDate.toString().substring(0, 10));
    return HoldingTrade(
      syncId: (json['syncId'] as String?) ?? '',
      accountKey: json['accountId'] as String?,
      market: ((json['market'] as String?) ?? '').toUpperCase(),
      symbol: ((json['symbol'] as String?) ?? '').toUpperCase(),
      tradeType: (json['tradeType'] as String?) ?? kStockTradeBuy,
      shares: f('shares'),
      price: (json['price'] as num?)?.toDouble(),
      fee: f('fee'),
      tax: f('tax'),
      amount: f('amount'),
      tradeDateKey: dateKey,
      securityName: json['securityName'] as String?,
      currency: json['currency'] as String?,
    );
  }
}

class Holding {
  final String? accountKey;
  final String market;
  final String symbol;
  String? securityName;
  String? currency;
  double shares = 0;
  double totalCost = 0;
  double realizedPnl = 0;
  double dividends = 0;
  int tradeCount = 0;
  String? firstTradeDate;
  String? lastTradeDate;

  Holding(
      {required this.accountKey, required this.market, required this.symbol});

  double get avgCost =>
      shares > HoldingsCalculator.eps ? totalCost / shares : 0;

  bool get isOpen => shares > HoldingsCalculator.eps;
}

class HoldingsCalculator {
  static const double eps = 1e-9;

  static const Map<String, int> _typeOrder = {
    kStockTradeOpening: 0,
    kStockTradeBuy: 1,
    kStockTradeReinvest: 2,
    kStockTradeStockDividend: 3,
    kStockTradeCashDividend: 4,
    kStockTradeSell: 5,
  };

  static List<HoldingTrade> sortTrades(Iterable<HoldingTrade> trades) {
    final list = trades.toList();
    list.sort((a, b) {
      final d = a.tradeDateKey.compareTo(b.tradeDateKey);
      if (d != 0) return d;
      final t = (_typeOrder[a.tradeType] ?? 9)
          .compareTo(_typeOrder[b.tradeType] ?? 9);
      if (t != 0) return t;
      return a.syncId.compareTo(b.syncId);
    });
    return list;
  }

  /// 回傳每個 (account, market, symbol) 的持股,依 (account, market, symbol)
  /// 排序。`includeClosed=false` 時濾掉股數為 0 的部位。
  static List<Holding> compute(Iterable<HoldingTrade> trades,
      {bool includeClosed = false}) {
    final book = <String, Holding>{};
    for (final t in sortTrades(trades)) {
      final key = '${t.accountKey ?? ''}\u0000${t.market}\u0000${t.symbol}';
      final h = book.putIfAbsent(
        key,
        () => Holding(
            accountKey: t.accountKey, market: t.market, symbol: t.symbol),
      );
      if (t.securityName != null && t.securityName!.isNotEmpty) {
        h.securityName = t.securityName;
      }
      if (t.currency != null && t.currency!.isNotEmpty) {
        h.currency = t.currency!.toUpperCase();
      }
      h.tradeCount += 1;
      if (t.tradeDateKey.isNotEmpty) {
        h.firstTradeDate ??= t.tradeDateKey;
        h.lastTradeDate = t.tradeDateKey;
      }
      final s = t.shares < 0 ? 0.0 : t.shares;
      switch (t.tradeType) {
        case kStockTradeOpening:
        case kStockTradeBuy:
          final cost = t.amount > 0 ? t.amount : s * (t.price ?? 0) + t.fee;
          h.shares += s;
          h.totalCost += cost;
          break;
        case kStockTradeReinvest:
          h.shares += s;
          h.totalCost += t.amount;
          h.dividends += t.amount;
          break;
        case kStockTradeStockDividend:
          h.shares += s;
          break;
        case kStockTradeCashDividend:
          h.dividends += t.amount;
          break;
        case kStockTradeSell:
          final sold = s < h.shares ? s : h.shares;
          final costOut = h.avgCost * sold;
          h.realizedPnl += t.amount - costOut;
          h.shares -= sold;
          h.totalCost -= costOut;
          if (h.shares <= eps) {
            h.shares = 0;
            h.totalCost = 0;
          }
          break;
      }
    }
    final out = book.values.where((h) => includeClosed || h.isOpen).toList();
    out.sort((a, b) {
      final c = (a.accountKey ?? '').compareTo(b.accountKey ?? '');
      if (c != 0) return c;
      final m = a.market.compareTo(b.market);
      if (m != 0) return m;
      return a.symbol.compareTo(b.symbol);
    });
    return out;
  }

  static double heldShares(
    Iterable<HoldingTrade> trades, {
    required String? accountKey,
    required String market,
    required String symbol,
  }) {
    for (final h in compute(trades, includeClosed: true)) {
      if (h.accountKey == accountKey &&
          h.market == market.toUpperCase() &&
          h.symbol == symbol.toUpperCase()) {
        return h.shares;
      }
    }
    return 0;
  }
}
