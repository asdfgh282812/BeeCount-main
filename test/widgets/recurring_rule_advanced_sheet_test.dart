/// 「進階設定」彈窗(`RecurringRuleAdvancedSheet`)——MOZE 對標的週期規則
/// 草稿編輯 UI。無法在此環境用模擬器實機驗證(見 docs/changes 說明),用
/// widget test 儘量覆蓋真實互動路徑(pump + tap),不只測純函式。
///
/// 覆蓋:
/// - 預設「單次」tab,確定後回傳 null。
/// - 切到「週期」tab、選「月」頻率,確定後回傳的 draft 帶正確 monthly_day
///   進階規則(預設用 anchorDate 的日期)。
/// - 切到「週期」+「週」頻率:互動式切換星期 chip 後,draft 帶正確
///   weekly_days 列表。
/// - 取消(不透過任何按鈕關閉)回傳 null。
/// - 「指定次數」模式下點次數數字叫出鍵盤輸入(取代原本只能 +/- 調整)。
/// - 新增「截止日期」結束方式,預設帶入 anchorDate。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/widgets/biz/recurring_rule_advanced_sheet.dart';

void main() {
  Widget host(void Function(AdvancedScheduleResult? result) onResult,
      {DateTime? anchorDate, bool installmentAvailable = false}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh', 'TW'),
      home: Scaffold(
        body: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              final result = await RecurringRuleAdvancedSheet.show(
                context,
                anchorDate: anchorDate ?? DateTime(2026, 3, 10),
                installmentAvailable: installmentAvailable,
              );
              onResult(result);
            },
            child: const Text('open'),
          );
        }),
      ),
    );
  }

  testWidgets('預設「單次」tab,確定後回傳 null', (tester) async {
    AdvancedScheduleResult? result;
    var resultCaptured = false;
    await tester.pumpWidget(host((r) {
      result = r;
      resultCaptured = true;
    }));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('確定'), findsOneWidget);
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();

    expect(resultCaptured, isTrue);
    expect(result, isNull);
  });

  testWidgets('切到「週期」+「月」頻率,確定後回傳 monthly_day draft(預設用 anchorDate 的日）',
      (tester) async {
    AdvancedScheduleResult? result;
    await tester
        .pumpWidget(host((r) => result = r, anchorDate: DateTime(2026, 3, 10)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('週期'));
    await tester.pumpAndSettle();
    // 頻率預設就是 monthly,不用額外點選 chip。
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.installment, isNull);
    final recurring = result!.recurring!;
    expect(recurring.frequency, 'monthly');
    expect(recurring.advancedRule, {'type': 'monthly_day', 'day': 10});
    expect(recurring.endAt, isNull); // 預設「無限期」
  });

  testWidgets('切到「週期」+「週」頻率,切換星期 chip 後回傳 weekly_days draft', (tester) async {
    AdvancedScheduleResult? result;
    // 2026-03-10 是星期二(weekday=2 → zero-based Monday=1)。
    await tester
        .pumpWidget(host((r) => result = r, anchorDate: DateTime(2026, 3, 10)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('週期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('週')); // 切到週頻率 → 顯示星期 chips
    await tester.pumpAndSettle();

    // 預設只勾了「二」(anchorDate 的星期);再勾「四」。
    await tester.tap(find.text('四'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    final recurring = result!.recurring!;
    expect(recurring.frequency, 'weekly');
    final days = (recurring.advancedRule!['days'] as List).cast<int>()..sort();
    expect(days, [1, 3]); // Tue=1, Thu=3 (Monday-based zero-index)
  });

  testWidgets('取消按鈕關閉彈窗,回傳 null', (tester) async {
    AdvancedScheduleResult? result;
    var resultCaptured = false;
    await tester.pumpWidget(host((r) {
      result = r;
      resultCaptured = true;
    }));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('週期')); // 先切到週期,確認取消仍然回傳 null
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(resultCaptured, isTrue);
    expect(result, isNull);
  });

  testWidgets('指定次數模式:點次數數字叫出鍵盤輸入,新次數反映到 endAt', (tester) async {
    AdvancedScheduleResult? result;
    await tester
        .pumpWidget(host((r) => result = r, anchorDate: DateTime(2026, 3, 10)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('週期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('指定次數'));
    await tester.pumpAndSettle();

    // 預設次數 12,點數字(不是 +/- 按鈕)叫出數字鍵盤輸入對話框。
    await tester.tap(find.byKey(const Key('recurringFixedCountValue')));
    await tester.pumpAndSettle();

    final dialogFinder = find.byType(AlertDialog);
    expect(dialogFinder, findsOneWidget);
    await tester.enterText(
      find.descendant(of: dialogFinder, matching: find.byType(TextField)),
      '3',
    );
    await tester
        .tap(find.descendant(of: dialogFinder, matching: find.text('確定')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    // 每月 10 號、共 3 次:3/10、4/10、5/10,endAt 取最後一次。
    expect(result!.recurring!.endAt, DateTime(2026, 5, 10));
  });

  testWidgets('截止日期模式:預設帶入 anchorDate,不額外選日期時 endAt 等於 anchorDate',
      (tester) async {
    AdvancedScheduleResult? result;
    await tester
        .pumpWidget(host((r) => result = r, anchorDate: DateTime(2026, 3, 10)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('週期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('截止日期'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.recurring!.endAt, DateTime(2026, 3, 10));
  });

  testWidgets('installmentAvailable=false 時不顯示「分期」tab', (tester) async {
    await tester.pumpWidget(host((_) {}, installmentAvailable: false));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('單次'), findsOneWidget);
    expect(find.text('週期'), findsOneWidget);
    expect(find.text('分期'), findsNothing);
  });

  testWidgets('installmentAvailable=true 時切到「分期」tab,確定後回傳 InstallmentDraft',
      (tester) async {
    AdvancedScheduleResult? result;
    await tester.pumpWidget(host((r) => result = r, installmentAvailable: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('分期'));
    await tester.pumpAndSettle();
    // 期數欄位預設是 12,直接確定即可觸發建立分期草稿的路徑。
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.recurring, isNull);
    expect(result!.installment, isNotNull);
    expect(result!.installment!.periods, 12);
  });

  testWidgets('截止日期模式:anchorDate 非月初時點開日曆子選擇器不會踩 table_calendar 斷言崩潰',
      (tester) async {
    // 回歸測試——anchorDate = 2026/3/10(月中,非 1 號)。修復前
    // entry_date_time_picker.dart 把 focusedDay 無條件正規化成
    // 「clamp 後那天所在月份的 1 號」,這裡就會落在 firstDay(=minDate=
    // anchorDate=3/10)之前,觸發 table_calendar_base.dart:77 的
    // `isSameDay(focusedDay, firstDay) || focusedDay.isAfter(firstDay)` 斷言,
    // 整個彈窗紅屏崩潰(見 issue 附的錯誤日誌)。
    await tester.pumpWidget(host((_) {}, anchorDate: DateTime(2026, 3, 10)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('週期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('截止日期'));
    await tester.pumpAndSettle();

    // 點開日期顯示,叫出 `showTransactionDatePicker` 的月曆子選擇器——修復前
    // 這一步的 build 就會拋 AssertionError。
    await tester.tap(find.text('2026/3/10'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TableCalendar), findsOneWidget);
  });
}
