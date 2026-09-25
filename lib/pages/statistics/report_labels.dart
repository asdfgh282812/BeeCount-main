import '../../l10n/app_localizations.dart';
import '../../models/report/report_definition.dart';
import '../../models/report/report_period.dart';
import '../../utils/month_range.dart';

String reportDisplayName(AppLocalizations l10n, ReportDefinition def) {
  final n = def.name?.trim();
  if (n != null && n.isNotEmpty) return n;
  switch (def.builtInKey) {
    case kBuiltInWeekly:
      return l10n.reportBuiltInWeekly;
    case kBuiltInYearly:
      return l10n.reportBuiltInYearly;
    case kBuiltInMonthly:
      return l10n.reportBuiltInMonthly;
  }
  return l10n.reportListTitle;
}

String reportUnitLabel(AppLocalizations l10n, ReportPeriodUnit u) {
  switch (u) {
    case ReportPeriodUnit.day:
      return l10n.reportUnitDay;
    case ReportPeriodUnit.week:
      return l10n.reportUnitWeek;
    case ReportPeriodUnit.month:
      return l10n.reportUnitMonth;
    case ReportPeriodUnit.year:
      return l10n.reportUnitYear;
  }
}

String reportUnitPlural(AppLocalizations l10n, ReportPeriodUnit u) {
  switch (u) {
    case ReportPeriodUnit.day:
      return l10n.reportUnitDays;
    case ReportPeriodUnit.week:
      return l10n.reportUnitWeeks;
    case ReportPeriodUnit.month:
      return l10n.reportUnitMonths;
    case ReportPeriodUnit.year:
      return l10n.reportUnitYears;
  }
}

String _ymd(DateTime d) => '${d.year}/${d.month}/${d.day}';

String _range(DateTime a, DateTime b) {
  if (a.year == b.year && a.month == b.month && a.day == b.day) return _ymd(a);
  if (a.year == b.year) return '${_ymd(a)} – ${b.month}/${b.day}';
  return '${_ymd(a)} – ${_ymd(b)}';
}

/// 報表頁首的期間文字。自然月 = `2026-09`(起始日非 1 時附「6.10-7.9」),
/// 年 = `2026`,其餘顯示日期區間。
String reportPeriodLabel(
  AppLocalizations l10n,
  ReportPeriod period,
  ResolvedPeriod r, {
  int monthStartDay = 1,
}) {
  switch (period) {
    case RecurringPeriod(:final unit, :final span):
      if (span == 1 && unit == ReportPeriodUnit.month) {
        final label = labelForDate(r.start, monthStartDay);
        final base = '${label.year}-${label.month.toString().padLeft(2, '0')}';
        final extra = periodRangeText(label.year, label.month, monthStartDay);
        return extra == null ? base : '$base ($extra)';
      }
      if (span == 1 && unit == ReportPeriodUnit.year && monthStartDay == 1) {
        return '${r.start.year}';
      }
      return _range(r.start, r.endInclusive);
    case UntilTodayPeriod(:final mode, :final unit, :final count, :final since):
      if (mode == UntilTodayMode.lastN) {
        return l10n.reportLastN(count, reportUnitPlural(l10n, unit));
      }
      if (since == null) return l10n.reportSinceAll;
      return l10n.reportSinceLabel(_ymd(since));
    case FixedRangePeriod():
      return _range(r.start, r.endInclusive);
  }
}

/// 報表清單卡片/編輯頁的期間類型描述(例:「重複循環・每 1 月」)。
String reportPeriodKindLabel(AppLocalizations l10n, ReportPeriod period) {
  switch (period) {
    case RecurringPeriod(:final unit, :final span):
      return '${l10n.reportPeriodRecurring} · '
          '${l10n.reportEveryN(span, reportUnitLabel(l10n, unit))}';
    case UntilTodayPeriod():
      return l10n.reportPeriodUntilToday;
    case FixedRangePeriod():
      return l10n.reportPeriodFixed;
  }
}
