/// 每周起始日设置(周一/周日)——验证 [weekStartsOnMondayProvider] 能同步驱动
/// 日历页的 TableCalendar 与通用日期选择器 [showAppDatePicker] 的
/// startingDayOfWeek,不需要逐个页面手工核对。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/calendar/calendar_body.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/providers/theme_providers.dart';
import 'package:beecount/widgets/ui/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
  });

  tearDown(() async => db.close());

  Ledger cnyLedger() => Ledger(
        id: 1,
        name: 'L',
        currency: 'CNY',
        type: 'personal',
        createdAt: DateTime(2026, 1, 1),
        myRole: 'owner',
        memberCount: 1,
        isShared: false,
        monthStartDay: 1,
      );

  TableCalendar calendarOf(WidgetTester tester) {
    final finder = find.byWidgetPredicate((w) => w is TableCalendar);
    return tester.widgetList(finder).single as TableCalendar;
  }

  Widget calendarHost({required bool weekStartsOnMonday}) {
    return ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentLedgerProvider
            .overrideWith((ref) => Stream<Ledger?>.value(cnyLedger())),
        weekStartsOnMondayProvider.overrideWith((ref) => weekStartsOnMonday),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(body: CalendarBody()),
      ),
    );
  }

  testWidgets('週起始日設定為週一 → 日曆頁 TableCalendar 以週一起始', (tester) async {
    await tester.pumpWidget(calendarHost(weekStartsOnMonday: true));
    await tester.pumpAndSettle();

    expect(calendarOf(tester).startingDayOfWeek, StartingDayOfWeek.monday);
  });

  testWidgets('週起始日設定為週日 → 日曆頁 TableCalendar 以週日起始', (tester) async {
    await tester.pumpWidget(calendarHost(weekStartsOnMonday: false));
    await tester.pumpAndSettle();

    expect(calendarOf(tester).startingDayOfWeek, StartingDayOfWeek.sunday);
  });

  Widget datePickerHost({required bool weekStartsOnMonday}) {
    return ProviderScope(
      overrides: [
        weekStartsOnMondayProvider.overrideWith((ref) => weekStartsOnMonday),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showAppDatePicker(context, initial: DateTime(2026, 9, 8)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('週起始日設定為週一 → showAppDatePicker 以週一起始', (tester) async {
    await tester.pumpWidget(datePickerHost(weekStartsOnMonday: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(calendarOf(tester).startingDayOfWeek, StartingDayOfWeek.monday);
  });

  testWidgets('週起始日設定為週日 → showAppDatePicker 以週日起始', (tester) async {
    await tester.pumpWidget(datePickerHost(weekStartsOnMonday: false));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(calendarOf(tester).startingDayOfWeek, StartingDayOfWeek.sunday);
  });
}
