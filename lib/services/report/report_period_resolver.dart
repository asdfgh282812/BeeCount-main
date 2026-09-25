/// 把 [ReportPeriod] 在某個 offset / 今天 / 帳本起始日下解析成實際區間。
///
/// 純函式,不依賴 Riverpod/Drift,方便單元測試。日期一律用日曆運算
/// (`DateTime(y, m, d + n)`)而非 `Duration`,避免 DST 時區加減 86400 秒落到
/// 前一天 23:00(同 `month_range.dart::periodRangeText` 的註解)。
library;

import '../../models/report/report_period.dart';
import '../../utils/month_range.dart';

DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

/// [date] 所在週的第一天(0 點)。
DateTime reportWeekStart(DateTime date, bool weekStartsOnMonday) {
  final offset = weekStartsOnMonday ? date.weekday - 1 : date.weekday % 7;
  return DateTime(date.year, date.month, date.day - offset);
}

/// 月份索引(year*12 + month-1),方便做 span 對齊。
int _monthIndex(DateTime label) => label.year * 12 + label.month - 1;

DateTime _labelFromIndex(int idx) {
  final y = idx >= 0 ? idx ~/ 12 : -((-idx - 1) ~/ 12) - 1;
  return DateTime(y, idx - y * 12 + 1, 1);
}

int _floorDiv(int a, int b) => (a / b).floor();

ReportGranularity _granularityForSpan(DateTime start, DateTime end) {
  final days = DateTime.utc(end.year, end.month, end.day)
      .difference(DateTime.utc(start.year, start.month, start.day))
      .inDays;
  if (days <= 45) return ReportGranularity.day;
  if (days <= 730) return ReportGranularity.month;
  return ReportGranularity.year;
}

ResolvedPeriod resolveReportPeriod(
  ReportPeriod period, {
  int offset = 0,
  DateTime? now,
  int monthStartDay = 1,
  bool weekStartsOnMonday = true,
  bool includeFuture = false,
}) {
  final today = _midnight(now ?? DateTime.now());
  final tomorrow = DateTime(today.year, today.month, today.day + 1);

  switch (period) {
    case RecurringPeriod(:final unit, :final span):
      final s = span < 1 ? 1 : span;
      late DateTime start;
      late DateTime end;
      late ReportGranularity granularity;
      switch (unit) {
        case ReportPeriodUnit.day:
          start = DateTime(today.year, today.month, today.day + s * offset);
          end = DateTime(start.year, start.month, start.day + s);
          granularity = ReportGranularity.day;
        case ReportPeriodUnit.week:
          final ws = reportWeekStart(today, weekStartsOnMonday);
          start = DateTime(ws.year, ws.month, ws.day + 7 * s * offset);
          end = DateTime(start.year, start.month, start.day + 7 * s);
          granularity = ReportGranularity.day;
        case ReportPeriodUnit.month:
          final nowIdx = _monthIndex(labelForDate(today, monthStartDay));
          // span>1 時對齊到 span 的整數倍(季從 1/4/7/10 月起、半年從 1/7 月起)
          final blockStart = _floorDiv(nowIdx, s) * s + offset * s;
          final a = _labelFromIndex(blockStart);
          final b = _labelFromIndex(blockStart + s);
          start = periodForLabel(a.year, a.month, monthStartDay).start;
          end = periodForLabel(b.year, b.month, monthStartDay).start;
          granularity =
              s <= 1 ? ReportGranularity.day : ReportGranularity.month;
        case ReportPeriodUnit.year:
          final nowYear = labelForDate(today, monthStartDay).year;
          final y = _floorDiv(nowYear, s) * s + offset * s;
          start = yearRangeFor(y, monthStartDay).start;
          end = yearRangeFor(y + s, monthStartDay).start;
          granularity =
              s <= 1 ? ReportGranularity.month : ReportGranularity.year;
      }
      final isCurrent = !today.isBefore(start) && today.isBefore(end);
      final isFuture = !start.isBefore(tomorrow);
      final clippedEnd = (!includeFuture && isCurrent && tomorrow.isBefore(end))
          ? tomorrow
          : end;
      return ResolvedPeriod(
        start: start,
        end: clippedEnd,
        nominalEnd: end,
        canPrev: true,
        canNext: !isCurrent && !isFuture,
        isCurrent: isCurrent,
        granularity: granularity,
      );

    case UntilTodayPeriod(:final mode, :final unit, :final count, :final since):
      late DateTime start;
      var openStart = false;
      if (mode == UntilTodayMode.since) {
        if (since == null) {
          start = DateTime(1970, 1, 1);
          openStart = true;
        } else {
          start = _midnight(since);
        }
      } else {
        final n = count < 1 ? 1 : count;
        switch (unit) {
          case ReportPeriodUnit.day:
            start = DateTime(today.year, today.month, today.day - (n - 1));
          case ReportPeriodUnit.week:
            final ws = reportWeekStart(today, weekStartsOnMonday);
            start = DateTime(ws.year, ws.month, ws.day - 7 * (n - 1));
          case ReportPeriodUnit.month:
            final idx = _monthIndex(labelForDate(today, monthStartDay));
            final a = _labelFromIndex(idx - (n - 1));
            start = periodForLabel(a.year, a.month, monthStartDay).start;
          case ReportPeriodUnit.year:
            final y = labelForDate(today, monthStartDay).year - (n - 1);
            start = yearRangeFor(y, monthStartDay).start;
        }
      }
      if (start.isAfter(today)) start = today;
      return ResolvedPeriod(
        start: start,
        end: tomorrow,
        nominalEnd: tomorrow,
        canPrev: false,
        canNext: false,
        isCurrent: true,
        granularity: openStart
            ? ReportGranularity.year
            : _granularityForSpan(start, tomorrow),
        openStart: openStart,
      );

    case FixedRangePeriod(:final start, :final endInclusive):
      var s = _midnight(start);
      var e = _midnight(endInclusive);
      if (e.isBefore(s)) {
        final t = s;
        s = e;
        e = t;
      }
      final end = DateTime(e.year, e.month, e.day + 1);
      return ResolvedPeriod(
        start: s,
        end: end,
        nominalEnd: end,
        canPrev: false,
        canNext: false,
        isCurrent: !today.isBefore(s) && today.isBefore(end),
        granularity: _granularityForSpan(s, end),
      );
  }
}
