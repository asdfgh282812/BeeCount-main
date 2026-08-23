/// [resolveNotificationJumpTarget] —— 通知中心點擊跳轉的 payload 解析邏輯,
/// 跟 Navigator/widget 樹完全解耦,純 Dart + 真的記憶體 Drift db 測試最快。
/// Widget 層的渲染/互動見 `test/widgets/notification_center_page_test.dart`。
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/debt_repository.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/pages/notifications/notification_center_page.dart';

void main() {
  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);

    await db.into(db.ledgers).insert(LedgersCompanion.insert(
          id: const d.Value(1),
          name: 'L1',
          currency: const d.Value('CNY'),
          syncId: const d.Value('ledger-sync-1'),
        ));
    await db.into(db.ledgers).insert(LedgersCompanion.insert(
          id: const d.Value(2),
          name: 'L2',
          currency: const d.Value('CNY'),
          syncId: const d.Value('ledger-sync-2'),
        ));
    await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: const d.Value(1),
          ledgerId: 1,
          name: '信用卡',
          currency: const d.Value('CNY'),
          syncId: const d.Value('account-sync-1'),
        ));
    await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: const d.Value(1),
          name: '餐饮',
          kind: 'expense',
          icon: const d.Value('restaurant'),
        ));
    // createRule 就地生成 syncId(UUID),测试要固定 syncId 才能拿来查,建完
    // 直接把这一列的 syncId 改成固定值。
    final ruleId = await repo.createRule(
      ledgerId: 1,
      type: 'expense',
      amount: 100,
      categoryId: 1,
      accountId: 1,
      merchant: '訂閱服務',
      frequency: 'monthly',
      interval: 1,
      nextRunAt: DateTime.now().add(const Duration(days: 1)),
    );
    await (db.update(db.recurringTransactions)
          ..where((r) => r.id.equals(ruleId)))
        .write(const RecurringTransactionsCompanion(
      syncId: d.Value('rule-sync-1'),
    ));
    final debtId = await repo.createDebt(
      ledgerId: 1,
      direction: kDebtDirectionPayable,
      counterpartyName: '小明',
      principalAmount: 300,
    );
    await (db.update(db.debts)..where((t) => t.id.equals(debtId))).write(
      const DebtsCompanion(syncId: d.Value('debt-sync-1')),
    );
  });

  tearDown(() async => db.close());

  test('payload 沒有 accountId/recurringRuleId → none，不切帳本', () async {
    var switched = false;
    final target = await resolveNotificationJumpTarget(
      repo,
      {'ledgerId': 'ledger-sync-1'},
      currentLedgerId: 1,
      onSwitchLedger: (_) => switched = true,
    );
    expect(target.account, isNull);
    expect(target.hasRuleTarget, isFalse);
    expect(target.notFound, isFalse);
    expect(target.ledgerNotSynced, isFalse);
    expect(switched, isFalse);
  });

  test('payload 為 null → none', () async {
    final target = await resolveNotificationJumpTarget(
      repo,
      null,
      currentLedgerId: 1,
      onSwitchLedger: (_) {},
    );
    expect(target.account, isNull);
    expect(target.hasRuleTarget, isFalse);
  });

  test('accountId 可解析、跟目前帳本相同 → 回傳 account，不切帳本', () async {
    var switched = false;
    final target = await resolveNotificationJumpTarget(
      repo,
      {'accountId': 'account-sync-1', 'ledgerId': 'ledger-sync-1'},
      currentLedgerId: 1,
      onSwitchLedger: (_) => switched = true,
    );
    expect(target.account, isNotNull);
    expect(target.account!.id, 1);
    expect(switched, isFalse);
  });

  test('accountId 找不到本機實體 → notFound', () async {
    final target = await resolveNotificationJumpTarget(
      repo,
      {'accountId': 'account-sync-missing', 'ledgerId': 'ledger-sync-1'},
      currentLedgerId: 1,
      onSwitchLedger: (_) {},
    );
    expect(target.notFound, isTrue);
    expect(target.account, isNull);
  });

  test('recurringRuleId 可解析 → hasRuleTarget', () async {
    final target = await resolveNotificationJumpTarget(
      repo,
      {'recurringRuleId': 'rule-sync-1', 'ledgerId': 'ledger-sync-1'},
      currentLedgerId: 1,
      onSwitchLedger: (_) {},
    );
    expect(target.hasRuleTarget, isTrue);
    expect(target.account, isNull);
  });

  test('recurringRuleId 找不到本機實體 → notFound', () async {
    final target = await resolveNotificationJumpTarget(
      repo,
      {'recurringRuleId': 'rule-sync-missing', 'ledgerId': 'ledger-sync-1'},
      currentLedgerId: 1,
      onSwitchLedger: (_) {},
    );
    expect(target.notFound, isTrue);
  });

  test('accountId 優先於 recurringRuleId（跟 web 端 handleJumpToDetail 一致）',
      () async {
    final target = await resolveNotificationJumpTarget(
      repo,
      {
        'accountId': 'account-sync-1',
        'recurringRuleId': 'rule-sync-1',
        'ledgerId': 'ledger-sync-1',
      },
      currentLedgerId: 1,
      onSwitchLedger: (_) {},
    );
    expect(target.account, isNotNull);
    expect(target.hasRuleTarget, isFalse);
  });

  test('ledgerId 指向跟目前不同的帳本 → 先切帳本再回傳 target', () async {
    int? switchedTo;
    final target = await resolveNotificationJumpTarget(
      repo,
      {'accountId': 'account-sync-1', 'ledgerId': 'ledger-sync-1'},
      currentLedgerId: 2,
      onSwitchLedger: (id) => switchedTo = id,
    );
    expect(switchedTo, 1);
    expect(target.account, isNotNull);
  });

  test('ledgerId 在本機找不到對應帳本 → ledgerNotSynced，不切帳本、不回傳 target', () async {
    var switched = false;
    final target = await resolveNotificationJumpTarget(
      repo,
      {'accountId': 'account-sync-1', 'ledgerId': 'ledger-sync-missing'},
      currentLedgerId: 1,
      onSwitchLedger: (_) => switched = true,
    );
    expect(target.ledgerNotSynced, isTrue);
    expect(target.account, isNull);
    expect(switched, isFalse);
  });

  test('payload 沒有 ledgerId 也能正常解析 accountId', () async {
    final target = await resolveNotificationJumpTarget(
      repo,
      {'accountId': 'account-sync-1'},
      currentLedgerId: 1,
      onSwitchLedger: (_) {},
    );
    expect(target.account, isNotNull);
  });

  test('debtId 可解析 → 回傳 debt(附即時算出的 remainingAmount)', () async {
    final target = await resolveNotificationJumpTarget(
      repo,
      {'debtId': 'debt-sync-1', 'ledgerId': 'ledger-sync-1'},
      currentLedgerId: 1,
      onSwitchLedger: (_) {},
    );
    expect(target.debt, isNotNull);
    expect(target.debt!.debt.counterpartyName, '小明');
    expect(target.debt!.remainingAmount, 300);
    expect(target.account, isNull);
    expect(target.hasRuleTarget, isFalse);
  });

  test('debtId 找不到本機實體 → notFound', () async {
    final target = await resolveNotificationJumpTarget(
      repo,
      {'debtId': 'debt-sync-missing', 'ledgerId': 'ledger-sync-1'},
      currentLedgerId: 1,
      onSwitchLedger: (_) {},
    );
    expect(target.notFound, isTrue);
    expect(target.debt, isNull);
  });

  test('recurringRuleId 優先於 debtId（兩者理論上不會同時出現在同一則通知,但解析順序要固定)',
      () async {
    final target = await resolveNotificationJumpTarget(
      repo,
      {
        'recurringRuleId': 'rule-sync-1',
        'debtId': 'debt-sync-1',
        'ledgerId': 'ledger-sync-1',
      },
      currentLedgerId: 1,
      onSwitchLedger: (_) {},
    );
    expect(target.hasRuleTarget, isTrue);
    expect(target.debt, isNull);
  });

  test('ledgerId 指向跟目前不同的帳本 → 先切帳本再回傳 debt target', () async {
    int? switchedTo;
    final target = await resolveNotificationJumpTarget(
      repo,
      {'debtId': 'debt-sync-1', 'ledgerId': 'ledger-sync-1'},
      currentLedgerId: 2,
      onSwitchLedger: (id) => switchedTo = id,
    );
    expect(switchedTo, 1);
    expect(target.debt, isNotNull);
  });
}
