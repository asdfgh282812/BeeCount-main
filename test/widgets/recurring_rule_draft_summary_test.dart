/// [RecurringRuleDraft.summary] 摘要文字——交易表單「週期」欄位 + 規則列表
/// 頁共用的展示邏輯,純函式(不依賴 widget tree),直接用生成的
/// `AppLocalizationsEn` 實例測。
///
/// 覆蓋:
/// - 簡單頻率(day/month/year,無 advancedRule)+ 無限期/有結束日。
/// - weekly_days 進階規則:星期標籤照 days 排序後拼接。
/// - monthly_day 進階規則:帶 interval 前綴 + 第 N 天。
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/l10n/app_localizations_en.dart';
import 'package:beecount/widgets/biz/recurring_rule_advanced_sheet.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('簡單頻率(monthly,interval=1)+ 無限期', () {
    const draft = RecurringRuleDraft(frequency: 'monthly', interval: 1);
    expect(draft.summary(l10n), contains('No end date'));
  });

  test('簡單頻率(yearly,interval=2)+ 有結束日', () {
    final draft = RecurringRuleDraft(
        frequency: 'yearly', interval: 2, endAt: DateTime(2030, 5, 1));
    final s = draft.summary(l10n);
    expect(s, contains('2'));
    expect(s, contains('Until'));
    expect(s, contains('2030/5/1'));
  });

  test('weekly_days 進階規則:星期標籤依 days 排序拼接', () {
    const draft = RecurringRuleDraft(
      frequency: 'weekly',
      interval: 1,
      advancedRule: {
        'type': 'weekly_days',
        'days': [5, 0, 2], // Sat, Mon, Wed(unsorted input)
      },
    );
    final s = draft.summary(l10n);
    // sorted: 0(Mon), 2(Wed), 5(Sat)
    expect(s, contains('Mon、Wed、Sat'));
  });

  test('monthly_day 進階規則:帶 interval + 第 N 天', () {
    const draft = RecurringRuleDraft(
      frequency: 'monthly',
      interval: 2,
      advancedRule: {'type': 'monthly_day', 'day': 15},
    );
    final s = draft.summary(l10n);
    expect(s, contains('Day 15'));
    expect(s, contains('2'));
  });
}
