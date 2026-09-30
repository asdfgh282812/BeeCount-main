import 'package:drift/drift.dart' as d;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import '../models/investment_settings.dart';
import '../services/currency/rate_math.dart';
import '../services/investment/holdings_calculator.dart';
import '../services/investment/markets.dart';
import '../cloud/sync/sync_engine.dart';
import '../services/system/logger_service.dart';
import 'currency_providers.dart';
import 'database_providers.dart';
import 'sync_providers.dart';

/// 股票持股(v63,docs/changes/2026-09-28-stock-holdings.md)的 provider 層。
///
/// 持股由本地 stock_trade 即時算([HoldingsCalculator]),報價從 BeeCount Cloud
/// 拉回來存進本地 [SecurityQuotes] 快取;非 Cloud 使用者可手動輸入價格(同一
/// 張快取表,source='manual')。

final stockTradesProvider = StreamProvider<List<StockTrade>>((ref) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchAllStockTrades();
});

/// key = [securityKey](`TW:2330`)。
final securityQuotesProvider =
    StreamProvider<Map<String, SecurityQuote>>((ref) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchSecurityQuotes().map((rows) => {
        for (final q in rows) securityKey(q.market, q.symbol): q,
      });
});

HoldingTrade holdingTradeOf(StockTrade t) => HoldingTrade(
      syncId: t.syncId ?? 'local_${t.id}',
      accountKey: t.accountId?.toString(),
      market: t.market,
      symbol: t.symbol,
      tradeType: t.tradeType,
      shares: t.shares,
      price: t.price,
      fee: t.fee,
      tax: t.tax,
      amount: t.amount,
      tradeDateKey: HoldingTrade.dateKey(t.tradeDate),
      securityName: t.securityName,
      currency: t.currency,
    );

/// 一檔持股 + 報價 + 市值。[marketValue] 等金額都以證券幣別計。
class HoldingView {
  final Holding holding;
  final int? accountId;
  final SecurityQuote? quote;

  /// 所屬投資理財帳戶的費用設定(試算預估賣出手續費/交易稅用)。
  final InvestmentSettings settings;

  const HoldingView({
    required this.holding,
    required this.accountId,
    required this.quote,
    this.settings = InvestmentSettings.empty,
  });

  String get key => securityKey(holding.market, holding.symbol);
  String get currency => (holding.currency ??
          quote?.currency ??
          stockMarketByCode(holding.market)?.currency ??
          '')
      .toUpperCase();
  String? get name => holding.securityName ?? quote?.name;
  double? get price => quote?.price;

  /// 毛市值 = 股數 × 現價(不扣任何費用),依幣別取整(台幣無條件捨去,
  /// 同成交價金 [InvestmentSettings.gross] 跟 Cloud `/workspace/holdings`)。
  double? get marketValue {
    final p = price;
    if (p == null || !holding.isOpen) return null;
    return InvestmentSettings.gross(holding.shares, p, currency);
  }

  /// 現在全部賣掉的預估手續費/交易稅(依帳戶費用設定 + 標的類型稅率)。
  SellCostEstimate? get sellEstimate {
    final p = price;
    if (p == null || !holding.isOpen) return null;
    return settings.estimateSell(
      shares: holding.shares,
      price: p,
      market: holding.market,
      symbol: holding.symbol,
      currency: currency,
    );
  }

  /// 預估變現淨值 = 毛市值 − 預估賣出手續費 − 預估交易稅。
  double? get netValue => sellEstimate?.net;

  /// 未實現損益要不要扣預估賣出費用(帳戶費用設定,預設開)。
  bool get pnlAfterSellCosts =>
      settings.resolvedFor(holding.market).pnlAfterSellCosts ?? true;

  /// 算未實現損益用的價值:開了「扣預估賣出費用」就是 [netValue],否則
  /// [marketValue]。
  double? get valuation => pnlAfterSellCosts ? netValue : marketValue;

  double? get unrealizedPnl {
    final v = valuation;
    return v == null ? null : v - holding.totalCost;
  }

