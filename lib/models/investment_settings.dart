import 'dart:convert';
import 'dart:math' as math;

import '../services/investment/markets.dart';

/// 投資理財帳戶的使用者自訂費用設定(v63,wire `investmentSettings`)。
///
/// key 與型別對齊 BeeCount Cloud `snapshot_mutator.normalize_investment_settings`
/// ——Cloud 端會丟掉未知 key,這裡新增欄位時兩邊要一起加。全部欄位 nullable:
/// null = 沿用 [InvestmentSettings.defaultsFor] 的市場預設值,使用者只改自己在意
/// 的那幾個。
///
/// 手續費等建議值只是「預填」,每筆交易都能覆寫,不會寫死(使用者確認的需求)。
class InvestmentSettings {
  /// 預設市場(新增交易時預選)。
  final String? market;

  /// 手續費率(例:台股 0.001425)。
  final double? feeRate;

  /// 手續費折扣(例:6 折 = 0.6)。
  final double? feeDiscount;

  /// 最低手續費(以證券幣別計,例:台股 20 元)。
  final double? feeMin;

  /// 賣出交易稅率。台股是「普通股」的稅率(0.003);ETF / 債券 ETF 另外看
  /// [etfSellTaxRate] / [bondEtfSellTaxRate],見 [sellTaxRateFor]。
  final double? sellTaxRate;

  /// 台股 ETF 賣出證交稅率(法定 0.001)。
  final double? etfSellTaxRate;

  /// 台股債券 ETF 賣出證交稅率(目前停徵,0)。
  final double? bondEtfSellTaxRate;

  /// 未實現損益要不要先扣掉「現在賣掉要付的手續費 + 交易稅」(台灣券商 App
  /// 顯示的損益就是這樣算的)。null = 預設開啟。
  final bool? pnlAfterSellCosts;

  /// 股利手續費:固定金額(例:匯費 10 元)+ 比率,Phase 2 股利入帳時用。
  final double? dividendFeeFixed;
  final double? dividendFeeRate;

  /// 股利預扣稅率(例:美股對台灣居民 0.3)。
  final double? dividendWithholdingRate;

  /// 二代健保補充保費率與門檻(台股單筆股利 ≥ 門檻才扣)。
  final double? nhiSupplementRate;
  final double? nhiThreshold;

  /// 股利預設再投入。
  final bool? reinvestDividends;

  /// 交割帳戶 syncId(買賣時預選的扣款/入帳帳戶)。
  final String? settlementAccountId;

  const InvestmentSettings({
    this.market,
    this.feeRate,
    this.feeDiscount,
    this.feeMin,
    this.sellTaxRate,
    this.etfSellTaxRate,
    this.bondEtfSellTaxRate,
    this.pnlAfterSellCosts,
    this.dividendFeeFixed,
    this.dividendFeeRate,
    this.dividendWithholdingRate,
    this.nhiSupplementRate,
    this.nhiThreshold,
    this.reinvestDividends,
    this.settlementAccountId,
  });

  static const empty = InvestmentSettings();

  /// 各市場建議預設值(台股:券商公告牌告費率;其它市場以常見複委託費率為
  /// 起點)。使用者設定優先,見 [resolvedFor]。
  static InvestmentSettings defaultsFor(String? market) {
    switch ((market ?? '').toUpperCase()) {
      case 'TW':
      case 'TWO':
        return const InvestmentSettings(
          feeRate: 0.001425,
          feeDiscount: 1,
          feeMin: 20,
          sellTaxRate: 0.003,
          etfSellTaxRate: 0.001,
          bondEtfSellTaxRate: 0,
          dividendFeeFixed: 10,
          dividendFeeRate: 0,
          dividendWithholdingRate: 0,
          nhiSupplementRate: 0.0211,
          nhiThreshold: 20000,
        );
      case 'US':
        return const InvestmentSettings(
          feeRate: 0.0025,
          feeDiscount: 1,
          feeMin: 0,
          sellTaxRate: 0,
          dividendFeeFixed: 0,
          dividendFeeRate: 0,
          dividendWithholdingRate: 0.3,
          nhiSupplementRate: 0,
          nhiThreshold: 0,
        );
      default:
        return const InvestmentSettings(
          feeRate: 0,
          feeDiscount: 1,
          feeMin: 0,
          sellTaxRate: 0,
          dividendFeeFixed: 0,
          dividendFeeRate: 0,
          dividendWithholdingRate: 0,
          nhiSupplementRate: 0,
          nhiThreshold: 0,
        );
    }
  }

