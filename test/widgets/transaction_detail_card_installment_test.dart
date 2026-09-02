/// 子專案 3(退款流程 + 交易明細頁「編輯選擇」對話框整合)的 widget 層測試。
///
/// 涵蓋設計文件 §5.3 的兩個對話框,透過 `showTransactionDetailCard` 整條路徑
/// 驗證(不是只測對話框本身回傳值):
/// - `InstallmentEditChoiceDialog` 四個選項各自正確導向
///   `updatePeriodOverride`/`rebalanceFrom`/`earlyRepayPrincipal`/`payoff`
///   ——取代子專案 1 唯讀鎖定 banner 後,點編輯圖示應該彈出這個選擇對話框,
///   而不是被攔下或直接進編輯頁。
/// - `InstallmentPeriodRefundChoiceDialog` 二選一:「只退這一期」呼叫
///   `refundPeriod`;「整筆退款」呼叫既有的 `deleteInstallmentPlan`。
///
/// Repository 層的計算細節(本金池/清零閾值等)已經在
/// test/repositories/local/installment_repository_test.dart 覆蓋過,這裡
/// 只驗證 UI 選擇 → 正確的 repository 呼叫這條路徑接得上。
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/installment_repository.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/widgets/biz/transaction_detail_card.dart';

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

  Widget host({required int txId}) {
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
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) {
            return ElevatedButton(
              onPressed: () async {
                final tx = await repo.getTransactionById(txId);
                await showTransactionDetailCard(context, ref, tx!, null);
              },
              child: const Text('open'),
            );
          }),
        ),
      ),
    );
  }

  /// 同 transaction_detail_card_edit_navigation_test.dart /
  /// transaction_edit_utils_delete_guarded_test.dart 的既有寫法:同步/
  /// toast 鏈路上有沒 mock 的 provider 時 `pumpAndSettle()` 會誤判成「還有
  /// 排程中的 frame」而超時,改用固定次數的有界 pump,最後再多流 3 秒排掉
  /// showToast 的自動關閉 Timer。
  Future<void> pumpSettleBounded(WidgetTester tester,
      {int times = 8,
      Duration step = const Duration(milliseconds: 150)}) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(step);
    }
    await tester.pump(const Duration(seconds: 3));
  }

  Future<int> createThreePeriodPlan({int? accountId}) {
    // firstPeriodAt 刻意用「現在 + 10 天」而不是寫死日期——
    // earlyRepayPrincipal/payoff/rebalanceFrom 都依賴「還有未到期的期數」
    // 才有意義,寫死的過去日期在測試跑的當下(現在日期會隨時間往前走)可能
    // 全部期數都已經過去,讓 earlyRepayPrincipal 合法地拋
    // 「超過剩餘本金」(因為可分配本金池已經是 0),不是這裡要測的東西。
    return repo.createInstallmentPlan(
      ledgerId: ledgerId,
      totalAmount: 300,
      periods: 3,
      firstPeriodAt: DateTime.now().add(const Duration(days: 10)),
      accountId: accountId,
      categoryId: categoryId,
    );
  }

  /// 分期的選擇彈窗/操作 sheet(4 選項 + 取消,或帶預覽區塊的 PayoffSheet)
  /// 內容比 recurring 的 2 選項彈窗高,預設測試視窗(600 高)裝不下,會在
  /// `showModalBottomSheet` 內部的 `DraggableScrollableSheet` 佈局時 overflow
  /// 幾個像素——同 test/widgets/calendar_month_jump_test.dart 的既有作法,
  /// 换一個更高的測試視窗即可,不代表真實裝置上有 UI 問題(真實手機螢幕
  /// 遠高於 600 邏輯像素)。
  Future<void> growViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> disposeCleanly(WidgetTester tester) async {
    // 主動在測試結束前把整棵 widget tree(含 ProviderScope 底下的 drift
    // stream provider)dispose 掉,才能在還能 pump 的時候排乾它們新建的
    // 一次性 Timer——否則會在 flutter_test 的 teardown 階段才觸發 dispose,
    // 踩到 `!timersPending` 断言(同 transaction_detail_card_edit_navigation_test.dart)。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  }

  group('InstallmentEditChoiceDialog', () {
    testWidgets('點編輯圖示彈出四選一對話框(取代唯讀鎖定 banner)', (tester) async {
      await growViewport(tester);
      final planId = await createThreePeriodPlan();
      final periods = await repo.getInstallmentPeriods(planId);
      final txId = periods.first.txId!;

      await tester.pumpWidget(host(txId: txId));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await pumpSettleBounded(tester, times: 4);

      expect(find.text('修改此記錄'), findsOneWidget);
      expect(find.text('修改連同未來'), findsOneWidget);
      expect(find.text('提前還本'), findsOneWidget);
      expect(find.text('提前繳清'), findsOneWidget);

      await disposeCleanly(tester);
    });

    testWidgets('選「修改此記錄」→ updatePeriodOverride:period 標記 overridden',
        (tester) async {
      await growViewport(tester);
      final planId = await createThreePeriodPlan();
      final periods = await repo.getInstallmentPeriods(planId);
      final target = periods.first;

      await tester.pumpWidget(host(txId: target.txId!));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await pumpSettleBounded(tester, times: 4);

      await tester.tap(find.text('修改此記錄'));
      await pumpSettleBounded(tester, times: 4);

      // PeriodOverrideSheet 三個欄位都已用目前值預填,直接按確認。
      await tester.tap(find.text('確定'));
      await pumpSettleBounded(tester);

      final updated = (await repo.getInstallmentPeriods(planId))
          .firstWhere((p) => p.id == target.id);
      expect(updated.status, kInstallmentPeriodStatusOverridden);

      await disposeCleanly(tester);
    });

    testWidgets('選「修改連同未來」→ rebalanceFrom 成功執行(顯示成功提示)', (tester) async {
      await growViewport(tester);
      final planId = await createThreePeriodPlan();
      final periods = await repo.getInstallmentPeriods(planId);
      final target = periods.first;

      await tester.pumpWidget(host(txId: target.txId!));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await pumpSettleBounded(tester, times: 4);

      await tester.tap(find.text('修改連同未來'));
      await pumpSettleBounded(tester, times: 4);

      await tester.tap(find.text('確定'));
      // Toast 有固定的自動關閉 Timer,要在它消失前檢查文字有沒有出現——
      // 跟 transaction_edit_utils_delete_guarded_test.dart 的既有寫法一樣,
      // 不能先用 pumpSettleBounded(累積超過 toast 的存活時間)才檢查。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final l10n =
          AppLocalizations.of(tester.element(find.byType(ElevatedButton)));
      expect(find.text(l10n.installmentRebalanceSuccess), findsOneWidget,
          reason: 'rebalanceFrom 完成後應該顯示成功 toast(卡片已關閉)');

      await pumpSettleBounded(tester);

      await disposeCleanly(tester);
    });

    testWidgets('選「提前還本」→ earlyRepayPrincipal:建立一筆部分還本交易', (tester) async {
      await growViewport(tester);
      final planId = await createThreePeriodPlan();
      final periods = await repo.getInstallmentPeriods(planId);
      final target = periods.first;

      await tester.pumpWidget(host(txId: target.txId!));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await pumpSettleBounded(tester, times: 4);

      await tester.tap(find.text('提前還本'));
      await pumpSettleBounded(tester, times: 4);

      // EarlyRepayPrincipalSheet 的金額欄位沒有預填,要手動輸入。
      await tester.enterText(find.byType(TextField).first, '50');
      await tester.tap(find.text('確定'));
      await pumpSettleBounded(tester);

      final repayTxs = await (db.select(db.transactions)
            ..where((t) => t.note.equals('分期部分還本')))
          .get();
      expect(repayTxs, hasLength(1));
      expect(repayTxs.first.amount, 50);

      await disposeCleanly(tester);
    });

    testWidgets('選「提前繳清」→ payoff:計畫標記 settled', (tester) async {
      await growViewport(tester);
      final planId = await createThreePeriodPlan();
      final periods = await repo.getInstallmentPeriods(planId);
      final target = periods.first;

      await tester.pumpWidget(host(txId: target.txId!));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await pumpSettleBounded(tester, times: 4);

      await tester.tap(find.text('提前繳清'));
      await pumpSettleBounded(tester, times: 4);

      await tester.tap(find.text('確定'));
      await pumpSettleBounded(tester);

      final plan = (await repo.getInstallmentPlan(planId))!;
      expect(plan.status, kInstallmentPlanStatusSettled);

      await disposeCleanly(tester);
    });
  });

  group('InstallmentPeriodRefundChoiceDialog', () {
    testWidgets('選「只退這一期」→ refundPeriod:期數標記 refunded、產生退款交易', (tester) async {
      await growViewport(tester);
      final planId = await createThreePeriodPlan();
      final periods = await repo.getInstallmentPeriods(planId);
      final target = periods.first;

      await tester.pumpWidget(host(txId: target.txId!));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.replay));
      await pumpSettleBounded(tester, times: 4);

      expect(find.text('只退這一期'), findsOneWidget);
      expect(find.text('整筆退款'), findsOneWidget);

      await tester.tap(find.text('只退這一期'));
      await pumpSettleBounded(tester, times: 4);

      // InstallmentPeriodRefundSheet 的金額欄位已用該期 totalAmount 預填。
      await tester.tap(find.text('確定'));
      await pumpSettleBounded(tester);

      final updated = (await repo.getInstallmentPeriods(planId))
          .firstWhere((p) => p.id == target.id);
      expect(updated.status, kInstallmentPeriodStatusRefunded);

      final originalTx = (await repo.getTransactionById(target.txId!))!;
      final refundTxs = await repo.getRefundsOf(originalTx.syncId!);
      expect(refundTxs, hasLength(1));
      expect(refundTxs.first.installmentPlanSyncId, isNull,
          reason: '退款交易不應該打 installmentPlanSyncId(§3.3 的關鍵要求)');

      await disposeCleanly(tester);
    });

    testWidgets('選「整筆退款」→ 二次確認後呼叫 deleteInstallmentPlan(計畫連交易一併消失)',
        (tester) async {
      await growViewport(tester);
      final planId = await createThreePeriodPlan();
      final periods = await repo.getInstallmentPeriods(planId);
      final target = periods.first;

      await tester.pumpWidget(host(txId: target.txId!));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.replay));
      await pumpSettleBounded(tester, times: 4);

      await tester.tap(find.text('整筆退款'));
      await pumpSettleBounded(tester, times: 4);

      // 破壞性操作二次確認(AppDialog.confirm,跟 installment_list_page.dart
      // 刪除計畫同一套 pattern)——先確認彈窗真的出現,再點確認鍵。
      final l10n =
          AppLocalizations.of(tester.element(find.byType(ElevatedButton)));
      expect(find.text(l10n.installmentRefundWholePlanConfirmTitle),
          findsOneWidget);

      await tester.tap(find.text(l10n.commonConfirm));
      await pumpSettleBounded(tester);

      expect(await repo.getInstallmentPlan(planId), isNull);
      final txsAfter = await (db.select(db.transactions)
            ..where((t) => t.installmentPlanSyncId.equals('nonexistent')))
          .get();
      expect(txsAfter, isEmpty);
      final allTxs = await db.select(db.transactions).get();
      expect(allTxs, isEmpty, reason: '整筆退款連同全部分期交易一起刪除');

      await disposeCleanly(tester);
    });
  });
}
