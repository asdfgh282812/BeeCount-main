/// 紅利回饋規則的週期計算——信用卡帳戶頁「交易明細」tab 的帳單彙總卡片跟
/// 紅利回饋彙總/明細頁共用同一套邏輯,確保週期算出來的區間一致。
///
/// 2026-08-18 邊界改版:結帳日當天的歸屬從「算進下一期(inclusive-start)」
/// 改成「算進這一期(inclusive-end)」,對齊 BeeCount Cloud
/// `services/credit_card.py`(`most_recently_closed_cycle`/
/// `billing_cycle_containing`/`shift_cycle`)的既有語意——後者的 docstring
/// 明確寫「涵蓋『上次結帳日(不含)~這次結帳日(含)』的消費」。改版前 App
/// 端反過來用「結帳日當天算進下一期」,同一個結帳日在兩端被歸到相鄰的兩期
/// 帳單,使用者在對帳/延後入帳時兩端顯示的週期會對不上(見
/// `docs/changes/` 對應改動記錄)。
library;

DateTime _clampDay(int year, int month, int day) {
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > lastDay ? lastDay : day);
}

/// 帳單週期:回傳的 [start]/[end] 是**查詢用的 inclusive-both 邊界**
/// (`start` = 上次結帳日隔天,`end` = 這次結帳日本身),不是結帳日本身的
/// 標籤配對——顯示「結帳日 – 結帳日」這種 label 文字的呼叫端要自己用
/// `start.subtract(const Duration(days: 1))` 換算回結帳日,見
/// `account_detail_page.dart`/`account_reconciliation_page.dart` 的
/// `_formatYmd` 呼叫處。這樣所有既有「inclusive-both 區間查詢」的呼叫端
/// (`getAccountTransactions(startDate:, endDate:)` 等)不用跟著改。
///
/// [offset]=0 為「涵蓋今天、尚未結束」的本期(結帳日剛好是今天時,今天算進
/// 這一期,明天才開始算下一期),負數往前推一期一期算。沒設 [billingDay]
/// 時退化成「每月 1 號」起算的自然月。
({DateTime start, DateTime end}) billingCyclePeriod(
    int? billingDay, int offset) {
  final day = billingDay ?? 1;
  final now = DateTime.now();
  var anchorYear = now.year;
  var anchorMonth = now.month;
  // 找「今天所在、尚未結束」那一期的結帳日所在月份:今天已經過了這個月的
  // 結帳日,表示這期已經結束,本期(offset=0)的結帳日要看下個月;今天還沒
  // 到或剛好是結帳日,這個月的結帳日就是本期的結帳日(今天算進今天結的這
  // 期)。對齊 Cloud `billing_cycle_containing` 的 `cycle_end` 選法。
  if (now.day > day) {
    anchorMonth += 1;
    if (anchorMonth > 12) {
      anchorMonth = 1;
      anchorYear += 1;
    }
  }
  anchorMonth += offset;
  while (anchorMonth <= 0) {
    anchorMonth += 12;
    anchorYear -= 1;
  }
  while (anchorMonth > 12) {
    anchorMonth -= 12;
    anchorYear += 1;
  }
  final end = _clampDay(anchorYear, anchorMonth, day);
  var prevMonth = anchorMonth - 1;
  var prevYear = anchorYear;
  if (prevMonth == 0) {
    prevMonth = 12;
    prevYear -= 1;
  }
  // 用原始 billingDay(不是已夾斷過的 end.day)重新夾斷上個月的結帳日,
  // 避免月底夾斷陷阱(例如 billingDay=31 的 2 月被夾成 28,往前推一個月不能
  // 拿這個 28 去推 1 月,得用原始的 31 重新夾斷成 1/31)。
  final start =
      _clampDay(prevYear, prevMonth, day).add(const Duration(days: 1));
  return (start: start, end: end);
}

/// 把 [start, end] 依自然月切段——用於「規則以自然月計算上限,但檢視視窗是
/// 帳單週期(如 8/5~9/4,橫跨 8、9 兩個自然月)」的情境:上限跟著自然月重置,
/// 不能把橫跨兩個自然月的帳單週期當一整段拿去跟單一自然月上限比較,見帳戶頁
/// 紅利回饋卡片/[cardRewardAccountSummaryProvider] 的呼叫處。每段都 clamp 在
/// 原始 [start, end] 範圍內(頭尾月可能不是整月)。
List<({DateTime start, DateTime end})> splitPeriodByCalendarMonth(
    DateTime start, DateTime end) {
  final segments = <({DateTime start, DateTime end})>[];
  var segStart = DateTime(start.year, start.month, start.day);
  final rangeEnd = DateTime(end.year, end.month, end.day);
  while (!segStart.isAfter(rangeEnd)) {
    final monthEnd = DateTime(segStart.year, segStart.month + 1, 1)
        .subtract(const Duration(days: 1));
    final segEnd = monthEnd.isAfter(rangeEnd) ? rangeEnd : monthEnd;
    segments.add((start: segStart, end: segEnd));
    segStart = segEnd.add(const Duration(days: 1));
  }
  return segments;
}