  /// 使用者設定蓋在市場預設值上。
  InvestmentSettings resolvedFor(String? market) {
    final d = defaultsFor(market ?? this.market);
    return InvestmentSettings(
      market: this.market ?? market,
      feeRate: feeRate ?? d.feeRate,
      feeDiscount: feeDiscount ?? d.feeDiscount,
      feeMin: feeMin ?? d.feeMin,
      sellTaxRate: sellTaxRate ?? d.sellTaxRate,
      etfSellTaxRate: etfSellTaxRate ?? d.etfSellTaxRate,
      bondEtfSellTaxRate: bondEtfSellTaxRate ?? d.bondEtfSellTaxRate,
      pnlAfterSellCosts: pnlAfterSellCosts ?? true,
      dividendFeeFixed: dividendFeeFixed ?? d.dividendFeeFixed,
      dividendFeeRate: dividendFeeRate ?? d.dividendFeeRate,
      dividendWithholdingRate:
          dividendWithholdingRate ?? d.dividendWithholdingRate,
      nhiSupplementRate: nhiSupplementRate ?? d.nhiSupplementRate,
      nhiThreshold: nhiThreshold ?? d.nhiThreshold,
      reinvestDividends: reinvestDividends ?? false,
      settlementAccountId: settlementAccountId,
    );
  }

  /// 台幣/日圓/韓圜這類沒有小數的幣別,成交價金/手續費/稅都無條件捨去到
  /// 整數(證交所與台灣券商的結算慣例);其它幣別四捨五入到分。
  static int currencyDecimals(String? currency) {
    switch ((currency ?? '').toUpperCase()) {
      case 'TWD':
      case 'JPY':
      case 'KRW':
        return 0;
      default:
        return 2;
    }
  }

  /// 依幣別取整。捨去前先四捨五入到小數 6 位,避免浮點殘渣
  /// (1000 × 600.1 = 600099.99999999… 直接捨去會少 1 元)。
  static double roundMoney(double value, String? currency) {
    final decimals = currencyDecimals(currency);
    final cleaned = double.parse(value.toStringAsFixed(6));
    if (decimals == 0) return cleaned.floorToDouble();
    final factor = math.pow(10, decimals).toDouble();
    // 放大後再清一次殘渣(30.015 × 100 = 3001.4999…)才四捨五入。
    return double.parse((cleaned * factor).toStringAsFixed(6)).roundToDouble() /
        factor;
  }

  /// 成交價金 = 股數 × 價格,依幣別取整(台幣無條件捨去:50 × 97.45 =
  /// 4,872.5 → 4,872)。同 Cloud `snapshot_mutator.stock_gross`。
  static double gross(double shares, double price, String? currency) =>
      roundMoney(shares * price, currency);

  /// 建議手續費 = max(成交金額 × 費率 × 折扣, 最低手續費)。成交金額 0 時回 0。
  double suggestFee(double gross, {String? market, String? currency}) {
    if (gross <= 0) return 0;
    final r = resolvedFor(market);
    final raw = gross * (r.feeRate ?? 0) * (r.feeDiscount ?? 1);
    return math.max(roundMoney(raw, currency), r.feeMin ?? 0);
  }

  /// 這檔標的的賣出交易稅率:台股依 [securityKindOf] 分普通股 / ETF / 債券
  /// ETF,其它市場一律 [sellTaxRate]。
  double sellTaxRateFor({String? market, String? symbol}) {
    final r = resolvedFor(market);
    final m = market ?? r.market;
    switch (securityKindOf(m, symbol)) {
      case SecurityKind.etf:
        return r.etfSellTaxRate ?? r.sellTaxRate ?? 0;
      case SecurityKind.bondEtf:
        return r.bondEtfSellTaxRate ?? 0;
      case SecurityKind.stock:
        return r.sellTaxRate ?? 0;
    }
  }

