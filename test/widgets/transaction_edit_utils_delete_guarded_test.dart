/// `TransactionEditUtils.deleteTransactionGuarded` 的 widget 層測試。
///
/// 問題 A 修正(2026-09-03,見
/// docs/changes/2026-09-03-installment-tracking-delete-sync-fixes.md)之前,
/// 這裡涵蓋的是子專案 2「刪除攔截邊界」——`installmentPlanSyncId != null`
/// 一律攔下、顯示「請去分期頁操作」提示。問題 A 把這個行為改成:
/// - plan 已不存在(孤兒,整筆刪除計畫後偶爾殘留的情境)→ 直接放行一般刪除,
///   不再顯示任何提示。
/// - plan 還存在 → 彈「只刪除這一筆 / 刪除整個分期計畫」二選一(靜默/批量
///   場景 `showFeedback: false` 維持舊行為,不彈窗、直接跳過)。
/// - 一般(非分期)交易透過同一入口刪除不受影響。
///
/// repo 內部狀態變更操作(earlyRepayPrincipal/payoff/terminateFuture...)
/// 能正常刪除分期期數交易、不受此攔截影響——這件事已經在
/// test/repositories/local/installment_repository_test.dart 的
/// 「deleteTransaction 攔截分期交易」群組驗證過,這裡不重複。
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/utils/transaction_edit_utils.dart';

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
          name: 'L',
          currency: const d.Value('CNY'),
        ));
    categoryId = await repo.createCategory(name: '餐饮', kind: 'expense');
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

  Widget host(
    void Function(bool result) onResult, {
    required int txId,
    bool showFeedback = true,
  }) {
    return ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentLedgerProvider
            .overrideWith((ref) => Stream<Ledger?>.value(cnyLedger())),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', 'TW'),
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) {
            return ElevatedButton(
              onPressed: () async {
                final tx = await repo.getTransactionById(txId);
                final result =
                    await TransactionEditUtils.deleteTransactionGuarded(
                        context, ref, tx!,
                        showFeedback: showFeedback);
                onResult(result);
              },
              child: const Text('delete'),
            );
          }),
        ),
      ),
    );
  }

  Future<void> pumpSettleBounded(WidgetTester tester,
      {int times = 6,
      Duration step = const Duration(milliseconds: 150)}) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(step);
    }
    // showToast 排了一個防抖/自動關閉的真 Timer,不流掉的話 tearDown 會因為
    // 還有 pending timer 斷言失敗(同 transaction_detail_card_edit_navigation_test.dart)。
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('plan 已不存在(孤兒):直接放行,不顯示任何提示,交易被刪除',
      (tester) async {
    final planId = await repo.createInstallmentPlan(
      ledgerId: ledgerId,
      totalAmount: 300,
      periods: 3,
      firstPeriodAt: DateTime.utc(2026, 1, 1),
      categoryId: categoryId,
    );
    final periods = await repo.getInstallmentPeriods(planId);
    final txId = periods.first.txId!;
    final periodId = periods.first.id;

    // 模擬「整筆刪除計畫後殘留孤兒」的情境——直接刪 plan 本身,繞過
    // deleteInstallmentPlan(那個方法會連帶刪光 period/交易)。
    await (db.delete(db.installmentPlans)..where((t) => t.id.equals(planId)))
        .go();

    bool? result;
    await tester.pumpWidget(host((r) => result = r, txId: txId));
    await tester.pumpAndSettle();

    await tester.tap(find.text('delete'));
    await pumpSettleBounded(tester);

    expect(result, isTrue);
    final gone = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingleOrNull();
    expect(gone, isNull);
    final periodGone = await (db.select(db.installmentPeriods)
          ..where((t) => t.id.equals(periodId)))
        .getSingleOrNull();
    expect(periodGone, isNull, reason: '孤兒 period 應該一併清掉');
  });

  testWidgets('plan 還存在、showFeedback=true:彈二選一,選「只刪除這一筆」呼叫 deletePeriod',
      (tester) async {
    final planId = await repo.createInstallmentPlan(
      ledgerId: ledgerId,
      totalAmount: 300,
      periods: 3,
      firstPeriodAt: DateTime.utc(2026, 1, 1),
      categoryId: categoryId,
    );
    final periods = await repo.getInstallmentPeriods(planId);
    final txId = periods.first.txId!;

    bool? result;
    await tester.pumpWidget(host((r) => result = r, txId: txId));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.text('delete')));
    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.installmentDeleteChoiceThisRecordOnly), findsOneWidget,
        reason: '應該彈出二選一對話框,而不是舊的「去分期頁操作」提示');
    await tester.tap(find.text(l10n.installmentDeleteChoiceThisRecordOnly));
    await pumpSettleBounded(tester);

    expect(result, isTrue);
    final txGone = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingleOrNull();
    expect(txGone, isNull);
    // 其餘 2 期不受影響。
    final remaining = await repo.getInstallmentPeriods(planId);
    expect(remaining, hasLength(2));
  });

  testWidgets('plan 還存在、showFeedback=true:選「刪除整個分期計畫」二次確認後呼叫 deleteInstallmentPlan',
      (tester) async {
    final planId = await repo.createInstallmentPlan(
      ledgerId: ledgerId,
      totalAmount: 300,
      periods: 3,
      firstPeriodAt: DateTime.utc(2026, 1, 1),
      categoryId: categoryId,
    );
    final periods = await repo.getInstallmentPeriods(planId);
    final txId = periods.first.txId!;

    bool? result;
    await tester.pumpWidget(host((r) => result = r, txId: txId));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.text('delete')));
    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.installmentDeleteChoiceWholePlan));
    await tester.pumpAndSettle();

    // 二次確認彈窗。
    expect(find.text(l10n.installmentDeleteWholePlanConfirmTitle), findsOneWidget);
    await tester.tap(find.text(l10n.commonConfirm));
    await pumpSettleBounded(tester);

    expect(result, isTrue);
    expect(await repo.getInstallmentPlan(planId), isNull);
    expect(await repo.getInstallmentPeriods(planId), isEmpty);
  });

  testWidgets('plan 還存在、showFeedback=false(靜默/批量場景):維持舊行為,不彈窗、直接跳過',
      (tester) async {
    final planId = await repo.createInstallmentPlan(
      ledgerId: ledgerId,
      totalAmount: 300,
      periods: 3,
      firstPeriodAt: DateTime.utc(2026, 1, 1),
      categoryId: categoryId,
    );
    final periods = await repo.getInstallmentPeriods(planId);
    final txId = periods.first.txId!;

    bool? result;
    await tester.pumpWidget(
        host((r) => result = r, txId: txId, showFeedback: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('delete'));
    await pumpSettleBounded(tester);

    expect(result, isFalse);
    final stillThere = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingleOrNull();
    expect(stillThere, isNotNull, reason: '批量場景被跳過的分期交易不應該被刪除');
  });

  testWidgets('一般(非分期)交易正常刪除:回傳 true、交易被刪除', (tester) async {
    final txId = await repo.addTransaction(
      ledgerId: ledgerId,
      type: 'expense',
      amount: 50,
      categoryId: categoryId,
      happenedAt: DateTime.utc(2026, 1, 1),
    );

    bool? result;
    await tester.pumpWidget(host((r) => result = r, txId: txId));
    await tester.pumpAndSettle();

    await tester.tap(find.text('delete'));
    await pumpSettleBounded(tester);

    expect(result, isTrue);
    final gone = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingleOrNull();
    expect(gone, isNull);
  });
}
