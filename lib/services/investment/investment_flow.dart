import 'markets.dart';
import 'stock_trade_types.dart';

/// 股票報表一致性(docs/changes/2026-10-03-stock-report-consistency.md):
/// 某段期間內「股票相關的現金流」彙總,純函式、不碰 DB / Riverpod。
///
/// 口徑(App 與 Web 要一致,見文件「Web 端應採用的口徑」):
/// - **買進總額** = 該期間 `buy` 明細的 `amount`(股數×價格 + 手續費,即實際從
///   交割帳戶流出的錢,證券幣別);**賣出總額** = `sell` 明細的 `amount`(股數×價格
///   − 手續費 − 證交稅,即實際流回交割帳戶的錢)。
/// - **淨投入** = 買進總額 − 賣出總額(正 = 這段期間淨流進投資帳戶、負 = 淨變現)。
///   它**不是支出也不是收入**,收支統計本來就不計轉帳,這裡只是補一個「錢去哪了」。
/// - **手續費與證交稅** = `buy`/`sell` 的 `fee + tax`。視為投資成本,**不計入支出**
///   (跟 Cloud `_stat_legs`、App 收支統計一致:轉帳連同它的手續費/折損一律不算收支,
///   只影響帳戶餘額)。
/// - **股利收入** = `cash_dividend` + `reinvest` 的 `amount`(實收/再投入成本)。它們各自
///   綁了一筆 `income`(分類「股利」),**已經算在收入裡**,這裡只是把它挑出來標示來源,
///   不可以再加到收入上(否則重複計算)。再投入股利不屬於「淨投入」(不是使用者從交割
///   帳戶掏出的錢,它是收入直接入投資帳戶),所以 [reinvest] 不進買進總額。
/// - `opening`(期初持股)、`stock_dividend`(配股)、`split`(分割)沒有現金流,
///   不計入任何項目。
///
/// 全部以**證券幣別**分開統計(不跨幣別加總);要折成單一幣別由呼叫端用
/// [InvestmentFlow.convertTo] 帶匯率換算,缺匯率的幣別會被剔除並列出。
class InvestmentFlowTrade {
  final String tradeType;
  final double amount;
  final double fee;
  final double tax;

  /// 證券幣別(大小寫皆可);空值時用 [market] 的預設幣別。
  final String? currency;
  final String market;
  final DateTime tradeDate;
  final int ledgerId;

  const InvestmentFlowTrade({
    required this.tradeType,
    required this.amount,
    this.fee = 0,
    this.tax = 0,
    this.currency,
    this.market = '',
    required this.tradeDate,
    required this.ledgerId,
  });

  String get currencyCode {
    final c = (currency ?? '').toUpperCase();
    if (c.isNotEmpty) return c;
    return (stockMarketByCode(market)?.currency ?? '').toUpperCase();
  }
}

/// 單一幣別的彙總。
class InvestmentFlowCurrency {
  double buy = 0;
  double sell = 0;

  /// buy/sell 的手續費 + 證交稅合計。
  double feesAndTax = 0;

  /// cash_dividend + reinvest 的 amount。
  double dividends = 0;

  int buyCount = 0;
  int sellCount = 0;

  double get netInvested => buy - sell;

  bool get isEmpty =>
      buyCount == 0 && sellCount == 0 && dividends.abs() < 1e-9;

  double _round(double v) => double.parse(v.toStringAsFixed(6));

  InvestmentFlowCurrency copyScaled(double rate) {
    final c = InvestmentFlowCurrency()
      ..buy = _round(buy * rate)
      ..sell = _round(sell * rate)
      ..feesAndTax = _round(feesAndTax * rate)
      ..dividends = _round(dividends * rate)
      ..buyCount = buyCount
      ..sellCount = sellCount;
    return c;
  }
}

/// [InvestmentFlow.convertTo] 的結果:單一幣別的彙總 + 缺匯率而被剔除的幣別。
class InvestmentFlowConverted {
  final String currency;
  final InvestmentFlowCurrency total;
  final List<String> missingCurrencies;

  const InvestmentFlowConverted({
    required this.currency,
    required this.total,
    required this.missingCurrencies,
  });
}

class InvestmentFlow {
  /// 幣別 → 彙總(只含有資料的幣別)。
  final Map<String, InvestmentFlowCurrency> byCurrency;