  double? get unrealizedPnlPercent {
    final pnl = unrealizedPnl;
    if (pnl == null || holding.totalCost <= 0) return null;
    return pnl / holding.totalCost * 100;
  }

  double? get dayChangePercent {
    final p = quote?.price;
    final prev = quote?.prevClose;
    if (p == null || prev == null || prev == 0) return null;
    return (p - prev) / prev * 100;
  }
}

/// 全部持股(含已全部賣出、只剩已實現損益的部位);還在載入時回 null。
final allHoldingsProvider = Provider<List<HoldingView>?>((ref) {
  final trades = ref.watch(stockTradesProvider).valueOrNull;
  final quotes = ref.watch(securityQuotesProvider).valueOrNull;
  if (trades == null) return null;
  final accounts =
      ref.watch(allAccountsStreamProvider).valueOrNull ?? const <Account>[];
  final settingsById = {
    for (final a in accounts)
      a.id: InvestmentSettings.parse(a.investmentSettingsJson),
  };
  final holdings = HoldingsCalculator.compute(trades.map(holdingTradeOf),
      includeClosed: true);
  return [
    for (final h in holdings)
      HoldingView(
        holding: h,
        accountId: int.tryParse(h.accountKey ?? ''),
        quote: quotes?[securityKey(h.market, h.symbol)],
        settings: settingsById[int.tryParse(h.accountKey ?? '')] ??
            InvestmentSettings.empty,
      ),
  ];
});

final accountHoldingsProvider =
    Provider.family<List<HoldingView>?, int>((ref, accountId) {
  final all = ref.watch(allHoldingsProvider);
  return all?.where((h) => h.accountId == accountId).toList();
});

/// 帳戶有沒有任何股票明細(決定帳戶詳情頁要不要以「持股」為主)。
final accountHasStockTradesProvider =
    Provider.family<bool, int>((ref, accountId) {
  final trades = ref.watch(stockTradesProvider).valueOrNull ?? const [];
  return trades.any((t) => t.accountId == accountId);
});

/// 投資市值總覽(折算成使用者主幣別,跟淨資產卡同一組匯率/同一套「缺匯率
/// 就剔除、不按 1.0 裸加」規則)。沒有任何未平倉部位時回 null(卡片不顯示)。
class InvestmentSummary {
  final String baseCurrency;

  /// 毛市值(股數 × 現價)。
  final double marketValue;

  /// 預估變現淨值(扣掉預估賣出手續費/交易稅)。
  final double netValue;

  /// 算未實現損益用的價值加總(每檔依所屬帳戶的設定取淨值或毛市值)。
  final double valuation;

  /// 有任何一檔是「扣預估賣出費用」算損益(卡片要標示)。
  final bool pnlAfterSellCosts;
  final double cost;
  final double realizedPnl;
  final double dividends;

  /// 有持股但沒有報價(非 Cloud 使用者還沒手動輸入價格,或報價抓取失敗)
  /// 的標的數,這些不計入市值/成本。
  final int unpricedCount;

  /// 缺匯率而被剔除的幣別。
  final List<String> missingCurrencies;

  /// 參與計算的報價裡最舊的報價時間。
  final DateTime? oldestQuoteTime;
  final int openPositions;

  const InvestmentSummary({
    required this.baseCurrency,
    required this.marketValue,
    required this.netValue,
    required this.valuation,
    required this.pnlAfterSellCosts,
    required this.cost,
    required this.realizedPnl,
    required this.dividends,
    required this.unpricedCount,
    required this.missingCurrencies,
    required this.oldestQuoteTime,
    required this.openPositions,
  });

  double get unrealizedPnl => valuation - cost;
  double? get unrealizedPnlPercent =>
      cost > 0 ? unrealizedPnl / cost * 100 : null;
}

double? rateToBase(
    String currency, String base, Map<String, EffectiveRate> rates) {
  final code = currency.toUpperCase();
  if (code == base.toUpperCase()) return 1.0;
  final r = double.tryParse(rates[code]?.rate ?? '');
  return (r == null || r <= 0) ? null : r;
}

