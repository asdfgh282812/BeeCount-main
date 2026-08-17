/// 週期性收支規則(v36,對齐 BeeCount Cloud recurring_rule)—
/// LocalRepository 編排邏輯的整合測試。
///
/// 覆蓋:
/// - createRule:無 endAt 生成 12 個月預設視窗、enabled 保持 true;有 endAt
///   全部生成完、enabled 自動變 false(fully generated)。
/// - 「修改此記錄」(updateOccurrence):只改這一筆,標記 overridden,不影響
///   其它期。
/// - 「修改連同未來週期」(updateRuleAndFuture):更新規則本身 + 批次更新
///   >= anchor 且未被單獨編輯過的既有 occurrence,過去的期數與已 overridden
///   的期數不受影響。
/// - 「刪除連同未來週期」(terminateFuture):只刪未發生的 occurrence,規則
///   標記 enabled=false,已發生的保留。
/// - deleteRule(deleteFutureOccurrences: true):連同未來 occurrence 一起刪
///   規則本身。
/// - transfer 自動扣繳(materializeDueTransferRules):餘額不足時跳過且不推
///   進 generatedUntilAt,餘額足夠時正常生成。
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
  });

  tearDown(() async => db.close());

  Future<int> seedLedgerAndAccount() async {
    final lid = await repo.createLedger(name: 'L');
    await repo.createAccount(ledgerId: lid, name: 'A');
    return lid;
  }

  test('createRule 无 endAt:生成 12 个月默认视窗,enabled 保持 true', () async {
    final lid = await seedLedgerAndAccount();
    final ruleId = await repo.createRule(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      frequency: 'monthly',
      interval: 1,
      nextRunAt: DateTime(2026, 1, 15),
    );

    final rule = await repo.getRuleById(ruleId);
    expect(rule!.enabled, isTrue);
    expect(rule.syncId, isNotNull);
    // 12 个月窗口:第一笔是 start 本身,最后一笔是 start + 12 个月。
    expect(rule.generatedUntilAt, DateTime(2027, 1, 15));

    final occurrences = await (db.select(db.transactions)
          ..where((t) => t.recurringRuleId.equals(rule.syncId!)))
        .get();
    expect(occurrences.length, 13); // 含 start 本身,每月一笔
    expect(occurrences.every((t) => t.recurringOccurrenceOverridden == false),
        isTrue);
  });

  test('createRule 有 endAt 全部生成完:enabled 自动变 false', () async {
    final lid = await seedLedgerAndAccount();
    final ruleId = await repo.createRule(
      ledgerId: lid,
      type: 'expense',
      amount: 50,
      frequency: 'monthly',
      interval: 1,
      nextRunAt: DateTime(2026, 1, 1),
      endAt: DateTime(2026, 3, 1),
    );

    final rule = await repo.getRuleById(ruleId);
    expect(rule!.enabled, isFalse);

    final occurrences = await (db.select(db.transactions)
          ..where((t) => t.recurringRuleId.equals(rule.syncId!)))
        .get();
    expect(occurrences.length, 3); // Jan/Feb/Mar
  });

  test('updateOccurrence(此记录):只改这一笔并标记 overridden,不影响其它期',
      () async {
    final lid = await seedLedgerAndAccount();
    final ruleId = await repo.createRule(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      frequency: 'monthly',
      interval: 1,
      nextRunAt: DateTime(2026, 1, 1),
      endAt: DateTime(2026, 3, 1),
    );
    final rule = await repo.getRuleById(ruleId);
    final occurrences = await (db.select(db.transactions)
          ..where((t) => t.recurringRuleId.equals(rule!.syncId!))
          ..orderBy([(t) => OrderingTerm(expression: t.happenedAt)]))
        .get();
    final feb = occurrences[1];

    await repo.updateOccurrence(transactionId: feb.id, amount: 999);

    final febAfter = await repo.getTransactionById(feb.id);
    expect(febAfter!.amount, 999);
    expect(febAfter.recurringOccurrenceOverridden, isTrue);

    final janAfter = await repo.getTransactionById(occurrences[0].id);
    final marAfter = await repo.getTransactionById(occurrences[2].id);
    expect(janAfter!.amount, 100);
    expect(marAfter!.amount, 100);
    expect(janAfter.recurringOccurrenceOverridden, isFalse);
  });

  test('updateRuleAndFuture(连同未来周期):只影响 >= anchor 且未 overridden 的期',
      () async {
    final lid = await seedLedgerAndAccount();
    final ruleId = await repo.createRule(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      frequency: 'monthly',
      interval: 1,
      nextRunAt: DateTime(2026, 1, 1),
      endAt: DateTime(2026, 4, 1),
    );
    final rule = await repo.getRuleById(ruleId);
    final occurrences = await (db.select(db.transactions)
          ..where((t) => t.recurringRuleId.equals(rule!.syncId!))
          ..orderBy([(t) => OrderingTerm(expression: t.happenedAt)]))
        .get();
    // occurrences: Jan/Feb/Mar/Apr。先把 Feb 标记为「此记录已单独编辑」。
    await repo.updateOccurrence(transactionId: occurrences[1].id, amount: 1);

    // 从 Mar(occurrences[2])开始「修改连同未来周期」。
    await repo.updateRuleAndFuture(
      ruleId: ruleId,
      anchorTransactionId: occurrences[2].id,
      amount: 500,
    );

    final jan = await repo.getTransactionById(occurrences[0].id);
    final feb = await repo.getTransactionById(occurrences[1].id);
    final mar = await repo.getTransactionById(occurrences[2].id);
    final apr = await repo.getTransactionById(occurrences[3].id);
    expect(jan!.amount, 100, reason: 'Jan 在 anchor 之前,不受影响');
    expect(feb!.amount, 1, reason: 'Feb 已 overridden,批次更新要跳过它');
    expect(mar!.amount, 500, reason: 'Mar 是 anchor 本身,要更新');
    expect(apr!.amount, 500, reason: 'Apr 在 anchor 之后且未 overridden,要更新');

    final updatedRule = await repo.getRuleById(ruleId);
    expect(updatedRule!.amount, 500, reason: '规则本身也要更新,供以后新期数延用');
  });

  test(
      'updateRuleAndFuture(anchorTransactionId 為 null):用 anchorDate 當起點,'
      '給規則列表頁「編輯」直接進來的入口用', () async {
    final lid = await seedLedgerAndAccount();
    final ruleId = await repo.createRule(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      frequency: 'monthly',
      interval: 1,
      nextRunAt: DateTime(2026, 1, 1),
      endAt: DateTime(2026, 4, 1),
    );
    final rule = await repo.getRuleById(ruleId);
    final occurrences = await (db.select(db.transactions)
          ..where((t) => t.recurringRuleId.equals(rule!.syncId!))
          ..orderBy([(t) => OrderingTerm(expression: t.happenedAt)]))
        .get();
    // Jan/Feb/Mar/Apr。先把 Feb 標記為「此記錄已單獨編輯」。
    await repo.updateOccurrence(transactionId: occurrences[1].id, amount: 1);

    // 不傳 anchorTransactionId,改用 anchorDate = Mar 1 當起點。
    await repo.updateRuleAndFuture(
      ruleId: ruleId,
      anchorDate: DateTime(2026, 3, 1),
      amount: 500,
    );

    final jan = await repo.getTransactionById(occurrences[0].id);
    final feb = await repo.getTransactionById(occurrences[1].id);
    final mar = await repo.getTransactionById(occurrences[2].id);
    final apr = await repo.getTransactionById(occurrences[3].id);
    expect(jan!.amount, 100, reason: 'Jan 在 anchorDate 之前,不受影响');
    expect(feb!.amount, 1, reason: 'Feb 已 overridden,批次更新要跳过它');
    expect(mar!.amount, 500, reason: 'Mar 是 anchorDate 本身,要更新');
    expect(apr!.amount, 500, reason: 'Apr 在 anchorDate 之后且未 overridden,要更新');

    final updatedRule = await repo.getRuleById(ruleId);
    expect(updatedRule!.amount, 500);
  });

  test(
      'updateRuleAndFuture(anchorTransactionId/anchorDate 皆為 null):'
      '預設用現在當起點', () async {
    final lid = await seedLedgerAndAccount();
    final past = DateTime.now().subtract(const Duration(days: 40));
    final ruleId = await repo.createRule(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      frequency: 'monthly',
      interval: 1,
      nextRunAt: past,
    );
    final rule = await repo.getRuleById(ruleId);
    final before = await (db.select(db.transactions)
          ..where((t) => t.recurringRuleId.equals(rule!.syncId!)))
        .get();
    final now = DateTime.now();
    final pastOnes = before.where((t) => t.happenedAt.isBefore(now)).toList();
    final futureOnes = before.where((t) => t.happenedAt.isAfter(now)).toList();
    expect(pastOnes, isNotEmpty);
    expect(futureOnes, isNotEmpty);

    await repo.updateRuleAndFuture(ruleId: ruleId, amount: 777);

    for (final t in pastOnes) {
      final after = await repo.getTransactionById(t.id);
      expect(after!.amount, 100, reason: '過去的期數不受影響');
    }
    for (final t in futureOnes) {
      final after = await repo.getTransactionById(t.id);
      expect(after!.amount, 777, reason: '未來的期數要被批次更新');
    }
  });

  test(
      'updateRuleAndFuture 縮短 endAt:刪除超出新結束時間、未發生、未 overridden '
      '的期數;已 overridden 的例外保留', () async {
    final lid = await seedLedgerAndAccount();
    final ruleId = await repo.createRule(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      frequency: 'monthly',
      interval: 1,
      nextRunAt: DateTime.now().add(const Duration(days: 10)),
      endAt: DateTime.now().add(const Duration(days: 10 + 120)),
    );
    final rule = await repo.getRuleById(ruleId);
    final before = await (db.select(db.transactions)
          ..where((t) => t.recurringRuleId.equals(rule!.syncId!))
          ..orderBy([(t) => OrderingTerm(expression: t.happenedAt)]))
        .get();
    expect(before.length, greaterThanOrEqualTo(4));
    // 標記第 2 筆為單獨編輯——縮短 endAt 後即使超出新結束時間也該保留。
    await repo.updateOccurrence(transactionId: before[1].id, amount: 1);

    // 新 endAt 落在第 0 筆之後、第 1 筆之前。
    final newEndAt = before[0].happenedAt.add(const Duration(days: 15));
    await repo.updateRuleAndFuture(ruleId: ruleId, endAt: newEndAt);

    final after = await (db.select(db.transactions)
          ..where((t) => t.recurringRuleId.equals(rule!.syncId!)))
        .get();
    final remainingIds = after.map((t) => t.id).toSet();
    expect(remainingIds.contains(before[0].id), isTrue,
        reason: '沒超出新 endAt,保留');
    expect(remainingIds.contains(before[1].id), isTrue,
        reason: '超出新 endAt 但已 overridden,例外保留');
    for (final t in before.skip(2)) {
      expect(remainingIds.contains(t.id), isFalse,
          reason: '超出新 endAt 且未 overridden,應該被刪除');
    }

    final updatedRule = await repo.getRuleById(ruleId);
    expect(updatedRule!.endAt, newEndAt);
  });

  test('setRuleEnabled:只切換 enabled 欄位', () async {
    final lid = await seedLedgerAndAccount();
    final ruleId = await repo.createRule(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      frequency: 'monthly',
      interval: 1,
      nextRunAt: DateTime.now().add(const Duration(days: 10)),
    );
    expect((await repo.getRuleById(ruleId))!.enabled, isTrue);

    await repo.setRuleEnabled(ruleId, false);
    expect((await repo.getRuleById(ruleId))!.enabled, isFalse);

    await repo.setRuleEnabled(ruleId, true);
    expect((await repo.getRuleById(ruleId))!.enabled, isTrue);
  });

  test('getOccurrencesForRule:依 happenedAt 由舊到新回傳該規則所有 occurrence',
      () async {
    final lid = await seedLedgerAndAccount();
    final ruleId = await repo.createRule(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      frequency: 'monthly',
      interval: 1,
      nextRunAt: DateTime(2026, 1, 1),
      endAt: DateTime(2026, 4, 1),
    );
    final rule = await repo.getRuleById(ruleId);

    final occurrences = await repo.getOccurrencesForRule(rule!.syncId!);

    expect(occurrences.length, 4);
    for (var i = 1; i < occurrences.length; i++) {
      expect(occurrences[i].happenedAt.isAfter(occurrences[i - 1].happenedAt),
          isTrue);
    }
  });

  test('terminateFuture(删除连同未来周期):只删未发生的,规则标记 enabled=false',
      () async {
    final lid = await seedLedgerAndAccount();
    final past = DateTime.now().subtract(const Duration(days: 40));
    final ruleId = await repo.createRule(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      frequency: 'monthly',
      interval: 1,
      nextRunAt: past,
    );
    final rule = await repo.getRuleById(ruleId);
    final before = await (db.select(db.transactions)
          ..where((t) => t.recurringRuleId.equals(rule!.syncId!)))
        .get();
    final pastCount = before.where((t) => t.happenedAt.isBefore(DateTime.now())).length;
    expect(pastCount, greaterThan(0));

    await repo.terminateFuture(ruleId);

    final after = await (db.select(db.transactions)
          ..where((t) => t.recurringRuleId.equals(rule!.syncId!)))
        .get();
    expect(after.length, pastCount, reason: '未发生的期数应该被删掉');
    expect(after.every((t) => t.happenedAt.isBefore(DateTime.now())), isTrue);

    final updatedRule = await repo.getRuleById(ruleId);
    expect(updatedRule!.enabled, isFalse);
  });

  test('deleteRule(deleteFutureOccurrences: true):连同未来 occurrence 一起删规则',
      () async {
    final lid = await seedLedgerAndAccount();
    final start = DateTime.now().add(const Duration(days: 10));
    final ruleId = await repo.createRule(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      frequency: 'monthly',
      interval: 1,
      nextRunAt: start,
      endAt: start.add(const Duration(days: 65)), // 全部落在未来
    );
    final rule = await repo.getRuleById(ruleId);
    final syncId = rule!.syncId!;

    await repo.deleteRule(ruleId);

    expect(await repo.getRuleById(ruleId), isNull);
    final remaining = await (db.select(db.transactions)
          ..where((t) => t.recurringRuleId.equals(syncId)))
        .get();
    expect(remaining, isEmpty);
  });

  group('transfer 自动扣缴(materializeDueTransferRules)', () {
    test('余额不足 → 跳过、不推进 generatedUntilAt、记录 skip 明细', () async {
      final lid = await repo.createLedger(name: 'L');
      final fromId =
          await repo.createAccount(ledgerId: lid, name: 'From', initialBalance: 10);
      final toId = await repo.createAccount(ledgerId: lid, name: 'To');
      final ruleId = await repo.createRule(
        ledgerId: lid,
        type: 'transfer',
        amount: 500,
        fromAccountId: fromId,
        toAccountId: toId,
        frequency: 'monthly',
        interval: 1,
        nextRunAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      final result = await repo.materializeDueTransferRules();

      expect(result.materialized, 0);
      expect(result.skipped, hasLength(1));
      expect(result.skipped.first.ruleId, ruleId);
      expect(result.skipped.first.requiredAmount, 500);

      final rule = await repo.getRuleById(ruleId);
      expect(rule!.generatedUntilAt, isNull);
      final txs = await (db.select(db.transactions)
            ..where((t) => t.recurringRuleId.equals(rule.syncId!)))
          .get();
      expect(txs, isEmpty);
    });

    test('余额充足 → 正常生成并推进 generatedUntilAt', () async {
      final lid = await repo.createLedger(name: 'L');
      final fromId = await repo.createAccount(
          ledgerId: lid, name: 'From', initialBalance: 1000);
      final toId = await repo.createAccount(ledgerId: lid, name: 'To');
      final due = DateTime.now().subtract(const Duration(days: 1));
      final ruleId = await repo.createRule(
        ledgerId: lid,
        type: 'transfer',
        amount: 500,
        fromAccountId: fromId,
        toAccountId: toId,
        frequency: 'monthly',
        interval: 1,
        nextRunAt: due,
      );

      final result = await repo.materializeDueTransferRules();

      expect(result.materialized, 1);
      expect(result.skipped, isEmpty);

      final rule = await repo.getRuleById(ruleId);
      expect(rule!.generatedUntilAt, isNotNull);
      final txs = await (db.select(db.transactions)
            ..where((t) => t.recurringRuleId.equals(rule.syncId!)))
          .get();
      expect(txs, hasLength(1));
      expect(txs.first.accountId, fromId);
      expect(txs.first.toAccountId, toId);
    });
  });
}
