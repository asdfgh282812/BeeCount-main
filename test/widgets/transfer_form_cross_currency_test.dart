/// v45 跨幣別轉帳 — transfer_form.dart 的 UI 行为(design doc
/// docs/superpowers/specs/2026-08-29-cross-currency-transfers-design.md §3):
///   - 轉出/轉入帳戶幣別不同時,顯示轉入金額區塊;送出後 toAmount 非 null。
///   - 同幣別轉帳送出時 toAmount 為 null(即使使用者曾經選過又改回同幣別帳戶,
///     也不殘留舊的 toAmount 狀態)。
///   - 轉入金額欄位手動編輯後,匯率顯示列即時更新。
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
        "(id, ledger_id, name, currency) VALUES (1, 1, '玉山熊本熊', 'JPY')");
    await db.customStatement("INSERT INTO accounts "
        "(id, ledger_id, name, currency) VALUES (2, 1, '永豐大戶', 'TWD')");
    await db.customStatement("INSERT INTO accounts "
        "(id, ledger_id, name, currency) VALUES (3, 1, '台幣戶2', 'TWD')");
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
        allAccountStatsProvider.overrideWith((ref) async => {}),
        // TxAuthorService 会 watch 这个 provider 判断是否共享账本;不 mock 的话
        // 测试环境里永远 resolve 不了,存档流程会卡住(同款注释见
        // transfer_form_recurring_edit_test.dart)。
        beecountCloudProviderInstance.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
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

  /// `PostProcessor.sync` 存檔後會經由 syncServiceProvider 鏈路碰到一個持續
  /// 請求新 frame 的來源,導致 `pumpAndSettle()` 誤判「還有排程中的 frame」而
  /// 超時。改用有界 pump,同款寫法/注釋見
  /// transfer_form_recurring_edit_test.dart 的 `pumpSettleBounded`。
  Future<void> pumpSettleBounded(WidgetTester tester,
      {int times = 8,
      Duration step = const Duration(milliseconds: 150)}) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(step);
    }
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('選不同幣別的轉出/轉入帳戶後,轉入金額區塊出現;送出後 toAmount 非 null', (tester) async {
    await tester.pumpWidget(host(fromId: 1, toId: 2, initialAmount: 4711));
    await tester.pumpAndSettle();

    // 跨幣別 → 轉入金額欄位出現(不是同幣別時的 SizedBox.shrink)。
    final toAmountField = find.byKey(const Key('transferToAmountField'));
    expect(toAmountField, findsOneWidget);

    // 線上匯率查無資料(測試環境沒有網路),關掉「採用線上匯率」開關手動輸入。
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.enterText(toAmountField, '999.87');
    await tester.pumpAndSettle();
    // 欄位聚焦時比照名稱/商家欄位收起底部小算盤(含送出鍵),需要先收起鍵盤
    // /取消聚焦,才摸得到送出鍵——這是既有設計(見 `_textFieldFocused`),
    // 不是新引入的行為。
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    // 匯率顯示列應該反映 999.87 / 4711。
    final rateText = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((s) => s.contains('JPY') && s.contains('TWD'))
        .toList();
    expect(rateText, isNotEmpty);

    await tester.tap(find.byIcon(Icons.check));
    await pumpSettleBounded(tester);

    final txs = await db.select(db.transactions).get();
    expect(txs, hasLength(1));
    expect(txs.single.toAmount, 999.87);
    expect(txs.single.amount, 4711);
  });

  testWidgets(
      '轉出帳戶是帳本本位幣(TWD)、轉入是外幣(JPY)時,線上匯率也能正確自動換算'
      '(回歸:修正前 rates 查詢方向錯誤,這個方向永遠顯示查無匯率)', (tester) async {
    // 帳本本位幣 TWD,rates['JPY'] = 「1 JPY = 5 TWD」。
    await repo.upsertAutoRates(
      base: 'TWD',
      rateDate: '2026-08-29',
      rates: {'JPY': '5'},
      source: 'test',
      fetchedAt: DateTime.utc(2026, 8, 29),
    );

    // fromId=2(永豐大戶,TWD=本位幣) → toId=1(玉山熊本熊,JPY)。
    await tester.pumpWidget(host(fromId: 2, toId: 1, initialAmount: 600));
    await tester.pumpAndSettle();

    // 預設「採用線上匯率」開啟,不用手動操作,600 TWD / 5 應該自動算出 120 JPY。
    final toAmountField = find.byKey(const Key('transferToAmountField'));
    expect(toAmountField, findsOneWidget);
    final field = tester.widget<TextField>(toAmountField);
    expect(field.controller?.text, '120.00');

    await tester.tap(find.byIcon(Icons.check));
    await pumpSettleBounded(tester);

    final txs = await db.select(db.transactions).get();
    expect(txs, hasLength(1));
    expect(txs.single.toAmount, closeTo(120.0, 1e-9));
    expect(txs.single.amount, 600);
  });

  testWidgets('同幣別轉帳送出時 toAmount 為 null(即使曾經選過跨幣別帳戶又改回同幣別)', (tester) async {
    await tester.pumpWidget(host(fromId: 2, toId: 3, initialAmount: 200));
    await tester.pumpAndSettle();

    // 同幣別 → 沒有轉入金額欄位。
    expect(find.byKey(const Key('transferToAmountField')), findsNothing);

    await tester.tap(find.byIcon(Icons.check));
    await pumpSettleBounded(tester);

    final txs = await db.select(db.transactions).get();
    expect(txs, hasLength(1));
    expect(txs.single.toAmount, isNull);
    expect(txs.single.amount, 200);
  });
}
