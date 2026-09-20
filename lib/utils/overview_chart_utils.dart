/// 資產管理頁「走勢」互動組合圖（長條：收入/支出 + 折線：淨資產）的純聚合邏輯。
///
/// 刻意把「怎麼把逐日/逐月/逐年原始資料分桶成統一的 [OverviewChartPoint] 序列」
/// 從 provider（負責 I/O：呼叫 repo）與 widget（負責畫圖/互動）中抽出來，讓分桶
/// 規則本身不依賴 Drift/Riverpod，可以直接單元測試（不需要假資料庫）。
library;

/// 統計粒度：按日／週／月／年切換，對應資產管理頁圖表右上角「按日 ⌄」按鈕。
enum OverviewGranularity { day, week, month, year }

/// 各粒度預設顯示的資料點數（見設計文件「資料層設計」表格）。
const kOverviewDayCount = 7;
const kOverviewWeekCount = 8;
const kOverviewMonthCount = 12;
const kOverviewYearCount = 5;

/// [OverviewComboChart] 消費的統一資料點：一個時間桶的收入/支出（長條）與
/// 淨資產（折線）。四種粒度的資料來源、聚合方式都不同，但最終都收斂成這個
/// 形狀，圖表元件因此不需要知道資料是怎麼來的。
typedef OverviewChartPoint = ({
  DateTime bucketStart,
  double income,
  double expense,
  double netWorth,
});

/// 下面幾個 typedef 只是給 repo 回傳的匿名 record 型別取個短名字,方便函式簽名
/// 閱讀,不代表這是這個檔案對外的核心型別(核心型別只有 [OverviewChartPoint])。
typedef OverviewDayTotal = ({DateTime day, double total});
typedef OverviewMonthTotal = ({DateTime month, double total});
typedef OverviewYearTotal = ({int year, double total});
typedef OverviewNetWorthDaily = ({
  DateTime date,
  double assets,
  double liabilities,
  double net
});

DateTime _atMidnight(DateTime d) => DateTime(d.year, d.month, d.day);

/// 給定日期所在週的起始日（0 點），依 [weekStartsOnMonday] 決定週一或週日起算。
/// DateTime.weekday：1=週一…7=週日。
DateTime _weekStart(DateTime date, bool weekStartsOnMonday) {
  final d = _atMidnight(date);
  final offset = weekStartsOnMonday ? d.weekday - 1 : d.weekday % 7;
  return d.subtract(Duration(days: offset));
}

List<DateTime> _dayBuckets(DateTime asOfDate, int count) => [
      for (int i = count - 1; i >= 0; i--)
        _atMidnight(asOfDate).subtract(Duration(days: i)),
    ];

List<DateTime> _weekBuckets(
    DateTime asOfDate, int count, bool weekStartsOnMonday) {
  final start = _weekStart(asOfDate, weekStartsOnMonday);
  return [
    for (int i = count - 1; i >= 0; i--) start.subtract(Duration(days: 7 * i)),
  ];
}

List<DateTime> _monthBuckets(DateTime asOfDate, int count) {
  final anchor = DateTime(asOfDate.year, asOfDate.month, 1);
  return [
    for (int i = count - 1; i >= 0; i--)
      DateTime(anchor.year, anchor.month - i, 1),
  ];
}

List<DateTime> _yearBuckets(DateTime asOfDate, int count) => [
      for (int i = count - 1; i >= 0; i--) DateTime(asOfDate.year - i, 1, 1),
    ];

/// 依粒度算出查詢視窗的起點（含），呼叫端（provider）用它組裝 repo 查詢範圍；
/// 終點固定是 [asOfDate]（含）。
DateTime overviewWindowStart(
  OverviewGranularity granularity,
  DateTime asOfDate, {
  bool weekStartsOnMonday = true,
}) {
  switch (granularity) {
    case OverviewGranularity.day:
      return _dayBuckets(asOfDate, kOverviewDayCount).first;
    case OverviewGranularity.week:
      return _weekBuckets(asOfDate, kOverviewWeekCount, weekStartsOnMonday)
          .first;
    case OverviewGranularity.month:
      return _monthBuckets(asOfDate, kOverviewMonthCount).first;
    case OverviewGranularity.year:
      return _yearBuckets(asOfDate, kOverviewYearCount).first;
  }
}

/// 逐日淨資產序列依 [keyOf] 分桶，同桶後到的值覆蓋前者 → 桶內「最後一天」的值
/// （做法沿用 net_worth_trend_utils.dart 的 downsampleMonthly，這裡泛化成任意
/// 分桶粒度）。入參須按日期升序 —— netWorthTrendSeriesProvider 回傳序列本就升序。
///
/// 「當前未結束的週期」（例如本週/本月/今年）不需要額外特判：呼叫端把查詢範圍的
/// 終點固定收斂在「今天」，所以最後一個桶天生就只包含到今天為止的資料，同桶
/// 覆蓋規則自然得到「今天」的值，而非等週期結束才有數字。
Map<K, double> _lastNetWorthByKey<K>(
  List<OverviewNetWorthDaily> netWorthDaily,
  K Function(DateTime) keyOf,
) {
  final map = <K, double>{};
  for (final e in netWorthDaily) {
    map[keyOf(e.date)] = e.net;
  }
  return map;
}

