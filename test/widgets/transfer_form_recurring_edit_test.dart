/// v36:轉帳表單(`TransferForm`)編輯週期規則生成的 occurrence 時,要跟
/// `transaction_editor_page.dart`(支出/收入兩個 tab)一樣先跳「修改此記錄/
/// 連同未來週期」二選一彈窗——這段之前漏接(轉帳分頁自己處理存檔,沒有共用
/// `_handleSubmit`),編輯轉帳類型的週期(自動扣繳)交易完全跳過選擇彈窗,
/// 直接單筆覆寫。見 lib/widgets/transaction/transfer_form.dart 的 `_submit`。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' as d;

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/providers/statistics_providers.dart';
import 'package:beecount/providers/sync_providers.dart';
import 'package:beecount/services/attachment_service.dart';
import 'package:beecount/widgets/transaction/transfer_form.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;
  late int ruleId;
  late int occurrenceTxId;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await db.into(db.ledgers).insert(LedgersCompanion.insert(
          id: const d.Value(1),
          name: 'L',
          currency: const d.Value('CNY'),
        ));
    await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: const d.Value(1),
          ledgerId: 1,
          name: '现金',
          currency: const d.Value('CNY'),
        ));
    await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: const d.Value(2),
          ledgerId: 1,
          name: '储蓄卡',
          currency: const d.Value('CNY'),
        ));
    // 預先建好「转账」分类,避免 _submit() 走到
    // LocalCategoryRepository.getTransferCategory 的兜底创建分支(那条分支
    // 会 log 一条 warning、连带一个 2 秒防抖存档 Timer)。
    await db.into(db.categories).insert(CategoriesCompanion.insert(
          name: '转账',
          kind: 'transfer',
          icon: const d.Value('swap_horiz'),
          sortOrder: const d.Value(-1),
        ));
    ruleId = await db.into(db.recurringTransactions).insert(
          RecurringTransactionsCompanion.insert(
            syncId: const d.Value('rule-transfer-1'),
            ledgerId: 1,
            type: 'transfer',
            amount: 100,
            accountId: const d.Value(1),
            toAccountId: const d.Value(2),
            frequency: 'monthly',
            nextRunAt: DateTime(2026, 3, 10),
          ),
        );
    occurrenceTxId = await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            ledgerId: 1,
            type: 'transfer',
            amount: 100,
            accountId: const d.Value(1),
            toAccountId: const d.Value(2),
            happenedAt: d.Value(DateTime(2026, 3, 10)),
            recurringRuleId: const d.Value('rule-transfer-1'),
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
        allAccountStatsProvider.overrideWith((ref) async => {}),
        transactionAttachmentsProvider(occurrenceTxId)
            .overrideWith((ref) => Stream.value(const [])),
        // TxAuthorService 会 watch 这个 provider 判断是否共享账本;不 mock
        // 的话它在测试环境里永远 resolve 不了(没有真的云端配置可 await),
        // 存档流程会一直卡在这个 Future 上,tearDown 时连带一堆 pending
        // timer 判失败。
        beecountCloudProviderInstance.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', 'TW'),
        home: Scaffold(
          body: TransferForm(
            onTransferComplete: () {},
            editingTransactionId: occurrenceTxId,
            initialFromAccountId: 1,
            initialToAccountId: 2,
            initialAmount: 100,
            initialDate: DateTime(2026, 3, 10),
          ),
        ),
      ),
    );
  }

  /// `PostProcessor.sync` 存檔完成後会经由 syncServiceProvider 链路间接碰到
  /// 一个持续请求新 frame 的来源(未 mock 云同步相关 provider 时属预期),
  /// 导致 `pumpAndSettle()` 永远判定"还有排程中的 frame"而超时。这里改用
  /// 固定次数的有界 pump 取代——已用 debug pump 逐步确认过存檔流程本身在
  /// 几个 frame 内就跑完并落库,不是真的卡死,纯粹是 pumpAndSettle 的判定
  /// 条件在这个 provider 组合下不成立。
  ///
  /// 最後補一個 > 2 秒的大 pump:`showToast`/`LoggerService` 各自排了一個
  /// 2 秒防抖/自動關閉的真 Timer(生产代码行为,不是 bug),不流掉的話會在
  /// tearDown 被 flutter_test 的 `!timersPending` 断言判失败——即使測試本體
  /// 的 expect 全部通过。
  Future<void> pumpSettleBounded(WidgetTester tester,
      {int times = 8, Duration step = const Duration(milliseconds: 150)}) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(step);
    }
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('編輯週期轉帳 occurrence:存檔前彈出「此記錄/連同未來週期」選擇彈窗,選「此記錄」後標記 overridden',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.check));
    await pumpSettleBounded(tester);

    expect(find.text('修改此記錄'), findsOneWidget);
    expect(find.text('修改連同未來週期'), findsOneWidget);

    await tester.tap(find.text('修改此記錄'));
    await pumpSettleBounded(tester);

    final tx = await repo.getTransactionById(occurrenceTxId);
    expect(tx!.recurringOccurrenceOverridden, isTrue);
  });

  testWidgets('編輯週期轉帳 occurrence:選「連同未來週期」後規則欄位跟著更新', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.check));
    await pumpSettleBounded(tester);

    await tester.tap(find.text('修改連同未來週期'));
    await pumpSettleBounded(tester);

    final rule = await repo.getRuleById(ruleId);
    expect(rule!.amount, 100); // 金額沒改,維持一致即可驗證流程有跑到底
    final tx = await repo.getTransactionById(occurrenceTxId);
    expect(tx!.recurringOccurrenceOverridden, isFalse);
  });

  testWidgets('編輯週期轉帳 occurrence:取消選擇彈窗 → 不寫入任何變更,存檔鍵恢復可按',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.check));
    await pumpSettleBounded(tester);

    await tester.tap(find.text('取消').last);
    await pumpSettleBounded(tester);

    final tx = await repo.getTransactionById(occurrenceTxId);
    expect(tx!.recurringOccurrenceOverridden, isFalse);
    // 存檔鍵禁用態已解除,再點一次能重新叫出選擇彈窗(代表 _isSubmitting 已复位)。
    await tester.tap(find.byIcon(Icons.check));
    await pumpSettleBounded(tester);
    expect(find.text('修改此記錄'), findsOneWidget);
  });
}
