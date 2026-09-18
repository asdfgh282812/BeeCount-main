/// `BillCardWidget` 商家/回饋顯示(design 2026-09-18 §6)。
///
/// 覆蓋:
/// - `billInfo.merchant` 非空時顯示「商家」列。
/// - 落庫交易掛了 `rewardRuleIds` 時顯示「回饋」列,格式「規則名稱 (比例%)」。
/// - 沒有回饋規則 / 已撤銷時,「回饋」列不顯示。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/ai/core/bill_info.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/widgets/ai/bill_card_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;
  late int ledgerId;
  late int accountId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    ledgerId = await repo.createLedger(name: '测试账本');
    accountId = await repo.createAccount(
      ledgerId: ledgerId,
      name: '信用卡',
      type: 'credit_card',
    );
  });

  tearDown(() async => db.close());

  Widget host(Widget child) {
    return ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', 'TW'),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  testWidgets('商家非空時顯示商家列', (tester) async {
    final billInfo = BillInfo(
      amount: -30,
      time: DateTime(2026, 5, 26),
      category: '餐饮',
      merchant: '星巴克',
    );

    await tester.pumpWidget(host(BillCardWidget(billInfo: billInfo)));
    await tester.pumpAndSettle();

    expect(find.text('星巴克'), findsOneWidget);
  });

  testWidgets('交易掛了回饋規則時顯示回饋列', (tester) async {
    final ruleId = await repo.createCardRewardRule(
      accountId: accountId,
      label: '網購5%回饋',
      rateType: 'percentage',
      rateValue: 5,
    );
    final rule = (await repo.getCardRewardRuleById(ruleId))!;
    final txId = await repo.addTransaction(
      ledgerId: ledgerId,
      type: 'expense',
      amount: 100,
      accountId: accountId,
      happenedAt: DateTime(2026, 5, 26),
      merchant: '全联',
      rewardRuleIds: [rule.syncId!],
    );

    final billInfo = BillInfo(
      amount: -100,
      time: DateTime(2026, 5, 26),
      category: '购物',
      merchant: '全联',
    );

    await tester.pumpWidget(
      host(BillCardWidget(billInfo: billInfo, transactionId: txId)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('網購5%回饋'), findsOneWidget);
  });

  testWidgets('沒有掛回饋規則時不顯示回饋列', (tester) async {
    final txId = await repo.addTransaction(
      ledgerId: ledgerId,
      type: 'expense',
      amount: 100,
      accountId: accountId,
      happenedAt: DateTime(2026, 5, 26),
    );
    final billInfo = BillInfo(
      amount: -100,
      time: DateTime(2026, 5, 26),
      category: '购物',
    );

    await tester.pumpWidget(
      host(BillCardWidget(billInfo: billInfo, transactionId: txId)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('🎁'), findsNothing);
  });

  testWidgets('已撤銷的卡片不顯示商家/回饋列', (tester) async {
    final ruleId = await repo.createCardRewardRule(
      accountId: accountId,
      label: '網購5%回饋',
      rateType: 'percentage',
      rateValue: 5,
    );
    final rule = (await repo.getCardRewardRuleById(ruleId))!;
    final txId = await repo.addTransaction(
      ledgerId: ledgerId,
      type: 'expense',
      amount: 100,
      accountId: accountId,
      happenedAt: DateTime(2026, 5, 26),
      merchant: '全联',
      rewardRuleIds: [rule.syncId!],
    );

    final billInfo = BillInfo(
      amount: -100,
      time: DateTime(2026, 5, 26),
      category: '购物',
      merchant: '全联',
    );

    await tester.pumpWidget(
      host(BillCardWidget(
        billInfo: billInfo,
        transactionId: txId,
        isUndone: true,
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('全联'), findsNothing);
    expect(find.textContaining('網購5%回饋'), findsNothing);
  });
}
