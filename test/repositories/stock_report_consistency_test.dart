// 股票報表一致性(docs/changes/2026-10-03-stock-report-consistency.md):
// 用真實的 LocalRepository 建買進/賣出/現金股利/股利再投入,驗證各報表口徑彼此對得上:
//   - 收入 = 只有股利(買進/賣出是轉帳,不算收入也不算支出)
//   - 支出 = 0(手續費與證交稅不計入支出)
//   - 全部帳戶餘額的變化 = 收入 − 支出 − 股票手續費稅
//     ——也就是「淨資產少的那一塊」剛好等於 InvestmentFlow 補充資訊裡的手續費稅,
//       不會有說不出來源的差額
//   - InvestmentFlow 的買進/賣出/淨投入/股利跟明細逐筆算的一致
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/cloud/sync/change_tracker.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/providers/securities_providers.dart' show holdingTradeOf;
import 'package:beecount/services/investment/investment_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db, changeTracker: ChangeTracker(db));
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency, sync_id) VALUES (1, 'L', 'TWD', 'lg1')");
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, type, currency, sync_id, initial_balance) VALUES "
        "(1, 1, '交割戶', 'bank_card', 'TWD', 'acc_bank', 1000000), "
        "(2, 1, '證券', 'investment', 'TWD', 'acc_inv', 0)");
  });

  tearDown(() async => db.close());

  test('收入=只有股利、支出=0;餘額變化 = 收入 − 支出 − 手續費稅(兩邊對得上)', () async {
    final day = DateTime(2026, 9, 10, 12);
    // 買進 1000 股 @600、手續費 855 → 轉帳 600,000 + feeAmount 855
    await repo.createStockTrade(
        ledgerId: 1, accountId: 2, tradeType: 'buy', market: 'TW', symbol: '2330',
        shares: 1000, price: 600, fee: 855, tradeDate: day, settlementAccountId: 1);
    // 賣出 400 股 @700、手續費 399、稅 840 → 轉帳 280,000 + discountAmount 1,239
    await repo.createStockTrade(
        ledgerId: 1, accountId: 2, tradeType: 'sell', market: 'TW', symbol: '2330',
        shares: 400, price: 700, fee: 399, tax: 840,
        tradeDate: DateTime(2026, 9, 12, 12), settlementAccountId: 1);
    // 現金股利:1000 股 × 7 − 匯費 10 = 6,990 入交割戶
    await repo.createStockTrade(
        ledgerId: 1, accountId: 2, tradeType: 'cash_dividend', market: 'TW', symbol: '2330',
        shares: 1000, price: 7, fee: 10,
        tradeDate: DateTime(2026, 9, 16, 12), settlementAccountId: 1);
    // 股利再投入:11 股 @630 + 手續費 1 = 6,931 入投資帳戶本身
    await repo.createStockTrade(
        ledgerId: 1, accountId: 2, tradeType: 'reinvest', market: 'TW', symbol: '2330',
        shares: 11, price: 630, fee: 1, tradeDate: DateTime(2026, 9, 20, 12));

    // ---- 收支統計(首頁/報表/年度報告共用的 totals) ----
    final (income, expense) =
        await repo.monthlyTotals(ledgerId: 1, month: DateTime(2026, 9));
    expect(income, 6990 + 6931, reason: '收入只有股利(現金 + 再投入),買賣不算收入');
    expect(expense, 0, reason: '買股票不是支出,手續費/證交稅也不計入支出');

    // ---- 帳戶餘額 ----
    final bank = await repo.getAccountBalance(1);
    final inv = await repo.getAccountBalance(2);
    // 交割戶:−(600,000+855) + (280,000−1,239) + 6,990
    expect(bank, 1000000 - 600855 + 278761 + 6990);
    // 投資帳戶(帳面):+600,000 − 280,000 + 6,931
    expect(inv, 600000 - 280000 + 6931);

    // ---- 對得上:全部帳戶餘額變化 = 收入 − 支出 − 股票手續費稅 ----
    final trades = await repo.getAllStockTrades();
    final flow = InvestmentFlow.compute([
      for (final t in trades)
        InvestmentFlowTrade(
          tradeType: t.tradeType,
          amount: t.amount,
          fee: t.fee,
          tax: t.tax,
          currency: t.currency,
          market: t.market,
          tradeDate: t.tradeDate,
          ledgerId: t.ledgerId,
        ),
    ]);
    final c = flow.byCurrency['TWD']!;
    expect(c.buy, 600855);
    expect(c.sell, 278761);
    expect(c.netInvested, 322094);
    expect(c.feesAndTax, 855 + 399 + 840);
    expect(c.dividends, 6990 + 6931);
    // 手續費稅合計 = 買進手續費 + 賣出(手續費+稅);股利匯費不在內(它已從股利實收裡扣掉)
    final balanceChange = (bank - 1000000) + inv;
    expect(balanceChange, income - expense - c.feesAndTax);
  });

  test('HoldingTrade 與 InvestmentFlowTrade 對同一批明細的買進總額一致(兩條路徑不矛盾)', () async {
    await repo.createStockTrade(
        ledgerId: 1, accountId: 2, tradeType: 'buy', market: 'TW', symbol: '2330',
        shares: 1000, price: 600, fee: 855,
        tradeDate: DateTime(2026, 9, 10, 12), settlementAccountId: 1);
    final trades = await repo.getAllStockTrades();
    final bought = trades.map(holdingTradeOf).where((t) => t.tradeType == 'buy').fold<double>(0, (a, t) => a + t.amount);
    final flow = InvestmentFlow.compute([
      for (final t in trades)
        InvestmentFlowTrade(
            tradeType: t.tradeType,
            amount: t.amount,
            fee: t.fee,
            tax: t.tax,
            currency: t.currency,
            market: t.market,
            tradeDate: t.tradeDate,
            ledgerId: t.ledgerId),
    ]);
    expect(flow.byCurrency['TWD']!.buy, bought);
  });
}
