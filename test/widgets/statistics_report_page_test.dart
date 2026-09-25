// 統計報表頁冒煙測試:清單頁 → 報表頁,10 個分頁都能渲染、上一期可切換。
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/statistics/statistics_report_list_page.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/providers/sync_providers.dart';
import 'package:beecount/widgets/biz/account_avatar.dart';
import 'package:beecount/widgets/biz/transaction_list.dart';
import 'package:beecount/widgets/statistics/share_bar_row.dart';
import 'package:beecount/widgets/ui/capsule_switcher.dart';

String _ym() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await db.into(db.ledgers).insert(LedgersCompanion.insert(
          id: const d.Value(1),
          name: 'L',
          currency: const d.Value('CNY'),
        ));
  });

  tearDown(() async => db.close());

  Ledger ledger() => Ledger(
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

  testWidgets('清單 → 每月報表,10 個分頁都能開', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final food = await repo.createCategory(name: '餐饮', kind: 'expense');
      final salary = await repo.createCategory(name: '薪资', kind: 'income');
      final acc = await repo.createAccount(ledgerId: 1, name: '現金');
      final tag = await repo.createTag(name: '出差');
      final now = DateTime.now();
      final t = await repo.addTransaction(
          ledgerId: 1,
          type: 'expense',
          amount: 120,
          categoryId: food,
          accountId: acc,
          merchant: '全聯',
          note: '午餐',
          happenedAt: DateTime(now.year, now.month, now.day, 8));
      await repo.addTagsToTransaction(transactionId: t, tagIds: [tag]);
      await repo.addTransaction(
          ledgerId: 1,
          type: 'income',
          amount: 5000,
          categoryId: salary,
          accountId: acc,
          happenedAt: DateTime(now.year, now.month, now.day, 7));
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentLedgerProvider
            .overrideWith((ref) => Stream<Ledger?>.value(ledger())),
        beecountCloudProviderInstance.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', 'TW'),
        home: const StatisticsReportListPage(),
      ),
    ));

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester
            .runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await settle();
    expect(find.text('每月報表'), findsOneWidget);
    expect(find.text('每週報表'), findsOneWidget);

    await tester.tap(find.text('每月報表'));
    await settle();
    await tester.pump(const Duration(milliseconds: 400));
    await settle();

    // 總覽
    expect(find.text('TOP 3 支出'), findsOneWidget);
    expect(find.text('午餐'), findsWidgets);

    for (final tab in [
      '明細',
      '類別',
      '排行',
      '帳戶',
      '專案',
      '帳戶分組',
      '名稱',
      '商家',
      '標籤和對象',
    ]) {
      await tester.ensureVisible(find.widgetWithText(Tab, tab));
      await tester.pump();
      await tester.tap(find.widgetWithText(Tab, tab));
      await tester.pump(const Duration(milliseconds: 400));
      await settle();
      expect(tester.takeException(), isNull, reason: '分頁 $tab 渲染失敗');
      if (tab == '明細') {
        // 列表跟著上方切換:支出只列支出,收入只列收入,結餘全列
        List<String> listed() => tester
            .widget<TransactionList>(find.byType(TransactionList))
            .transactions!
            .map((v) => v.t.type)
            .toList();
        await tester.pump(const Duration(seconds: 1));
        expect(listed(), ['expense']);
        for (final (label, types) in [
          ('收入', ['income']),
          ('結餘', ['expense', 'income']),
          ('支出', ['expense']),
        ]) {
          await tester.tap(find.descendant(
              of: find.byType(CapsuleSwitcher<String>),
              matching: find.text(label)));
          await tester.pump(const Duration(milliseconds: 300));
          await settle();
          expect(listed(), types, reason: '明細切到 $label');
        }
      }
    }
    expect(find.text('出差'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(ShareBarRow), matching: find.byType(Icon)),
        findsNothing,
        reason: '標籤/對象是純文字維度,不加圖標');

    await tester.ensureVisible(find.widgetWithText(Tab, '帳戶'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(Tab, '帳戶'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle();
    expect(find.text('現金'), findsOneWidget);
    expect(find.byType(AccountAvatar), findsWidgets, reason: '帳戶用資產頁的頭像');

    // 支出/收入/轉帳/回饋金切換都能渲染(回饋金會非同步估算)
    for (final flow in ['收入', '轉帳', '回饋金', '支出']) {
      await tester.tap(find.text(flow).first);
      await tester.pump(const Duration(milliseconds: 300));
      await settle();
      expect(tester.takeException(), isNull, reason: '切到 $flow 失敗');
    }
    expect(find.text('現金'), findsOneWidget);

    // 支出頁點帳戶 → 下鑽只算支出(收入 5000 那筆不會混進來)
    await tester.tap(find.text('現金'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle();
    expect(find.text('${_ym()} · 支出'), findsOneWidget);
    expect(find.text('支出 '), findsOneWidget, reason: '表頭只顯示支出合計');
    expect(find.text('收入 '), findsNothing, reason: '收入 5000 不該混進支出下鑽');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await settle();
    expect(find.text('${_ym()} · 支出'), findsNothing, reason: '已返回報表頁');

    // 上一期:本月的交易不在上個月
    await tester.tap(find.byIcon(Icons.chevron_left));
    await settle();
    expect(find.text('現金'), findsNothing);
  });
}
