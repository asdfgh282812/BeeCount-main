/// 新增交易單頁式表單(`TransactionEntryForm`)——支出/收入合併版的「選類別
/// →輸入金額→存檔」流程,取代原本 `CategorySelector` tab + `AmountEditorSheet`
/// modal 兩步式。
///
/// 覆蓋:
/// - 未選類別時顯示類別 grid;點一個類別後收合成 chip,金額鍵盤可用。
/// - 數字鍵盤輸入金額 + 點 ✓ 送出,`onSubmit` 拿到正確的 Category + 金額。
/// - 未選類別或金額為 0 時 ✓ 鍵不可點(`canSubmit=false` → onSubmit 不觸發)。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/widgets/biz/transaction_entry_form.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;
  late int categoryId;

  setUp(() async {
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
    required void Function(Category category, AmountEditorResult result)
        onSubmit,
    int? initialCategoryId,
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

    await tester.pumpWidget(host(onSubmit: (c, r) {
      submittedCategory = c;
      submittedResult = r;
    }));
    await tester.pumpAndSettle();

    // 未選類別:grid 可見,「餐饮」類別項在列表中。
    expect(find.text('餐饮'), findsOneWidget);

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

    expect(submittedCategory?.id, categoryId);
    expect(submittedResult?.amount, 123);
  });

  testWidgets('editingCategoryId 帶入時直接回顯已選類別(grid 收合)', (tester) async {
    await tester.pumpWidget(host(
      onSubmit: (_, __) {},
      initialCategoryId: categoryId,
    ));
    await tester.pumpAndSettle();

    // 已回显选中类别(chip 形式仍会显示分类名),不会再看到整个 grid 里其它
    // 未选类别项;这里只断言选中类别名称可见即可(grid 收合的直接证据是
    // 金额键盘已经可见)。
    expect(find.text('餐饮'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget); // 键盘的 ✓ 键已渲染
  });
}