InvestmentSummary? computeInvestmentSummary({
  required List<HoldingView> holdings,
  required Map<String, EffectiveRate> rates,
  required String base,
}) {
  final open = holdings.where((h) => h.holding.isOpen).toList();
  if (open.isEmpty) return null;
  var mv = 0.0, net = 0.0, valuation = 0.0;
  var cost = 0.0, realized = 0.0, dividends = 0.0;
  var unpriced = 0;
  var afterCosts = false;
  final missing = <String>{};
  DateTime? oldest;
  for (final h in holdings) {
    final rate = rateToBase(h.currency, base, rates);
    if (rate == null) {
      if (h.currency.isNotEmpty) missing.add(h.currency);
      continue;
    }
    realized += h.holding.realizedPnl * rate;
    dividends += h.holding.dividends * rate;
    if (!h.holding.isOpen) continue;
    final value = h.marketValue;
    if (value == null) {
      unpriced += 1;
      continue;
    }
    mv += value * rate;
    net += (h.netValue ?? value) * rate;
    valuation += (h.valuation ?? value) * rate;
    if (h.pnlAfterSellCosts) afterCosts = true;
    cost += h.holding.totalCost * rate;
    final qt = h.quote?.quoteTime ?? h.quote?.fetchedAt;
    if (qt != null && (oldest == null || qt.isBefore(oldest))) oldest = qt;
  }
  return InvestmentSummary(
    baseCurrency: base.toUpperCase(),
    marketValue: mv,
    netValue: net,
    valuation: valuation,
    pnlAfterSellCosts: afterCosts,
    cost: cost,
    realizedPnl: realized,
    dividends: dividends,
    unpricedCount: unpriced,
    missingCurrencies: missing.toList()..sort(),
    oldestQuoteTime: oldest,
    openPositions: open.length,
  );
}

final investmentSummaryProvider = Provider<InvestmentSummary?>((ref) {
  final holdings = ref.watch(allHoldingsProvider);
  if (holdings == null) return null;
  final rates = ref.watch(effectiveRatesProvider).valueOrNull ??
      const <String, EffectiveRate>{};
  final base = ref.watch(baseCurrencyProvider);
  return computeInvestmentSummary(holdings: holdings, rates: rates, base: base);
});

/// 投資理財帳戶以「帳戶幣別」計的持股市值(帳戶列表顯示用,取代交易累計的
/// 成本餘額)。帳戶有未平倉部位但任何一檔缺報價/缺匯率時不給值,讓列表
/// 退回顯示原本的餘額,不顯示一個少算的市值。
final investmentAccountMarketValuesProvider = Provider<Map<int, double>>((ref) {
  final holdings = ref.watch(allHoldingsProvider);
  final accounts = ref.watch(allAccountsStreamProvider).valueOrNull;
  if (holdings == null || accounts == null) return const {};
  final rates = ref.watch(effectiveRatesProvider).valueOrNull ??
      const <String, EffectiveRate>{};
  final base = ref.watch(baseCurrencyProvider);
  final accountCurrency = {
    for (final a in accounts) a.id: a.currency.toUpperCase()
  };
  final sums = <int, double>{};
  final broken = <int>{};
  for (final h in holdings) {
    final aid = h.accountId;
    if (aid == null || !h.holding.isOpen) continue;
    final accCcy = accountCurrency[aid];
    final mv = h.marketValue;
    if (accCcy == null || mv == null) {
      broken.add(aid);
      continue;
    }
    double? converted;
    if (h.currency == accCcy) {
      converted = mv;
    } else {
      final toBase = rateToBase(h.currency, base, rates);
      final accToBase = rateToBase(accCcy, base, rates);
      if (toBase != null && accToBase != null)
        converted = mv * toBase / accToBase;
    }
    if (converted == null) {
      broken.add(aid);
      continue;
    }
    sums.update(aid, (v) => v + converted!, ifAbsent: () => converted!);
  }
  for (final aid in broken) {
    sums.remove(aid);
  }
  return sums;
});

