/// `AccountOverviewChartPage`(資產管理頁「走勢」全螢幕圖表頁)的 smoke test:
/// 頁面能開啟、標題正確、空資料時顯示空狀態、有資料時能切換統計區間。互動
/// 組合圖(OverviewComboChart)拖曳選點的數字正確性已在
/// test/utils/overview_chart_utils_test.dart 用純函式覆蓋,這裡不重複驗證。
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/account/account_overview_chart_page.dart';
import 'package:beecount/providers/database_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(LocalRepository repo) => ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh', 'TW'),
          home: AccountOverviewChartPage(),
        ),
      );

  testWidgets('空账本:显示标题,资料不足显示空状态文案,不崩溃', (tester) async {
    final db = BeeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LocalRepository(db);

    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();

    expect(find.text('收支與淨值走勢'), findsOneWidget);
    expect(find.text('暫無資料'), findsWidgets);
  });

  testWidgets('有資料時顯示統計區間按鈕,點擊彈出統計區間選單', (tester) async {
    final db = BeeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LocalRepository(db);
    final accId = await db.into(db.accounts).insert(AccountsCompanion.insert(
        ledgerId: 1,
        name: '现金',
        type: const d.Value('cash'),
        initialBalance: const d.Value(1000)));
    final now = DateTime.now();
    for (int i = 0; i < 8; i++) {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
          ledgerId: 1,
          type: 'expense',
          amount: 50,
          accountId: d.Value(accId),
          happenedAt: d.Value(DateTime(now.year, now.month, now.day - i))));
    }

    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();

    expect(find.text('按日'), findsOneWidget);
    await tester.tap(find.text('按日'));
    await tester.pumpAndSettle();
    expect(find.text('統計區間'), findsOneWidget);
    expect(find.text('按週'), findsOneWidget);
    expect(find.text('按月'), findsOneWidget);
    expect(find.text('按年'), findsOneWidget);
  });
}
