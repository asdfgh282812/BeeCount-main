/// 迴歸測試——`TransactionDetailCard._handleEdit` pop 卡片後,原本用卡片
/// 自己的 `ref`(來自這個 State 自己的 `ConsumerState`)去呼叫
/// `TransactionEditUtils.editTransaction`。`editTransaction` 現在會先
/// `await showRecurringEditChoiceSheet(...)` 等使用者在「此記錄/連同未來
/// 週期」二選一彈窗上做選擇——這段等待通常比卡片 pop 後的 dispose 慢,等
/// 使用者選完,卡片的 State 早就 dispose 完了,`ref.read(...)` 會直接丟
/// Riverpod 的「used after dispose」例外,整段 await 鏈沒有 try/catch,
/// 表現成「選完彈窗選項後畫面停在原地,沒有跳轉進編輯頁」。
///
/// 修法是改用呼叫端(卡片開啟前、生命週期比卡片長的)`hostRef`,不是卡片
/// 自己的 `ref`,見 lib/widgets/biz/transaction_detail_card.dart。
///
/// 這裡刻意在「選擇彈窗跳出來」和「使用者點選項」之間多 pump 幾百毫秒
/// (`pumpSettleBounded`),模擬真實裝置上使用者看到彈窗、伸手點擊之間會
/// 流逝的時間——detail card 的退場動畫在這段時間內會真的跑完並 dispose,
/// 這樣才能重現修復前的 race condition(纯粹用 `tester.tap` 立即接力不會
/// 讓時間流逝,不會踩到這個 bug)。
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
import 'package:beecount/widgets/biz/transaction_detail_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;
  late int txId;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await db.into(db.ledgers).insert(LedgersCompanion.insert(
          id: const d.Value(1),
          name: 'L',
          currency: const d.Value('CNY'),
        ));
    final categoryId = await repo.createCategory(name: '餐饮', kind: 'expense');
    await db.into(db.recurringTransactions).insert(
          RecurringTransactionsCompanion.insert(
            syncId: const d.Value('rule-1'),
            ledgerId: 1,
            type: 'expense',
            amount: 50,
            categoryId: d.Value(categoryId),
            frequency: 'monthly',
            nextRunAt: DateTime(2026, 3, 10),
          ),
        );
    txId = await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            ledgerId: 1,
            type: 'expense',
            amount: 50,
            categoryId: d.Value(categoryId),
            happenedAt: d.Value(DateTime(2026, 3, 10)),
            recurringRuleId: const d.Value('rule-1'),
          ),
        );
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

  Widget host() {
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
                await showTransactionDetailCard(context, ref, tx!, null);
              },
              child: const Text('open'),
            );
          }),
        ),
      ),
    );
  }

  /// 同 test/widgets/transfer_form_recurring_edit_test.dart 的
  /// `pumpSettleBounded`:存檔/同步鏈路裡有沒 mock 的 provider 會讓
  /// `pumpAndSettle()` 誤判「還有排程中的 frame」而超時,改用固定次數的
  /// 有界 pump。
  Future<void> pumpSettleBounded(WidgetTester tester,
      {int times = 8,
      Duration step = const Duration(milliseconds: 150)}) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(step);
    }
    // showToast/LoggerService 各自排了一個 2 秒防抖/自動關閉的真 Timer,不
    // 流掉的話會在 tearDown 被 `!timersPending` 断言判失败(同
    // transfer_form_recurring_edit_test.dart 的 pumpSettleBounded)。
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('點編輯圖示彈出選擇彈窗,等一段時間(卡片已 dispose)後選「修改此記錄」仍能正確導航進編輯頁',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    // 選擇彈窗跳出來之前,先讓 detail card 的退場動畫有機會真的跑完、
    // dispose——這段時間差就是修復前會觸發 bug 的關鍵。
    await pumpSettleBounded(tester, times: 4);

    expect(find.text('修改此記錄'), findsOneWidget);
    expect(find.text('修改連同未來週期'), findsOneWidget);

    await tester.tap(find.text('修改此記錄'));
    await pumpSettleBounded(tester);

    // 修復前:這裡選完後畫面停在原地(選擇彈窗消失,既沒有例外訊息也沒有
    // 編輯頁),下面兩個 expect 都會落空。
    expect(tester.takeException(), isNull);
    expect(find.text('支出分類'), findsOneWidget); // 編輯頁的 tab 之一
    expect(find.text('轉帳'), findsOneWidget);

    // 主動在測試本體結束前 dispose 整棵 widget tree(含 ProviderScope 底下
    // 的 drift stream provider),才能在還能 pump 的時候排乾它們 dispose
    // 時新建的一次性 Timer——否則會在 flutter_test 的 teardown 階段才觸發
    // dispose,踩到 `!timersPending` 断言(同
    // test/widget/widget_render_harness_repro_test.dart 的既有寫法)。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });
}