// ---------------------------------------------------------------------------
// 報價刷新
// ---------------------------------------------------------------------------

class QuoteRefreshState {
  final bool refreshing;
  final DateTime? lastRefreshAt;
  final String? lastError;

  /// 目前登入的是 BeeCount Cloud(才有報價可拉);null = 還沒判斷過。
  final bool? cloudAvailable;

  const QuoteRefreshState({
    this.refreshing = false,
    this.lastRefreshAt,
    this.lastError,
    this.cloudAvailable,
  });

  QuoteRefreshState copyWith({
    bool? refreshing,
    DateTime? lastRefreshAt,
    String? lastError,
    bool clearError = false,
    bool? cloudAvailable,
  }) =>
      QuoteRefreshState(
        refreshing: refreshing ?? this.refreshing,
        lastRefreshAt: lastRefreshAt ?? this.lastRefreshAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
        cloudAvailable: cloudAvailable ?? this.cloudAvailable,
      );
}

/// 向 BeeCount Cloud 拉持有標的的報價,寫進本地快取。
///
/// 觸發點:帳戶頁 initState、App 回到前景、持股頁下拉/按鈕。非強制刷新時
/// 1 分鐘內不重打(真正的「盤中 15 分鐘」快取判斷在 server 端,這裡只是避免
/// 同一時間多個畫面各打一次)。
class QuoteRefreshNotifier extends StateNotifier<QuoteRefreshState> {
  QuoteRefreshNotifier(this._ref) : super(const QuoteRefreshState());

  final Ref _ref;
  static const _throttle = Duration(minutes: 1);

  Future<void> refresh({bool force = false, List<String>? extraKeys}) async {
    if (state.refreshing) return;
    final last = state.lastRefreshAt;
    if (!force && last != null && DateTime.now().difference(last) < _throttle)
      return;

    final repo = _ref.read(repositoryProvider);
    final trades = await repo.getAllStockTrades();
    final open = HoldingsCalculator.compute(trades.map(holdingTradeOf))
        .map((h) => securityKey(h.market, h.symbol))
        .toSet();
    if (extraKeys != null) open.addAll(extraKeys);
    if (open.isEmpty) return;

    final cloud = await _ref.read(beecountCloudProviderInstance.future);
    if (cloud == null) {
      state = state.copyWith(cloudAvailable: false);
      return;
    }
    state = state.copyWith(
        refreshing: true, cloudAvailable: true, clearError: true);
    try {
      final rows =
          await cloud.fetchSecurityQuotes(symbolKeys: open.toList()..sort());
      final now = DateTime.now();
      final companions = <SecurityQuotesCompanion>[];
      for (final r in rows) {
        final price = (r['price'] as num?)?.toDouble();
        if (price == null) continue;
        companions.add(SecurityQuotesCompanion.insert(
          market: (r['market'] as String).toUpperCase(),
          symbol: (r['symbol'] as String).toUpperCase(),
          name: d.Value(r['name'] as String?),
          currency: d.Value(r['currency'] as String?),
          price: d.Value(price),
          prevClose: d.Value((r['prev_close'] as num?)?.toDouble()),
          quoteTime:
              d.Value(DateTime.tryParse((r['quote_time'] as String?) ?? '')),
          session: d.Value(r['session'] as String?),
          source: d.Value(r['source'] as String?),
          fetchedAt:
              DateTime.tryParse((r['fetched_at'] as String?) ?? '') ?? now,
        ));
      }
      await repo.upsertSecurityQuotes(companions);
      state = state.copyWith(refreshing: false, lastRefreshAt: now);
    } catch (e) {
      logger.warning('Securities', '報價刷新失敗: $e');
      state = state.copyWith(
          refreshing: false, lastRefreshAt: DateTime.now(), lastError: '$e');
    }
  }

