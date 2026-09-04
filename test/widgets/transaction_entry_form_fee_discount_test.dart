/// v51 支出/收入手續費/折扣——`transaction_entry_form.dart` 的 UI 行為
/// (對齐 BeeCount Cloud `_compute_fee_discount_amount`)。
///
/// 覆蓋:
///   - 金額列旁的「+」展開單一面板(手續費列 + 折扣列同時顯示)。
///   - 手續費/折扣金額改用跟主金額一致的計算機鍵盤輸入(不是系統鍵盤)——
///     點金額文字才叫出鍵盤,點面板其餘區域(標籤欄、幣別徽章、空白)不會
///     誤觸叫出鍵盤,對齐使用者回饋「點到金額才跳出來」。
///   - 送出後 onSubmit 拿到正確的 baseAmount/feeAmount/feeLabel/
///     discountAmount/discountLabel,`amount` 已套用公式重算成淨額。
///   - 手續費/折扣金額為負數時擋下送出(用「-」運算子鍵組出負值,計算機鍵盤
///     本身沒有負號數字鍵)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/widgets/biz/transaction_entry_form.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;
  late int categoryId;
  late int accountId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    categoryId = await repo.createCategory(name: '餐饮', kind: 'expense');
    accountId = await repo.createAccount(
      ledgerId: 0,
      name: 'Cash',
      type: 'cash',
      currency: 'CNY',
      initialBalance: 0,
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

  Widget host({
    required TransactionSubmitCallback onSubmit,
    double? initialBaseAmount,
    double? initialFeeAmount,
    String? initialFeeLabel,
    double? initialDiscountAmount,
    String? initialDiscountLabel,
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
        locale: const Locale('zh'),
        home: Scaffold(
          body: TransactionEntryForm(
            kind: 'expense',
            initialCategoryId: categoryId,
            initialAccountId: accountId,
            initialDate: DateTime(2026, 7, 12),
            ledgerId: 1,
            onSubmit: onSubmit,
            initialBaseAmount: initialBaseAmount,
            initialFeeAmount: initialFeeAmount,
            initialFeeLabel: initialFeeLabel,
            initialDiscountAmount: initialDiscountAmount,
            initialDiscountLabel: initialDiscountLabel,
          ),
        ),
      ),
    );
  }

  testWidgets('點「+」展開手續費/折扣面板,兩列同時可見', (tester) async {
    await tester.pumpWidget(host(onSubmit: (_, __) async {}));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('feeLabelField')), findsNothing);

    final toggle = find.byKey(const Key('feeDiscountToggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('feeLabelField')), findsOneWidget);
    expect(find.byKey(const Key('feeAmountField')), findsOneWidget);
    expect(find.byKey(const Key('discountLabelField')), findsOneWidget);
    expect(find.byKey(const Key('discountAmountField')), findsOneWidget);
  });

  testWidgets(
      '輸入本金 123 + 手續費 5 + 折扣 20(手續費/折扣金額用計算機鍵盤輸入),'
      '送出後 onSubmit 拿到 amount=108(支出公式)跟正確的分量', (tester) async {
    AmountEditorResult? submittedResult;
    await tester.pumpWidget(host(onSubmit: (c, r) async {
      submittedResult = r;
    }));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('amountDisplayTap')));
    await tester.pumpAndSettle();
    // 避開 '0' 鍵:pump 前小算盤初始顯示的 "0" 文字會跟鍵盤上的 "0" 鍵撞名,
    // 見 transaction_entry_form_test.dart 的同款註解。
    await tester.ensureVisible(find.text('1'));
    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(find.text('123'), findsOneWidget);

    final toggle = find.byKey(const Key('feeDiscountToggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final feeLabelField = find.byKey(const Key('feeLabelField'));
    await tester.ensureVisible(feeLabelField);
    await tester.enterText(feeLabelField, '手續費');
    await tester.pumpAndSettle();

    // 手續費金額:點金額文字本身(不是整個面板)叫出計算機鍵盤,輸入 5。
    final feeAmountField = find.byKey(const Key('feeAmountField'));
    await tester.ensureVisible(feeAmountField);
    await tester.tap(feeAmountField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();

    final discountLabelField = find.byKey(const Key('discountLabelField'));
    await tester.ensureVisible(discountLabelField);
    await tester.enterText(discountLabelField, '折扣券');
    await tester.pumpAndSettle();

    // 折扣金額:同樣點金額文字叫出計算機鍵盤,輸入 20。
    final discountAmountField = find.byKey(const Key('discountAmountField'));
    await tester.ensureVisible(discountAmountField);
    await tester.tap(discountAmountField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2'));
    // 點完 '2' 先 pump 讓畫面重繪成 "2",不然折扣欄位還顯示初始值 "0",跟
    // 鍵盤自己的 "0" 鍵撞名(同 transaction_entry_form_test.dart 的註解)。
    await tester.pump();
    await tester.tap(find.text('0'));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    // 淨額預覽即時反映(123 + 5 - 20 = 108)。
    final l10n =
        AppLocalizations.of(tester.element(find.byType(TransactionEntryForm)));
    expect(find.text('${l10n.transactionFeeDiscountTotalLabel} 108'),
        findsOneWidget);

    // 目前小算盤還指向折扣欄位——點回主金額文字本身,把小算盤切回主金額
    // (只有指向主金額時,✓ 鍵才是「送出整張表單」,見 _AmountKeypadTarget
    // 的說明),再按 ✓ 送出。這一步同時驗證了使用者回饋的另一半:點主金額
    // 文字本身仍能精準叫回主金額鍵盤,不受下方面板高度影響。
    await tester.ensureVisible(find.text('123'));
    await tester.tap(find.text('123'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.check));
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(submittedResult?.amount, 108);
    expect(submittedResult?.baseAmount, 123);
    expect(submittedResult?.feeAmount, 5);
    expect(submittedResult?.feeLabel, '手續費');
    expect(submittedResult?.discountAmount, 20);
    expect(submittedResult?.discountLabel, '折扣券');
  });

  testWidgets('點面板空白處(標籤欄、幣別徽章)不會誤觸叫出主金額鍵盤', (tester) async {
    await tester.pumpWidget(host(onSubmit: (_, __) async {}));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('amountDisplayTap')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('1'));
    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();

    final toggle = find.byKey(const Key('feeDiscountToggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    // 收起鍵盤(點名稱欄轉走系統鍵盤焦點,連帶清掉 _amountFocused)。
    await tester.tap(find.byKey(const Key('nameField')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsNothing);

    // 點手續費列的幣別徽章(面板內的空白/非金額區域,刻意排除主金額旁邊
    // 那顆「CNY」幣別 chip——那顆本來就該保留點下去開主鍵盤的行為)。
    final panelCurrencyBadge = find.descendant(
      of: find.byKey(const Key('feeDiscountPanel')),
      matching: find.text('CNY'),
    );
    expect(panelCurrencyBadge, findsWidgets);
    await tester.tap(panelCurrencyBadge.first);
    await tester.pumpAndSettle();

    // 鍵盤仍未叫出——不是點金額文字本身,不該觸發任何一顆小算盤。
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('手續費金額組出負值時擋下送出,onSubmit 不被呼叫', (tester) async {
    var submitCalled = false;
    await tester.pumpWidget(host(onSubmit: (_, __) async {
      submitCalled = true;
    }));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('amountDisplayTap')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('1'));
    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();

    final toggle = find.byKey(const Key('feeDiscountToggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    // 計算機鍵盤沒有負號數字鍵——用「0 - 5」組出 -5,驗證 _submit() 讀到的
    // 是完整解析過運算子的 total,不是還沒按等號的原始字串。
    final feeAmountField = find.byKey(const Key('feeAmountField'));
    await tester.ensureVisible(feeAmountField);
    await tester.tap(feeAmountField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('-'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();

    // 切回主金額(讓 ✓ 鍵語意變回「送出整張表單」)再按送出。
    await tester.ensureVisible(find.text('123'));
    await tester.tap(find.text('123'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.check));
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(submitCalled, false);
  });

  testWidgets('編輯模式帶入 initialBaseAmount 時,小算盤顯示原始金額且面板已回填', (tester) async {
    await tester.pumpWidget(host(
      onSubmit: (_, __) async {},
      initialBaseAmount: 100,
      initialFeeAmount: 5,
      initialFeeLabel: '手續費',
      initialDiscountAmount: 20,
      initialDiscountLabel: '折扣券',
    ));
    await tester.pumpAndSettle();

    // 小算盤顯示 baseAmount(100),不是套用公式後的淨額。
    expect(find.text('100'), findsOneWidget);
    expect(find.byKey(const Key('feeLabelField')), findsOneWidget);
    expect(
      find.descendant(
          of: find.byKey(const Key('feeAmountField')),
          matching: find.text('5')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: find.byKey(const Key('discountAmountField')),
          matching: find.text('20')),
      findsOneWidget,
    );
  });
}