  /// 建議交易稅(只有賣出)= 成交金額 × 標的對應稅率,依幣別取整。
  double suggestSellTax(double gross,
      {String? market, String? symbol, String? currency}) {
    if (gross <= 0) return 0;
    return roundMoney(
        gross * sellTaxRateFor(market: market, symbol: symbol), currency);
  }

  /// 「現在全部賣掉」的預估手續費 / 交易稅 / 淨額(庫存的預估變現淨值)。
  SellCostEstimate estimateSell({
    required double shares,
    required double price,
    String? market,
    String? symbol,
    String? currency,
  }) {
    final g = gross(shares, price, currency);
    if (g <= 0) return const SellCostEstimate(gross: 0, fee: 0, tax: 0);
    return SellCostEstimate(
      gross: g,
      fee: suggestFee(g, market: market, currency: currency),
      tax:
          suggestSellTax(g, market: market, symbol: symbol, currency: currency),
    );
  }

  factory InvestmentSettings.fromJson(Map<String, dynamic> json) {
    double? f(String key) => (json[key] as num?)?.toDouble();
    return InvestmentSettings(
      market: (json['market'] as String?)?.toUpperCase(),
      feeRate: f('feeRate'),
      feeDiscount: f('feeDiscount'),
      feeMin: f('feeMin'),
      sellTaxRate: f('sellTaxRate'),
      etfSellTaxRate: f('etfSellTaxRate'),
      bondEtfSellTaxRate: f('bondEtfSellTaxRate'),
      pnlAfterSellCosts: json['pnlAfterSellCosts'] as bool?,
      dividendFeeFixed: f('dividendFeeFixed'),
      dividendFeeRate: f('dividendFeeRate'),
      dividendWithholdingRate: f('dividendWithholdingRate'),
      nhiSupplementRate: f('nhiSupplementRate'),
      nhiThreshold: f('nhiThreshold'),
      reinvestDividends: json['reinvestDividends'] as bool?,
      settlementAccountId: json['settlementAccountId'] as String?,
    );
  }

  /// 本地 `Accounts.investmentSettingsJson` → 物件;null/壞資料回 [empty]。
  static InvestmentSettings parse(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return InvestmentSettings.fromJson(decoded);
      }
    } catch (_) {}
    return empty;
  }

  /// 只輸出有值的 key(null = 沿用預設,不必佔位)。
  Map<String, dynamic> toJson() => {
        if (market != null) 'market': market,
        if (feeRate != null) 'feeRate': feeRate,
        if (feeDiscount != null) 'feeDiscount': feeDiscount,
        if (feeMin != null) 'feeMin': feeMin,
        if (sellTaxRate != null) 'sellTaxRate': sellTaxRate,
        if (etfSellTaxRate != null) 'etfSellTaxRate': etfSellTaxRate,
        if (bondEtfSellTaxRate != null)
          'bondEtfSellTaxRate': bondEtfSellTaxRate,
        if (pnlAfterSellCosts != null) 'pnlAfterSellCosts': pnlAfterSellCosts,
        if (dividendFeeFixed != null) 'dividendFeeFixed': dividendFeeFixed,
        if (dividendFeeRate != null) 'dividendFeeRate': dividendFeeRate,
        if (dividendWithholdingRate != null)
          'dividendWithholdingRate': dividendWithholdingRate,
        if (nhiSupplementRate != null) 'nhiSupplementRate': nhiSupplementRate,
        if (nhiThreshold != null) 'nhiThreshold': nhiThreshold,
        if (reinvestDividends != null) 'reinvestDividends': reinvestDividends,
        if (settlementAccountId != null)
          'settlementAccountId': settlementAccountId,
      };

  String? encode() {
    final json = toJson();
    return json.isEmpty ? null : jsonEncode(json);
  }

  bool get isEmpty => toJson().isEmpty;
}

/// [InvestmentSettings.estimateSell] 的結果(證券幣別)。
class SellCostEstimate {
  final double gross;
  final double fee;
  final double tax;

  const SellCostEstimate(
      {required this.gross, required this.fee, required this.tax});

  /// 預估變現淨值 = 毛市值 − 手續費 − 交易稅(不會小於 0)。
  double get net => math.max(gross - fee - tax, 0);
}
