/// 股票定期定額(v64,`RecurringTransactions.kind == 'stock_dca'`)—
/// LocalRepository 編排邏輯的整合測試。
///
/// 覆蓋:
/// - createRule(kind='stock_dca'):不預生成任何 occurrence(同 transfer 規則,
///   到期才生成)。
/// - materializeDueStockRules:報價齊全 + 交割帳戶餘額足夠 → 生成一筆
///   StockTrade(buy)+ 連帶轉帳交易(帶 recurringRuleId),推進
///   generatedUntilAt。
/// - 報價缺失 → 跳過(quoteUnavailable),不推進進度。
/// - 交割帳戶餘額不足 → 跳過(insufficientBalance),不推進進度。
/// - stockFeeRate/stockFeeMin 覆寫:優先於投資帳戶的預設 InvestmentSettings。
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/data/repositories/recurring_rule_repository.dart';

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

  Future<({int ledgerId, int settlementId, int investmentId})>
      seedLedgerAndAccounts({double settlementBalance = 100000}) async {
    final lid = await repo.createLedger(name: 'L');
    final settlementId = await repo.createAccount(
        ledgerId: lid,
        name: '交割戶',
        currency: 'TWD',
        initialBalance: settlementBalance);
    final investmentId = await repo.createAccount(
        ledgerId: lid, name: '證券戶', type: 'investment', currency: 'TWD');
    return (ledgerId: lid, settlementId: settlementId, investmentId: investmentId);
  }

  Future<void> insertQuote(String market, String symbol, double price) async {
    await db.into(db.securityQuotes).insert(
          SecurityQuotesCompanion.insert(
            market: market,
            symbol: symbol,
            price: d.Value(price),
            fetchedAt: DateTime.now(),
          ),
        );
  }

  test('createRule(kind=stock_dca) 不預生成任何 occurrence', () async {
    final s = await seedLedgerAndAccounts();
    final ruleId = await repo.createRule(
      ledgerId: s.ledgerId,
      type: 'transfer',
      amount: 3000,
      fromAccountId: s.settlementId,
      toAccountId: s.investmentId,
      frequency: 'monthly',
      interval: 1,
      nextRunAt: DateTime(2026, 1, 15),
      kind: 'stock_dca',
      market: 'TW',
      symbol: '0050',
      securityName: '元大台灣50',
    );

    final rule = await repo.getRuleById(ruleId);
    expect(rule!.kind, 'stock_dca');
    expect(rule.generatedUntilAt, isNull);
    expect(rule.enabled, isTrue);

    final trades = await repo.getAllStockTrades();
    expect(trades, isEmpty);
  });

  test('materializeDueStockRules:報價+餘額齊全 → 生成 buy 明細與連帶轉帳', () async {
    final s = await seedLedgerAndAccounts();
    await insertQuote('TW', '0050', 97.45);
    final ruleId = await repo.createRule(
      ledgerId: s.ledgerId,
      type: 'transfer',
      amount: 3000,
      fromAccountId: s.settlementId,
      toAccountId: s.investmentId,
      frequency: 'monthly',
      interval: 1,
      nextRunAt: DateTime.now().subtract(const Duration(days: 1)),
      kind: 'stock_dca',
      market: 'TW',
      symbol: '0050',
    );

    final result = await repo.materializeDueStockRules();
    expect(result.materialized, 1);
    expect(result.skipped, isEmpty);

    final trades = await repo.getAllStockTrades();
    expect(trades.length, 1);
    expect(trades.first.tradeType, 'buy');
    expect(trades.first.shares, closeTo(3000 / 97.45, 1e-9));
    expect(trades.first.txSyncId, isNotNull);

    final rule = await repo.getRuleById(ruleId);
    expect(rule!.generatedUntilAt, isNotNull);
  });

  test('materializeDueStockRules:沒有報價 → 跳過(quoteUnavailable),不推進進度',
      () async {
    final s = await seedLedgerAndAccounts();
    await repo.createRule(
      ledgerId: s.ledgerId,
      type: 'transfer',
      amount: 3000,
      fromAccountId: s.settlementId,
      toAccountId: s.investmentId,
      frequency: 'monthly',
      interval: 1,
      nextRunAt: DateTime.now().subtract(const Duration(days: 1)),
      kind: 'stock_dca',
      market: 'TW',
      symbol: '0050',
    );

    final result = await repo.materializeDueStockRules();
    expect(result.materialized, 0);
    expect(result.skipped, hasLength(1));
    expect(result.skipped.first.reason,
        RecurringRuleStockSkipReason.quoteUnavailable);

    final trades = await repo.getAllStockTrades();
    expect(trades, isEmpty);
  });

  test('materializeDueStockRules:交割帳戶餘額不足 → 跳過(insufficientBalance)',
      () async {
    final s = await seedLedgerAndAccounts(settlementBalance: 100);
    await insertQuote('TW', '0050', 97.45);
    await repo.createRule(
      ledgerId: s.ledgerId,
      type: 'transfer',
      amount: 3000,
      fromAccountId: s.settlementId,
      toAccountId: s.investmentId,
      frequency: 'monthly',
      interval: 1,
      nextRunAt: DateTime.now().subtract(const Duration(days: 1)),
      kind: 'stock_dca',
      market: 'TW',
      symbol: '0050',
    );

    final result = await repo.materializeDueStockRules();
    expect(result.materialized, 0);
    expect(result.skipped, hasLength(1));
    expect(result.skipped.first.reason,
        RecurringRuleStockSkipReason.insufficientBalance);

    final trades = await repo.getAllStockTrades();
    expect(trades, isEmpty);
  });

  test('stockFeeRate/stockFeeMin 覆寫優先於投資帳戶預設費率', () async {
    final s = await seedLedgerAndAccounts();
    await insertQuote('TW', '0050', 100);
    await repo.createRule(
      ledgerId: s.ledgerId,
      type: 'transfer',
      amount: 10000,
      fromAccountId: s.settlementId,
      toAccountId: s.investmentId,
      frequency: 'monthly',
      interval: 1,
      nextRunAt: DateTime.now().subtract(const Duration(days: 1)),
      kind: 'stock_dca',
      market: 'TW',
      symbol: '0050',
      // 覆寫成 0 手續費(部分券商定期定額前 N 期免手續費之類的情境)。
      stockFeeRate: 0,
      stockFeeMin: 0,
    );

    final result = await repo.materializeDueStockRules();
    expect(result.materialized, 1);
    final trades = await repo.getAllStockTrades();
    expect(trades.first.fee, 0);
  });
}
