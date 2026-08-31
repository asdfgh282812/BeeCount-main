/// 記帳表單「選擇專案」bottom sheet(`ProjectPicker`)——比照 moze 的清單
/// 呈現,每一列除了名稱還要能看到剩餘額度/純記錄狀態,不再只是名稱+打勾。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/widgets/biz/project_picker.dart';

Ledger _cnyLedger() => Ledger(
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

  Widget host(Function(ProjectPickResult? result) onPicked) {
    return ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentLedgerProvider
            .overrideWith((ref) => Stream<Ledger?>.value(_cnyLedger())),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', 'TW'),
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                final result = await ProjectPicker.show(context, ledgerId: 1);
                onPicked(result);
              },
              child: const Text('open'),
            );
          }),
        ),
      ),
    );
  }

  testWidgets('有預算的專案顯示剩餘額度,純記錄專案顯示「純記錄」', (tester) async {
    final budgetedId = await repo.createProject(
      ledgerId: 1,
      name: '生活開銷',
      budgetAmount: 100,
      periodType: 'monthly',
    );
    final budgetedProject = await repo.getProject(budgetedId);
    await repo.addTransaction(
      ledgerId: 1,
      type: 'expense',
      amount: 30,
      happenedAt: DateTime.now(),
      projectSyncId: budgetedProject!.syncId,
    );
    await repo.createProject(ledgerId: 1, name: '純記錄專案');

    ProjectPickResult? picked;
    await tester.pumpWidget(host((r) => picked = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('生活開銷'), findsOneWidget);
    expect(find.textContaining('剩餘'), findsOneWidget);
    expect(find.textContaining('¥70'), findsOneWidget);
    expect(find.text('純記錄'), findsOneWidget);

    await tester.tap(find.text('生活開銷'));
    await tester.pumpAndSettle();
    expect(picked?.project?.name, '生活開銷');
  });
}
