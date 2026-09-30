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
import 'package:beecount/cloud/sync/entity_serializer.dart';
import 'package:beecount/data/repositories/recurring_rule_repository.dart';
import 'package:beecount/services/investment/stock_dca.dart';

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
    // 台股只買整數股:(3000 − 手續費 20) ÷ 97.45 = 30.58 → 30 股,
    // 價金 2,923 + 手續費 20 = 扣款 2,943,零頭不扣(同 Cloud 測試)。
    expect(trades.first.shares, 30);
    expect(trades.first.fee, 20);
    expect(trades.first.txSyncId, isNotNull);
    final tx = await (db.select(db.transactions)
          ..where((t) => t.syncId.equals(trades.first.txSyncId!)))
        .getSingle();
    expect(tx.type, 'transfer');
    expect(tx.amount, 2923);
    expect(tx.feeAmount, 20);
    expect(tx.note, '定期定額 0050 30股');
    expect(await repo.getAccountBalance(s.settlementId), 100000 - 2943);

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

  // ---------------------------------------------------------------------
  // 2026-09-29 修正回歸測試
  // ---------------------------------------------------------------------

  Future<int> createDca(
    ({int ledgerId, int settlementId, int investmentId}) s, {
    DateTime? nextRunAt,
    String frequency = 'monthly',
    double amount = 3000,
    int? fromAccountId,
  }) =>
      repo.createRule(
        ledgerId: s.ledgerId,
        type: 'transfer',
        amount: amount,
        fromAccountId: fromAccountId ?? s.settlementId,
        toAccountId: s.investmentId,
        frequency: frequency,
        interval: 1,
        nextRunAt:
            nextRunAt ?? DateTime.now().subtract(const Duration(minutes: 5)),
        kind: 'stock_dca',
        market: 'TW',
        symbol: '0050',
      );

  test('自動扣繳排程不處理 stock_dca(不會生成沒有持股明細的裸轉帳)', () async {
    final s = await seedLedgerAndAccounts();
    await insertQuote('TW', '0050', 100);
    final ruleId = await createDca(s);

    final transfer = await repo.materializeDueTransferRules();
    expect(transfer.materialized, 0);
    expect((await repo.getRuleById(ruleId))!.generatedUntilAt, isNull);

    final stock = await repo.materializeDueStockRules();
    expect(stock.materialized, 1);
    expect((await repo.getAllStockTrades()).length, 1);
  });

  test('每期用固定 syncId(對齊 Cloud),重跑不會重複買', () async {
    final s = await seedLedgerAndAccounts();
    await insertQuote('TW', '0050', 100);
    final due = DateTime.now().subtract(const Duration(minutes: 5));
    final ruleId = await createDca(s, nextRunAt: due);
    final rule = (await repo.getRuleById(ruleId))!;

    await repo.materializeDueStockRules();
    final trades = await repo.getAllStockTrades();
    final ids = stockDcaOccurrenceIds(rule.syncId!, due);
    expect(trades.single.syncId, ids.tradeSyncId);
    expect(trades.single.txSyncId, ids.txSyncId);

    final again = await repo.materializeDueStockRules();
    expect(again.materialized, 0);
    expect((await repo.getAllStockTrades()).length, 1);
  });

  test('Cloud 已生成(本地已有同 syncId 的明細)→ 只推進進度,不重複買', () async {
    final s = await seedLedgerAndAccounts();
    await insertQuote('TW', '0050', 100);
    final due = DateTime.now().subtract(const Duration(minutes: 5));
    final ruleId = await createDca(s, nextRunAt: due);
    final rule = (await repo.getRuleById(ruleId))!;
    final ids = stockDcaOccurrenceIds(rule.syncId!, due);
    // 模擬 pull 下來的 Cloud 明細
    await repo.createStockTrade(
      ledgerId: s.ledgerId,
      accountId: s.investmentId,
      tradeType: 'buy',
      market: 'TW',
      symbol: '0050',
      shares: 30,
      price: 100,
      tradeDate: due,
      settlementAccountId: s.settlementId,
      recurringRuleId: rule.syncId,
      syncId: ids.tradeSyncId,
      txSyncId: ids.txSyncId,
    );

    final result = await repo.materializeDueStockRules();
    expect(result.materialized, 0);
    expect((await repo.getAllStockTrades()).length, 1);
    expect((await repo.getRuleById(ruleId))!.generatedUntilAt, isNotNull);
  });

  test('超過 7 天的過期期數略過不補買(不會全用今天的價格買)', () async {
    final s = await seedLedgerAndAccounts();
    await insertQuote('TW', '0050', 100);
    await createDca(s,
        frequency: 'daily',
        amount: 1000,
        nextRunAt: DateTime.now().subtract(const Duration(days: 20)));

    final result = await repo.materializeDueStockRules();
    expect(result.materialized, inInclusiveRange(7, 8));
    final stale = result.skipped
        .where((k) => k.reason == RecurringRuleStockSkipReason.staleSkipped)
        .single;
    expect(stale.skippedCount + result.materialized, 21);
    final cutoff =
        DateTime.now().subtract(kStockDcaMaxCatchUp + const Duration(minutes: 1));
    for (final t in await repo.getAllStockTrades()) {
      expect(t.tradeDate.isAfter(cutoff), isTrue);
    }
  });

  test('一條規則設定壞掉(跨幣別交割)不會讓整批中斷', () async {
    final s = await seedLedgerAndAccounts();
    await insertQuote('TW', '0050', 100);
    final usd = await repo.createAccount(
        ledgerId: s.ledgerId, name: 'USD', currency: 'USD', initialBalance: 1e6);
    final broken = await createDca(s, fromAccountId: usd);
    await createDca(s);

    final result = await repo.materializeDueStockRules();
    expect(result.materialized, 1);
    final failed = result.skipped
        .where((k) => k.reason == RecurringRuleStockSkipReason.failed)
        .single;
    expect(failed.ruleId, broken);
  });

  test('push payload 帶齊定期定額欄位(含顯式 null)', () async {
    final s = await seedLedgerAndAccounts();
    final ruleId = await createDca(s);
    final rule = (await repo.getRuleById(ruleId))!;
    final payload = EntitySerializer.serializeRecurringRule(rule);
    expect(payload['kind'], 'stock_dca');
    expect(payload['market'], 'TW');
    expect(payload['symbol'], '0050');
    expect(payload.containsKey('stockFeeRate'), isTrue);
    expect(payload['stockFeeRate'], isNull);
  });

  test('第一期之後改下次執行時間:往後改會從新時間重新起算', () async {
    final s = await seedLedgerAndAccounts();
    await insertQuote('TW', '0050', 100);
    final ruleId = await createDca(s);
    await repo.materializeDueStockRules();
    final before = (await repo.getRuleById(ruleId))!;
    expect(before.generatedUntilAt, isNotNull);

    final t = DateTime.now().add(const Duration(days: 3));
    // Drift 以秒為精度存 DateTime。
    final newNext = DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
    await repo.updateRuleAndFuture(ruleId: ruleId, nextRunAt: newNext);
    final after = (await repo.getRuleById(ruleId))!;
    expect(after.generatedUntilAt, isNull);
    expect(after.kind, 'stock_dca');
    expect(
        nextPendingOccurrence(
          nextRunAt: after.nextRunAt,
          generatedUntilAt: after.generatedUntilAt,
          frequency: after.frequency,
          interval: after.interval,
        ),
        newNext);
    // 已生成的那期(StockTrade 連帶的轉帳)不會被改到
    // 29 股 × 100 + 手續費 20(台股整數股)
    expect((await repo.getAllStockTrades()).single.amount, closeTo(2920, 1e-6));
  });

  // ---------------------------------------------------------------------
  // 2026-09-30:台股整數股 / 美股碎股
  // ---------------------------------------------------------------------

  test('台股每期金額買不起 1 股 → 略過這期(amountTooSmall),推進進度', () async {
    final s = await seedLedgerAndAccounts();
    await insertQuote('TW', '0050', 200);
    final ruleId = await createDca(s, amount: 150);

    final result = await repo.materializeDueStockRules();
    expect(result.materialized, 0);
    expect(result.skipped.single.reason,
        RecurringRuleStockSkipReason.amountTooSmall);
    expect(await repo.getAllStockTrades(), isEmpty);
    expect((await repo.getRuleById(ruleId))!.generatedUntilAt, isNotNull);
    // 不會卡在同一期每次啟動都通知
    final again = await repo.materializeDueStockRules();
    expect(again.skipped, isEmpty);
  });

  test('美股維持碎股:金額全部買進、手續費另計', () async {
    final lid = await repo.createLedger(name: 'L');
    final bank = await repo.createAccount(
        ledgerId: lid, name: '美元交割', currency: 'USD', initialBalance: 10000);
    final inv = await repo.createAccount(
        ledgerId: lid, name: '複委託', type: 'investment', currency: 'USD');
    await insertQuote('US', 'VOO', 450);
    await repo.createRule(
      ledgerId: lid,
      type: 'transfer',
      amount: 100,
      fromAccountId: bank,
      toAccountId: inv,
      frequency: 'monthly',
      interval: 1,
      nextRunAt: DateTime.now().subtract(const Duration(minutes: 5)),
      kind: 'stock_dca',
      market: 'US',
      symbol: 'VOO',
    );
    expect((await repo.materializeDueStockRules()).materialized, 1);
    final trade = (await repo.getAllStockTrades()).single;
    expect(trade.shares, closeTo(100 / 450, 1e-9));
    expect(trade.fee, 0.25);
  });
}
