// 信用卡帳單口徑「已繳金額」(getCreditCardPaidTotal)合併帳單群組場景的
// 幣別修正:2026-09-06 使用者反饋——群組底下一張子卡跟群組本身幣別不同
// (例如 TWD 群組掛一張 JPY 子卡)時,原本 paidTotal 固定用 `toAmount ??
// amount`(轉入方/這張卡自己幣別的數字)加總,拿去跟已經改用
// `convertToLedgerCurrency: true` 折算成帳本本位幣的 charged 側相減比較,
// 會把子卡自己幣別的原始數字誤當帳本本位幣算,「已繳金額」/「剩餘帳款」
// 嚴重失真。跟 BeeCount Cloud `src/services/credit_card_billing.py` 同一批
// 修正——Cloud 也是同樣的 bug:paidTotal 原本只讀 `to_amount`,沒有跟
// charged 側一樣改讀折算過帳本本位幣的欄位。
//
// 修法:`getCreditCardPaidTotal` 新增 `convertToLedgerCurrency` 參數(跟
// `getCreditCardChargedAsOf` 同名參數同款語意),傳 `true` 時改用
// `nativeAmount ?? amount`(轉出方金額折算帳本本位幣的快照,跟 charged 側
// 用的是同一個欄位/同一個換算基準);單一帳戶(非群組)場景維持 `false`
// 預設值,行為不變。

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

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

  Future<int> seedAccount(int ledgerId, String name, {String? syncId}) {
    return db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: ledgerId,
          name: name,
          type: const Value('credit_card'),
          syncId: Value(syncId ?? name),
        ));
  }

  test(
      'convertToLedgerCurrency: false(預設,單一帳戶場景)沿用 toAmount ?? amount,行為不變',
      () async {
    final lid = await seedLedger();
    final cardId = await seedAccount(lid, '日圓子卡');
    final cashId = await seedAccount(lid, '日幣現金');

    // 同幣別(JPY→JPY)繳款:原幣 8030,折台幣本位幣快照 2030——單一帳戶
    // 場景本來就用該帳戶自己的幣別顯示,不該被折算成帳本本位幣。
    await repo.addTransaction(
      ledgerId: lid,
      type: 'transfer',
      amount: 8030,
      nativeAmount: 2030,
      accountId: cashId,
      toAccountId: cardId,
      happenedAt: DateTime(2020, 8, 1),
    );

    final paid = await repo.getCreditCardPaidTotal(cardId);
    expect(paid, 8030);
  });

  test(
      'convertToLedgerCurrency: true(合併帳單群組場景)改用 nativeAmount ?? amount,不會把子卡自己幣別的原始數字誤當帳本本位幣',
      () async {
    final lid = await seedLedger();
    final cardId = await seedAccount(lid, '日圓子卡');
    final cashId = await seedAccount(lid, '日幣現金');

    // 這是本次要修的 bug 現場重現:同幣別(JPY→JPY)繳款不會帶 toAmount,
    // 折算後的帳本本位幣金額只存在 nativeAmount——群組彙總必須讀這個欄位,
    // 不能退回 to_amount 缺席時的 amount(原幣 8030,遠高於實際台幣等值)。
    await repo.addTransaction(
      ledgerId: lid,
      type: 'transfer',
      amount: 8030,
      nativeAmount: 2030,
      accountId: cashId,
      toAccountId: cardId,
      happenedAt: DateTime(2020, 8, 1),
    );

    final paid =
        await repo.getCreditCardPaidTotal(cardId, convertToLedgerCurrency: true);
    expect(paid, 2030);
  });

  test('convertToLedgerCurrency: true 但 nativeAmount 缺席時退回 amount(舊資料相容)',
      () async {
    final lid = await seedLedger();
    final cardId = await seedAccount(lid, '台幣子卡');
    final cashId = await seedAccount(lid, '台幣現金');

    // 同幣別繳款、帳戶本身幣別跟帳本本位幣一致時,nativeAmount 本來就不會
    // 額外折算(隐含汇率 1.0),缺席時退回 amount 是正確行為,不是 bug。
    await repo.addTransaction(
      ledgerId: lid,
      type: 'transfer',
      amount: 500,
      accountId: cashId,
      toAccountId: cardId,
      happenedAt: DateTime(2020, 8, 1),
    );

    final paid =
        await repo.getCreditCardPaidTotal(cardId, convertToLedgerCurrency: true);
    expect(paid, 500);
  });
}
