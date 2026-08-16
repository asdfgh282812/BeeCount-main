/// 週期 occurrence 編輯/刪除二選一彈窗(`showRecurringEditChoiceSheet` /
/// `showRecurringDeleteChoiceSheet`)——MOZE 對標的「此記錄」vs「連同未來
/// 週期」語意,見 lib/widgets/biz/recurring_occurrence_dialogs.dart。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/widgets/biz/recurring_occurrence_dialogs.dart';

void main() {
  Widget host(Widget Function(BuildContext) buttonBuilder) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh', 'TW'),
      home: Scaffold(body: Builder(builder: buttonBuilder)),
    );
  }

  testWidgets('編輯選擇彈窗:點「修改此記錄」回傳 thisOnly', (tester) async {
    RecurringEditScope? result;
    await tester.pumpWidget(host((context) => ElevatedButton(
          onPressed: () async {
            result = await showRecurringEditChoiceSheet(context);
          },
          child: const Text('open'),
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('修改此記錄'), findsOneWidget);
    expect(find.text('修改連同未來週期'), findsOneWidget);
    await tester.tap(find.text('修改此記錄'));
    await tester.pumpAndSettle();

    expect(result, RecurringEditScope.thisOnly);
  });

  testWidgets('編輯選擇彈窗:點「修改連同未來週期」回傳 thisAndFuture', (tester) async {
    RecurringEditScope? result;
    await tester.pumpWidget(host((context) => ElevatedButton(
          onPressed: () async {
            result = await showRecurringEditChoiceSheet(context);
          },
          child: const Text('open'),
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改連同未來週期'));
    await tester.pumpAndSettle();

    expect(result, RecurringEditScope.thisAndFuture);
  });

  testWidgets('刪除選擇彈窗:點「取消」回傳 null', (tester) async {
    RecurringDeleteScope? result;
    var captured = false;
    await tester.pumpWidget(host((context) => ElevatedButton(
          onPressed: () async {
            result = await showRecurringDeleteChoiceSheet(context);
            captured = true;
          },
          child: const Text('open'),
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('刪除此記錄'), findsOneWidget);
    expect(find.text('刪除連同未來週期'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(captured, isTrue);
    expect(result, isNull);
  });

  testWidgets('刪除選擇彈窗:點「刪除連同未來週期」回傳 thisAndFuture', (tester) async {
    RecurringDeleteScope? result;
    await tester.pumpWidget(host((context) => ElevatedButton(
          onPressed: () async {
            result = await showRecurringDeleteChoiceSheet(context);
          },
          child: const Text('open'),
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除連同未來週期'));
    await tester.pumpAndSettle();

    expect(result, RecurringDeleteScope.thisAndFuture);
  });
}