  /// 本地快取裡沒有報價的持股代號,上次為了它們補抓的時間(同一組缺報價的
  /// 代號 10 分鐘內不重打,避免 server 本來就抓不到的代號一直重試)。
  final Map<String, DateTime> _missingAttempts = {};
  static const _missingRetry = Duration(minutes: 10);

  /// 明細變了(本機新增,或 sync 從 Web/其它裝置拉回新代號)時檢查:有未平倉
  /// 部位卻沒有報價的代號就立刻補抓。以前只在帳戶頁 initState / 回前景時抓,
  /// sync 晚一步把新代號拉回來的話要等到下次回前景才有市值。
  Future<void> onTradesChanged(List<StockTrade>? trades) async {
    if (trades == null || trades.isEmpty) return;
    final open = HoldingsCalculator.compute(trades.map(holdingTradeOf))
        .map((h) => securityKey(h.market, h.symbol))
        .toSet();
    if (open.isEmpty) return;
    final cached = (await _ref.read(repositoryProvider).getSecurityQuotes())
        .where((q) => q.price != null)
        .map((q) => securityKey(q.market, q.symbol))
        .toSet();
    final now = DateTime.now();
    final missing = open.difference(cached).where((k) {
      final last = _missingAttempts[k];
      return last == null || now.difference(last) >= _missingRetry;
    }).toList();
    if (missing.isEmpty) return;
    for (final k in missing) {
      _missingAttempts[k] = now;
    }
    await refresh(force: true, extraKeys: missing);
  }

  /// 股票定期定額到期生成前(App 啟動時,見 ui_state_providers.dart)補抓啟用中
  /// 定期定額標的的報價(2026-09-29)。還沒持有的代號(第一期還沒扣)不在
  /// [refresh] 的持股清單裡,以前快取永遠沒有報價,每次啟動都被
  /// quoteUnavailable 跳過。只抓快取缺價或超過 15 分鐘的;沒登入 Cloud 時
  /// [refresh] 自己會直接結束(非 Cloud 使用者只能手動輸入價格)。
  Future<void> refreshForStockDcaRules() async {
    final repo = _ref.read(repositoryProvider);
    final rules = await repo.getAllRulesForExport();
    final keys = rules
        .where((r) =>
            r.enabled && r.kind == 'stock_dca' && r.market != null && r.symbol != null)
        .map((r) => securityKey(r.market!, r.symbol!))
        .toSet();
    if (keys.isEmpty) return;
    final now = DateTime.now();
    final fresh = (await repo.getSecurityQuotes())
        .where((q) =>
            q.price != null &&
            now.difference(q.fetchedAt) < const Duration(minutes: 15))
        .map((q) => securityKey(q.market, q.symbol))
        .toSet();
    final missing = keys.difference(fresh).toList();
    if (missing.isEmpty) return;
    await refresh(force: true, extraKeys: missing);
  }

  /// 新增交易時預帶價格用:本地快取有 15 分鐘內的報價就直接用,否則向 Cloud
  /// 補抓一次(沒登入 Cloud 時只回本地快取,可能是手動輸入的價格)。
  Future<SecurityQuote?> quoteFor(String market, String symbol) async {
    final key = securityKey(market, symbol);
    final repo = _ref.read(repositoryProvider);
    SecurityQuote? find(List<SecurityQuote> rows) {
      for (final q in rows) {
        if (securityKey(q.market, q.symbol) == key && q.price != null) return q;
      }
      return null;
    }

    final cached = find(await repo.getSecurityQuotes());
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) <
            const Duration(minutes: 15)) {
      return cached;
    }
    await refresh(force: true, extraKeys: [key]);
    return find(await repo.getSecurityQuotes()) ?? cached;
  }

  /// 非 Cloud 使用者手動輸入價格(也可以用來暫時覆蓋報價)。
  Future<void> setManualPrice({
    required String market,
    required String symbol,
    required double price,
    String? currency,
    String? name,
  }) async {
    final repo = _ref.read(repositoryProvider);
    final now = DateTime.now();
    await repo.upsertSecurityQuotes([
      SecurityQuotesCompanion.insert(
        market: market.toUpperCase(),
        symbol: symbol.toUpperCase(),
        name: d.Value(name),
        currency: d.Value(currency),
        price: d.Value(price),
        quoteTime: d.Value(now),
        session: const d.Value('manual'),
        source: const d.Value('manual'),
        fetchedAt: now,
      ),
    ]);
  }
}

