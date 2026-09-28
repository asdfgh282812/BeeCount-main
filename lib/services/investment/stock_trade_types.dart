/// stock_trade 的交易類型字面量,對齊 BeeCount Cloud
/// `snapshot_mutator.STOCK_TRADE_TYPES`。
const String kStockTradeBuy = 'buy';
const String kStockTradeSell = 'sell';
const String kStockTradeOpening = 'opening';
const String kStockTradeCashDividend = 'cash_dividend';
const String kStockTradeStockDividend = 'stock_dividend';
const String kStockTradeReinvest = 'reinvest';

const Set<String> kStockTradeTypes = {
  kStockTradeBuy,
  kStockTradeSell,
  kStockTradeOpening,
  kStockTradeCashDividend,
  kStockTradeStockDividend,
  kStockTradeReinvest,
};

/// 會連帶建立轉帳交易(交割帳戶 ⇄ 投資理財帳戶)的類型。
const Set<String> kStockTradeCashTypes = {kStockTradeBuy, kStockTradeSell};

/// 會連帶建立 income 交易的類型(Phase 2 股利):cash_dividend 入「入帳帳戶」,
/// reinvest 入投資理財帳戶本身。對齊 Cloud `STOCK_TRADE_INCOME_TYPES`。
const Set<String> kStockTradeIncomeTypes = {
  kStockTradeCashDividend,
  kStockTradeReinvest
};

/// 股利 income 交易的分類名稱,跟 Cloud `card_rewards.DIVIDEND_CATEGORY_NAME`
/// 一致(兩邊用同名找同一個分類,不會各建一個)。
const String kDividendCategoryName = '股利';
