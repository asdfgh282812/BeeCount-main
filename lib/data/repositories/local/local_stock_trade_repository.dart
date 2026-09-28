import 'package:drift/drift.dart' as d;

import '../../db.dart';

/// 股票交易明細的低層 Drift 存取:只做單表讀寫,不碰轉帳交易、不記
/// changeTracker——那些由 LocalRepository 包裝層統一處理(同
/// LocalDebtRepository 的分工)。
class LocalStockTradeRepository {
  final BeeDatabase db;

  LocalStockTradeRepository(this.db);

  Stream<List<StockTrade>> watchAll() =>
      (db.select(db.stockTrades)..orderBy([(t) => d.OrderingTerm.asc(t.tradeDate)])).watch();

  Future<List<StockTrade>> getAll() =>
      (db.select(db.stockTrades)..orderBy([(t) => d.OrderingTerm.asc(t.tradeDate)])).get();

  Future<List<StockTrade>> getForAccount(int accountId) =>
      (db.select(db.stockTrades)
            ..where((t) => t.accountId.equals(accountId))
            ..orderBy([(t) => d.OrderingTerm.asc(t.tradeDate)]))
          .get();

  Future<List<StockTrade>> getForPosition(int accountId, String market, String symbol) =>
      (db.select(db.stockTrades)
            ..where((t) =>
                t.accountId.equals(accountId) &
                t.market.equals(market.toUpperCase()) &
                t.symbol.equals(symbol.toUpperCase())))
          .get();

  Future<StockTrade?> getById(int id) =>
      (db.select(db.stockTrades)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<StockTrade?> getBySyncId(String syncId) =>
      (db.select(db.stockTrades)..where((t) => t.syncId.equals(syncId))).getSingleOrNull();

  Future<List<StockTrade>> getByTxSyncId(String txSyncId) =>
      (db.select(db.stockTrades)..where((t) => t.txSyncId.equals(txSyncId))).get();

  Future<int> insert(StockTradesCompanion row) => db.into(db.stockTrades).insert(row);

  Future<void> update(int id, StockTradesCompanion row) =>
      (db.update(db.stockTrades)..where((t) => t.id.equals(id))).write(row);

  Future<void> delete(int id) =>
      (db.delete(db.stockTrades)..where((t) => t.id.equals(id))).go();

  Stream<List<SecurityQuote>> watchQuotes() => db.select(db.securityQuotes).watch();

  Future<List<SecurityQuote>> getQuotes() => db.select(db.securityQuotes).get();

  Future<void> upsertQuotes(List<SecurityQuotesCompanion> rows) async {
    if (rows.isEmpty) return;
    await db.batch((b) {
      for (final row in rows) {
        b.insert(db.securityQuotes, row, mode: d.InsertMode.insertOrReplace);
      }
    });
  }
}
