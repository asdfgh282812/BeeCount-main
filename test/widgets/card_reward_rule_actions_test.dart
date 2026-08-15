/// 信用卡紅利回饋規則的「複製」/「刪除」共用邏輯
/// (`lib/widgets/biz/card_reward_rule_actions.dart`)。
///
/// 覆蓋:
/// - `duplicateCardRewardRule`:複製出一條新規則,欄位一致、名稱帶「(複製)」
///   後綴,排在原有規則之後,syncId 獨立。
/// - `confirmAndDeleteCardRewardRule`:
///   - 沒有本地交易引用時,對話框走「一般刪除」文案,確認後硬刪除。
///   - 有本地交易引用(`transactions.rewardRuleIdsJson` 命中)時,對話框改走
///     「已鎖定」文案,確認後軟刪除(`enabled=false`),規則行仍然存在。
///   - 取消對話框不做任何變更。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/widgets/biz/card_reward_rule_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;
  late int accountId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    final ledgerId = await repo.createLedger(name: 'L');
    accountId = await repo.createAccount(
      ledgerId: ledgerId,
      name: '信用卡',
      type: 'credit_card',
    );
  });

  tearDown(() async => db.close());

  Widget host(WidgetBuilder builder) {
    return ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(body: Consumer(builder: (context, ref, _) {
          return builder(context);
        })),
      ),
    );
  }

  testWidgets('duplicateCardRewardRule 複製出新規則,欄位一致、名稱帶後綴', (tester) async {
    final ruleId = await repo.createCardRewardRule(
      accountId: accountId,
      label: '國內消費',
      rateType: 'percentage',
      rateValue: 1.5,
      capAmount: 500,
      sortOrder: 3,
    );
    final rule = (await repo.getCardRewardRuleById(ruleId))!;

    await tester.pumpWidget(host((context) {
      return Consumer(builder: (context, ref, _) {
        return ElevatedButton(
          onPressed: () => duplicateCardRewardRule(context, ref, rule),
          child: const Text('copy'),
        );
      });
    }));

    await tester.tap(find.text('copy'));
    await tester.pumpAndSettle();
    // duplicateCardRewardRule 成功后 showToast 起一个 2s Future.delayed 自动
    // 消失的计时器,不是 frame-scheduled,pumpAndSettle 逮不到——手动推进时钟
    // 让它触发+清理,避免 "Timer still pending" 断言炸测试。
    await tester.pump(const Duration(seconds: 3));

    final all = await repo.getCardRewardRulesForAccount(accountId);
    expect(all, hasLength(2));
    final copy = all.firstWhere((r) => r.id != ruleId);
    expect(copy.label, contains('國內消費'));
    expect(copy.label, isNot(equals('國內消費')), reason: '複製出來的名稱要帶後綴,跟原名不同');
    expect(copy.rateType, rule.rateType);
    expect(copy.rateValue, rule.rateValue);
    expect(copy.capAmount, rule.capAmount);
    expect(copy.sortOrder, greaterThan(rule.sortOrder));
    expect(copy.syncId, isNot(equals(rule.syncId)), reason: '複製要有獨立的 syncId');
  });

  testWidgets('confirmAndDeleteCardRewardRule 無交易引用時走硬刪除', (tester) async {
    final ruleId = await repo.createCardRewardRule(
      accountId: accountId,
      label: '國內消費',
      rateType: 'percentage',
      rateValue: 1.5,
    );
    final rule = (await repo.getCardRewardRuleById(ruleId))!;

    bool? deleted;
    late BuildContext capturedContext;
    await tester.pumpWidget(host((context) {
      return Consumer(builder: (context, ref, _) {
        capturedContext = context;
        return ElevatedButton(
          onPressed: () async {
            deleted = await confirmAndDeleteCardRewardRule(context, ref, rule);
          },
          child: const Text('delete'),
        );
      });
    }));

    await tester.tap(find.text('delete'));
    await tester.pump();

    final l10n = AppLocalizations.of(capturedContext);
    expect(find.text(l10n.cardRewardRuleDeleteConfirmTitle), findsOneWidget);
    await tester.tap(find.text(l10n.commonDelete));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3)); // 见上面 duplicate 测试的注释

    expect(deleted, isTrue);
    expect(await repo.getCardRewardRuleById(ruleId), isNull,
        reason: '沒有交易引用時應該是硬刪除,查不到這一行');
  });

  testWidgets('confirmAndDeleteCardRewardRule 有交易引用時走軟刪除(disable)',
      (tester) async {
    final ruleId = await repo.createCardRewardRule(
      accountId: accountId,
      label: '國內消費',
      rateType: 'percentage',
      rateValue: 1.5,
    );
    final rule = (await repo.getCardRewardRuleById(ruleId))!;

    final ledgerId = await repo.createLedger(name: 'L2');
    await repo.addTransaction(
      ledgerId: ledgerId,
      type: 'expense',
      amount: 100,
      happenedAt: DateTime.now(),
      accountId: accountId,
      rewardRuleIds: [rule.syncId!],
    );

    bool? deleted;
    late BuildContext capturedContext;
    await tester.pumpWidget(host((context) {
      return Consumer(builder: (context, ref, _) {
        capturedContext = context;
        return ElevatedButton(
          onPressed: () async {
            deleted = await confirmAndDeleteCardRewardRule(context, ref, rule);
          },
          child: const Text('delete'),
        );
      });
    }));

    await tester.tap(find.text('delete'));
    await tester.pump();

    final l10n = AppLocalizations.of(capturedContext);
    expect(find.text(l10n.cardRewardRuleDeleteLockedTitle), findsOneWidget);
    await tester.tap(find.text(l10n.commonDelete));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3)); // 见上面 duplicate 测试的注释

    expect(deleted, isTrue);
    final stillThere = await repo.getCardRewardRuleById(ruleId);
    expect(stillThere, isNotNull, reason: '有交易引用時不能真刪,行還在');
    expect(stillThere!.enabled, isFalse, reason: '改成軟刪除(停用)');
  });

  testWidgets('取消對話框不做任何變更', (tester) async {
    final ruleId = await repo.createCardRewardRule(
      accountId: accountId,
      label: '國內消費',
      rateType: 'percentage',
      rateValue: 1.5,
    );
    final rule = (await repo.getCardRewardRuleById(ruleId))!;

    bool? deleted;
    late BuildContext capturedContext;
    await tester.pumpWidget(host((context) {
      return Consumer(builder: (context, ref, _) {
        capturedContext = context;
        return ElevatedButton(
          onPressed: () async {
            deleted = await confirmAndDeleteCardRewardRule(context, ref, rule);
          },
          child: const Text('delete'),
        );
      });
    }));

    await tester.tap(find.text('delete'));
    await tester.pump();

    final l10n = AppLocalizations.of(capturedContext);
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();

    expect(deleted, isFalse);
    final stillThere = await repo.getCardRewardRuleById(ruleId);
    expect(stillThere, isNotNull);
    expect(stillThere!.enabled, isTrue);
  });
}