final quoteRefreshProvider =
    StateNotifierProvider<QuoteRefreshNotifier, QuoteRefreshState>((ref) {
  final notifier = QuoteRefreshNotifier(ref);
  ref.listen<AsyncValue<List<StockTrade>>>(stockTradesProvider,
      (_, next) => notifier.onTradesChanged(next.valueOrNull),
      fireImmediately: true);
  return notifier;
});

/// 目前是否登入 BeeCount Cloud(決定證券搜尋/報價入口要不要顯示)。
final securitiesCloudAvailableProvider = FutureProvider<bool>((ref) async {
  final cloud = await ref.watch(beecountCloudProviderInstance.future);
  return cloud != null;
});

// ============================================================================
// 待確認股利(Phase 2,docs/changes/2026-09-28-stock-dividends.md)
// ============================================================================

/// server `GET /read/securities/pending-dividends` 的一筆。不存本地——狀態只在
/// server,確認後建出來的明細/交易靠 sync pull 回來。
class PendingDividend {
  final int id;
  final String? ledgerSyncId;
  final String accountSyncId;
  final String? accountName;
  final String market;
  final String symbol;
  final String? securityName;
  final String? currency;
  final DateTime exDate;
  final DateTime? payDate;
  final double cashPerShare;
  final double stockPerShare;
  final double shares;
  final double estGross;
  final double estFee;
  final double estTax;
  final double estNet;
  final double estStockShares;
  final String status;
  final bool reinvestDefault;
  final String? settlementAccountSyncId;
  final double? quotePrice;

  const PendingDividend({
    required this.id,
    required this.ledgerSyncId,
    required this.accountSyncId,
    required this.accountName,
    required this.market,
    required this.symbol,
    required this.securityName,
    required this.currency,
    required this.exDate,
    required this.payDate,
    required this.cashPerShare,
    required this.stockPerShare,
    required this.shares,
    required this.estGross,
    required this.estFee,
    required this.estTax,
    required this.estNet,
    required this.estStockShares,
    required this.status,
    required this.reinvestDefault,
    required this.settlementAccountSyncId,
    required this.quotePrice,
  });

  factory PendingDividend.fromJson(Map<String, dynamic> j) {
    double n(String k) => (j[k] as num?)?.toDouble() ?? 0;
    return PendingDividend(
      id: (j['id'] as num).toInt(),
      ledgerSyncId: j['ledger_id'] as String?,
      accountSyncId: j['account_id'] as String,
      accountName: j['account_name'] as String?,
      market: (j['market'] as String).toUpperCase(),
      symbol: (j['symbol'] as String).toUpperCase(),
      securityName: j['security_name'] as String?,
      currency: (j['currency'] as String?)?.toUpperCase(),
      exDate: DateTime.parse(j['ex_date'] as String),
      payDate: DateTime.tryParse((j['pay_date'] as String?) ?? ''),
      cashPerShare: n('cash_per_share'),
      stockPerShare: n('stock_per_share'),
      shares: n('shares'),
      estGross: n('est_gross'),
      estFee: n('est_fee'),
      estTax: n('est_tax'),
      estNet: n('est_net'),
      estStockShares: n('est_stock_shares'),
      status: (j['status'] as String?) ?? 'pending',
      reinvestDefault: j['reinvest_default'] == true,
      settlementAccountSyncId: j['settlement_account_id'] as String?,
      quotePrice: (j['quote_price'] as num?)?.toDouble(),
    );
  }
}

class PendingDividendsState {
  final List<PendingDividend> items;
  final bool loading;
  final DateTime? lastRefreshAt;
  final String? lastError;

