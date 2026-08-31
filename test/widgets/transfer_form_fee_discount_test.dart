/// v46 轉帳手續費/折損 — transfer_form.dart 的 UI 行为(design doc
/// docs/superpowers/specs/2026-08-29-transfer-fee-discount-design.md §4):
///   - 代入餘額箭頭點擊後,對應金額欄位被正確填值。
///   - 同幣別轉帳、未啟用轉入側折損/未按過代入箭頭時,轉入金額區塊維持隱藏。
///   - 按過轉入側代入箭頭後,轉入金額區塊出現,折損面板可以展開。
///   - 送出後 repo.addTransaction 收到正確的 feeAmount/feeLabel/
///     discountAmount/discountLabel。
///   - discountAmount 超過轉入金額時跳出驗證錯誤,無法送出。
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
import 'package:beecount/widgets/transaction/transfer_form.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'TWD')");
    await db.customStatement("INSERT INTO accounts "
        "(id, ledger_id, name, currency, initial_balance) "
        "VALUES (1, 1, '現金', 'TWD', 5000)");
    await db.customStatement("INSERT INTO accounts "
        "(id, ledger_id, name, currency, initial_balance) "
        "VALUES (2, 1, '銀行', 'TWD', 3000)");
    // 預先建好「转账」分类,避免 _submit() 走到
    // LocalCategoryRepository.getTransferCategory 的兜底创建分支(那条分支
    // 会连带一个 2 秒防抖存档 Timer,同款注释见
    // transfer_form_recurring_edit_test.dart)。
    await db.into(db.categories).insert(CategoriesCompanion.insert(
          name: '转账',
          kind: 'transfer',
          icon: const d.Value('swap_horiz'),
          sortOrder: const d.Value(-1),
        ));
  });

  tearDown(() async => db.close());

  Ledger twdLedger() => Ledger(
        id: 1,
        name: 'L',
        currency: 'TWD',
        type: 'personal',
        createdAt: DateTime(2026, 1, 1),
        myRole: 'owner',
        memberCount: 1,
        isShared: false,
        monthStartDay: 1,
      );

  Widget host({int? fromId, int? toId, double? initialAmount}) {
    return ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentLedgerProvider
            .overrideWith((ref) => Stream<Ledger?>.value(twdLedger())),
        allAccountStatsProvider.overrideWith((ref) async => {
              1: (balance: 5000.0, expense: 0.0, income: 0.0),
              2: (balance: 3000.0, expense: 0.0, income: 0.0),
            }),
        beecountCloudProviderInstance.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', 'TW'),
        home: Scaffold(
          body: TransferForm(
            onTransferComplete: () {},
            initialFromAccountId: fromId,
            initialToAccountId: toId,
            initialAmount: initialAmount,
          ),
        ),
      ),
    );
  }

  /// 同款有界 pump,見 transfer_form_cross_currency_test.dart 的
  /// `pumpSettleBounded` 注釋(PostProcessor.sync 持續請求新 frame 會讓
  /// `pumpAndSettle()` 誤判逾時)。
  Future<void> pumpSettleBounded(WidgetTester tester,
      {int times = 8,
      Duration step = const Duration(milliseconds: 150)}) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(step);
    }
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('代入餘額箭頭點擊後,對應金額欄位被正確填值', (tester) async {
    await tester.pumpWidget(host(fromId: 1, toId: 2));
    await tester.pumpAndSettle();

    final arrows = find.byIcon(Icons.arrow_circle_down_outlined);
    expect(arrows, findsNWidgets(2)); // 轉出/轉入各一個

    // 點轉出側箭頭 → 計算機式金額顯示 5000。
    await tester.tap(arrows.at(0));
    await tester.pumpAndSettle();
    expect(find.text('5000'), findsOneWidget);

    // 點轉入側箭頭 → 轉入金額區塊出現,欄位值 = 轉入帳戶餘額 3000。
    final toAmountField = find.byKey(const Key('transferToAmountField'));
    expect(toAmountField, findsNothing);
    await tester.tap(arrows.at(1));
    await tester.pumpAndSettle();
    expect(toAmountField, findsOneWidget);
    final field = tester.widget<TextField>(toAmountField);
    expect(field.controller?.text, '3000');
    expect(field.enabled, isTrue); // _toAmountManuallySet=true → 可編輯
  });

  testWidgets('同幣別轉帳、未按過代入箭頭/未啟用折損時,轉入金額區塊維持隱藏', (tester) async {
    await tester.pumpWidget(host(fromId: 1, toId: 2, initialAmount: 200));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('transferToAmountField')), findsNothing);
    final l10n = AppLocalizations.of(
        tester.element(find.byType(TransferForm)));
    expect(find.byTooltip(l10n.transferAddDiscountButton), findsNothing);
  });

  testWidgets('按過轉入側代入箭頭後,折損面板可以展開並顯示唯讀計算結果', (tester) async {
    await tester.pumpWidget(host(fromId: 1, toId: 2, initialAmount: 200));
    await tester.pumpAndSettle();

    // 先按轉入側代入箭頭,讓區塊出現。
    await tester.tap(find.byIcon(Icons.arrow_circle_down_outlined).at(1));
    await tester.pumpAndSettle();

    final discountToggle = find.byKey(const Key('transferDiscountToggle'));
    expect(discountToggle, findsOneWidget);
    await tester.tap(discountToggle);
    await tester.pumpAndSettle();

    // 折損面板出現:標籤欄位 + 金額欄位。
    expect(find.byKey(const Key('transferDiscountLabelField')),
        findsOneWidget);
    expect(find.byKey(const Key('transferDiscountAmountField')),
        findsOneWidget);
  });

  testWidgets('送出後 repo.addTransaction 收到正確的 feeAmount/feeLabel/discountAmount/discountLabel',
      (tester) async {
    await tester.pumpWidget(host(fromId: 1, toId: 2, initialAmount: 200));
    await tester.pumpAndSettle();

    // 開啟轉出側手續費面板(面板/键盘会让下方内容位移甚至滚出可视区,先
    // `ensureVisible` 避免 tap/enterText 落空)。
    final feeToggle = find.byKey(const Key('transferFeeToggle'));
    await tester.ensureVisible(feeToggle);
    await tester.tap(feeToggle);
    await tester.pumpAndSettle();
    final feeLabelField = find.byKey(const Key('transferFeeLabelField'));
    await tester.ensureVisible(feeLabelField);
    await tester.enterText(feeLabelField, '跨行手續費');
    await tester.pumpAndSettle();
    final feeAmountField = find.byKey(const Key('transferFeeAmountField'));
    await tester.ensureVisible(feeAmountField);
    await tester.enterText(feeAmountField, '10');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    // 開啟轉入側折損面板(需先按代入箭頭讓區塊出現)。
    final toArrow = find.byIcon(Icons.arrow_circle_down_outlined).at(1);
    await tester.ensureVisible(toArrow);
    await tester.tap(toArrow);
    await tester.pumpAndSettle();
    final discountToggle = find.byKey(const Key('transferDiscountToggle'));
    await tester.ensureVisible(discountToggle);
    await tester.tap(discountToggle);
    await tester.pumpAndSettle();
    final discountLabelField =
        find.byKey(const Key('transferDiscountLabelField'));
    await tester.ensureVisible(discountLabelField);
    await tester.enterText(discountLabelField, '到帳折損');
    await tester.pumpAndSettle();
    final discountAmountField =
        find.byKey(const Key('transferDiscountAmountField'));
    await tester.ensureVisible(discountAmountField);
    await tester.enterText(discountAmountField, '5');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    final amountDisplay = find.byKey(const Key('amountDisplayTap'));
    await tester.ensureVisible(amountDisplay);
    await tester.tap(amountDisplay);
    await tester.pumpAndSettle();
    final submitButton = find.byIcon(Icons.check);
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await pumpSettleBounded(tester);

    final txs = await db.select(db.transactions).get();
    expect(txs, hasLength(1));
    expect(txs.single.feeAmount, 10);
    expect(txs.single.feeLabel, '跨行手續費');
    expect(txs.single.discountAmount, 5);
    expect(txs.single.discountLabel, '到帳折損');
  });

  testWidgets('discountAmount 超過轉入金額時跳出驗證錯誤,無法送出', (tester) async {
    await tester.pumpWidget(host(fromId: 1, toId: 2, initialAmount: 200));
    await tester.pumpAndSettle();

    final l10n =
        AppLocalizations.of(tester.element(find.byType(TransferForm)));

    // 按代入箭頭讓區塊出現(順帶把轉入金額欄位填成轉入帳戶餘額 3000,不是
    // 轉帳金額 200)——手動改回 200,測試「折損不能讓轉入金額變負數」時才是
    // 針對這筆轉帳實際的轉入金額,不是帳戶餘額。
    final toArrow = find.byIcon(Icons.arrow_circle_down_outlined).at(1);
    await tester.ensureVisible(toArrow);
    await tester.tap(toArrow);
    await tester.pumpAndSettle();
    final toAmountField = find.byKey(const Key('transferToAmountField'));
    await tester.ensureVisible(toAmountField);
    await tester.enterText(toAmountField, '200');
    await tester.pumpAndSettle();
    final discountToggle = find.byKey(const Key('transferDiscountToggle'));
    await tester.ensureVisible(discountToggle);
    await tester.tap(discountToggle);
    await tester.pumpAndSettle();
    final discountAmountField =
        find.byKey(const Key('transferDiscountAmountField'));
    await tester.ensureVisible(discountAmountField);
    await tester.enterText(discountAmountField, '999');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    final amountDisplay = find.byKey(const Key('amountDisplayTap'));
    await tester.ensureVisible(amountDisplay);
    await tester.tap(amountDisplay);
    await tester.pumpAndSettle();
    final submitButton = find.byIcon(Icons.check);
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(l10n.transferDiscountExceedsAmountError), findsOneWidget);
    final txs = await db.select(db.transactions).get();
    expect(txs, isEmpty);

    // showToast 內部有個 2 秒後自動移除 overlay 的 Future.delayed,測試結束前
    // 要讓它跑完,否則 flutter_test 會斷言「還有 pending timer」。
    await tester.pump(const Duration(seconds: 3));
  });
}
