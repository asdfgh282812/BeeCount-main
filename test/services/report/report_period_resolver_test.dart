import 'package:beecount/models/report/report_period.dart';
import 'package:beecount/services/report/report_period_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const monthly = RecurringPeriod(unit: ReportPeriodUnit.month);

  group('重複循環 - 月', () {
    test('自然月:當期截到明天、不可往後', () {
      final r = resolveReportPeriod(monthly, now: DateTime(2026, 9, 25, 15));
      expect(r.start, DateTime(2026, 9, 1));
      expect(r.end, DateTime(2026, 9, 26));
      expect(r.nominalEnd, DateTime(2026, 10, 1));
      expect(r.isCurrent, isTrue);
      expect(r.canNext, isFalse);
      expect(r.canPrev, isTrue);
      expect(r.granularity, ReportGranularity.day);
    });

    test('offset -1 = 上個月完整區間、可往後', () {
      final r =
          resolveReportPeriod(monthly, offset: -1, now: DateTime(2026, 9, 25));
      expect(r.start, DateTime(2026, 8, 1));
      expect(r.end, DateTime(2026, 9, 1));
      expect(r.canNext, isTrue);
      expect(r.isCurrent, isFalse);
    });

    test('offset -12 跨年', () {
      final r =
          resolveReportPeriod(monthly, offset: -12, now: DateTime(2026, 1, 15));
      expect(r.start, DateTime(2025, 1, 1));
      expect(r.end, DateTime(2025, 2, 1));
    });

    test('起始日 10:6/5 屬於 5 月週期', () {
      final r = resolveReportPeriod(monthly,
          now: DateTime(2026, 6, 5), monthStartDay: 10);
      expect(r.start, DateTime(2026, 5, 10));
      expect(r.nominalEnd, DateTime(2026, 6, 10));
      expect(r.end, DateTime(2026, 6, 6));
    });

    test('includeFuture 時當期不截短', () {
      final r = resolveReportPeriod(monthly,
          now: DateTime(2026, 9, 25), includeFuture: true);
      expect(r.end, DateTime(2026, 10, 1));
    });

    test('每季(span 3)對齊 1/4/7/10 月', () {
      const q = RecurringPeriod(unit: ReportPeriodUnit.month, span: 3);
      final r = resolveReportPeriod(q, now: DateTime(2026, 8, 20));
      expect(r.start, DateTime(2026, 7, 1));
      expect(r.nominalEnd, DateTime(2026, 10, 1));
      expect(r.granularity, ReportGranularity.month);
      final prev =
          resolveReportPeriod(q, offset: -1, now: DateTime(2026, 8, 20));
      expect(prev.start, DateTime(2026, 4, 1));
      expect(prev.end, DateTime(2026, 7, 1));
    });
  });

  group('重複循環 - 週/日/年', () {
    test('週一起始', () {
      // 2026-09-25 是週五
      final r = resolveReportPeriod(
          const RecurringPeriod(unit: ReportPeriodUnit.week),
          now: DateTime(2026, 9, 25));
      expect(r.start, DateTime(2026, 9, 21));
      expect(r.nominalEnd, DateTime(2026, 9, 28));
    });

    test('週日起始', () {
      final r = resolveReportPeriod(
          const RecurringPeriod(unit: ReportPeriodUnit.week),
          now: DateTime(2026, 9, 25),
          weekStartsOnMonday: false);
      expect(r.start, DateTime(2026, 9, 20));
    });

    test('日 offset -1', () {
      final r = resolveReportPeriod(
          const RecurringPeriod(unit: ReportPeriodUnit.day),
          offset: -1,
          now: DateTime(2026, 3, 1));
      expect(r.start, DateTime(2026, 2, 28));
      expect(r.end, DateTime(2026, 3, 1));
    });

    test('年 + 起始日 10:1/5 仍屬上一年度', () {
      final r = resolveReportPeriod(
          const RecurringPeriod(unit: ReportPeriodUnit.year),
          now: DateTime(2026, 1, 5),
          monthStartDay: 10);
      expect(r.start, DateTime(2025, 1, 10));
      expect(r.nominalEnd, DateTime(2026, 1, 10));
      expect(r.granularity, ReportGranularity.month);
    });
  });

  group('截至今天', () {
    test('最近 30 天含今天', () {
      final r = resolveReportPeriod(
          const UntilTodayPeriod(
              mode: UntilTodayMode.lastN,
              unit: ReportPeriodUnit.day,
              count: 30),
          now: DateTime(2026, 9, 25));
      expect(r.start, DateTime(2026, 8, 27));
      expect(r.end, DateTime(2026, 9, 26));
      expect(r.canPrev, isFalse);
      expect(r.canNext, isFalse);
    });

    test('最近 3 個月', () {
      final r = resolveReportPeriod(
          const UntilTodayPeriod(
              mode: UntilTodayMode.lastN,
              unit: ReportPeriodUnit.month,
              count: 3),
          now: DateTime(2026, 9, 25));
      expect(r.start, DateTime(2026, 7, 1));
      expect(r.granularity, ReportGranularity.month);
    });

    test('從某日起', () {
      final r = resolveReportPeriod(
          UntilTodayPeriod(
              mode: UntilTodayMode.since, since: DateTime(2026, 9, 1, 13)),
          now: DateTime(2026, 9, 25));
      expect(r.start, DateTime(2026, 9, 1));
      expect(r.openStart, isFalse);
    });

    test('全部 = 無下限', () {
      final r = resolveReportPeriod(
          const UntilTodayPeriod(mode: UntilTodayMode.since),
          now: DateTime(2026, 9, 25));
      expect(r.openStart, isTrue);
      expect(r.granularity, ReportGranularity.year);
    });
  });

  test('單一區間:含結束日、顛倒自動校正', () {
    final r = resolveReportPeriod(
        FixedRangePeriod(
            start: DateTime(2026, 3, 31), endInclusive: DateTime(2026, 1, 5)),
        now: DateTime(2026, 9, 25));
    expect(r.start, DateTime(2026, 1, 5));
    expect(r.end, DateTime(2026, 4, 1));
    expect(r.endInclusive, DateTime(2026, 3, 31));
    expect(r.granularity, ReportGranularity.month);
  });

  test('JSON round-trip', () {
    final periods = <ReportPeriod>[
      const RecurringPeriod(unit: ReportPeriodUnit.week, span: 2),
      UntilTodayPeriod(
          mode: UntilTodayMode.since, since: DateTime(2025, 12, 31)),
      const UntilTodayPeriod(
          mode: UntilTodayMode.lastN, unit: ReportPeriodUnit.year, count: 2),
      FixedRangePeriod(
          start: DateTime(2026, 1, 1), endInclusive: DateTime(2026, 6, 30)),
    ];
    for (final p in periods) {
      expect(ReportPeriod.fromJson(p.toJson()), p);
    }
    expect(ReportPeriod.fromJson({'kind': '???'}),
        const RecurringPeriod(unit: ReportPeriodUnit.month));
  });
}