  const InvestmentFlow(this.byCurrency);

  static const empty = InvestmentFlow({});

  /// 期間內沒有任何買賣/股利(UI 此時不顯示補充資訊)。
  bool get isEmpty => byCurrency.values.every((c) => c.isEmpty);

  /// 有買賣(不含只有股利),決定要不要顯示「淨投入」那一行。
  bool get hasTrades =>
      byCurrency.values.any((c) => c.buyCount > 0 || c.sellCount > 0);

  bool get hasDividends =>
      byCurrency.values.any((c) => c.dividends.abs() > 1e-9);

  bool get hasFees => byCurrency.values.any((c) => c.feesAndTax > 1e-9);

  /// 彙總 [trades] 中 `tradeDate ∈ [start, end)` 的明細(半開區間,同統計報表)。
  /// [ledgerId] 非 null 時只算該帳本(統計/日曆是帳本維度;帳戶頁淨資產則傳 null
  /// 算全部帳本)。[start]/[end] 皆可省略 = 不限。
  static InvestmentFlow compute(
    Iterable<InvestmentFlowTrade> trades, {
    DateTime? start,
    DateTime? end,
    int? ledgerId,
  }) {
    final out = <String, InvestmentFlowCurrency>{};
    for (final t in trades) {
      if (ledgerId != null && t.ledgerId != ledgerId) continue;
      if (start != null && t.tradeDate.isBefore(start)) continue;
      if (end != null && !t.tradeDate.isBefore(end)) continue;
      final type = t.tradeType;
      final isCash = type == kStockTradeBuy || type == kStockTradeSell;
      final isDividend =
          type == kStockTradeCashDividend || type == kStockTradeReinvest;
      if (!isCash && !isDividend) continue;
      final bucket =
          out.putIfAbsent(t.currencyCode, () => InvestmentFlowCurrency());
      if (type == kStockTradeBuy) {
        bucket.buy += t.amount;
        bucket.buyCount += 1;
        bucket.feesAndTax += t.fee + t.tax;
      } else if (type == kStockTradeSell) {
        bucket.sell += t.amount;
        bucket.sellCount += 1;
        bucket.feesAndTax += t.fee + t.tax;
      } else {
        bucket.dividends += t.amount;
      }
    }
    return InvestmentFlow(out);
  }

  /// 折成 [target] 幣別。[rateOf] 回傳「1 單位該幣別 = 多少 target」,查不到回 null
  /// → 該幣別整個剔除並列入 [InvestmentFlowConverted.missingCurrencies](不按 1.0
  /// 裸加,同淨資產卡)。
  InvestmentFlowConverted convertTo(
      String target, double? Function(String currency) rateOf) {
    final total = InvestmentFlowCurrency();
    final missing = <String>[];
    for (final e in byCurrency.entries) {
      final rate = e.key.isEmpty
          ? null
          : (e.key == target.toUpperCase() ? 1.0 : rateOf(e.key));
      if (rate == null || rate <= 0) {
        if (!e.value.isEmpty) missing.add(e.key);
        continue;
      }
      final s = e.value.copyScaled(rate);
      total.buy += s.buy;
      total.sell += s.sell;
      total.feesAndTax += s.feesAndTax;
      total.dividends += s.dividends;
      total.buyCount += s.buyCount;
      total.sellCount += s.sellCount;
    }
    missing.sort();
    return InvestmentFlowConverted(
        currency: target.toUpperCase(), total: total, missingCurrencies: missing);
  }

  /// 用同一組「到使用者主幣別」的匯率換算到任意 [target] 幣別:
  /// 1 單位 c = rateToBase(c) / rateToBase(target) 單位 target。任一邊缺匯率回 null。
  static double? crossRate(String from, String target,
      double? Function(String currency) rateToBase) {
    if (from.toUpperCase() == target.toUpperCase()) return 1.0;
    final a = rateToBase(from);
    final b = rateToBase(target);
    if (a == null || b == null || a <= 0 || b <= 0) return null;
    return a / b;
  }
}

/// 各幣別彙總中符合 [tradeTypes] 的股票交易:給列表標籤用的小工具集合。
const Set<String> kStockTxLabelTypes = {
  kStockTradeBuy,
  kStockTradeSell,
  kStockTradeReinvest,
};
