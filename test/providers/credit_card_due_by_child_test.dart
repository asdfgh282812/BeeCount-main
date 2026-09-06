// 合併帳單群組「剩餘帳款」多幣別淨額換算修正(2026-09-07)。
//
// 使用者反饋的真實場景:合併帳單群組裡有一張外幣子卡，使用者已經用該卡
// 自己的幣別把這期帳單繳清了（消費 JPY 10000、繳款也是 JPY 10000，淨額
// 剛好是 0）。但帳單彙總卡片的「剩餘帳款」原本是「先把每筆交易分別折算成
// 帳本本位幣、再相減」——消費當下的匯率跟繳款當下的匯率不同，兩邊各自
// 折算後相減會殘留一筆匯差，被誤當成「這張已結清的外幣子卡還欠群組一筆
// 錢」疊加進總額，讓合併群組的「剩餘帳款」比只看台幣子卡真正欠的金額還多
// （這次是多算了 100，對應使用者回報的情境是多算了 7）。
//
// 修法：[creditCardDueByChildAsOf] 先用每張子卡自己的幣別算淨額，已結清
// （<= 0.005）的直接跳過，完全不受匯率換算殘值影響；只有還沒結清的子卡才
// 需要為了跟其他不同幣別的子卡加總而換算。

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/providers/credit_card_billing_providers.dart';
import 'package:beecount/utils/credit_card_payment.dart';

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

  Future<int> seedCategory(String name, String kind) {
    return db.into(db.categories).insert(CategoriesCompanion.insert(
          name: name,
          kind: kind,
        ));
  }

  test('外幣子卡已用自己幣別繳清(淨額=0) → 換算殘值不會被算進群組剩餘帳款,只剩台幣子卡真正欠的金額', () async {
    final lid = await seedLedger();
    final expenseCat = await seedCategory('購物', 'expense');
    final cashTwd = await seedAccount(lid, '台幣現金');
    final cardTwd = await seedAccount(lid, '台幣子卡');
    final cardJpy = await seedAccount(lid, '日圓子卡');

    // 台幣子卡:單純消費 4657、未繳款,這是唯一真正還欠的金額。
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 4657,
      categoryId: expenseCat,
      accountId: cardTwd,
      happenedAt: DateTime(2026, 8, 10),
    );

    // 日圓子卡:消費當下匯率折算 nativeAmount=2200(帳本本位幣快照)。
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 10000,
      nativeAmount: 2200,
      categoryId: expenseCat,
      accountId: cardJpy,
      happenedAt: DateTime(2026, 8, 12),
    );
    // 已經用同幣別(JPY→JPY)把這張卡全額繳清,但繳款當下匯率已經跌到
    // nativeAmount=2100 ——同一筆錢,消費/繳款兩次獨立折算的帳本本位幣快照
    // 不會剛好相等,這就是匯差殘值的來源。
    await repo.addTransaction(
      ledgerId: lid,
      type: 'transfer',
      amount: 10000,
      nativeAmount: 2100,
      accountId: cashTwd,
      toAccountId: cardJpy,
      happenedAt: DateTime(2026, 8, 20),
    );

    final cutoff = endOfDay(DateTime(2026, 9, 5));
    final byChild =
        await creditCardDueByChildAsOf(repo, [cardTwd, cardJpy], cutoff);

    // 日圓子卡已經用自己的幣別結清,不該出現在回傳的 map 裡,更不該貢獻任何
    // 匯差殘值。
    expect(byChild.containsKey(cardJpy), isFalse);
    expect(byChild[cardTwd], 4657);
    expect(byChild.values.fold(0.0, (a, b) => a + b), 4657);
  });

  test('外幣子卡真的還沒繳清時,仍會折算成帳本本位幣一起加總', () async {
    final lid = await seedLedger();
    final expenseCat = await seedCategory('購物', 'expense');
    final cardTwd = await seedAccount(lid, '台幣子卡');
    final cardJpy = await seedAccount(lid, '日圓子卡');

    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 1000,
      categoryId: expenseCat,
      accountId: cardTwd,
      happenedAt: DateTime(2026, 8, 10),
    );
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 10000,
      nativeAmount: 2200,
      categoryId: expenseCat,
      accountId: cardJpy,
      happenedAt: DateTime(2026, 8, 12),
    );

    final cutoff = endOfDay(DateTime(2026, 9, 5));
    final byChild =
        await creditCardDueByChildAsOf(repo, [cardTwd, cardJpy], cutoff);

    expect(byChild[cardTwd], 1000);
    expect(byChild[cardJpy], 2200);
    expect(byChild.values.fold(0.0, (a, b) => a + b), 3200);
  });
}
