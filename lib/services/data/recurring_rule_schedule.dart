/// 週期性收支 occurrence 枚举。純函式,無 DB 依賴,對齊 BeeCount Cloud
/// `services/recurring_schedule.py` 的演算法(建規則/視窗續產生都要「給一個
/// 時間範圍,一次列出範圍內全部發生時間」的批次版本,兩端用同一份演算法才
/// 能保證各自算出的日期序列一致)。
///
/// `advancedRule` 只支援兩種、不做過度泛化:
/// - `{"type": "weekly_days", "days": [0, 6]}`:每週指定星期幾各收一次。
///   **`days` 用 `Monday=0 … Sunday=6`(對齊 Python `datetime.weekday()`
///   慣例)——跟 Dart 原生 `DateTime.weekday`(`Monday=1..Sunday=7`)不同**,
///   本檔案內部一律用 [_weekdayZeroBased] 換算,呼叫端組 UI 選擇結果時也要
///   過這層轉換,不要直接塞 `DateTime.weekday`。
/// - `{"type": "monthly_day", "day": 10}`:每隔 [interval] 個月的第 [day]
///   天收一次(超過當月天數會夾斷到月底)。
library;

/// weekly_days 用逐日掃描實現;`end == null`(長期規則)時用這個硬上限兜
/// 底,避免規則組合導致掃描失控(實際會先被 [maxCount] 截住,這只是最後防
/// 線)。
const int kWeeklyScanHardStopDays = 366 * 20;

/// 視窗生成預設策略:沒設 `end`(長期規則)→ 建立當下先生成 12 個月或 200
/// 筆,取先到者;之後由續產生邏輯低頻補窗口。
const int kDefaultWindowMonths = 12;
const int kDefaultWindowMaxOccurrences = 200;

/// 即使設了 `end`,單次生成也設安全上限,避免
/// `frequency=daily, end=+50年` 這類極端規則一次炸出數萬筆本地寫入;超過上
/// 限的尾段改成視窗續產生。
const int kMaxOccurrencesPerGeneration = 2000;

/// 視窗續產生:`generatedUntilAt` 距今 < 此天數時觸發續產生。
const int kRefillThresholdDays = 30;
const int kRefillWindowMonths = 12;

/// [enumerateOccurrences] / [planInitialGeneration] 共用的合法頻率集合。
const Set<String> kRecurringFrequencies = {'daily', 'weekly', 'monthly', 'yearly'};

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// 用跟 [dt] 相同的 UTC/local 屬性重建日期(避免 `DateTime(...)` 悄悄把
/// UTC 輸入變成 local——這個函式庫的呼叫端可能傳 UTC 也可能傳 local,兩種
/// 都要原樣保留,不強制轉換)。
DateTime _withDate(DateTime dt, int year, int month, int day) {
  return dt.isUtc
      ? DateTime.utc(
          year, month, day, dt.hour, dt.minute, dt.second, dt.millisecond, dt.microsecond)
      : DateTime(
          year, month, day, dt.hour, dt.minute, dt.second, dt.millisecond, dt.microsecond);
}

/// 月/年推進,處理月末溢出(31 號 + 1 月 → 2 月最後一天,不進 3 月)。
DateTime addMonths(DateTime dt, int months) {
  final total = dt.month - 1 + months;
  final year = dt.year + total ~/ 12;
  final month = total % 12 + 1;
  final day = dt.day > _daysInMonth(year, month) ? _daysInMonth(year, month) : dt.day;
  return _withDate(dt, year, month, day);
}

/// 算下一次 `nextRunAt`:frequency 單位 * interval。月/年用日曆推進(借用
/// [addMonths] 處理月末溢出)。
DateTime nextRunFrom(DateTime now, String frequency, int interval) {
  final safeInterval = interval < 1 ? 1 : interval;
  switch (frequency) {
    case 'daily':
      return now.add(Duration(days: safeInterval));
    case 'weekly':
      return now.add(Duration(days: 7 * safeInterval));
    case 'yearly':
      return addMonths(now, safeInterval * 12);
    default: // monthly(默认兜底)
      return addMonths(now, safeInterval);
  }
}

/// Dart `DateTime.weekday`(Monday=1..Sunday=7)換算成 [advancedRule] 用的
/// `Monday=0..Sunday=6` 慣例。
int weekdayZeroBased(DateTime dt) => (dt.weekday - 1) % 7;

/// 枚舉 `[start, end]`(`end == null` 視為不設上限)範圍內的發生時間,最多
/// [maxCount] 筆。`start` 本身一定是第一筆結果(呼叫方保證 `start` 就是
/// 「下一個該發生的時間點」,不是「上一次已發生的時間點」)。
List<DateTime> enumerateOccurrences({
  required DateTime start,
  DateTime? end,
  required String frequency,
  required int interval,
  Map<String, dynamic>? advancedRule,
  required int maxCount,
}) {
  if (maxCount <= 0) return const [];
  if (end != null && start.isAfter(end)) return const [];
  if (advancedRule == null) {
    return _enumerateSimple(start, end, frequency, interval, maxCount);
  }
  final ruleType = advancedRule['type'];
  switch (ruleType) {
    case 'weekly_days':
      return _enumerateWeeklyDays(start, end, advancedRule, maxCount);
    case 'monthly_day':
      return _enumerateMonthlyDay(start, end, advancedRule, interval, maxCount);
    default:
      throw ArgumentError('unsupported advanced_rule type: $ruleType');
  }
}

