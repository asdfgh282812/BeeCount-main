import 'dart:convert';

import 'package:beecount/models/report/report_definition.dart';
import 'package:beecount/models/report/report_filter.dart';
import 'package:beecount/models/report/report_period.dart';
import 'package:beecount/providers/report_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ReportStoreNotifier> fresh(
      [Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    final n = ReportStoreNotifier(autoLoad: false);
    await n.load();
    return n;
  }

  test('首次載入植入內建三份並寫回 prefs', () async {
    final n = await fresh();
    expect(n.state.loaded, isTrue);
    expect(n.state.reports.map((r) => r.builtInKey),
        [kBuiltInMonthly, kBuiltInWeekly, kBuiltInYearly]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ReportStoreNotifier.prefsKey), isNotNull);

    // 刪光後重新載入不會再自動植入
    for (final r in [...n.state.reports]) {
      await n.delete(r.id);
    }
    final again = ReportStoreNotifier(autoLoad: false);
    await again.load();
    expect(again.state.reports, isEmpty);
  });

  test('新增/更新/複製/排序/恢復預設', () async {
    final n = await fresh();
    final custom = ReportDefinition(
      id: 'c1',
      name: '餐飲',
      period: const UntilTodayPeriod(
          mode: UntilTodayMode.lastN, unit: ReportPeriodUnit.day, count: 7),
      filter: const ReportFilter(
          merchants: KeySetFilter(mode: FilterMode.exclude, values: {'全聯'}),
          minAmount: 10),
    );
    await n.add(custom);
    expect(n.state.reports.last.id, 'c1');

    await n.update(custom.copyWith(name: () => '外食'));
    expect(n.state.byId('c1')!.name, '外食');

    final copy = await n.duplicate('builtin-monthly', '每月報表 副本');
    expect(copy!.builtInKey, isNull);
    expect(n.state.reports[1].id, copy.id, reason: '副本放在原報表後面');

    await n.reorder(0, 2);
    expect(n.state.reports[2].id, 'builtin-monthly');

    await n.delete('builtin-yearly');
    await n.restoreBuiltIns();
    expect(
        n.state.reports.where((r) => r.builtInKey == kBuiltInYearly).length, 1);
    expect(
        n.state.reports.where((r) => r.builtInKey == kBuiltInMonthly).length, 1,
        reason: '已存在的內建報表不重複加');

    // 持久化 round-trip
    final reloaded = ReportStoreNotifier(autoLoad: false);
    await reloaded.load();
    final r = reloaded.state.byId('c1')!;
    expect(r.name, '外食');
    expect(r.period, custom.period);
    expect(r.filter, custom.filter);
  });

  test('JSON 損毀時退回內建範本', () async {
    final n = await fresh({ReportStoreNotifier.prefsKey: '{not json'});
    expect(n.state.reports.length, 3);
  });

  test('忽略壞掉的單筆報表', () async {
    final n = await fresh({
      ReportStoreNotifier.prefsKey: jsonEncode({
        'version': 1,
        'reports': [
          {
            'id': 'ok',
            'period': {
              'kind': 'fixed',
              'start': '2026-01-01',
              'end': '2026-01-31'
            }
          },
          {'no-id': true},
          'garbage',
        ],
      }),
    });
    expect(n.state.reports.single.id, 'ok');
    expect(n.state.reports.single.period, isA<FixedRangePeriod>());
  });
}
