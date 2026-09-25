/// 統計報表的期間定義(對齊 doc.moze.app/analysis/statistics-report 的三種
/// 期間類型)。純資料 + JSON,不含任何日期計算——「今天對應哪個區間」一律
/// 由 `lib/services/report/report_period_resolver.dart` 解析,讓期間本身可以
/// 原封不動存進 SharedPreferences(見 `report_definition.dart`)。
library;

/// 期間單位。重複循環用來決定「一期多長」,截至今天用來決定「往回幾個單位」。
enum ReportPeriodUnit { day, week, month, year }

/// 截至今天的兩種模式:往回 N 個單位 / 從某一天開始(null = 全部)。
enum UntilTodayMode { lastN, since }

sealed class ReportPeriod {
  const ReportPeriod();

  Map<String, dynamic> toJson();

  /// 解析失敗(欄位缺漏/未知類型)一律回退成「每月」,不讓一份壞掉的報表
  /// 拖垮整個清單。
  static ReportPeriod fromJson(Map<String, dynamic> json) {
    try {
      switch (json['kind']) {
        case 'recurring':
          return RecurringPeriod(
            unit: _unitFrom(json['unit']) ?? ReportPeriodUnit.month,
            span: ((json['span'] as num?)?.toInt() ?? 1).clamp(1, 120),
          );
        case 'untilToday':
          final mode = json['mode'] == 'since'
              ? UntilTodayMode.since
              : UntilTodayMode.lastN;
          final since = json['since'] as String?;
          return UntilTodayPeriod(
            mode: mode,
            unit: _unitFrom(json['unit']) ?? ReportPeriodUnit.day,
            count: ((json['count'] as num?)?.toInt() ?? 30).clamp(1, 9999),
            since: since == null ? null : DateTime.parse(since),
          );
        case 'fixed':
          return FixedRangePeriod(
            start: DateTime.parse(json['start'] as String),
            endInclusive: DateTime.parse(json['end'] as String),
          );
      }
    } catch (_) {
      // fall through
    }
    return const RecurringPeriod(unit: ReportPeriodUnit.month);
  }

  static ReportPeriodUnit? _unitFrom(Object? name) {
    for (final u in ReportPeriodUnit.values) {
      if (u.name == name) return u;
    }
    return null;
  }
}

/// 重複循環:每 [span] 個 [unit] 為一期(例:month + span 3 = 每季),可左右
/// 切換上一期/下一期。月/年依帳本 monthStartDay 切。
class RecurringPeriod extends ReportPeriod {
  final ReportPeriodUnit unit;
  final int span;

  const RecurringPeriod({required this.unit, this.span = 1});

  @override
  Map<String, dynamic> toJson() =>
      {'kind': 'recurring', 'unit': unit.name, 'span': span};

  @override
  bool operator ==(Object other) =>
      other is RecurringPeriod && other.unit == unit && other.span == span;

  @override
  int get hashCode => Object.hash('recurring', unit, span);
}

/// 截至今天:[mode] = lastN 時是「最近 [count] 個 [unit]」(含今天所在的那一
/// 個單位);[mode] = since 時是「[since] ~ 今天」,[since] 為 null 代表全部。
class UntilTodayPeriod extends ReportPeriod {
  final UntilTodayMode mode;
  final ReportPeriodUnit unit;
  final int count;
  final DateTime? since;

  const UntilTodayPeriod({
    required this.mode,
    this.unit = ReportPeriodUnit.day,
    this.count = 30,
    this.since,
  });

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'untilToday',
        'mode': mode.name,
        'unit': unit.name,
        'count': count,
        if (since != null) 'since': _dateOnly(since!),
      };

  @override
  bool operator ==(Object other) =>
      other is UntilTodayPeriod &&
      other.mode == mode &&
      other.unit == unit &&
      other.count == count &&
      other.since == since;

  @override
  int get hashCode => Object.hash('untilToday', mode, unit, count, since);
}

/// 單一區間:[start] ~ [endInclusive](兩端皆含,只取日期)。
class FixedRangePeriod extends ReportPeriod {
  final DateTime start;
  final DateTime endInclusive;

  const FixedRangePeriod({required this.start, required this.endInclusive});

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'fixed',
        'start': _dateOnly(start),
        'end': _dateOnly(endInclusive),
      };

  @override
  bool operator ==(Object other) =>
      other is FixedRangePeriod &&
      other.start == start &&
      other.endInclusive == endInclusive;

  @override
  int get hashCode => Object.hash('fixed', start, endInclusive);
}

String _dateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 趨勢圖的分桶粒度。
enum ReportGranularity { day, month, year }

/// [ReportPeriod] 在某個 offset、某個「今天」下解析出的實際區間。
class ResolvedPeriod {
  /// 半開區間 [start, end),同 `month_range.dart` 全庫約定。
  final DateTime start;
  final DateTime end;

  /// 區間原本的結束點(未因「不含未來」截短前),顯示「6/1–6/30」用。
  final DateTime nominalEnd;

  final bool canPrev;
  final bool canNext;

  /// 是否為涵蓋今天的那一期(只有重複循環有意義)。
  final bool isCurrent;

  final ReportGranularity granularity;

  /// 起點是否為「無下限」(截至今天 + since=null)。趨勢圖會把前面沒資料的
  /// 桶裁掉,不然會從 1970 年開始畫。
  final bool openStart;

  const ResolvedPeriod({
    required this.start,
    required this.end,
    required this.nominalEnd,
    required this.canPrev,
    required this.canNext,
    required this.isCurrent,
    required this.granularity,
    this.openStart = false,
  });

  /// 顯示用的最後一天(含)。
  DateTime get endInclusive =>
      DateTime(nominalEnd.year, nominalEnd.month, nominalEnd.day - 1);
}
