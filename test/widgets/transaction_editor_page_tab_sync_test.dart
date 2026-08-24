/// 迴歸測試——切換交易編輯器的支出/收入/轉帳 tab 時,已輸入的共用欄位
/// (金額等)要同步帶到新切到的 tab,不能被重置成空白/0。
///
/// 根因(修復前):`_syncSharedFieldsOnTabChange` 是 `TabController` 的
/// listener,在 `initState` 註冊,比 `TabBarView` 自己訂閱 `_tab` 的
/// listener 還早;`ChangeNotifier` 依註冊順序同步呼叫,所以這個 method
/// 執行的當下,新切到的那個 tab 通常還沒被 `TabBarView`(內部是
/// `PageView`,鄰近分頁要等切頁動畫推進到一定進度、真的進入 cache 範圍才會
/// build 出來,不是換頁那一刻的下一幀就 mount 完成)build 出來——
/// `GlobalKey.currentState` 還是 null,`applySharedFields` 整個 no-op,
/// 分頁接著才用自己預設的空白狀態 build 出來。修法是把套用動作改成「每一幀
/// 用 `WidgetsBinding.addPostFrameCallback` 檢查一次,還沒 mount 就排下一
/// 幀繼續重試」,見 lib/pages/transaction/transaction_editor_page.dart 的
/// `_applySharedFieldsWhenReady`。
///
/// 這裡直接用 `GlobalKey`/`State` 讀寫 `exportSharedFields`/
/// `applySharedFields`(跟正式程式碼機制完全一致)來設值/驗證,不透過金額
/// 鍵盤 UI 打字——鍵盤上的數字鍵跟金額顯示本身在畫面上常常同時出現相同文字
/// (例如「0」),用 `find.text` 戳很容易撞到不只一個 widget,且鄰近分頁的
/// `AmountCalculatorKeypad` 何時被 `PageView` build 出來這件事本身跟這個
/// bug 無關,不該讓測試因為這個時機而變 flaky。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/pages/transaction/transaction_editor_page.dart';
import 'package:beecount/widgets/biz/transaction_entry_form.dart';
import 'package:beecount/widgets/transaction/debt_entry_form.dart';

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
        home: const TransactionEditorPage(initialKind: 'expense'),
      ),
    );
  }

  TransactionEntryFormState formStateFor(WidgetTester tester, String kind) {
    return tester.state<TransactionEntryFormState>(find
        .byWidgetPredicate((w) => w is TransactionEntryForm && w.kind == kind));
  }

  testWidgets('支出分頁輸入金額後切到收入 tab,金額同步帶過去(不是空白/0)', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final expenseState = formStateFor(tester, 'expense');
    expenseState.applySharedFields((
      amountStr: '600',
      amountAcc: 0,
      amountOp: null,
      date: DateTime(2026, 3, 10),
      note: '晚餐',
      merchant: '肯德基',
      tagIds: const [],
      accountId: null,
    ));
    await tester.pump();
    expect(expenseState.exportSharedFields().amountStr, '600');

    // 切到「收入分類」tab——真的透過 TabBar 點擊觸發 `_tab.index` 改變,
    // 走跟使用者操作一致的路徑(而不是直接呼叫 `_tab.animateTo`)。
    await tester.tap(find.text('收入分類'));
    // `_syncSharedFieldsOnTabChange` 在這一次 tap 造成的 setState 之後、
    // TabBarView 真的把收入分頁 build 出來之前就已經同步執行完;修法把
    // 套用動作丟進 postFrameCallback,所以要多 pump 幾次讓那一幀跟
    // callback 都跑完,再讓 `PageView` 的切頁動畫 settle。
    await tester.pumpAndSettle();

    final incomeState = formStateFor(tester, 'income');
    final incomeFields = incomeState.exportSharedFields();

    // 修復前:income 分頁沒收到套用,金額停留在自己預設的 '0'。
    expect(incomeFields.amountStr, '600');
    expect(incomeFields.note, '晚餐');
    expect(incomeFields.merchant, '肯德基');

    // 見 transaction_detail_card_edit_navigation_test.dart 同樣的說明:主動
    // 在測試本體內 dispose,才能排乾 drift stream provider dispose 時新建
    // 的一次性 Timer,避免 teardown 階段踩到 `!timersPending` 断言。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('支出分頁輸入內容後切到欠款 tab,內容同步帶過去(不再被吃進隱藏的轉帳分頁)',
      (tester) async {
    // 迴歸測試——`_applySharedFields` 原本的 switch 用 `_ => null` 當
    // default,同時吃掉 tabIndex 2(轉帳)跟 3(欠款),導致切到欠款分頁時
    // 什麼都沒拿到,反而把剛匯出的欄位誤寫進隱藏的轉帳分頁狀態。
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final expenseState = formStateFor(tester, 'expense');
    expenseState.applySharedFields((
      amountStr: '600',
      amountAcc: 0,
      amountOp: null,
      date: DateTime(2026, 3, 10),
      note: '晚餐',
      merchant: '肯德基',
      tagIds: const [],
      accountId: null,
    ));
    await tester.pump();

    await tester.tap(find.text('欠款'));
    await tester.pumpAndSettle();

    final debtState =
        tester.state<DebtEntryFormState>(find.byType(DebtEntryForm));
    final debtFields = debtState.exportSharedFields();

    // 修復前:欠款分頁完全沒收到套用,金額停留在自己預設的 '0'。
    expect(debtFields.amountStr, '600');
    expect(debtFields.note, '晚餐');
    // 商家欄位映射到欠款分頁的「對象」欄位——語意最接近。
    expect(debtFields.merchant, '肯德基');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });
}
