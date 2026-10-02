import '../../models/investment_settings.dart';
import '../db.dart';

/// 賣出股數超過持有股數。UI 應先用 [StockTradeRepository.getHeldShares] 擋,
/// repository 內部會再擋一次(同 BeeCount Cloud `_assert_can_sell`)。
class StockTradeOversellException implements Exception {
  final double requested;
  final double held;
  const StockTradeOversellException(this.requested, this.held);
  @override
  String toString() => 'cannot sell $requested shares, only $held held';
}

/// 帳戶不是投資理財(`investment`)帳戶,或交割帳戶不合法。
class StockTradeAccountException implements Exception {
  final String message;
  const StockTradeAccountException(this.message);
  @override
  String toString() => message;
}

/// 股票交易明細 + 報價快取(v63,docs/changes/2026-09-28-stock-holdings.md)。
///
/// ledger-scoped,對齊 BeeCount Cloud `stock_trade` sync entity。持股不落庫,
/// 由 [HoldingsCalculator] 從明細即時算。buy/sell 會同時建立一筆轉帳交易
/// (交割帳戶 ⇄ 投資理財帳戶),兩者由這裡的 create/update/delete 一起維護
/// ——不要繞過這些方法直接改 StockTrades 表或那筆轉帳。
abstract class StockTradeRepository {
  Stream<List<StockTrade>> watchAllStockTrades();
  Future<List<StockTrade>> getAllStockTrades();
  Future<List<StockTrade>> getStockTradesForAccount(int accountId);
  Future<StockTrade?> getStockTrade(int id);
  Future<StockTrade?> getStockTradeByTxSyncId(String txSyncId);

  /// 跨所有帳本彙總([accountId] 是 user-global 帳戶,同一個帳戶可能在多個
  /// 帳本都有交易)。[excludeTradeId] 給編輯賣出明細時排除自己。
  Future<double> getHeldShares({
    required int accountId,
    required String market,
    required String symbol,
    int? excludeTradeId,
  });

  /// 建立一筆明細;buy/sell 連帶建立轉帳交易([settlementAccountId] 必填,
  /// 交割帳戶幣別跟證券幣別不同時 [settlementAmount] 必填)。[txNote] 是轉帳
  /// 交易的備註(UI 傳在地化的預設文字),null 時用 [note] 或內建格式。
  /// [recurringRuleId] 供股票定期定額規則(`kind='stock_dca'`)到期生成用:
  /// 帶上規則 syncId,綁定的轉帳交易就會出現在該規則「查看已生成交易」清
  /// 單裡(同一般週期性收支規則的 occurrence 語意)。[syncId]/[txSyncId] 也
  /// 只給定期定額用:每一期用 `stockDcaOccurrenceIds` 推出來的固定 syncId,
  /// App 跟 Cloud 各自生成同一期時 sync 只會互相覆蓋,不會變兩筆。
  Future<int> createStockTrade({
    required int ledgerId,
    required int accountId,
    required String tradeType,
    required String market,
    required String symbol,
    String? securityName,
    required double shares,
    double? price,
    double fee = 0,
    double tax = 0,
    String? currency,
    required DateTime tradeDate,
    int? settlementAccountId,
    double? settlementAmount,
    String? note,
    String? txNote,
    String? recurringRuleId,
    String? syncId,
    String? txSyncId,
  });

  /// trade_type / 帳戶 / 標的建立後不可改(改了等同刪掉重建,同 Cloud)。
  /// 綁定的轉帳交易跟著重算。
  Future<void> updateStockTrade(
    int id, {
    required double shares,
    double? price,
    double fee = 0,
    double tax = 0,
    required DateTime tradeDate,
    String? securityName,
    String? note,
    int? settlementAccountId,
    double? settlementAmount,
    String? txNote,
  });

  /// 刪除明細並連帶刪除綁定的轉帳交易。
  Future<void> deleteStockTrade(int id);

  /// 投資理財帳戶費用設定(user-global,走 account 同步)。
  Future<void> updateAccountInvestmentSettings(int accountId, InvestmentSettings settings);

  // ---- 報價快取(不同步) ----
  Stream<List<SecurityQuote>> watchSecurityQuotes();
  Future<List<SecurityQuote>> getSecurityQuotes();
  Future<void> upsertSecurityQuotes(List<SecurityQuotesCompanion> rows);
}
