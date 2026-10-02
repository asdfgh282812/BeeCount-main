// v63 股票持股 — LocalRepository 層契約(docs/changes/2026-09-28-stock-holdings.md):
//   - buy/sell 連帶建立轉帳交易(交割帳戶 ⇄ 投資理財帳戶),金額換算同 Cloud
//   - 賣超擋下、非投資理財帳戶擋下、缺交割帳戶擋下
//   - 編輯明細重算轉帳;刪明細連帶刪轉帳;刪轉帳連帶刪明細
//   - 每個寫入都記 stock_trade change(ledger-scoped)
//   - Phase 2:cash_dividend 建「股利」income 入入帳帳戶;reinvest 入投資帳戶
//     本身;編輯重算、刪除連帶刪交易;跨幣別要實際入帳金額
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/cloud/sync/change_tracker.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/data/repositories/stock_trade_repository.dart';
import 'package:beecount/models/investment_settings.dart';
import 'package:beecount/services/investment/stock_trade_tx_mapper.dart';

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
        "INSERT INTO accounts (id, ledger_id, name, type, currency, sync_id) VALUES "
        "(1, 1, '交割戶', 'bank_card', 'TWD', 'acc_bank'), "
        "(2, 1, '證券', 'investment', 'TWD', 'acc_inv'), "
        "(3, 1, '美股', 'investment', 'USD', 'acc_us')");
  });

  tearDown(() async => db.close());

  Future<int> buy({double shares = 1000, double price = 600, double fee = 855}) => repo.createStockTrade(
        ledgerId: 1,
        accountId: 2,
        tradeType: 'buy',
        market: 'TW',
        symbol: '2330',
        securityName: '台積電',
        shares: shares,
        price: price,
        fee: fee,
        tradeDate: DateTime.utc(2026, 9, 1, 2),
        settlementAccountId: 1,
      );

  Future<List<LocalChange>> changesOf(String type) =>
      (db.select(db.localChanges)..where((c) => c.entityType.equals(type))).get();

  test('買進:建立轉帳(交割戶→證券,本體+手續費)與明細,並記 change', () async {
    final id = await buy();
    final trade = (await repo.getStockTrade(id))!;
    expect(trade.amount, 600855);
    expect(trade.currency, 'TWD');
    expect(trade.txSyncId, isNotNull);
    final tx = (await repo.getTransactionBySyncId(trade.txSyncId!))!;
    expect(tx.type, 'transfer');
    expect(tx.accountId, 1);
    expect(tx.toAccountId, 2);
    expect(tx.amount, 600000);
    expect(tx.feeAmount, 855);
    expect(tx.note, contains('2330'));
    // 綁定轉帳不帶分類,跟 Cloud 排程/Web 手動買賣建立的一致。
    expect(tx.categoryId, isNull);
    final changes = await changesOf('stock_trade');
    expect(changes.single.action, 'create');
    expect(changes.single.ledgerId, 1);
    expect((await changesOf('transaction')).single.action, 'create');
  });

  test('0050 零股買進:價金 50×97.45 捨去成 4,872,明細成本 4,878(同券商對帳單)', () async {
    final id = await repo.createStockTrade(
      ledgerId: 1,
      accountId: 2,
      tradeType: 'buy',
      market: 'TW',
      symbol: '0050',
      shares: 50,
      price: 97.45,
      fee: 6,
      tradeDate: DateTime.utc(2026, 9, 1, 2),
      settlementAccountId: 1,
    );
    final trade = (await repo.getStockTrade(id))!;
    expect(trade.amount, 4878);
    final tx = (await repo.getTransactionBySyncId(trade.txSyncId!))!;
    expect(tx.amount, 4872);
    expect(tx.feeAmount, 6);
  });

  test('賣出:discountAmount = 手續費+稅;賣超擋下', () async {
    await buy();
    expect(
      () => repo.createStockTrade(ledgerId: 1, accountId: 2, tradeType: 'sell', market: 'TW', symbol: '2330',
          shares: 1500, price: 700, tradeDate: DateTime.utc(2026, 9, 10), settlementAccountId: 1),
      throwsA(isA<StockTradeOversellException>()),
    );
    final id = await repo.createStockTrade(ledgerId: 1, accountId: 2, tradeType: 'sell', market: 'TW',
        symbol: '2330', shares: 400, price: 700, fee: 399, tax: 840,
        tradeDate: DateTime.utc(2026, 9, 10), settlementAccountId: 1);
    final trade = (await repo.getStockTrade(id))!;
    final tx = (await repo.getTransactionBySyncId(trade.txSyncId!))!;
    expect(tx.accountId, 2);
    expect(tx.toAccountId, 1);
    expect(tx.amount, 280000);
    expect(tx.discountAmount, 1239);
    expect(await repo.getHeldShares(accountId: 2, market: 'TW', symbol: '2330'), 600);
  });

  test('非投資理財帳戶、缺交割帳戶都擋下;期初持股不建交易', () async {
    expect(
      () => repo.createStockTrade(ledgerId: 1, accountId: 1, tradeType: 'buy', market: 'TW', symbol: '2330',
          shares: 1, price: 1, tradeDate: DateTime.utc(2026, 9, 1), settlementAccountId: 2),
      throwsA(isA<StockTradeAccountException>()),
    );
    expect(
      () => repo.createStockTrade(ledgerId: 1, accountId: 2, tradeType: 'buy', market: 'TW', symbol: '2330',
          shares: 1, price: 1, tradeDate: DateTime.utc(2026, 9, 1)),
      throwsA(isA<StockTradeAccountException>()),
    );
    final id = await repo.createStockTrade(ledgerId: 1, accountId: 2, tradeType: 'opening', market: 'TW',
        symbol: '0050', shares: 100, price: 150, tradeDate: DateTime.utc(2026, 1, 1));
    final trade = (await repo.getStockTrade(id))!;
    expect(trade.txSyncId, isNull);
    expect(trade.amount, 15000);
    expect(await changesOf('transaction'), isEmpty);
  });

  test('跨幣別買進(台幣交割戶→美股帳戶):amount=交割金額、toAmount=成本,native=交割金額', () async {
    final id = await repo.createStockTrade(ledgerId: 1, accountId: 3, tradeType: 'buy', market: 'US',
        symbol: 'AAPL', shares: 10, price: 200, fee: 5, tradeDate: DateTime.utc(2026, 9, 1),
        settlementAccountId: 1, settlementAmount: 64500);
    final trade = (await repo.getStockTrade(id))!;
    expect(trade.currency, 'USD');
    expect(trade.amount, 2005);
    final tx = (await repo.getTransactionBySyncId(trade.txSyncId!))!;
    expect(tx.amount, 64500);
    expect(tx.toAmount, 2005);
    expect(tx.feeAmount, isNull);
  });

  test('編輯明細重算轉帳', () async {
    final id = await buy();
    await repo.updateStockTrade(id, shares: 2000, price: 600, fee: 1710, tradeDate: DateTime.utc(2026, 9, 2),
        note: '加碼');
    final trade = (await repo.getStockTrade(id))!;
    expect(trade.amount, 1201710);
    expect(trade.note, '加碼');
    final tx = (await repo.getTransactionBySyncId(trade.txSyncId!))!;
    expect(tx.amount, 1200000);
    expect(tx.feeAmount, 1710);
    expect(tx.toAccountId, 2);
    expect(tx.happenedAt.toUtc(), DateTime.utc(2026, 9, 2));
    expect((await changesOf('stock_trade')).map((c) => c.action), containsAll(['create', 'update']));
  });

  test('刪明細連帶刪轉帳;刪轉帳連帶刪明細', () async {
    final id1 = await buy();
    final tx1 = (await repo.getStockTrade(id1))!.txSyncId!;
    await repo.deleteStockTrade(id1);
    expect(await repo.getStockTrade(id1), isNull);
    expect(await repo.getTransactionBySyncId(tx1), isNull);
    expect((await changesOf('stock_trade')).where((c) => c.action == 'delete').length, 1);

    final id2 = await buy();
    final tx2 = (await repo.getTransactionBySyncId((await repo.getStockTrade(id2))!.txSyncId!))!;
    await repo.deleteTransaction(tx2.id);
    expect(await repo.getStockTrade(id2), isNull);
    expect((await changesOf('stock_trade')).where((c) => c.action == 'delete').length, 2);
  });

  test('費用設定寫入帳戶並記 user-global change', () async {
    await repo.updateAccountInvestmentSettings(2, const InvestmentSettings(feeDiscount: 0.6));
    final acc = (await repo.getAccount(2))!;
    expect(InvestmentSettings.parse(acc.investmentSettingsJson).feeDiscount, 0.6);
    final changes = await changesOf('account');
    expect(changes.single.ledgerId, 0);
  });

  test('現金股利:建「股利」income 入入帳帳戶,編輯重算,刪除連帶刪交易', () async {
    await buy();
    final id = await repo.createStockTrade(
      ledgerId: 1, accountId: 2, tradeType: 'cash_dividend', market: 'TW', symbol: '2330',
      securityName: '台積電', shares: 1000, price: 7, fee: 10, tax: 0,
      tradeDate: DateTime(2026, 9, 16, 12), settlementAccountId: 1,
    );
    final trade = (await repo.getStockTrade(id))!;
    expect(trade.amount, 6990);
    final tx = (await repo.getTransactionBySyncId(trade.txSyncId!))!;
    expect(tx.type, 'income');
    expect(tx.accountId, 1);
    expect(tx.amount, 6990);
    final cat = (await repo.getCategoryById(tx.categoryId!))!;
    expect(cat.name, '股利');
    expect(cat.kind, 'income');
    expect((await changesOf('category')).single.ledgerId, 0); // user-global

    // 第二筆股利沿用同一個分類
    final id2 = await repo.createStockTrade(
      ledgerId: 1, accountId: 2, tradeType: 'cash_dividend', market: 'TW', symbol: '2330',
      shares: 1000, price: 5, fee: 10, tradeDate: DateTime(2026, 6, 11, 12), settlementAccountId: 1,
    );
    final tx2 = (await repo.getTransactionBySyncId((await repo.getStockTrade(id2))!.txSyncId!))!;
    expect(tx2.categoryId, tx.categoryId);

    await repo.updateStockTrade(id, shares: 1000, price: 8, fee: 10, tax: 0, tradeDate: DateTime(2026, 9, 16, 12));
    expect((await repo.getTransactionBySyncId(trade.txSyncId!))!.amount, 7990);
    // 股利不影響股數
    expect(await repo.getHeldShares(accountId: 2, market: 'TW', symbol: '2330'), 1000);

    await repo.deleteStockTrade(id);
    expect(await repo.getTransactionBySyncId(trade.txSyncId!), isNull);
  });

  test('股利再投入:income 入投資帳戶本身,增加股數與成本', () async {
    await buy();
    final id = await repo.createStockTrade(
      ledgerId: 1, accountId: 2, tradeType: 'reinvest', market: 'TW', symbol: '2330',
      shares: 11, price: 630, fee: 1, tradeDate: DateTime(2026, 9, 20, 12),
    );
    final trade = (await repo.getStockTrade(id))!;
    expect(trade.amount, 6931);
    final tx = (await repo.getTransactionBySyncId(trade.txSyncId!))!;
    expect(tx.type, 'income');
    expect(tx.accountId, 2);
    expect(tx.amount, 6931);
    expect(await repo.getHeldShares(accountId: 2, market: 'TW', symbol: '2330'), 1011);
  });

  test('現金股利缺入帳帳戶擋下;入帳帳戶幣別不同要給實際入帳金額', () async {
    expect(
      () => repo.createStockTrade(ledgerId: 1, accountId: 3, tradeType: 'cash_dividend', market: 'US',
          symbol: 'AAPL', shares: 10, price: 0.27, tax: 0.81, tradeDate: DateTime(2026, 8, 10, 12)),
      throwsA(isA<StockTradeAccountException>()),
    );
    expect(
      () => repo.createStockTrade(ledgerId: 1, accountId: 3, tradeType: 'cash_dividend', market: 'US',
          symbol: 'AAPL', shares: 10, price: 0.27, tax: 0.81, tradeDate: DateTime(2026, 8, 10, 12),
          settlementAccountId: 1),
      throwsA(isA<StockTradeSettlementAmountRequired>()),
    );
    final id = await repo.createStockTrade(ledgerId: 1, accountId: 3, tradeType: 'cash_dividend', market: 'US',
        symbol: 'AAPL', shares: 10, price: 0.27, tax: 0.81, tradeDate: DateTime(2026, 8, 10, 12),
        settlementAccountId: 1, settlementAmount: 60);
    final tx = (await repo.getTransactionBySyncId((await repo.getStockTrade(id))!.txSyncId!))!;
    expect(tx.accountId, 1);
    expect(tx.amount, 60);
    // 股利可以直接入美股帳戶本身(同幣別,不用另外填)
    final id2 = await repo.createStockTrade(ledgerId: 1, accountId: 3, tradeType: 'cash_dividend', market: 'US',
        symbol: 'AAPL', shares: 10, price: 0.27, tax: 0.81, tradeDate: DateTime(2026, 8, 10, 12),
        settlementAccountId: 3);
    final tx2 = (await repo.getTransactionBySyncId((await repo.getStockTrade(id2))!.txSyncId!))!;
    expect(tx2.accountId, 3);
    expect(tx2.amount, closeTo(1.89, 1e-9));
  });

  test('零碎股再投入:成交價金與收入金額都四捨五入到分', () async {
    final id = await repo.createStockTrade(ledgerId: 1, accountId: 3, tradeType: 'reinvest', market: 'US',
        symbol: 'AAPL', shares: 0.0055, price: 341.07, tradeDate: DateTime(2026, 8, 10, 12));
    final trade = (await repo.getStockTrade(id))!;
    // 成交價金依幣別取整(美元到分,InvestmentSettings.gross),同 Cloud。
    expect(trade.amount, 1.88);
    final tx = (await repo.getTransactionBySyncId(trade.txSyncId!))!;
    expect(tx.amount, 1.88);
    expect(tx.accountId, 3);
  });
}