  const PendingDividendsState({
    this.items = const [],
    this.loading = false,
    this.lastRefreshAt,
    this.lastError,
  });

  PendingDividendsState copyWith({
    List<PendingDividend>? items,
    bool? loading,
    DateTime? lastRefreshAt,
    String? lastError,
    bool clearError = false,
  }) =>
      PendingDividendsState(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        lastRefreshAt: lastRefreshAt ?? this.lastRefreshAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

class PendingDividendsNotifier extends StateNotifier<PendingDividendsState> {
  PendingDividendsNotifier(this._ref) : super(const PendingDividendsState());

  final Ref _ref;
  static const _throttle = Duration(minutes: 1);

  Future<void> refresh({bool force = false}) async {
    if (state.loading) return;
    final last = state.lastRefreshAt;
    if (!force && last != null && DateTime.now().difference(last) < _throttle)
      return;
    final cloud = await _ref.read(beecountCloudProviderInstance.future);
    if (cloud == null || !mounted) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final rows = await cloud.fetchPendingDividends();
      if (!mounted) return;
      state = PendingDividendsState(
        items: rows.map(PendingDividend.fromJson).toList(),
        lastRefreshAt: DateTime.now(),
      );
    } catch (e) {
      // 舊版 server 沒有這個端點(404)→ 當作沒有待確認股利。
      logger.warning('Securities', '待確認股利讀取失敗: $e');
      if (!mounted) return;
      state = state.copyWith(
          loading: false, lastRefreshAt: DateTime.now(), lastError: '$e');
    }
  }

  Future<List<PendingDividend>> fetchDismissed() async {
    final cloud = await _ref.read(beecountCloudProviderInstance.future);
    if (cloud == null) return const [];
    final rows = await cloud.fetchPendingDividends(status: 'dismissed');
    return rows.map(PendingDividend.fromJson).toList();
  }

  /// 確認後觸發一次 sync 把 server 建的明細/交易拉回來(WS 也會通知,這是
  /// 保險)。[body] 見 Cloud `PendingDividendConfirmRequest`。
  Future<void> confirm(PendingDividend item, Map<String, dynamic> body) async {
    final cloud = await _ref.read(beecountCloudProviderInstance.future);
    if (cloud == null) throw StateError('BeeCount Cloud is not available');
    await cloud.confirmPendingDividend(id: item.id, body: body);
    if (mounted)
      state = state.copyWith(
          items: state.items.where((p) => p.id != item.id).toList());
    await _pullAfterWrite();
  }

  Future<void> setDismissed(PendingDividend item, bool dismissed) async {
    final cloud = await _ref.read(beecountCloudProviderInstance.future);
    if (cloud == null) throw StateError('BeeCount Cloud is not available');
    await cloud.setPendingDividendDismissed(id: item.id, dismissed: dismissed);
    await refresh(force: true);
  }

  Future<void> _pullAfterWrite() async {
    final sync = _ref.read(syncServiceProvider);
    if (sync is! SyncEngine) return;
    final ledgerId = _ref.read(currentLedgerIdProvider);
    try {
      await sync.sync(ledgerId: ledgerId.toString());
      _ref.read(syncStatusRefreshProvider.notifier).state++;
    } catch (e) {
      logger.warning('Securities', '確認股利後同步失敗: $e');
    }
  }
}

final pendingDividendsProvider =
    StateNotifierProvider<PendingDividendsNotifier, PendingDividendsState>(
        (ref) => PendingDividendsNotifier(ref));

/// 某個投資理財帳戶(本地 id)的待確認股利。
final accountPendingDividendsProvider =
    Provider.family<List<PendingDividend>, int>((ref, accountId) {
  final items = ref.watch(pendingDividendsProvider.select((s) => s.items));
  final accounts =
      ref.watch(allAccountsStreamProvider).valueOrNull ?? const <Account>[];
  final syncId = accounts.where((a) => a.id == accountId).firstOrNull?.syncId;
  if (syncId == null) return const [];
  return items.where((p) => p.accountSyncId == syncId).toList();
});