List<OverviewChartPoint> _composePoints(
  List<DateTime> buckets,
  Map<DateTime, double> incomeByBucket,
  Map<DateTime, double> expenseByBucket,
  Map<DateTime, double> netWorthByBucket,
) =>
    [
      for (final b in buckets)
        (
          bucketStart: b,
          income: incomeByBucket[b] ?? 0.0,
          expense: expenseByBucket[b] ?? 0.0,
          netWorth: netWorthByBucket[b] ?? 0.0,
        ),
    ];

/// 按日粒度：近 [kOverviewDayCount] 天，收入/支出/淨資產逐日一一對應，不需聚合。
List<OverviewChartPoint> buildDailyOverviewPoints({
  required List<OverviewDayTotal> incomeDaily,
  required List<OverviewDayTotal> expenseDaily,
  required List<OverviewNetWorthDaily> netWorthDaily,
  required DateTime asOfDate,
}) {
  final buckets = _dayBuckets(asOfDate, kOverviewDayCount);
  final incomeMap = {for (final e in incomeDaily) _atMidnight(e.day): e.total};
  final expenseMap = {
    for (final e in expenseDaily) _atMidnight(e.day): e.total
  };
  final netMap = _lastNetWorthByKey(netWorthDaily, _atMidnight);
  return _composePoints(buckets, incomeMap, expenseMap, netMap);
}

/// 按週粒度：近 [kOverviewWeekCount] 週。收入/支出把 [incomeDaily]/[expenseDaily]
/// 逐日加總進所屬週桶；淨資產取桶內最後一天的值。
List<OverviewChartPoint> buildWeeklyOverviewPoints({
  required List<OverviewDayTotal> incomeDaily,
  required List<OverviewDayTotal> expenseDaily,
  required List<OverviewNetWorthDaily> netWorthDaily,
  required DateTime asOfDate,
  required bool weekStartsOnMonday,
}) {
  final buckets =
      _weekBuckets(asOfDate, kOverviewWeekCount, weekStartsOnMonday);
  DateTime keyOf(DateTime d) => _weekStart(d, weekStartsOnMonday);

  final incomeMap = <DateTime, double>{};
  for (final e in incomeDaily) {
    final k = keyOf(e.day);
    incomeMap.update(k, (v) => v + e.total, ifAbsent: () => e.total);
  }
  final expenseMap = <DateTime, double>{};
  for (final e in expenseDaily) {
    final k = keyOf(e.day);
    expenseMap.update(k, (v) => v + e.total, ifAbsent: () => e.total);
  }
  final netMap = _lastNetWorthByKey(netWorthDaily, keyOf);
  return _composePoints(buckets, incomeMap, expenseMap, netMap);
}

/// 按月粒度：近 [kOverviewMonthCount] 個月。[incomeMonthly]/[expenseMonthly] 由
/// 呼叫端合併「今年 + 去年」兩次 totalsByMonth 查詢結果、過濾未來月份後傳入
/// （見 accountOverviewChartSeriesProvider），這裡只負責取最近 12 個月並跟淨資產
/// 對齊。
List<OverviewChartPoint> buildMonthlyOverviewPoints({
  required List<OverviewMonthTotal> incomeMonthly,
  required List<OverviewMonthTotal> expenseMonthly,
  required List<OverviewNetWorthDaily> netWorthDaily,
  required DateTime asOfDate,
}) {
  final buckets = _monthBuckets(asOfDate, kOverviewMonthCount);
  DateTime keyOf(DateTime d) => DateTime(d.year, d.month, 1);
  final incomeMap = {for (final e in incomeMonthly) keyOf(e.month): e.total};
  final expenseMap = {for (final e in expenseMonthly) keyOf(e.month): e.total};
  final netMap = _lastNetWorthByKey(netWorthDaily, keyOf);
  return _composePoints(buckets, incomeMap, expenseMap, netMap);
}

/// 按年粒度：近 [kOverviewYearCount] 年。
List<OverviewChartPoint> buildYearlyOverviewPoints({
  required List<OverviewYearTotal> incomeYearly,
  required List<OverviewYearTotal> expenseYearly,
  required List<OverviewNetWorthDaily> netWorthDaily,
  required DateTime asOfDate,
}) {
  final buckets = _yearBuckets(asOfDate, kOverviewYearCount);
  DateTime keyOf(DateTime d) => DateTime(d.year, 1, 1);
  final incomeMap = {
    for (final e in incomeYearly) DateTime(e.year, 1, 1): e.total
  };
  final expenseMap = {
    for (final e in expenseYearly) DateTime(e.year, 1, 1): e.total
  };
  final netMap = _lastNetWorthByKey(netWorthDaily, keyOf);
  return _composePoints(buckets, incomeMap, expenseMap, netMap);
}
