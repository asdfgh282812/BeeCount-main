import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/utils/overview_chart_utils.dart';

OverviewDayTotal _day(DateTime d, double total) => (day: d, total: total);
OverviewMonthTotal _month(DateTime m, double total) => (month: m, total: total);
OverviewYearTotal _year(int y, double total) => (year: y, total: total);
OverviewNetWorthDaily _net(DateTime d, double net) =>
    (date: d, assets: net, liabilities: 0, net: net);

void main() {
  group('overviewWindowStart', () {
    test('按日:近 7 天,起点是 asOfDate 往前推 6 天', () {
      final asOf = DateTime(2026, 9, 20);
      final start = overviewWindowStart(OverviewGranularity.day, asOf);
      expect(start, DateTime(2026, 9, 14));
    });

    test('按週(週一起算):起点是 8 周前那一周的周一', () {
      // 2026-09-20 是周日;本周一是 2026-09-14。往前 7 个整周 = 49 天。
      final asOf = DateTime(2026, 9, 20);
      final start = overviewWindowStart(OverviewGranularity.week, asOf,
          weekStartsOnMonday: true);
      expect(start, DateTime(2026, 9, 14).subtract(const Duration(days: 49)));
    });

    test('按週(週日起算):同一天所在周的起点改成周日', () {
      final asOf = DateTime(2026, 9, 20); // 周日
      final start = overviewWindowStart(OverviewGranularity.week, asOf,
          weekStartsOnMonday: false);
      // 周日起算时,2026-09-20 本身就是当周周日(周起点)。
      expect(start, DateTime(2026, 9, 20).subtract(const Duration(days: 49)));
    });

    test('按月:近 12 个月,起点是 asOfDate 所在月往前推 11 个月的月初', () {
      final asOf = DateTime(2026, 3, 15);
      final start = overviewWindowStart(OverviewGranularity.month, asOf);
      expect(start, DateTime(2025, 4, 1));
    });

    test('按年:近 5 年,起点是 asOfDate 年份往前推 4 年', () {
      final asOf = DateTime(2026, 3, 15);
      final start = overviewWindowStart(OverviewGranularity.year, asOf);
      expect(start, DateTime(2022, 1, 1));
    });
  });

  group('buildDailyOverviewPoints', () {
    test('7 天逐日一一对应,缺失的收入/支出/净资产补 0', () {
      final asOf = DateTime(2026, 9, 20);
      final income = [
        _day(DateTime(2026, 9, 19), 100),
        _day(DateTime(2026, 9, 20), 50),
      ];
      final expense = [
        _day(DateTime(2026, 9, 20), 30),
      ];
      final netWorth = [
        _net(DateTime(2026, 9, 18), 1000),
        _net(DateTime(2026, 9, 20), 1200),
      ];

      final points = buildDailyOverviewPoints(
        incomeDaily: income,
        expenseDaily: expense,
        netWorthDaily: netWorth,
        asOfDate: asOf,
      );

      expect(points.length, 7);
      expect(points.first.bucketStart, DateTime(2026, 9, 14));
      expect(points.last.bucketStart, DateTime(2026, 9, 20));
      // 9/19 只有收入没有支出/净资产 → 支出与净资产补 0。
      final sep19 =
          points.firstWhere((p) => p.bucketStart == DateTime(2026, 9, 19));
      expect(sep19.income, 100);
      expect(sep19.expense, 0);
      expect(sep19.netWorth, 0);
      // 9/20(最新一天,当前未结束周期):income/expense/netWorth 都是当天实际值。
      final sep20 = points.last;
      expect(sep20.income, 50);
      expect(sep20.expense, 30);
      expect(sep20.netWorth, 1200);
    });
  });

  group('buildWeeklyOverviewPoints', () {
    test('当前未结束的周:金额只加总到今天,净资产取今天的值(而非未来日期)', () {
      // asOf 是周三(2026-09-16 是周三),本周(周一起算)是 09-14~09-20,
      // 但只应统计到 09-16 为止(未来日期本就不在输入序列里)。
      final asOf = DateTime(2026, 9, 16);
      final income = [
        _day(DateTime(2026, 9, 14), 10), // 上周(实际是本周一,算作本周)
        _day(DateTime(2026, 9, 15), 20),
        _day(DateTime(2026, 9, 16), 30),
      ];
      final expense = <OverviewDayTotal>[];
      final netWorth = [
        _net(DateTime(2026, 9, 14), 100),
        _net(DateTime(2026, 9, 15), 110),
        _net(DateTime(2026, 9, 16), 120), // 今天的值
      ];

      final points = buildWeeklyOverviewPoints(
        incomeDaily: income,
        expenseDaily: expense,
        netWorthDaily: netWorth,
        asOfDate: asOf,
        weekStartsOnMonday: true,
      );

      expect(points.length, 8);
      final currentWeek = points.last;
      expect(currentWeek.bucketStart, DateTime(2026, 9, 14)); // 本周一
      expect(currentWeek.income, 60); // 10+20+30,只到今天为止
      expect(currentWeek.netWorth, 120); // 今天的值,不是未来某天
    });

    test('周起始日切换(周日起算)分桶结果不同', () {
      final asOf = DateTime(2026, 9, 16); // 周三
      final income = [
        _day(DateTime(2026, 9, 13), 5), // 周日,若周日起算属于本周
        _day(DateTime(2026, 9, 14), 10),
        _day(DateTime(2026, 9, 16), 30),
      ];
      final points = buildWeeklyOverviewPoints(
        incomeDaily: income,
        expenseDaily: const [],
        netWorthDaily: const [],
        asOfDate: asOf,
        weekStartsOnMonday: false,
      );
      final currentWeek = points.last;
      expect(currentWeek.bucketStart, DateTime(2026, 9, 13)); // 本周周日起点
      expect(currentWeek.income, 45); // 5+10+30 都落在同一周
    });
  });

  group('buildMonthlyOverviewPoints', () {
    test('12 个月按月对齐,跨年边界(去年 12 月与今年 1 月)不串桶', () {
      final asOf = DateTime(2026, 1, 20);
      final incomeMonthly = [
        _month(DateTime(2025, 2, 1), 100), // 会被 12 个月窗口截掉(超出范围)
        _month(DateTime(2025, 3, 1), 100),
        _month(DateTime(2025, 12, 1), 500),
        _month(DateTime(2026, 1, 1), 700),
      ];
      final netWorth = [
        _net(DateTime(2025, 12, 31), 900),
        _net(DateTime(2026, 1, 20), 950),
      ];

      final points = buildMonthlyOverviewPoints(
        incomeMonthly: incomeMonthly,
        expenseMonthly: const [],
        netWorthDaily: netWorth,
        asOfDate: asOf,
      );

      expect(points.length, 12);
      expect(points.first.bucketStart, DateTime(2025, 2, 1));
      expect(points.last.bucketStart, DateTime(2026, 1, 1));
      final dec2025 =
          points.firstWhere((p) => p.bucketStart == DateTime(2025, 12, 1));
      expect(dec2025.income, 500);
      expect(dec2025.netWorth, 900);
      final jan2026 = points.last;
      expect(jan2026.income, 700);
      expect(jan2026.netWorth, 950); // 当月(未结束)取今天的净资产值
    });
  });

  group('buildYearlyOverviewPoints', () {
    test('近 5 年,缺数据的年份补 0(新账本只有 1 年数据)', () {
      final asOf = DateTime(2026, 6, 1);
      final incomeYearly = [
        _year(2026, 300),
      ];
      final points = buildYearlyOverviewPoints(
        incomeYearly: incomeYearly,
        expenseYearly: const [],
        netWorthDaily: [_net(DateTime(2026, 6, 1), 400)],
        asOfDate: asOf,
      );

      expect(points.length, 5);
      expect(points.map((p) => p.bucketStart.year).toList(),
          [2022, 2023, 2024, 2025, 2026]);
      expect(points[0].income, 0);
      expect(points.last.income, 300);
      expect(points.last.netWorth, 400);
    });
  });
}
