/// `RecurringRuleEditorPage`——規則列表頁「編輯」入口新增的獨立規則編輯頁
/// (v2)。覆蓋:欄位回填、存檔時走 anchor 為 null 的
/// `updateRuleAndFuture`(批次套用到未來未 overridden 的 occurrence,已
/// overridden 的不受影響),以及帶 `anchorTransactionId`(「連同以後」入口)
/// 時只影響 anchor 之後的期數。
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/transaction/recurring_rule_editor_page.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/providers/statistics_providers.dart';
import 'package:beecount/providers/sync_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;

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
    await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: const d.Value(1),
          name: '餐饮',
          kind: 'expense',
          icon: const d.Value('restaurant'),
        ));
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

  Widget host({required RecurringTransaction rule, int? anchorTransactionId}) {
    return ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentLedgerProvider
            .overrideWith((ref) => Stream<Ledger?>.value(cnyLedger())),
        beecountCloudProviderInstance.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', 'TW'),
        home: RecurringRuleEditorPage(
          rule: rule,
          anchorTransactionId: anchorTransactionId,
        ),
      ),
    );
  }

  /// 同 transfer_form_recurring_edit_test.dart 的既知坑:存檔會經
  /// PostProcessor.sync 碰到沒 mock 的雲同步 provider 鏈,`pumpAndSettle()`
  /// 判定「還有排程中的 frame」永遠不會 settle;showToast/LoggerService 各自
  /// 有 2 秒防抖/自動關閉的真 Timer,不流掉會讓 tearDown 判 pending timer
  /// 失敗。改用固定次數的有界 pump。
  Future<void> pumpSettleBounded(WidgetTester tester,
      {int times = 8, Duration step = const Duration(milliseconds: 150)}) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(step);
    }
    await tester.pump(const Duration(seconds: 3));
  }

  Future<int> createRuleWithOccurrences() async {
    final ruleId = await repo.createRule(
      ledgerId: 1,
      type: 'expense',
      amount: 100,
      categoryId: 1,
      accountId: 1,
      merchant: '原商家',
      frequency: 'monthly',
      interval: 1,
      nextRunAt: DateTime.now().subtract(const Duration(days: 70)),
      endAt: DateTime.now().add(const Duration(days: 130)),
    );
    return ruleId;
  }

  testWidgets('欄位回填:金額/商家顯示既有規則的值', (tester) async {
    final ruleId = await createRuleWithOccurrences();
    final rule = (await repo.getRuleById(ruleId))!;

    await tester.pumpWidget(host(rule: rule));
    await tester.pumpAndSettle();

    expect(find.text('100'), findsOneWidget);
    final merchantField = tester
        .widget<TextField>(find.byKey(const Key('recurringEditorMerchantField')));
    expect(merchantField.controller!.text, '原商家');
  });

  testWidgets('編輯規則(anchorTransactionId 為 null):存檔套用到未來未 overridden 的期數,'
      '已 overridden 的不受影響', (tester) async {
    final ruleId = await createRuleWithOccurrences();
    final rule = (await repo.getRuleById(ruleId))!;
    final occurrences = await repo.getOccurrencesForRule(rule.syncId!);
    final now = DateTime.now();
    final futureOnes =
        occurrences.where((t) => t.happenedAt.isAfter(now)).toList();
    expect(futureOnes.length, greaterThan(1));
    // 把其中一筆未來期數標記為單獨編輯過——批次更新應該跳過它。
    await repo.updateOccurrence(transactionId: futureOnes[0].id, amount: 1);

    await tester.pumpWidget(host(rule: rule));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('recurringEditorAmountField')), '250');
    await tester.pump();
    await tester.tap(find.text('儲存'));
    await pumpSettleBounded(tester);

    // 確認彈窗跳出來,點確認。
    expect(find.text('套用到未來交易？'), findsOneWidget);
    await tester.tap(find.text('確定'));
    await pumpSettleBounded(tester);

    final updatedRule = await repo.getRuleById(ruleId);
    expect(updatedRule!.amount, 250, reason: '規則本身要更新');

    final overriddenAfter = await repo.getTransactionById(futureOnes[0].id);
    expect(overriddenAfter!.amount, 1, reason: '已單獨編輯過的期數不受批次更新影響');

    for (final t in futureOnes.skip(1)) {
      final after = await repo.getTransactionById(t.id);
      expect(after!.amount, 250, reason: '未來、未 overridden 的期數要被批次更新');
    }
  });

  testWidgets('連同以後(anchorTransactionId 非 null):只影響 anchor 當天起的期數',
      (tester) async {
    final ruleId = await createRuleWithOccurrences();
    final rule = (await repo.getRuleById(ruleId))!;
    final occurrences = await repo.getOccurrencesForRule(rule.syncId!);
    // 選中間某一筆當 anchor。
    final anchorIndex = occurrences.length ~/ 2;
    final anchor = occurrences[anchorIndex];

    await tester.pumpWidget(
        host(rule: rule, anchorTransactionId: anchor.id));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('recurringEditorAmountField')), '300');
    await tester.pump();
    await tester.tap(find.text('儲存'));
    await pumpSettleBounded(tester);
    await tester.tap(find.text('確定'));
    await pumpSettleBounded(tester);

    for (var i = 0; i < anchorIndex; i++) {
      final t = await repo.getTransactionById(occurrences[i].id);
      expect(t!.amount, 100, reason: 'anchor 之前的期數不受影響');
    }
    for (var i = anchorIndex; i < occurrences.length; i++) {
      final t = await repo.getTransactionById(occurrences[i].id);
      expect(t!.amount, 300, reason: 'anchor 當天起的期數要被更新');
    }
  });
}
