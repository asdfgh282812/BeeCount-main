/// 股票市場代碼。對齊 BeeCount Cloud `src/services/securities/markets.py`
/// (那邊另外有時區/交易時段,App 用不到)——代碼一旦寫進使用者的
/// stock_trade 就不能改名,新增市場要兩邊一起加。
class StockMarket {
  final String code;
  final String currency;

  /// 台股代號是純數字,輸入時不必轉大寫/檢查英文;其它市場代號會轉大寫。
  final bool numericSymbols;

  const StockMarket(this.code, this.currency, {this.numericSymbols = false});
}

const List<StockMarket> kStockMarkets = [
  StockMarket('TW', 'TWD', numericSymbols: true),
  StockMarket('TWO', 'TWD', numericSymbols: true),
  StockMarket('US', 'USD'),
  StockMarket('HK', 'HKD', numericSymbols: true),
  StockMarket('JP', 'JPY', numericSymbols: true),
  StockMarket('SS', 'CNY', numericSymbols: true),
  StockMarket('SZ', 'CNY', numericSymbols: true),
  StockMarket('KS', 'KRW', numericSymbols: true),
  StockMarket('KQ', 'KRW', numericSymbols: true),
  StockMarket('LSE', 'GBP'),
];

StockMarket? stockMarketByCode(String? code) {
  if (code == null) return null;
  final upper = code.toUpperCase();
  for (final m in kStockMarkets) {
    if (m.code == upper) return m;
  }
  return null;
}

/// 報價/持股的查詢鍵,跟 Cloud `/read/securities/quotes?symbols=` 的格式一致。
String securityKey(String market, String symbol) =>
    '${market.toUpperCase()}:${symbol.toUpperCase()}';

/// 標的類型,決定台股賣出證交稅率(普通股 0.3%、ETF 0.1%、債券 ETF 免徵)。
///
/// 只看代號,不必查資料庫,App / Cloud / Web 三端用同一條規則
/// (Cloud `services/securities/trade_fees.security_kind`、Web
/// `lib/investment.ts::securityKind`):台股(TW/TWO)代號 `00` 開頭是 ETF
/// (0050、00878、00631L…),其中結尾是 `B` 的是債券 ETF(00679B)。其它市場
/// 沒有依類型分稅率,一律回 [SecurityKind.stock]。
enum SecurityKind { stock, etf, bondEtf }

final RegExp _twEtfSymbol = RegExp(r'^00\d{2,4}[A-Z]?$');

SecurityKind securityKindOf(String? market, String? symbol) {
  final m = (market ?? '').toUpperCase();
  if (m != 'TW' && m != 'TWO') return SecurityKind.stock;
  final s = (symbol ?? '').trim().toUpperCase();
  if (!_twEtfSymbol.hasMatch(s)) return SecurityKind.stock;
  return s.endsWith('B') ? SecurityKind.bondEtf : SecurityKind.etf;
}
