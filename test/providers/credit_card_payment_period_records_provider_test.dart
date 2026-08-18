// creditCardPaymentPeriodRecordsProvider(帳戶詳情頁「繳款記錄」小節用)必須
// 把一筆繳款依 FIFO 模擬歸屬到它實際沖銷掉的帳期,而不是它自己的交易日期
// 落在哪個帳期窗口——2026-08-18 使用者用「星展信用卡」真實資料明確要求這個
// 行為(見 docs/changes/2026-08-18-credit-card-payment-record-attribution-restore.md):
// 兩筆繳款(819、5744)雖然交易日期落在 2026/08/11–09/11 這期的窗口內,但它們
// 沖銷的是更舊的兩期(2026/06/11–07/11 的 2304、2026/07/11–08/11 的 4259),
// 「繳款記錄」小節應該顯示在它們實際繳清的那一期,不是交易發生的那一期。

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/providers.dart';

void main() {
  late BeeDatabase db;
  late LocalRepository repo;
  late ProviderContainer container;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<int> seedLedger() {
    return db.into(db.ledgers).insert(LedgersCompanion.insert(
          name: '测试账本',
          monthStartDay: const Value(1),
        ));
  }

  test('星展信用卡真實場景:819/5744 兩筆繳款依 FIFO 歸屬到它們實際繳清的舊帳期', () async {
    final lid = await seedLedger();
    final groupId = await db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: lid,
          name: '星展信用卡',
          type: const Value('account_group'),
          syncId: const Value('acc_group'),
          billingDay: const Value(11),
          paymentDueDay: const Value(27),
        ));
    final ecoId = await db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: lid,
          name: '星展eco卡',
          type: const Value('credit_card'),
          syncId: const Value('acc_eco'),
          parentAccountId: const Value('acc_group'),
        ));
    final heroId = await db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: lid,
          name: '星展英雄聯盟卡',
          type: const Value('credit_card'),
          syncId: const Value('acc_hero'),
          parentAccountId: const Value('acc_group'),
        ));

    // 期一(06/11–07/11)6 筆消費共 2304;期二(07/11–08/11)9 筆消費 + 1 筆
    // 回饋收入淨額 4259;期三(08/11–09/11,當期)兩筆繳款轉入(819、5744)+
    // 少量其它交易——跟 test/repositories/account_statement_transactions_test.dart
    // 用的是同一組「星展信用卡」真實金額。這裡只需要 charged/paid 的口徑對,
    // 用相對「現在」固定的日期(而不是像那份 fixture 用 2020 年固定日期)
    // 才能讓 billingCyclePeriod(anchored 在 DateTime.now())把這些交易正確
    // 分進 offset -2/-1/0 三期——用 [DateTime.now] 反推三個帳期的日期。
    final now = DateTime.now();
    final period0 = _billingPeriodFor(now, 11, 0);
    final period1 = _billingPeriodFor(now, 11, -1);
    final period2 = _billingPeriodFor(now, 11, -2);

    Future<void> expense(int accountId, double amount, DateTime happenedAt) =>
        repo
            .addTransaction(
              ledgerId: lid,
              type: 'expense',
              amount: amount,
              accountId: accountId,
              happenedAt: happenedAt,
            )
            .then((_) {});

    Future<void> income(int accountId, double amount, DateTime happenedAt) =>
        repo
            .addTransaction(
              ledgerId: lid,
              type: 'income',
              amount: amount,
              accountId: accountId,
              happenedAt: happenedAt,
            )
            .then((_) {});

    Future<void> transferIn(int toAccountId, double amount, DateTime at) => repo
        .addTransaction(
          ledgerId: lid,
          type: 'transfer',
          amount: amount,
          toAccountId: toAccountId,
          happenedAt: at,
        )
        .then((_) {});

    DateTime mid(({DateTime start, DateTime end}) p) =>
        p.start.add(const Duration(days: 2));

    // 期二(offset -2,最舊):6 筆消費共 2304。
    await expense(heroId, 930, mid(period2));
    await expense(heroId, 398, mid(period2));
    await expense(heroId, 264, mid(period2));
    await expense(heroId, 420, mid(period2));
    await expense(heroId, 145, mid(period2));
    await expense(heroId, 147, mid(period2));

    // 期一(offset -1):9 筆消費 + 1 筆回饋收入,淨額 4259。
    await expense(heroId, 1350, mid(period1));
    await expense(heroId, 486, mid(period1));
    await expense(heroId, 31, mid(period1));
    await income(heroId, 900, mid(period1));
    await expense(ecoId, 819, mid(period1));
    await expense(heroId, 91, mid(period1));
    await expense(heroId, 120, mid(period1));
    await expense(heroId, 2166, mid(period1));
    await expense(heroId, 96, mid(period1));

    // 期三(offset 0,當期):兩筆繳款轉入,交易日期都落在這期窗口內。
    await transferIn(ecoId, 819, mid(period0));
    await transferIn(heroId, 5744, mid(period0));

    final extraIdsKey = ([ecoId, heroId]..sort()).join(',');

    final recordsForPeriod0 =
        await container.read(creditCardPaymentPeriodRecordsProvider((
      accountId: groupId,
      extraIdsKey: extraIdsKey,
      billingDay: 11,
      targetOffset: 0,
    )).future);
    expect(recordsForPeriod0, isEmpty,
        reason: '819/5744 都被 FIFO 歸屬到更舊的帳期,不應該出現在當期(offset 0)');

    final recordsForPeriod1 =
        await container.read(creditCardPaymentPeriodRecordsProvider((
      accountId: groupId,
      extraIdsKey: extraIdsKey,
      billingDay: 11,
      targetOffset: -1,
    )).future);
    expect(recordsForPeriod1.length, 1);
    expect(recordsForPeriod1.single.amount, 5744);

    final recordsForPeriod2 =
        await container.read(creditCardPaymentPeriodRecordsProvider((
      accountId: groupId,
      extraIdsKey: extraIdsKey,
      billingDay: 11,
      targetOffset: -2,
    )).future);
    expect(recordsForPeriod2.length, 1);
    expect(recordsForPeriod2.single.amount, 819);
  });
}

/// 跟 `card_reward_period.dart::billingCyclePeriod` 邏輯等價,但把 `now` 當
/// 參數傳入(方便測試用固定基準點反推帳期日期,而不是真的依賴系統時鐘)。
({DateTime start, DateTime end}) _billingPeriodFor(
    DateTime now, int day, int offset) {
  var anchorYear = now.year;
  var anchorMonth = now.month;
  if (now.day > day) {
    anchorMonth += 1;
    if (anchorMonth > 12) {
      anchorMonth = 1;
      anchorYear += 1;
    }
  }
  anchorMonth += offset;
  while (anchorMonth <= 0) {
    anchorMonth += 12;
    anchorYear -= 1;
  }
  while (anchorMonth > 12) {
    anchorMonth -= 12;
    anchorYear += 1;
  }
  DateTime clampDay(int year, int month, int d) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, d > lastDay ? lastDay : d);
  }

  final end = clampDay(anchorYear, anchorMonth, day);
  var prevMonth = anchorMonth - 1;
  var prevYear = anchorYear;
  if (prevMonth == 0) {
    prevMonth = 12;
    prevYear -= 1;
  }
  final start = clampDay(prevYear, prevMonth, day).add(const Duration(days: 1));
  return (start: start, end: end);
}
