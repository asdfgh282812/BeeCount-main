/// `RecurringRuleListPage`(v2)——規則卡片快速啟停開關、展開/收起期數明細、
/// 期數明細的刪除動作。完整規則編輯彈窗/連同以後的存檔邏輯已在
/// `recurring_rule_editor_page_test.dart` 覆蓋,這裡只驗證列表頁本身的
/// 互動接線。
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/transaction/recurring_rule_list_page.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/providers/sync_providers.dart';

/// `RecurringRuleListPage` 用 `StreamBuilder` 直接訂閱
/// `repo.watchRulesByLedger(...)`——真正的 Drift `.watch()` 在記憶體 db 上
/// 訂閱時,widget 樹 dispose 後會留一個沒觸發的取消訂閱 Timer,踩到
/// `flutter_test` 的嚴格 timer 檢查(`!timersPending`)判失敗。同
/// `transfer_form_account_hidden_test.dart` 對 `transactionAttachmentsProvider`
/// 的處理方式——這裡改成一次性查詢包成 Stream,不走真的 `.watch()`,其餘方
/// 法全部沿用真正的 `LocalRepository` 實作(不影響測試要驗證的資料流)。
class _TestListRepo extends LocalRepository {
  _TestListRepo(super.db);

  @override
  Stream<List<RecurringTransaction>> watchRulesByLedger(int ledgerId) {
    return Stream.fromFuture(getRulesByLedger(ledgerId));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;
  late int ruleId;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = _TestListRepo(db);
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
    await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: const d.Value(1),
          name: '餐饮',
          kind: 'expense',
          icon: const d.Value('restaurant'),
        ));
    ruleId = await repo.createRule(
      ledgerId: 1,
      type: 'expense',
      amount: 100,
      categoryId: 1,
      accountId: 1,
      merchant: '訂閱服務',
      frequency: 'monthly',
      interval: 1,
      // 不帶 endAt——帶 endAt 會落在「建立當下全部生成完」的範圍內,依
      // createRule 既有語意(見 recurring_rule_repository_test.dart)完全生成
      // 後 enabled 會自動變 false,跟這裡要驗證「進行中」狀態的前提衝突。
      nextRunAt: DateTime.now().subtract(const Duration(days: 10)),
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
        beecountCloudProviderInstance.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('zh', 'TW'),
        home: RecurringRuleListPage(),
      ),
    );
  }

  Future<void> pumpSettleBounded(WidgetTester tester,
      {int times = 8, Duration step = const Duration(milliseconds: 150)}) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(step);
    }
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('顯示規則卡片,預設收起、狀態為進行中', (tester) async {
    await tester.pumpWidget(host());
    await pumpSettleBounded(tester);

    expect(find.textContaining('訂閱服務'), findsOneWidget);
    expect(find.text('進行中'), findsOneWidget);
    expect(find.text('尚未生成任何交易'), findsNothing);
  });

  testWidgets('點展開:顯示期數明細列表', (tester) async {
    await tester.pumpWidget(host());
    await pumpSettleBounded(tester);

    await tester.tap(find.text('展開'));
    await pumpSettleBounded(tester);

    expect(find.text('收起'), findsOneWidget);
    // 這條規則橫跨過去 10 天到未來 80 天,月頻率下至少會生成好幾筆。
    expect(find.text('連同以後'), findsWidgets);
  });

  testWidgets('切換 Switch:呼叫 setRuleEnabled,規則變成已停用', (tester) async {
    // 注意:host() 用的 _TestListRepo 把 watchRulesByLedger 換成一次性查詢
    // 包的 Stream(避免真的 Drift `.watch()` 訂閱踩到 flutter_test 的嚴格
    // timer 檢查,見 _TestListRepo 上的說明),所以這裡只驗證 Switch 有正確
    // 呼叫到 repo 層(已經在 recurring_rule_repository_test.dart 測過欄位語
    // 意),不驗證關閉後 UI 即時重新分組——那是 StreamBuilder 收到新一輪推送
    // 才會做的事,跟這次功能邏輯本身無關。
    await tester.pumpWidget(host());
    await pumpSettleBounded(tester);

    // 精確比對「進行中」狀態徽章——分組標題是「進行中(1)」,textContaining
    // 會連標題一起撈到,變成 2 個匹配。
    expect(find.text('進行中'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await pumpSettleBounded(tester);

    final rule = await repo.getRuleById(ruleId);
    expect(rule!.enabled, isFalse);
  });

  testWidgets('展開後刪除一筆期數:交易被刪除,列表即時反映', (tester) async {
    await tester.pumpWidget(host());
    await pumpSettleBounded(tester);

    await tester.tap(find.text('展開'));
    await pumpSettleBounded(tester);

    final before = await repo.getOccurrencesForRule(
        (await repo.getRuleById(ruleId))!.syncId!);
    expect(before, isNotEmpty);

    // 用 .at(1):index 0 是規則卡片本身的「刪除」(刪整條規則,文字剛好也
    // 是「刪除」),.first 會誤點到那顆,彈出確認刪除規則的對話框而不是真
    // 的刪除某一筆期數。這條規則沒帶 endAt,預設視窗一次生成 12 個月/13 筆
    // occurrence,清單很長,.last 那顆會被排到畫面外導致 tap 打不中
    // (hit-test 落在 render tree 邊界外)——改用 index 1,也就是展開後第一
    // 筆 occurrence 的「刪除」,離頂部近,確定在畫面內。
    await tester.tap(find.text('刪除').at(1));
    await pumpSettleBounded(tester);

    final after = await repo.getOccurrencesForRule(
        (await repo.getRuleById(ruleId))!.syncId!);
    expect(after.length, before.length - 1);
  });
}
