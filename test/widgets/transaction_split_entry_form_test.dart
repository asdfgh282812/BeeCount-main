/// v38 拆帳(split into multiple categories)在 `TransactionEntryForm` 裡的
/// 端對端流程:選第一個分類 → 輸入金額 → 點拆帳圖示 → 選第二個分類(彈出
/// `CategorySelectorDialog`)→ 輸入第二筆金額 → 送出,`onSubmit` 拿到的
/// `AmountEditorResult.splits` 應該是兩筆明細、金額對得上。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/widgets/biz/transaction_entry_form.dart';
import 'package:beecount/widgets/biz/amount_calculator_keypad.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;
  late int foodId;
  late int clothId;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    foodId = await repo.createCategory(name: '餐饮', kind: 'expense');
    clothId = await repo.createCategory(name: '衣物', kind: 'expense');
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

  Widget host({required TransactionSubmitCallback onSubmit}) {
    return ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentLedgerProvider
            .overrideWith((ref) => Stream<Ledger?>.value(cnyLedger())),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // zh(简体)的 app_zh.arb 已不再维护新 key(见 l10n 政策备忘),新增的
        // txSplit* 只进了 app_en.arb / app_zh_TW.arb,这里用 zh_TW 才能断言
        // 到真正的翻译文字,而不是英文 fallback。
        locale: const Locale('zh', 'TW'),
        home: Scaffold(
          body: TransactionEntryForm(
            kind: 'expense',
            initialDate: DateTime(2026, 7, 12),
            ledgerId: 1,
            onSubmit: onSubmit,
          ),
        ),
      ),
    );
  }

  // '0' 在鍵盤上跟「金額顯示區目前也顯示 0」的文字會撞名,find.text('0')
  // 在金額為 0 時是歧義的;一律限定在 AmountCalculatorKeypad 這個 widget
  // 子樹裡找數字鍵,避免點到金額顯示區(不可點,點了也沒反應但會讓測試
  // 誤以為成功)。
  Future<void> tapDigits(WidgetTester tester, String digits) async {
    final keypad = find.byType(AmountCalculatorKeypad);
    for (final ch in digits.split('')) {
      await tester.tap(find.descendant(of: keypad, matching: find.text(ch)));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('選類別→輸入金額→拆帳→選第二分類→輸入金額→送出,splits 正確', (tester) async {
    Category? submittedCategory;
    AmountEditorResult? submittedResult;

    // 記帳表單現在必填帳戶(見 2026-08-22 交易必須選擇帳戶功能),setUp()
    // 沒建帳戶會讓 _selectedAccountId 一直是 null、送出被擋下。這裡建一個
    // 帳戶並設成預設支出帳戶,讓 _loadDefaultAccount() 能自動選上,不影響
    // 這個測試本來要驗證的拆帳邏輯。
    final accountId = await repo.createAccount(
      ledgerId: 0,
      name: 'Cash',
      type: 'cash',
      currency: 'CNY',
      initialBalance: 0,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('default_expense_account_id', accountId);

    await tester.pumpWidget(host(onSubmit: (c, r) async {
      submittedCategory = c;
      submittedResult = r;
    }));
    await tester.pumpAndSettle();

    // 選第一個分類「餐饮」
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();

    // 小算盤現在只在點金額欄位後才顯示,先叫出來。
    await tester.tap(find.byKey(const Key('amountDisplayTap')));
    await tester.pumpAndSettle();

    // 輸入 100
    await tapDigits(tester, '100');
    expect(find.text('100'), findsOneWidget);

    // 點拆帳圖示,開啟分類選單(排除已選的「餐饮」,只剩「衣物」可選)
    await tester.tap(find.byIcon(Icons.call_split));
    await tester.pumpAndSettle();
    expect(find.text('衣物'), findsOneWidget);
    await tester.tap(find.text('衣物'));
    await tester.pumpAndSettle();

    // 拆帳模式:圖示條顯示彙總 + 兩筆明細 + 新增鍵
    expect(find.text('多類別'), findsOneWidget);
    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('衣物'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);

    // 第二筆(衣物,目前焦點)金額還是 0,送出鍵應被擋下
    await tester.ensureVisible(find.byIcon(Icons.check));
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();
    expect(submittedCategory, isNull);

    // 輸入第二筆金額 40
    await tapDigits(tester, '40');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byIcon(Icons.check));
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();

    expect(submittedResult, isNotNull);
    expect(submittedResult!.amount, 140); // 100(餐饮) + 40(衣物)
    final splits = submittedResult!.splits;
    expect(splits, isNotNull);
    expect(splits!.length, 2);
    expect(splits[0].categoryId, foodId);
    expect(splits[0].amount, 100);
    expect(splits[1].categoryId, clothId);
    expect(splits[1].amount, 40);
  });
}
