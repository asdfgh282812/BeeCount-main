/// 問題 C(對標 Moze,見
/// docs/changes/2026-09-03-installment-tracking-delete-sync-fixes.md)的
/// widget 層測試:`installment_list_page.dart` 的每期列表要同時顯示本金/
/// 利息拆分(不是只有 totalAmount),卡片摘要區塊(collapse 狀態)也要有
/// 本金/利息各自的總計/已還/剩餘六個數字。
///
/// 計算邏輯本身(依 dueAt<=now 分「已還」/>now 分「剩餘」分別加總
/// principalAmount/interestAmount)沒有獨立抽成純函式(見
/// `installment_list_page.dart` 的 `_buildPrincipalInterestSummary` 註解:
/// 跟 `_openPayoff`/`transaction_detail_card.dart` 的 `_applyPayoff` 同款
/// 風格,刻意不共用),所以這裡透過整個 widget 樹渲染出來的文字驗證計算
/// 結果,而不是單獨測一個純函式。
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/installment/installment_list_page.dart';
import 'package:beecount/providers/database_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;
  late int ledgerId;
  late int categoryId;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    ledgerId = await db.into(db.ledgers).insert(LedgersCompanion.insert(
          id: const d.Value(1),
          name: 'L',
          currency: const d.Value('CNY'),
        ));
    categoryId = await repo.createCategory(name: '分期消費', kind: 'expense');
  });

  tearDown(() async => db.close());

  Ledger cnyLedger() => Ledger(
        id: ledgerId,
        name: 'L',
        currency: 'CNY',
        type: 'personal',
        createdAt: DateTime(2026, 1, 1),
        myRole: 'owner',
        memberCount: 1,
        isShared: false,
        monthStartDay: 1,
      );

  Widget host() {
    return ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentLedgerIdProvider.overrideWith((ref) => ledgerId),
        currentLedgerProvider
            .overrideWith((ref) => Stream<Ledger?>.value(cnyLedger())),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', 'TW'),
        home: const InstallmentListPage(),
      ),
    );
  }

  Future<void> pumpSettleBounded(WidgetTester tester,
      {int times = 8, Duration step = const Duration(milliseconds: 150)}) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(step);
    }
  }

  /// 建一個 4 期計畫,直接把每期的 principal/interest/total/dueAt 改成可控
  /// 的固定值(不依賴攤還演算法算出的實際數字)——前 2 期改到過去(已還),
  /// 後 2 期改到未來(剩餘),讓「總計/已還/剩餘」三組數字都可控可驗證。
  Future<void> seedControlledPlan() async {
    final planId = await repo.createInstallmentPlan(
      ledgerId: ledgerId,
      totalAmount: 460,
      periods: 4,
      firstPeriodAt: DateTime.now().add(const Duration(days: 10)),
      categoryId: categoryId,
      note: 'test-plan',
    );
    final periods = await repo.getInstallmentPeriods(planId);
    final now = DateTime.now();
    final fixtures = [
      (principal: 100.0, interest: 10.0, dueAt: now.subtract(const Duration(days: 40))),
      (principal: 100.0, interest: 10.0, dueAt: now.subtract(const Duration(days: 10))),
      (principal: 100.0, interest: 5.0, dueAt: now.add(const Duration(days: 10))),
      (principal: 100.0, interest: 5.0, dueAt: now.add(const Duration(days: 40))),
    ];
    for (var i = 0; i < periods.length; i++) {
      final f = fixtures[i];
      await (db.update(db.installmentPeriods)
            ..where((t) => t.id.equals(periods[i].id)))
          .write(InstallmentPeriodsCompanion(
        principalAmount: d.Value(f.principal),
        interestAmount: d.Value(f.interest),
        totalAmount: d.Value(f.principal + f.interest),
        dueAt: d.Value(f.dueAt),
      ));
    }
  }

  testWidgets('卡片摘要顯示本金/利息各自的總計/已還/剩餘六個數字', (tester) async {
    await seedControlledPlan();

    await tester.pumpWidget(host());
    await pumpSettleBounded(tester);

    // 本金:總計 400(100*4)・已還 200(前兩期)・剩餘 200(後兩期)。
    expect(find.textContaining('本金'), findsWidgets);
    expect(find.textContaining('總計 ¥400.00'), findsOneWidget);
    expect(find.textContaining('已還 ¥200.00'), findsOneWidget);
    expect(find.textContaining('剩餘 ¥200.00'), findsOneWidget);
    // 利息:總計 30(10+10+5+5)・已還 20(前兩期)・剩餘 10(後兩期)。
    expect(find.textContaining('總計 ¥30.00'), findsOneWidget);
    expect(find.textContaining('已還 ¥20.00'), findsOneWidget);
    expect(find.textContaining('剩餘 ¥10.00'), findsOneWidget);
  });

  testWidgets('展開卡片後每期列表同時顯示本金/利息(不是只有合計)', (tester) async {
    await seedControlledPlan();

    await tester.pumpWidget(host());
    await pumpSettleBounded(tester);

    // 點卡片標題區展開期數明細。
    await tester.tap(find.text('test-plan'));
    await pumpSettleBounded(tester);

    // 第一期:本金 100・利息 10。
    expect(find.textContaining('本金 ¥100.00・利息 ¥10.00'), findsWidgets);
    // 第三期(未到期):本金 100・利息 5。
    expect(find.textContaining('本金 ¥100.00・利息 ¥5.00'), findsWidgets);
  });
}
