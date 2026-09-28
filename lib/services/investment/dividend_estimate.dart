import 'dart:math' as math;

import '../../models/investment_settings.dart';

/// 股利實收估算。Cloud `services/securities/dividends.estimate_dividend`、Web
/// `web-features/src/lib/investment.ts::estimateDividend` 是同一套規則,改一邊
/// 要改另外兩邊(三端對同一筆股利算出不同的實收會讓使用者困惑)。
///
/// - 股利總額 = 股數 × 每股股利(TWD/JPY/KRW 捨去到整數,其它四捨五入到分)
/// - 預扣稅 = 總額 × dividendWithholdingRate
/// - 二代健保 = 總額 ≥ nhiThreshold 時 總額 × nhiSupplementRate
/// - 手續費 = dividendFeeFixed + 總額 × dividendFeeRate(總額 0 時不收)
/// - 實收 = 總額 − 手續費 − 預扣稅 − 二代健保
/// - 配股 = 股數 × 每股配股數(台股捨去到整股)
class DividendEstimate {
  final double gross;
  final double fee;

  /// 預扣稅 + 二代健保。
  final double tax;
  final double net;
  final double stockShares;

  const DividendEstimate({
    required this.gross,
    required this.fee,
    required this.tax,
    required this.net,
    required this.stockShares,
  });
}

double _roundMoney(double value, String? currency) {
  if (InvestmentSettings.currencyDecimals(currency) == 0) {
    return (value + 1e-9).floorToDouble();
  }
  return (value * 100).roundToDouble() / 100;
}

DividendEstimate estimateDividend({
  required String market,
  required String? currency,
  required double shares,
  required double cashPerShare,
  double stockPerShare = 0,
  required InvestmentSettings settings,
}) {
  final r = settings.resolvedFor(market);
  final held = math.max(shares, 0.0);
  final gross = _roundMoney(held * math.max(cashPerShare, 0.0), currency);
  var fee = 0.0;
  var tax = 0.0;
  if (gross > 0) {
    final withholding =
        _roundMoney(gross * (r.dividendWithholdingRate ?? 0), currency);
    final nhiRate = r.nhiSupplementRate ?? 0;
    final nhi = nhiRate > 0 && gross >= (r.nhiThreshold ?? 0)
        ? _roundMoney(gross * nhiRate, currency)
        : 0.0;
    tax = withholding + nhi;
    fee = math.min(
      _roundMoney((r.dividendFeeFixed ?? 0) + gross * (r.dividendFeeRate ?? 0),
          currency),
      math.max(gross - tax, 0.0),
    );
  }
  final net = _roundMoney(math.max(gross - fee - tax, 0.0), currency);
  final rawStock = held * math.max(stockPerShare, 0.0);
  final upper = market.toUpperCase();
  final stockShares = upper == 'TW' || upper == 'TWO'
      ? ((rawStock * 1000).roundToDouble() / 1000).floorToDouble()
      : (rawStock * 1e6).roundToDouble() / 1e6;
  return DividendEstimate(
      gross: gross, fee: fee, tax: tax, net: net, stockShares: stockShares);
}
