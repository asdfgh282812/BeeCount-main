import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../../models/investment_settings.dart';
import '../data/recurring_rule_schedule.dart' as recurring_schedule;

/// 股票定期定額(`RecurringTransactions.kind == 'stock_dca'`)跟 BeeCount Cloud
/// 共用的生成規則。改這裡要同步改 Cloud
/// `src/services/recurring_materializer.py` 的同名常數/函式。

/// 補期上限:到期生成只讀得到「當下」報價,超過這個天數還沒生成的期數(起始日
/// 設在很久以前、規則停用後重新啟用、App 很久沒開)照補的話每一期都會用今天
/// 的價格買進,股數/成本全錯。超過上限的期數略過不買、只推進進度。
/// 對齊 Cloud `STOCK_DCA_MAX_CATCH_UP`。
const Duration kStockDcaMaxCatchUp = Duration(days: 7);

/// 某一期生成的(轉帳交易 syncId, StockTrade syncId)。
///
/// App 是「啟動時先生成、之後才 pull」,Cloud 則是 15 分鐘排程——兩邊都可能
/// 生成同一期。用「規則 syncId + 該期時間(秒級 epoch,無條件捨去)」推出固定
/// 的 uuid5(namespace = URL),兩邊得到同一組 syncId,sync 時只會互相覆蓋,
/// 不會變成兩筆。對齊 Cloud `stock_dca_occurrence_ids`(test_recurring_stock_dca.py
/// `test_stock_dca_occurrence_ids_are_stable` 有對照的固定值)。
({String txSyncId, String tradeSyncId}) stockDcaOccurrenceIds(
    String ruleSyncId, DateTime occurrence) {
  final seconds = occurrence.toUtc().millisecondsSinceEpoch ~/ 1000;
  final key = '$ruleSyncId:$seconds';
  const uuid = Uuid();
  return (
    txSyncId: uuid.v5(Namespace.url.value, 'beecount:stock_dca:tx:$key'),
    tradeSyncId: uuid.v5(Namespace.url.value, 'beecount:stock_dca:trade:$key'),
  );
}

/// 「到期才逐筆生成」的規則(transfer 自動扣繳 / stock_dca)真正的下一期:
/// 還沒生成過 = [nextRunAt],否則 = [generatedUntilAt] 之後的下一期(規則的
/// nextRunAt 在第一期之後就不再變動)。對齊 Cloud
/// `recurring_materializer.next_pending_occurrence`。
DateTime? nextPendingOccurrence({
  required DateTime nextRunAt,
  DateTime? generatedUntilAt,
  required String frequency,
  required int interval,
  Map<String, dynamic>? advancedRule,
}) {
  if (generatedUntilAt == null) return nextRunAt;
  final following = recurring_schedule.enumerateOccurrences(
    start: generatedUntilAt,
    end: null,
    frequency: frequency,
    interval: interval,
    advancedRule: advancedRule,
    maxCount: 2,
  );
  return following.length > 1 ? following[1] : null;
}

/// 股票定期定額「只買整數股」的市場(2026-09-30 使用者回報)。台股不論定期
/// 定額或盤中零股都要進證交所撮合,最小單位 1 股,券商沒辦法把 0.5 股放進
/// 集保戶頭:每期金額(含手續費)能買幾個整股就買幾股,零頭不扣款。美股等
/// 市場的券商(含複委託)自己吃下整股再切碎分配,允許碎股。對齊 Cloud
/// `trade_fees.STOCK_DCA_WHOLE_SHARE_MARKETS`、Web `STOCK_DCA_WHOLE_SHARE_MARKETS`。
const Set<String> kStockDcaWholeShareMarkets = {'TW', 'TWO'};

bool stockDcaWholeShares(String? market) =>
    kStockDcaWholeShareMarkets.contains((market ?? '').toUpperCase());

/// 定期定額一期的下單結果。[gross] = 成交價金(綁定轉帳的金額),
/// [total] = 交割帳戶實際扣款(價金 + 手續費)。
typedef StockDcaOrder = ({double shares, double gross, double fee});

extension StockDcaOrderTotal on StockDcaOrder {
  double get total => gross + fee;
}

/// 定期定額一期要買幾股;買不到任何股數回 null。
///
/// - 整數股市場([stockDcaWholeShares]):[amount] 是「含手續費」的扣款上限,
///   股數 = 使「成交價金 + 手續費 <= amount」的最大整數(券商算法:(投入金額
///   − 手續費) ÷ 成交價,無條件捨去),手續費依實際成交價金計。
/// - 其它市場(碎股):成交價金 = amount,手續費另計,股數 = amount ÷ 股價。
///
/// [feeSettings] 已經套好規則覆寫的費率/折扣/最低。對齊 Cloud
/// `trade_fees.stock_dca_order`,兩邊測試用同一組數字。
StockDcaOrder? stockDcaOrder({
  required double amount,
  required double price,
  required String market,
  required String? currency,
  required InvestmentSettings feeSettings,
}) {
  if (price <= 0) return null;
  final budget = InvestmentSettings.roundMoney(amount, currency);
  if (budget <= 0) return null;
  double feeOf(double gross) =>
      feeSettings.suggestFee(gross, market: market, currency: currency);

  if (!stockDcaWholeShares(market)) {
    return (shares: budget / price, gross: budget, fee: feeOf(budget));
  }

  bool fits(int n) {
    final gross = InvestmentSettings.gross(n.toDouble(), price, currency);
    return gross + feeOf(gross) <= budget + 1e-9;
  }

  // 起點用券商公式(以整筆預算估手續費,一定買得起),再往上試:實際成交
  // 價金較小、手續費可能也較小,多出來的錢說不定夠再買 1 股。
  var n = math.max(
      double.parse(((budget - feeOf(budget)) / price).toStringAsFixed(9))
          .floor(),
      0);
  while (fits(n + 1)) {
    n++;
  }
  while (n > 0 && !fits(n)) {
    n--;
  }
  if (n <= 0) return null;
  final gross = InvestmentSettings.gross(n.toDouble(), price, currency);
  return (shares: n.toDouble(), gross: gross, fee: feeOf(gross));
}