/// 建規則(或視窗續產生)時,決定「這次要一口氣生成哪些 occurrence」。
///
/// - 有 `end`:枚舉 `[start, end]` 全部(受 [kMaxOccurrencesPerGeneration]
///   硬上限保護),`fullyGenerated=true` 代表確實枚舉到了 `end` 本身(沒被
///   硬上限截斷),規則可以標記 `enabled=false`;截斷時視窗續產生 loop 會
///   在下次 refill 補齊剩下的部分。
/// - 沒有 `end`(長期規則):只生成一個預設視窗([kDefaultWindowMonths] 個
///   月或 [kDefaultWindowMaxOccurrences] 筆,取先到者),`fullyGenerated`
///   恆為 `false`(長期規則永遠需要續產生)。
({List<DateTime> occurrences, DateTime generatedUntilAt, bool fullyGenerated})
    planInitialGeneration({
  required DateTime start,
  DateTime? end,
  required String frequency,
  required int interval,
  Map<String, dynamic>? advancedRule,
}) {
  if (end != null) {
    final occurrences = enumerateOccurrences(
      start: start,
      end: end,
      frequency: frequency,
      interval: interval,
      advancedRule: advancedRule,
      maxCount: kMaxOccurrencesPerGeneration,
    );
    final fullyGenerated = occurrences.length < kMaxOccurrencesPerGeneration;
    final generatedUntilAt = occurrences.isNotEmpty ? occurrences.last : start;
    return (
      occurrences: occurrences,
      generatedUntilAt: generatedUntilAt,
      fullyGenerated: fullyGenerated,
    );
  }

  final windowEnd = addMonths(start, kDefaultWindowMonths);
  final occurrences = enumerateOccurrences(
    start: start,
    end: windowEnd,
    frequency: frequency,
    interval: interval,
    advancedRule: advancedRule,
    maxCount: kDefaultWindowMaxOccurrences,
  );
  final generatedUntilAt = occurrences.isNotEmpty ? occurrences.last : start;
  return (occurrences: occurrences, generatedUntilAt: generatedUntilAt, fullyGenerated: false);
}

List<DateTime> _enumerateSimple(
  DateTime start,
  DateTime? end,
  String frequency,
  int interval,
  int maxCount,
) {
  final occurrences = <DateTime>[start];
  var current = start;
  while (occurrences.length < maxCount) {
    current = nextRunFrom(current, frequency, interval);
    if (end != null && current.isAfter(end)) break;
    occurrences.add(current);
  }
  return occurrences;
}

List<DateTime> _enumerateWeeklyDays(
  DateTime start,
  DateTime? end,
  Map<String, dynamic> advancedRule,
  int maxCount,
) {
  final rawDays = advancedRule['days'];
  if (rawDays is! List || rawDays.isEmpty) {
    throw ArgumentError("weekly_days rule requires non-empty 'days'");
  }
  final daysSet = rawDays.map((d) => d as int).toSet();
  if (daysSet.any((d) => d < 0 || d > 6)) {
    throw ArgumentError(
        "weekly_days 'days' must be within 0..6 (Monday=0 .. Sunday=6)");
  }

  final hardStop = start.add(const Duration(days: kWeeklyScanHardStopDays));
  final occurrences = <DateTime>[];
  var cursor = start;
  while (occurrences.length < maxCount && !cursor.isAfter(hardStop)) {
    if (end != null && cursor.isAfter(end)) break;
    if (daysSet.contains(weekdayZeroBased(cursor))) {
      occurrences.add(cursor);
    }
    cursor = cursor.add(const Duration(days: 1));
  }
  return occurrences;
}

DateTime _onMonthDay(DateTime dt, int day) {
  final clamped = day > _daysInMonth(dt.year, dt.month) ? _daysInMonth(dt.year, dt.month) : day;
  return _withDate(dt, dt.year, dt.month, clamped);
}

List<DateTime> _enumerateMonthlyDay(
  DateTime start,
  DateTime? end,
  Map<String, dynamic> advancedRule,
  int interval,
  int maxCount,
) {
  final day = advancedRule['day'];
  if (day is! int || day < 1 || day > 31) {
    throw ArgumentError("monthly_day rule requires 'day' in 1..31");
  }
  final safeInterval = interval < 1 ? 1 : interval;

  var first = _onMonthDay(start, day);
  if (first.isBefore(start)) {
    first = _onMonthDay(addMonths(first, safeInterval), day);
  }
  if (end != null && first.isAfter(end)) return const [];

  final occurrences = <DateTime>[first];
  var cursor = first;
  while (occurrences.length < maxCount) {
    cursor = _onMonthDay(addMonths(cursor, safeInterval), day);
    if (end != null && cursor.isAfter(end)) break;
    occurrences.add(cursor);
  }
  return occurrences;
}
