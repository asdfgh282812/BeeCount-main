import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/services/data/recurring_rule_schedule.dart';

void main() {
  group('enumerateOccurrences - simple frequency', () {
    test('monthly with no end respects maxCount', () {
      final start = DateTime.utc(2026, 1, 15);
      final occ = enumerateOccurrences(
        start: start,
        end: null,
        frequency: 'monthly',
        interval: 1,
        advancedRule: null,
        maxCount: 5,
      );
      expect(occ.length, 5);
      expect(occ[0], start);
      expect(occ[1], DateTime.utc(2026, 2, 15));
      expect(occ[4], DateTime.utc(2026, 5, 15));
    });

    test('with end stops at boundary', () {
      final start = DateTime.utc(2026, 1, 1);
      final end = DateTime.utc(2026, 3, 15);
      final occ = enumerateOccurrences(
        start: start,
        end: end,
        frequency: 'monthly',
        interval: 1,
        advancedRule: null,
        maxCount: 200,
      );
      expect(occ, [
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 2, 1),
        DateTime.utc(2026, 3, 1),
      ]);
    });

    test('start after end returns empty', () {
      final start = DateTime.utc(2026, 5, 1);
      final end = DateTime.utc(2026, 1, 1);
      final occ = enumerateOccurrences(
        start: start,
        end: end,
        frequency: 'monthly',
        interval: 1,
        advancedRule: null,
        maxCount: 10,
      );
      expect(occ, isEmpty);
    });

    test('maxCount zero returns empty', () {
      final start = DateTime.utc(2026, 1, 5);
      final occ = enumerateOccurrences(
        start: start,
        end: null,
        frequency: 'daily',
        interval: 1,
        advancedRule: null,
        maxCount: 0,
      );
      expect(occ, isEmpty);
    });
  });

  group('enumerateOccurrences - weekly_days', () {
    test('Sat/Sun keeps time-of-day and matches weekday mapping', () {
      // 2026-01-05 是週一(weekdayZeroBased == 0)。
      final start = DateTime.utc(2026, 1, 5, 9, 0);
      final occ = enumerateOccurrences(
        start: start,
        end: null,
        frequency: 'weekly',
        interval: 1,
        advancedRule: {
          'type': 'weekly_days',
          'days': [5, 6], // Sat, Sun
        },
        maxCount: 4,
      );
      expect(occ.length, 4);
      expect(occ.map(weekdayZeroBased).toList(), [5, 6, 5, 6]);
      expect(occ[0], DateTime.utc(2026, 1, 10, 9, 0)); // 第一个週六
      expect(occ[1], DateTime.utc(2026, 1, 11, 9, 0)); // 週日
      expect(occ.every((d) => d.hour == 9), isTrue);
    });

    test('invalid days throws', () {
      final start = DateTime.utc(2026, 1, 5);
      expect(
        () => enumerateOccurrences(
          start: start,
          end: null,
          frequency: 'weekly',
          interval: 1,
          advancedRule: {'type': 'weekly_days', 'days': <int>[]},
          maxCount: 4,
        ),
        throwsArgumentError,
      );
      expect(
        () => enumerateOccurrences(
          start: start,
          end: null,
          frequency: 'weekly',
          interval: 1,
          advancedRule: {
            'type': 'weekly_days',
            'days': [7]
          },
          maxCount: 4,
        ),
        throwsArgumentError,
      );
    });
  });

  group('enumerateOccurrences - monthly_day', () {
    test('basic', () {
      final start = DateTime.utc(2026, 1, 5, 8, 0);
      final occ = enumerateOccurrences(
        start: start,
        end: null,
        frequency: 'monthly',
        interval: 1,
        advancedRule: {'type': 'monthly_day', 'day': 10},
        maxCount: 3,
      );
      expect(occ, [
        DateTime.utc(2026, 1, 10, 8, 0),
        DateTime.utc(2026, 2, 10, 8, 0),
        DateTime.utc(2026, 3, 10, 8, 0),
      ]);
    });

    test('start after target day skips to next month', () {
      final start = DateTime.utc(2026, 1, 15);
      final occ = enumerateOccurrences(
        start: start,
        end: null,
        frequency: 'monthly',
        interval: 1,
        advancedRule: {'type': 'monthly_day', 'day': 10},
        maxCount: 1,
      );
      expect(occ, [DateTime.utc(2026, 2, 10)]);
    });

    test('clamps to month end', () {
      final start = DateTime.utc(2026, 1, 5);
      final occ = enumerateOccurrences(
        start: start,
        end: null,
        frequency: 'monthly',
        interval: 1,
        advancedRule: {'type': 'monthly_day', 'day': 31},
        maxCount: 3,
      );
      expect(occ[0], DateTime.utc(2026, 1, 31));
      expect(occ[1], DateTime.utc(2026, 2, 28)); // 非闰年
      expect(occ[2], DateTime.utc(2026, 3, 31));
    });

    test('invalid day throws', () {
      final start = DateTime.utc(2026, 1, 5);
      expect(
        () => enumerateOccurrences(
          start: start,
          end: null,
          frequency: 'monthly',
          interval: 1,
          advancedRule: {'type': 'monthly_day', 'day': 32},
          maxCount: 1,
        ),
        throwsArgumentError,
      );
    });
  });

  test('unsupported advanced rule type throws', () {
    final start = DateTime.utc(2026, 1, 5);
    expect(
      () => enumerateOccurrences(
        start: start,
        end: null,
        frequency: 'monthly',
        interval: 1,
        advancedRule: {'type': 'yearly_on_date'},
        maxCount: 1,
      ),
      throwsArgumentError,
    );
  });

  group('planInitialGeneration', () {
    test('with end generates entire range and marks fully generated', () {
      final start = DateTime.utc(2026, 1, 1);
      final end = DateTime.utc(2026, 3, 1);
      final result = planInitialGeneration(
        start: start,
        end: end,
        frequency: 'monthly',
        interval: 1,
        advancedRule: null,
      );
      expect(result.occurrences, [
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 2, 1),
        DateTime.utc(2026, 3, 1),
      ]);
      expect(result.generatedUntilAt, DateTime.utc(2026, 3, 1));
      expect(result.fullyGenerated, isTrue);
    });

    test('without end generates one default window, never fully generated', () {
      final start = DateTime.utc(2026, 1, 1);
      final result = planInitialGeneration(
        start: start,
        end: null,
        frequency: 'monthly',
        interval: 1,
        advancedRule: null,
      );
      // 12 个月窗口,每月一笔 → 13 笔(含 start 本身)。
      expect(result.occurrences.length, 13);
      expect(result.occurrences.first, start);
      expect(result.generatedUntilAt, result.occurrences.last);
      expect(result.fullyGenerated, isFalse);
    });
  });

  group('addMonths', () {
    test('clamps day to month end on overflow', () {
      expect(addMonths(DateTime.utc(2026, 1, 31), 1), DateTime.utc(2026, 2, 28));
      expect(addMonths(DateTime.utc(2028, 1, 31), 1), DateTime.utc(2028, 2, 29)); // 闰年
    });

    test('carries year on month wraparound', () {
      expect(addMonths(DateTime.utc(2026, 12, 15), 2), DateTime.utc(2027, 2, 15));
    });
  });

  group('nextRunFrom', () {
    test('daily/weekly add fixed durations', () {
      final now = DateTime.utc(2026, 1, 1);
      expect(nextRunFrom(now, 'daily', 3), DateTime.utc(2026, 1, 4));
      expect(nextRunFrom(now, 'weekly', 2), DateTime.utc(2026, 1, 15));
    });

    test('yearly advances by interval * 12 months', () {
      final now = DateTime.utc(2026, 2, 28);
      expect(nextRunFrom(now, 'yearly', 1), DateTime.utc(2027, 2, 28));
    });
  });
}
