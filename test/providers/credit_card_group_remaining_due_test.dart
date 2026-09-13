// 合併帳單群組「剩餘帳款」溢繳淨額修正(2026-09-13)。
//
// 使用者反饋的真實場景:合併帳單群組裡有兩張子卡，其中一張只有一筆回饋金
// 入帳(income)、沒有其他消費，淨額(charged-paid)變成負值(溢繳)。帳單
// 彙總卡片的「應繳金額」(當期交易迴圈,見 account_detail_page.dart)正確地
// 把這筆溢繳併入群組總額一起淨額計算，但「剩餘帳款」(accountBalanceAsOfProvider
// → _dueAsOf → 舊版 creditCardDueByChildAsOf)是先把每張子卡自己的欠款
// floor 到 0 再加總——溢繳的那張子卡被floor成0並整個跳過，該筆溢繳額度
// 沒有拿去抵掉另一張子卡的欠款，讓「剩餘帳款」比「應繳金額」多算了溢繳
// 的金額(見 docs/changes/2026-09-13-merged-billing-group-credit-netting-fix.md)。
//
// 修法:_dueAsOf 改成鏡射 Cloud `compute_group_billing::remaining_due =
// sum(per_child_remaining_due_signed.values())`——先加總每張子卡「可能為負」
// 的淨額，只在最後的總和上 floor 到 0。

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/providers/credit_card_billing_providers.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/utils/credit_card_payment.dart' show endOfDay;

void main() {
  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
  });

  tearDown(() async => db.close());

  Future<int> seedLedger() {
    return db.into(db.ledgers).insert(LedgersCompanion.insert(
          name: '台幣帳本',
          monthStartDay: const Value(1),
        ));
  }

  Future<int> seedAccount(int ledgerId, String name) {
    return db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: ledgerId,
          name: name,
          type: const Value('credit_card'),
          syncId: Value(name),
        ));
  }

  test(
      '子卡因回饋金入帳變成溢繳(淨額<0)時,群組「剩餘帳款」要用該筆溢繳淨額扣抵其他子卡欠款,'
      '不能把溢繳的子卡 floor 成 0 後整個跳過', () async {
    final lid = await seedLedger();
    final cardMain = await seedAccount(lid, '聯邦LINE Bank聯名信用卡');
    final cardReward = await seedAccount(lid, '聯邦M卡');

    // 主要子卡:消費 820、回饋金收入 332 入帳在同一張卡 → 淨欠款 488。
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 820,
      accountId: cardMain,
      happenedAt: DateTime(2026, 8, 15),
    );
    await repo.addTransaction(
      ledgerId: lid,
      type: 'income',
      amount: 332,
      accountId: cardMain,
      happenedAt: DateTime(2026, 8, 15),
    );

    // 回饋卡:只有一筆 +23 回饋金,沒有任何消費 → 淨額 -23(溢繳)。
    await repo.addTransaction(
      ledgerId: lid,
      type: 'income',
      amount: 23,
      accountId: cardReward,
      happenedAt: DateTime(2026, 8, 15),
    );

    final cutoff = endOfDay(DateTime(2026, 9, 12));

    // 分攤預覽用的 per-child map:回饋卡溢繳、被排除在外,只剩主卡自己的
    // 488 —— 這個函式的既有行為不受這次修法影響。
    final byChild =
        await creditCardDueByChildAsOf(repo, [cardMain, cardReward], cutoff);
    expect(byChild.containsKey(cardReward), isFalse);
    expect(byChild[cardMain], 488);

    // 群組「剩餘帳款」則要把回饋卡的 -23 淨額也算進去,得到 465,而不是把
    // 回饋卡的溢繳丟掉、只看主卡的 488。
    final container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    final remaining = await container.read(accountBalanceAsOfProvider((
      accountId: cardMain,
      extraIdsKey: '$cardReward',
      asOf: cutoff,
    )).future);

    // accountBalanceAsOfProvider 回傳「負值代表欠款」,所以正確答案是 -465。
    expect(remaining, -465);

    // 群組繳款頁預帶的「繳款總額」(creditCardGroupDueAsOf)必須跟「剩餘
    // 帳款」是同一個數字 465,不能像舊版那樣沿用 [creditCardDueByChildAsOf]
    // 的加總(488)——2026-09-13 第二輪 bugfix:使用者反饋「剩餘帳款」修好
    // 之後,群組繳款頁預帶的金額卻還是舊的錯誤數字 488。
    final groupTotal =
        await creditCardGroupDueAsOf(repo, [cardMain, cardReward], cutoff);
    expect(groupTotal, 465);
  });
}
