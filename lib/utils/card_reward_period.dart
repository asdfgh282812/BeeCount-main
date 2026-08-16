/// 紅利回饋規則的週期計算——信用卡帳戶頁「交易明細」tab 的帳單彙總卡片跟
/// 紅利回饋彙總/明細頁共用同一套邏輯,確保週期算出來的區間一致。
library;

/// 帳單週期起訖:[offset]=0 為涵蓋今天的本期,負數往前推一期一期算。
/// 沒設 [billingDay] 時退化成「每月 1 號」起算的自然月。
({DateTime start, DateTime end}) billingCyclePeriod(
    int? billingDay, int offset) {
  final day = billingDay ?? 1;
  final now = DateTime.now();
  var anchorYear = now.year;
  var anchorMonth = now.month;
  if (now.day < day) {
    anchorMonth -= 1;
    if (anchorMonth == 0) {
      anchorMonth = 12;
      anchorYear -= 1;
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
  final start = DateTime(anchorYear, anchorMonth, day);
  final nextStart = DateTime(anchorYear, anchorMonth + 1, day);
  final end = nextStart.subtract(const Duration(days: 1));
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
