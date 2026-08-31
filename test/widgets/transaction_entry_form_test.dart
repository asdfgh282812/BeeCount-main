/// 新增交易單頁式表單(`TransactionEntryForm`)——支出/收入合併版的「選類別
/// →輸入金額→存檔」流程,取代原本 `CategorySelector` tab + `AmountEditorSheet`
/// modal 兩步式。
///
/// 覆蓋:
/// - 未選類別時顯示類別 grid;點一個類別後收合成 chip,金額鍵盤可用。
/// - 數字鍵盤輸入金額 + 點 ✓ 送出,`onSubmit` 拿到正確的 Category + 金額。
/// - 未選類別或金額為 0 時 ✓ 鍵不可點(`canSubmit=false` → onSubmit 不觸發)。
/// - 跨幣別帳戶選擇 + 換算對話框雙向編輯(docs/superpowers/specs/
///   2026-08-28-cross-currency-account-picker-design.md 子專案 A)。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers/currency_providers.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/services/currency/rate_math.dart';
import 'package:beecount/widgets/biz/transaction_entry_form.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;
  late int categoryId;

  setUp(() async {
    // 每个 test 独立的 db 都从 id=1 起算,SharedPreferences mock 若不逐 test
    // 重置,前一个 test 写入的 'default_expense_account_id' 之类的 key 会跟
    // 这个 test 的账户 id 撞上,污染 _loadDefaultAccount() 的自动选取结果。
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    categoryId = await repo.createCategory(name: '餐饮', kind: 'expense');
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
    int? initialCategoryId,
    List<Override> extraOverrides = const [],
  }) {
    return ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentLedgerProvider
            .overrideWith((ref) => Stream<Ledger?>.value(cnyLedger())),
        ...extraOverrides,
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: TransactionEntryForm(
            kind: 'expense',
            initialCategoryId: initialCategoryId,
            initialDate: DateTime(2026, 7, 12),
            ledgerId: 1,
            onSubmit: onSubmit,
          ),
        ),
      ),
    );
  }

  testWidgets('未選類別顯示 grid;點類別後收合,輸入金額+送出觸發 onSubmit', (tester) async {
    Category? submittedCategory;
    AmountEditorResult? submittedResult;

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

    // 未選類別:grid 可見,「餐饮」類別項在列表中。
    expect(find.text('餐饮'), findsOneWidget);

    // 小算盤現在只在點金額欄位後才顯示(見 amountDisplayTap),先叫出來。
    await tester.tap(find.byKey(const Key('amountDisplayTap')));
    await tester.pumpAndSettle();

    // ✓ 鍵此时不可点(没有类别 + 金额为 0)。
    await tester.ensureVisible(find.byIcon(Icons.check));
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(submittedCategory, isNull);

    await tester.ensureVisible(find.text('餐饮'));
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();

    // 输入 123
    await tester.ensureVisible(find.text('1'));
    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();

    expect(find.text('123'), findsOneWidget);

    await tester.ensureVisible(find.byIcon(Icons.check));
    await tester.tap(find.byIcon(Icons.check));
    // 不用 pumpAndSettle:提交后 _isSubmitting=true 会渲染一个不确定态
    // CircularProgressIndicator(在生产代码里页面会被立刻 pop 掉、这里没有
    // 上层导航所以它会一直转),indeterminate 动画永远不「settle」,pump 一帧
    // 就足够让本次 tap 的同步回调(onSubmit)跑完。
    await tester.pump();
    // repo.createAccount 内部 logger.debug 起了一个 2s 节流保存计时器(见
    // LoggerService._saveLogs),不是 frame-scheduled,pumpAndSettle 逮不到——
    // 手动推进时钟让它触发+清理,避免 "Timer still pending" 断言炸测试
    // (同样的模式见 test/widgets/card_reward_rule_actions_test.dart)。
    await tester.pump(const Duration(seconds: 3));

    expect(submittedCategory?.id, categoryId);
    expect(submittedResult?.amount, 123);
  });

  testWidgets('editingCategoryId 帶入時直接回顯已選類別(grid 收合)', (tester) async {
    await tester.pumpWidget(host(
      onSubmit: (_, __) async {},
      initialCategoryId: categoryId,
    ));
    await tester.pumpAndSettle();

    // 已回显选中类别(chip 形式仍会显示分类名),不会再看到整个 grid 里其它
    // 未选类别项;这里只断言选中类别名称可见即可。
    expect(find.text('餐饮'), findsOneWidget);

    // 小算盤只在點金額欄位後才顯示,點一下確認鍵盤(含 ✓ 鍵)正確渲染。
    await tester.tap(find.byKey(const Key('amountDisplayTap')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsOneWidget); // 键盘的 ✓ 键已渲染
  });

  testWidgets('沒有帳戶時送出被擋下,onSubmit 不會被呼叫', (tester) async {
    var submitCalled = false;
    await tester.pumpWidget(host(onSubmit: (_, __) async {
      submitCalled = true;
    }));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('餐饮'));
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('amountDisplayTap')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('1'));
    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byIcon(Icons.check));
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();
    // _submit() 被挡下时会走 showToast,起一个 2s Future.delayed 自动消失的
    // 计时器,不是 frame-scheduled,pumpAndSettle 逮不到——手动推进时钟让它
    // 触发+清理,避免 "Timer still pending" 断言炸测试。
    await tester.pump(const Duration(seconds: 3));

    expect(submitCalled, false);
  });

  testWidgets('選外幣帳戶後換算預覽隨時可點,編輯換算金額後 nativeAmount 反映新結果', (tester) async {
    await repo.createAccount(
      ledgerId: 0,
      name: '日元户',
      type: 'bank_card',
      currency: 'JPY',
      initialBalance: 0,
    );

    AmountEditorResult? submittedResult;
    await tester.pumpWidget(host(
      onSubmit: (c, r) async {
        submittedResult = r;
      },
      extraOverrides: [
        effectiveRatesForLedgerProvider.overrideWith((ref) async =>
            {'JPY': const EffectiveRate(rate: '0.05', manual: false)}),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('餐饮'));
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('amountDisplayTap')));
    await tester.pumpAndSettle();

    // 輸入金額 123(避開 0,keypad 的 "0" 鍵在還沒 pump 前跟初始顯示的 "0"
    // 文字會撞名,tap 會因為「找到兩個」而炸掉)。
    await tester.ensureVisible(find.text('1'));
    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();

    // 帳戶選擇器不再依幣別過濾:能選到跟帳本本位幣(CNY)不同的日元帳戶。
    await tester.ensureVisible(find.byIcon(Icons.credit_card));
    await tester.tap(find.byIcon(Icons.credit_card));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日元户'));
    await tester.pumpAndSettle();

    final l10n =
        AppLocalizations.of(tester.element(find.byType(TransactionEntryForm)));

    // 有線上匯率(非缺失)時換算預覽依然可點開編輯——本次改動前只有匯率
    // 缺失時才可點。
    final previewText = l10n.txConvertedPreview('6.15', 'CNY');
    expect(find.text(previewText), findsOneWidget);
    await tester.ensureVisible(find.text(previewText));
    await tester.tap(find.text(previewText));
    await tester.pumpAndSettle();

    expect(find.text(l10n.txConvertDialogTitle), findsOneWidget);

    // 關閉「採用線上匯率」開關後兩欄位才能手動編輯。
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final convertedField = find
        .descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField))
        .first;
    await tester.enterText(convertedField, '30');
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.commonConfirm));
    await tester.pumpAndSettle();

    // 換算預覽反映新輸入的換算金額(123 × (30/123) ≈ 30.00)。
    expect(find.text(l10n.txConvertedPreview('30.00', 'CNY')), findsOneWidget);

    await tester.ensureVisible(find.byIcon(Icons.check));
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(submittedResult?.currencyCode, 'JPY');
    expect(submittedResult?.nativeAmount, closeTo(30.0, 0.01));
  });

  testWidgets('換算對話框內編輯匯率欄位即時更新換算金額欄位,反之亦然', (tester) async {
    await repo.createAccount(
      ledgerId: 0,
      name: '日元户',
      type: 'bank_card',
      currency: 'JPY',
      initialBalance: 0,
    );

    await tester.pumpWidget(host(
      onSubmit: (_, __) async {},
      extraOverrides: [
        effectiveRatesForLedgerProvider.overrideWith((ref) async =>
            {'JPY': const EffectiveRate(rate: '0.05', manual: false)}),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('餐饮'));
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('amountDisplayTap')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('1'));
    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byIcon(Icons.credit_card));
    await tester.tap(find.byIcon(Icons.credit_card));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日元户'));
    await tester.pumpAndSettle();

    final l10n =
        AppLocalizations.of(tester.element(find.byType(TransactionEntryForm)));
    await tester
        .ensureVisible(find.text(l10n.txConvertedPreview('6.15', 'CNY')));
    await tester.tap(find.text(l10n.txConvertedPreview('6.15', 'CNY')));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    final convertedField = fields.first;
    final rateField = fields.at(1);

    // 編輯「匯率」欄位 → 換算金額即時更新(amount=123,rate=0.1 → 12.30)。
    await tester.enterText(rateField, '0.1');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(convertedField).controller!.text, '12.30');

    // 編輯「換算金額」欄位 → 匯率反推更新(30 / 123 ≈ 0.243902)。
    await tester.enterText(convertedField, '30');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(rateField).controller!.text,
        (30 / 123).toStringAsPrecision(6));
  });

  testWidgets('名稱欄位聚焦時鍵盤上方顯示歷史備註建議,點選後填入且保留焦點', (tester) async {
    await repo.addTransaction(
      ledgerId: 1,
      type: 'expense',
      amount: 20,
      categoryId: categoryId,
      note: '午餐',
      happenedAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(host(
      onSubmit: (_, __) async {},
      initialCategoryId: categoryId,
    ));
    await tester.pumpAndSettle();

    // 尚未聚焦名稱欄位:建議條不出現。
    expect(find.text('午餐'), findsNothing);

    await tester.tap(find.byKey(const Key('nameField')));
    await tester.pumpAndSettle();

    // 聚焦後,鍵盤上方直接跳出建議 chip(比照 moze),不需要另外點時鐘圖示。
    expect(find.text('午餐'), findsOneWidget);

    await tester.tap(find.text('午餐'));
    await tester.pumpAndSettle();

    final nameField =
        tester.widget<TextField>(find.byKey(const Key('nameField')));
    expect(nameField.controller!.text, '午餐');
    // 選完後鍵盤保留(焦點沒被收起),建議條應該還在。
    expect(find.byKey(const Key('nameField')), findsOneWidget);
    expect(nameField.focusNode!.hasFocus, isTrue);
  });
}
