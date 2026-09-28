import '../../models/investment_settings.dart';
import 'stock_trade_types.dart';

/// stock_trade ⇄ 轉帳交易的金額換算。BeeCount Cloud
/// `snapshot_mutator.stock_trade_tx_fields`/`stock_trade_amount` 是同一套規則
/// (Web 買賣走那邊),改一邊要改另一邊——兩端規則不同的話,同一筆買進在
/// App 跟 Web 記出來的轉帳金額會不一樣。
class StockTradeTxFields {
  /// 轉帳本體金額(轉出帳戶幣別)。
  final double amount;

  /// 轉入帳戶幣別的金額,只有跨幣別才有值。
  final double? toAmount;

  /// 轉出端多扣的手續費(同幣別買進)。
  final double? feeAmount;

  /// 轉入端少收的手續費+稅(同幣別賣出)。
  final double? discountAmount;

  const StockTradeTxFields({
    required this.amount,
    this.toAmount,
    this.feeAmount,
    this.discountAmount,
  });
}

class StockTradeSettlementAmountRequired implements Exception {
  const StockTradeSettlementAmountRequired();
  @override
  String toString() =>
      'settlement amount is required when settlement account currency differs from security currency';
}

double _round(double v) => double.parse(v.toStringAsFixed(8));

/// 以證券幣別計的現金影響(正數)。成交價金依 [currency] 取整
/// ([InvestmentSettings.gross]:台幣無條件捨去到整數),所以 0050 買 50 股
/// @97.45、手續費 6 → 4,872 + 6 = 4,878(跟券商對帳單一致)。
double stockTradeAmount({
  required String tradeType,
  required double shares,
  required double price,
  required double fee,
  required double tax,
  String? currency,
}) {
  final gross = InvestmentSettings.gross(shares, price, currency);
  switch (tradeType) {
    case kStockTradeBuy:
    case kStockTradeOpening:
    case kStockTradeReinvest:
      return _round(gross + fee);
    case kStockTradeSell:
    case kStockTradeCashDividend:
      return _round(gross - fee - tax);
    default:
      return 0;
  }
}

/// cash_dividend / reinvest 綁定的 income 交易金額(入帳帳戶幣別)。
/// 同幣別 = [tradeAmount](cash_dividend 實收 / reinvest 成本);入帳帳戶幣別
/// 跟證券幣別不同時必須給 [settlementAmount](實際入帳金額)。同 Cloud
/// `snapshot_mutator._apply_dividend_tx`。
double stockDividendTxAmount({
  required double tradeAmount,
  required String? securityCurrency,
  required String? receivingCurrency,
  double? settlementAmount,
}) {
  final sameCurrency = securityCurrency == null ||
      securityCurrency.isEmpty ||
      receivingCurrency == null ||
      receivingCurrency.isEmpty ||
      securityCurrency.toUpperCase() == receivingCurrency.toUpperCase();
  // 交易金額是錢,四捨五入到分(再投入成本 = 股數×價格 可能有很多位小數)。
  if (sameCurrency) return (tradeAmount * 100).roundToDouble() / 100;
  if (settlementAmount == null || settlementAmount <= 0) {
    throw const StockTradeSettlementAmountRequired();
  }
  return _round(settlementAmount);
}

/// 同幣別:
///   buy  → amount = 股數×價格,feeAmount = 手續費(轉出端多扣)
///   sell → amount = 股數×價格,discountAmount = 手續費+交易稅(轉入端少收)
/// 跨幣別(例:台幣交割戶買美股):必須給 [settlementAmount](交割帳戶實際
/// 扣款/入帳金額,已含手續費/稅),手續費/稅併進證券端金額,不另外拆:
///   buy  → amount = settlementAmount,toAmount = 股數×價格+手續費
///   sell → amount = 股數×價格−手續費−稅,toAmount = settlementAmount
StockTradeTxFields stockTradeTxFields({
  required String tradeType,
  required double shares,
  required double price,
  required double fee,
  required double tax,
  required String? securityCurrency,
  required String? settlementCurrency,
  double? settlementAmount,
}) {
  final gross = InvestmentSettings.gross(shares, price, securityCurrency);
  final sameCurrency = securityCurrency == null ||
      securityCurrency.isEmpty ||
      settlementCurrency == null ||
      settlementCurrency.isEmpty ||
      securityCurrency.toUpperCase() == settlementCurrency.toUpperCase();
  if (tradeType == kStockTradeBuy) {
    if (sameCurrency) {
      return StockTradeTxFields(
          amount: gross, feeAmount: fee > 0 ? _round(fee) : null);
    }
    if (settlementAmount == null || settlementAmount <= 0) {
      throw const StockTradeSettlementAmountRequired();
    }
    return StockTradeTxFields(
        amount: _round(settlementAmount), toAmount: _round(gross + fee));
  }
  if (tradeType == kStockTradeSell) {
    if (sameCurrency) {
      return StockTradeTxFields(
        amount: gross,
        discountAmount: fee + tax > 0 ? _round(fee + tax) : null,
      );
    }
    if (settlementAmount == null || settlementAmount <= 0) {
      throw const StockTradeSettlementAmountRequired();
    }
    return StockTradeTxFields(
        amount: _round(gross - fee - tax), toAmount: _round(settlementAmount));
  }
  throw ArgumentError('trade type $tradeType has no linked transaction');
}
