import 'dart:async';
import 'dart:convert';

import '../../data/db.dart'
    show Account, RecurringTransaction, SecurityQuote, StockTrade;
import '../../data/repositories/base_repository.dart';
import '../../models/investment_settings.dart';
import '../../providers/securities_providers.dart'
    show HoldingView, holdingTradeOf;
import '../../utils/zh_variants.dart';
import '../investment/holdings_calculator.dart';
import '../investment/markets.dart';
import '../investment/realized_pnl_report.dart';
import '../investment/stock_dca.dart';
import '../investment/stock_trade_types.dart';
import 'free_chat_tool_spec.dart';

/// 自由對話的股票唯讀工具(2026-10-03,docs/changes/2026-10-03-stock-ai-tools.md)。
///
/// 全部唯讀、全部打本機 SQLite:
/// - **跨帳本**:股票明細的帳戶是 user-global,持股頁也是跨帳本彙總
///   (`stockTradesProvider` = `watchAllStockTrades`),所以這裡一律讀全部帳本,
///   不吃 router 傳進來的 ledgerId。
/// - **口徑同持股頁**:持股/市值/未實現損益直接重用 [HoldingView]
///   (含「扣預估賣出手續費/證交稅」帳戶設定),已實現損益重用
///   [RealizedPnlReport],不另寫一份算法。
/// - **報價只讀本機快取**(`SecurityQuotes`),聊天中不打網路;每筆報價都帶
///   時間與是否過期,讓回答可以說明「報價為某時間」。
/// - **各幣別分開**:任何彙總都以幣別為 key,不跨幣別加總。
/// - **大小有上限**:明細/持股/分組都有筆數上限,超過會標 `truncated`,
///   彙總數字永遠涵蓋全部資料(同 query_transactions 的設計)。

/// 待確認股利只存在 Cloud(不進本機 DB,見 securities_providers 的
/// `PendingDividend`),聊天只能讀「App 目前已載入的快取」。呼叫端(provider)
/// 把它轉成純 Map 傳進來,避免 services 依賴 provider 型別。
///
/// 每個 Map 的 key:accountName、market、symbol、securityName、currency、
/// exDate(yyyy-MM-dd)、payDate(yyyy-MM-dd|null)、cashPerShare、stockPerShare、
/// shares、estGross、estNet、estStockShares、status。
typedef StockPendingDividendsLoader = FutureOr<List<Map<String, dynamic>>>
    Function();

/// 明細樣本預設/最大筆數。
const int kStockToolSampleDefault = 20;
const int kStockToolSampleMax = 50;

/// 持股列表最多回傳幾檔(彙總永遠涵蓋全部)。
const int kStockToolMaxPositions = 25;

/// 已實現損益:最多回傳幾個標的分組、每組最多幾筆賣出明細。
const int kStockToolMaxGroups = 15;
const int kStockToolMaxEventsPerGroup = 5;

/// 報價超過這麼久沒更新就標 `stale: true`。72 小時 = 容得下「週五收盤抓一次、
/// 週一下午前沒開 App」的正常週末,超過就是真的沒更新到。
const Duration kStockQuoteStaleAfter = Duration(hours: 72);

/// 投資分析的觀察門檻(都是「客觀陳述」用的,不是買賣訊號)。
const double kConcentrationSingleWeightPercent = 50;
const double kConcentrationTop3WeightPercent = 80;
const int kLongLossHoldDays = 365;
const double kLongLossPercent = -10;
const double kDeepLossPercent = -30;
const double kFeeTaxHighPercentOfBuy = 1;

const String kStockToolDataScopeNote =
    '資料來自本機所有帳本的股票明細(同持股頁);報價是本機快取、聊天中不會即時更新;'
    '各幣別分開計算,請勿跨幣別加總。';

const String _accountDesc = '限定投資理財帳戶名稱(例如「永豐證券」)。'
    '完全相同優先,沒有完全相同時退化為包含比對。省略則涵蓋所有投資帳戶';
const String _symbolDesc = '限定標的:代號(2330、AAPL、TW:2330)或名稱(台積電),'
    '可給字串或陣列(例如 ["2330","0050"])。省略則不限標的';
const String _stockStartDesc = '區間開始日期(交易日),格式 YYYY-MM-DD。省略代表不限開始';
const String _stockEndDesc = '區間結束日期(含當天),格式 YYYY-MM-DD。省略代表到今天為止';

const List<FreeChatToolSpec> freeChatStockToolSpecs = [
  FreeChatToolSpec(
    name: 'stock_holdings',
    description: '目前股票持股:每檔的股數/平均成本/總成本/本機快取報價(含報價時間與是否過期)/'
        '市值/未實現損益(跟持股頁同口徑,依帳戶「損益是否扣預估賣出成本」設定),'
        '並附各幣別分開的總市值、成本、未實現損益。適合「我現在有哪些股票」'
        '「台積電我有幾股、成本多少」「股票目前賺還是賠」',
    params: [
      FreeChatToolParam(
          name: 'account', type: 'string', description: _accountDesc),
      FreeChatToolParam(
          name: 'symbol', type: 'string|array', description: _symbolDesc),
      FreeChatToolParam(
        name: 'includeClosed',
        type: 'bool',
        description: 'true 時也列出已全部賣出的部位(只剩已實現損益/股利),預設 false',
      ),
    ],
  ),
  FreeChatToolSpec(
    name: 'stock_trades',
    description: '股票交易明細(買進/賣出/期初持股/股利/配股/分割):回傳**完整彙總**'
        '(各幣別買進金額、賣出淨額、手續費總額、交易稅總額、筆數)加上依日期新到舊的明細樣本與'
        '最近一筆。適合「我買過哪些股票」「這個月買賣了什麼」「手續費/交易稅總共多少」'
        '「最近一筆交易是什麼」「台積電買賣紀錄」',
    params: [
      FreeChatToolParam(
          name: 'account', type: 'string', description: _accountDesc),
      FreeChatToolParam(
          name: 'symbol', type: 'string|array', description: _symbolDesc),
      FreeChatToolParam(
          name: 'startDate', type: 'date', description: _stockStartDesc),
      FreeChatToolParam(
          name: 'endDate', type: 'date', description: _stockEndDesc),
      FreeChatToolParam(
        name: 'tradeType',
        type: 'string',
        description: "交易類型:'buy' 買進、'sell' 賣出、'opening' 期初持股、"
            "'cash_dividend' 現金股利、'reinvest' 股利再投入、'stock_dividend' 配股、"
            "'split' 股票分割、'dividend' 以上三種股利合稱。省略則全部類型",
      ),
      FreeChatToolParam(
        name: 'limit',
        type: 'int',
        description: '明細樣本最多幾筆,0~50,預設 20。0 代表只要彙總。'
            '只影響樣本,不影響彙總數字',
      ),
    ],
  ),
  FreeChatToolSpec(
    name: 'stock_realized_pnl',
    description: '已實現損益(賣出已落袋的賺賠,移動平均成本法、已扣手續費與交易稅)'
        '加期間內累計股利,各幣別分開,依標的分組並附賣出明細。可依年度/標的/帳戶篩選。'
        '適合「今年賣股賺了多少」「台積電賣出賺賠」「哪年已實現損益最多」',
    params: [
      FreeChatToolParam(
        name: 'year',
        type: 'int',
        description: '西元年度,例如 2026。省略代表全部年度',
      ),
      FreeChatToolParam(
          name: 'account', type: 'string', description: _accountDesc),
      FreeChatToolParam(
          name: 'symbol', type: 'string|array', description: _symbolDesc),
    ],
  ),
  FreeChatToolSpec(
    name: 'stock_dividends',
    description: '股利:已入帳的現金股利/股利再投入/配股(各幣別累計、依標的分組、近 12 個月、'
        '最近幾筆),以及 App 目前已知的待確認股利(除息後尚未確認入帳)。'
        '適合「我領過多少股利」「今年股利」「台積電配息紀錄」「有沒有待確認的股利」',
    params: [
      FreeChatToolParam(
        name: 'year',
        type: 'int',
        description: '西元年度。省略代表全部期間(startDate/endDate 另可指定區間)',
      ),
      FreeChatToolParam(
          name: 'startDate', type: 'date', description: _stockStartDesc),
      FreeChatToolParam(
          name: 'endDate', type: 'date', description: _stockEndDesc),
      FreeChatToolParam(
          name: 'account', type: 'string', description: _accountDesc),
      FreeChatToolParam(
          name: 'symbol', type: 'string|array', description: _symbolDesc),
    ],
  ),
  FreeChatToolSpec(
    name: 'stock_settings',
    description: '投資理財帳戶的費用設定:手續費率/折扣/最低手續費、證交稅率(普通股/ETF/債券 ETF)、'
        '股利手續費/預扣稅/二代健保、預設交割帳戶、股利是否預設再投入、'
        '未實現損益是否扣預估賣出成本;分「使用者自訂的項目」與「實際生效值(含市場預設)」。'
        '適合「我的手續費設定是幾折」「證交稅怎麼算」「損益有沒有扣賣出成本」',
    params: [
      FreeChatToolParam(
          name: 'account', type: 'string', description: _accountDesc),
    ],
  ),
  FreeChatToolSpec(
    name: 'stock_dca_plans',
    description: '股票定期定額計畫(週期性收支裡 kind=stock_dca 的規則):標的、每期金額、'
        '頻率、下次扣款日、交割/投資帳戶、手續費覆寫、已執行期數與累計投入。'
        '適合「我有哪些定期定額」「0050 定期定額每月多少、已經扣幾期」',
    params: [
      FreeChatToolParam(
          name: 'account', type: 'string', description: _accountDesc),
      FreeChatToolParam(
          name: 'symbol', type: 'string|array', description: _symbolDesc),
      FreeChatToolParam(
        name: 'includeDisabled',
        type: 'bool',
        description: '是否包含已停用/已結束的計畫,預設 true(每筆都標 enabled)',
      ),
    ],
  ),
  FreeChatToolSpec(
    name: 'stock_performance',
    description: '股票賺不賺錢:各幣別的總報酬 = 未實現損益 + 已實現損益 + 累計股利,'
        '每檔表現排名(依總報酬),以及股利殖利率估算(近 12 個月股利 ÷ 持股成本、÷ 持股市值)。'
        '適合「我股票整體賺還是賠」「總報酬多少」「哪檔賺最多/賠最多」「殖利率多少」',
    params: [
      FreeChatToolParam(
          name: 'account', type: 'string', description: _accountDesc),
      FreeChatToolParam(
          name: 'symbol', type: 'string|array', description: _symbolDesc),
    ],
  ),
  FreeChatToolSpec(
    name: 'stock_portfolio_analysis',
    description: '基於持股數據的投資組合分析(給理財建議類問題用):集中度(單一標的/帳戶佔比、'
        '前三大合計)、幣別與市場分布、ETF 與個股比例(僅台股可分類)、長期虧損/深度虧損標的、'
        '手續費與交易稅佔投入比例、股利收入概況,並附客觀的 observations 清單。'
        '適合「幫我分析持股」「我的投資組合有什麼風險」「是不是太集中」'
        '「該怎麼調整/有什麼建議」「手續費會不會太高」。**回答必須附免責聲明**',
    params: [
      FreeChatToolParam(
          name: 'account', type: 'string', description: _accountDesc),
    ],
  ),
];

final Set<String> _stockToolNames =
    freeChatStockToolSpecs.map((t) => t.name).toSet();

bool isFreeChatStockTool(String name) => _stockToolNames.contains(name);

/// 分派到對應的股票工具。參數錯誤(日期格式、tradeType 不合法)拋
/// [FreeChatToolException],由 router 降級。
Future<Map<String, dynamic>> executeFreeChatStockTool(
  String toolName,
  Map<String, dynamic> params, {
  required BaseRepository repo,
  required DateTime now,
  StockPendingDividendsLoader? pendingDividends,
}) async {
  final tools = _StockTools(await _StockData.load(repo, now), repo);
  switch (toolName) {
    case 'stock_holdings':
      return tools.holdings(params);
    case 'stock_trades':
      return tools.trades(params);
    case 'stock_realized_pnl':
      return tools.realizedPnl(params);
    case 'stock_dividends':
      return tools.dividends(params, pendingDividends);
    case 'stock_settings':
      return tools.settings(params);
    case 'stock_dca_plans':
      return tools.dcaPlans(params);
    case 'stock_performance':
      return tools.performance(params);
    case 'stock_portfolio_analysis':
      return tools.portfolioAnalysis(params);
    default:
      throw FreeChatToolException('未知工具: $toolName');
  }
}

// ============================================================================
// 資料載入與範圍解析
// ============================================================================

class _StockData {
  final DateTime now;
  final List<StockTrade> trades;
  final List<Account> accounts;
  final Map<int, Account> accById;
  final Map<String, SecurityQuote> quotes;

  /// 全部明細算出的持股(含已出清),已套上報價與帳戶設定,同
  /// `allHoldingsProvider`。
  final List<HoldingView> views;

  /// securityKey → 顯示名稱(明細最新名稱 > 報價名稱 > 定期定額規則名稱)。
  final Map<String, String> securityNames;

  _StockData._(this.now, this.trades, this.accounts, this.accById, this.quotes,
      this.views, this.securityNames);

  static Future<_StockData> load(BaseRepository repo, DateTime now) async {
    final trades = await repo.getAllStockTrades();
    final accounts = await repo.getAllAccounts();
    final quoteRows = await repo.getSecurityQuotes();
    final quotes = {
      for (final q in quoteRows) securityKey(q.market, q.symbol): q,
    };
    final accById = {for (final a in accounts) a.id: a};
    final settingsById = {
      for (final a in accounts)
        a.id: InvestmentSettings.parse(a.investmentSettingsJson),
    };
    final holdings = HoldingsCalculator.compute(
      trades.map(holdingTradeOf),
      includeClosed: true,
    );
    final views = [
      for (final h in holdings)
        HoldingView(
          holding: h,
          accountId: int.tryParse(h.accountKey ?? ''),
          quote: quotes[securityKey(h.market, h.symbol)],
          settings: settingsById[int.tryParse(h.accountKey ?? '')] ??
              InvestmentSettings.empty,
        ),
    ];

    final names = <String, String>{};
    for (final q in quoteRows) {
      final n = q.name;
      if (n != null && n.isNotEmpty) names[securityKey(q.market, q.symbol)] = n;
    }
    final sorted = [...trades]
      ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
    for (final t in sorted) {
      final n = t.securityName;
      if (n != null && n.isNotEmpty) names[securityKey(t.market, t.symbol)] = n;
    }
    // 定期定額規則可能指向「還沒買過」的標的,名稱也要能被比對到。
    final rules = await repo.getAllRulesForExport();
    for (final r in rules) {
      if (r.kind != 'stock_dca' || r.market == null || r.symbol == null) {
        continue;
      }
      final key = securityKey(r.market!, r.symbol!);
      final n = r.securityName;
      if (n != null && n.isNotEmpty) names.putIfAbsent(key, () => n);
      names.putIfAbsent(key, () => '');
    }
    return _StockData._(now, trades, accounts, accById, quotes, views, names);
  }

  String accountName(int? id) =>
      id == null ? '' : (accById[id]?.name ?? '帳戶#$id');

  String currencyOf(String? currency, String market) {
    final c = (currency ?? '').toUpperCase();
    if (c.isNotEmpty) return c;
    return stockMarketByCode(market)?.currency ?? '';
  }

  String? nameOf(String market, String symbol) {
    final n = securityNames[securityKey(market, symbol)];
    return (n == null || n.isEmpty) ? null : n;
  }
}

/// `account` / `symbol` 參數解析後的篩選範圍。
class _Scope {
  /// null = 不篩帳戶。
  final Set<int>? accountIds;
  final List<String> accountNames;

  /// null = 不篩標的(securityKey 集合)。
  final Set<String>? securityKeys;
  final List<String> securityLabels;
  final String? accountQuery;
  final List<String> symbolQueries;

  const _Scope({
    required this.accountIds,
    required this.accountNames,
    required this.securityKeys,
    required this.securityLabels,
    required this.accountQuery,
    required this.symbolQueries,
  });

  /// 有指定但一個都沒比對到 → 整個結果必為空,工具應直接回「找不到」。
  bool get accountUnmatched => accountQuery != null && accountIds!.isEmpty;
  bool get symbolUnmatched => symbolQueries.isNotEmpty && securityKeys!.isEmpty;
  bool get unmatched => accountUnmatched || symbolUnmatched;

  bool matchesAccount(int? id) =>
      accountIds == null || (id != null && accountIds!.contains(id));
  bool matchesSecurity(String market, String symbol) =>
      securityKeys == null ||
      securityKeys!.contains(securityKey(market, symbol));
  bool matches(int? accountId, String market, String symbol) =>
      matchesAccount(accountId) && matchesSecurity(market, symbol);

  Map<String, dynamic> toJson() => {
        'account': accountQuery,
        'resolvedAccounts': accountIds == null ? null : accountNames,
        'symbol': symbolQueries.isEmpty ? null : symbolQueries,
        'resolvedSecurities': securityKeys == null ? null : securityLabels,
        if (unmatched)
          'warning': accountUnmatched
              ? '找不到名稱相近的投資理財帳戶,結果為空'
              : '找不到相符的股票標的(沒有任何交易/計畫紀錄),結果為空',
      };
}

// ============================================================================
// 工具本體
// ============================================================================

class _StockTools {
  final _StockData d;
  final BaseRepository repo;
  _StockTools(this.d, this.repo);

  // --------------------------------------------------------------------------
  // 參數解析
  // --------------------------------------------------------------------------

  _Scope scope(Map<String, dynamic> params, {bool withSymbol = true}) {
    final accountQuery = _optString(params['account']);
    Set<int>? accountIds;
    var accountNames = <String>[];
    if (accountQuery != null) {
      final pool = d.accounts.where((a) => a.type == 'investment').toList();
      final folded = foldZh(accountQuery);
      List<Account> pick(bool Function(String n) test) =>
          pool.where((a) => test(foldZh(a.name))).toList();
      var hits = pick((n) => n == folded);
      if (hits.isEmpty) hits = pick((n) => n.contains(folded));
      if (hits.isEmpty) hits = pick((n) => folded.contains(n));
      accountIds = {for (final a in hits) a.id};
      accountNames = [for (final a in hits) a.name];
    }

    final symbolQueries = withSymbol
        ? _optStringList(params['symbol']) ?? const <String>[]
        : const <String>[];
    Set<String>? keys;
    var labels = <String>[];
    if (symbolQueries.isNotEmpty) {
      keys = <String>{};
      for (final q in symbolQueries) {
        keys.addAll(_resolveSecurity(q));
      }
      labels = [
        for (final k in keys)
          d.securityNames[k]?.isNotEmpty == true
              ? '$k ${d.securityNames[k]}'
              : k,
      ];
    }
    return _Scope(
      accountIds: accountIds,
      accountNames: accountNames,
      securityKeys: keys,
      securityLabels: labels,
      accountQuery: accountQuery,
      symbolQueries: symbolQueries,
    );
  }

  /// 代號/名稱 → securityKey 集合。依序:`MKT:SYM` 完整鍵 → 代號完全相同
  /// (大小寫不分,台股 TW/TWO 都算)→ 名稱完全相同 → 名稱包含 → 查詢字串包含名稱。
  /// 有命中就不再往下,避免模糊比對發散。
  Set<String> _resolveSecurity(String query) {
    final catalog = d.securityNames.keys.toList();
    final q = query.trim();
    final upper = q.toUpperCase();
    String symOf(String key) => key.substring(key.indexOf(':') + 1);

    if (upper.contains(':')) {
      return catalog.where((k) => k == upper).toSet();
    }
    var hits = catalog.where((k) => symOf(k) == upper).toSet();
    if (hits.isNotEmpty) return hits;

    final folded = foldZh(q);
    String? nameOf(String k) {
      final n = d.securityNames[k];
      return (n == null || n.isEmpty) ? null : foldZh(n);
    }

    hits = catalog.where((k) => nameOf(k) == folded).toSet();
    if (hits.isNotEmpty) return hits;
    hits = catalog.where((k) => nameOf(k)?.contains(folded) ?? false).toSet();
    if (hits.isNotEmpty) return hits;
    return catalog.where((k) {
      final n = nameOf(k);
      return n != null && n.length >= 2 && folded.contains(n);
    }).toSet();
  }

  /// 回傳 (開始, 結束) 的 `yyyy-MM-dd`(含頭含尾);沒給就是 null。
  ({String? start, String? end}) dateRange(Map<String, dynamic> params) {
    String? parse(String key) {
      final raw = params[key];
      if (raw == null) return null;
      if (raw is! String || raw.isEmpty) {
        throw FreeChatToolException('參數 $key 日期格式錯誤: $raw');
      }
      final p = DateTime.tryParse(raw);
      if (p == null) throw FreeChatToolException('參數 $key 日期格式錯誤: $raw');
      return formatIsoDate(p);
    }

    return (start: parse('startDate'), end: parse('endDate'));
  }

  int? year(Map<String, dynamic> params) {
    final raw = params['year'];
    if (raw == null) return null;
    final y = raw is num ? raw.toInt() : int.tryParse(raw.toString().trim());
    if (y == null || y < 1900 || y > 2200) {
      throw FreeChatToolException('參數 year 必須是西元年度: $raw');
    }
    return y;
  }

  static String? _optString(dynamic raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    return raw.trim();
  }

  static List<String>? _optStringList(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      final v = raw.trim();
      return v.isEmpty ? null : [v];
    }
    if (raw is List) {
      final out = raw
          .whereType<Object>()
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return out.isEmpty ? null : out;
    }
    throw FreeChatToolException('參數 symbol 必須是字串或字串陣列: $raw');
  }

  int limit(dynamic raw) {
    var v = kStockToolSampleDefault;
    if (raw is num) {
      v = raw.toInt();
    } else if (raw is String) {
      v = int.tryParse(raw) ?? kStockToolSampleDefault;
    }
    return v.clamp(0, kStockToolSampleMax);
  }

  // --------------------------------------------------------------------------
  // 輸出整理
  // --------------------------------------------------------------------------

  static double _r(double v, [int digits = 2]) {
    final f = _pow10(digits);
    return (v * f).roundToDouble() / f;
  }

  static double _pow10(int n) {
    var r = 1.0;
    for (var i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }

  static double? _rn(double? v, [int digits = 2]) =>
      v == null ? null : _r(v, digits);

  String _stamp(DateTime t) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${formatIsoDate(t)} ${p(t.hour)}:${p(t.minute)}';
  }

  /// 報價資訊:價格、報價時間、抓取時間、來源 session、是否過期。
  Map<String, dynamic> quoteMeta(SecurityQuote? q) {
    if (q == null || q.price == null) {
      return {'available': false};
    }
    final fetched = q.fetchedAt;
    final age = d.now.difference(fetched);
    return {
      'available': true,
      'price': q.price,
      'quoteTime': q.quoteTime == null ? null : _stamp(q.quoteTime!),
      'fetchedAt': _stamp(fetched),
      'session': q.session,
      'source': q.source,
      'ageHours': age.isNegative ? 0 : age.inHours,
      'stale': age > kStockQuoteStaleAfter,
    };
  }

  Map<String, dynamic> positionJson(HoldingView v) {
    final h = v.holding;
    final est = v.sellEstimate;
    return {
      'account': d.accountName(v.accountId),
      'market': h.market,
      'symbol': h.symbol,
      'name': v.name,
      'currency': v.currency,
      'isOpen': h.isOpen,
      'shares': _r(h.shares, 4),
      'avgCost': _r(h.avgCost, 4),
      'totalCost': _r(h.totalCost),
      'quote': quoteMeta(v.quote),
      'marketValue': _rn(v.marketValue),
      'estSellFee': _rn(est?.fee),
      'estSellTax': _rn(est?.tax),
      'netValue': _rn(v.netValue),
      'unrealizedPnl': _rn(v.unrealizedPnl),
      'unrealizedPnlPercent': _rn(v.unrealizedPnlPercent),
      'dayChangePercent': _rn(v.dayChangePercent),
      'realizedPnl': _r(h.realizedPnl),
      'dividends': _r(h.dividends),
      'tradeCount': h.tradeCount,
      'firstTradeDate': h.firstTradeDate,
      'lastTradeDate': h.lastTradeDate,
    };
  }

  /// 各幣別彙總(持股頁口徑)。[views] 含已出清部位時,已實現/股利也算進去,
  /// 市值/成本/未實現只算未平倉。
  Map<String, Map<String, dynamic>> currencyTotals(List<HoldingView> views) {
    final acc = <String, _CcyAcc>{};
    for (final v in views) {
      final a = acc.putIfAbsent(v.currency, _CcyAcc.new);
      a.realized += v.holding.realizedPnl;
      a.dividends += v.holding.dividends;
      if (!v.holding.isOpen) continue;
      a.positions += 1;
      a.cost += v.holding.totalCost;
      final value = v.marketValue;
      if (value == null) {
        a.unpriced += 1;
        continue;
      }
      a.pricedCost += v.holding.totalCost;
      a.marketValue += value;
      a.netValue += v.netValue ?? value;
      a.valuation += v.valuation ?? value;
      a.afterCostFlags.add(v.pnlAfterSellCosts);
      final qt = v.quote?.quoteTime ?? v.quote?.fetchedAt;
      if (qt != null &&
          (a.oldestQuote == null || qt.isBefore(a.oldestQuote!))) {
        a.oldestQuote = qt;
      }
      if (v.quote != null &&
          d.now.difference(v.quote!.fetchedAt) > kStockQuoteStaleAfter) {
        a.staleCount += 1;
      }
    }
    return {
      for (final e in acc.entries)
        e.key: {
          'openPositions': e.value.positions,
          'cost': _r(e.value.cost),
          'pricedCost': _r(e.value.pricedCost),
          'marketValue': _r(e.value.marketValue),
          'netValue': _r(e.value.netValue),
          'valuation': _r(e.value.valuation),
          'unrealizedPnl': _r(e.value.valuation - e.value.pricedCost),
          'unrealizedPnlPercent': e.value.pricedCost > 0
              ? _r((e.value.valuation - e.value.pricedCost) /
                  e.value.pricedCost *
                  100)
              : null,
          'pnlBasis': e.value.pnlBasis,
          'unpricedCount': e.value.unpriced,
          'staleQuoteCount': e.value.staleCount,
          'oldestQuoteTime':
              e.value.oldestQuote == null ? null : _stamp(e.value.oldestQuote!),
          'realizedPnl': _r(e.value.realized),
          'dividends': _r(e.value.dividends),
        },
    };
  }

  List<HoldingView> viewsIn(_Scope s, {bool includeClosed = true}) => d.views
      .where((v) =>
          s.matches(v.accountId, v.holding.market, v.holding.symbol) &&
          (includeClosed || v.holding.isOpen))
      .toList();

  Map<String, dynamic> emptyResult(_Scope s, String what) => {
        'filters': s.toJson(),
        'note': s.unmatched
            ? '篩選條件沒有比對到任何$what。${s.toJson()['warning']}'
            : '目前沒有任何$what。如果使用者說有,請提醒他先在投資頁新增股票交易。',
      };

  // --------------------------------------------------------------------------
  // stock_holdings
  // --------------------------------------------------------------------------

  Map<String, dynamic> holdings(Map<String, dynamic> params) {
    final s = scope(params);
    final includeClosed = params['includeClosed'] == true;
    final all = viewsIn(s);
    final open = all.where((v) => v.holding.isOpen).toList();
    if (s.unmatched || (open.isEmpty && !includeClosed && all.isEmpty)) {
      return {...emptyResult(s, '股票持股'), 'holdingCount': 0};
    }

    final shown = (includeClosed ? all : open)
      ..sort((a, b) => b.holding.totalCost.compareTo(a.holding.totalCost));
    final capped = shown.take(kStockToolMaxPositions).toList();
    return {
      'asOf': _stamp(d.now),
      'filters': s.toJson(),
      'holdingCount': open.length,
      'positions': capped.map(positionJson).toList(),
      'positionsTruncated': shown.length > capped.length,
      'byCurrency': currencyTotals(all),
      'note': '$kStockToolDataScopeNote unrealizedPnl 口徑同持股頁:pnlBasis 為 '
          'afterEstimatedSellCosts 表示已扣預估賣出手續費與證交稅。'
          'byCurrency 已涵蓋全部持股,positions 若 truncated 只是其中成本最大的幾檔。',
      if (open.isEmpty) 'emptyHint': '目前沒有未平倉的持股(全部已賣出)',
    };
  }

  // --------------------------------------------------------------------------
  // stock_trades
  // --------------------------------------------------------------------------

  static const _dividendTypes = {
    kStockTradeCashDividend,
    kStockTradeReinvest,
    kStockTradeStockDividend,
  };

  Map<String, dynamic> trades(Map<String, dynamic> params) {
    final s = scope(params);
    final range = dateRange(params);
    final typeRaw = _optString(params['tradeType'])?.toLowerCase();
    Set<String>? types;
    if (typeRaw != null) {
      if (typeRaw == 'dividend') {
        types = _dividendTypes;
      } else if (kStockTradeTypes.contains(typeRaw)) {
        types = {typeRaw};
      } else {
        throw FreeChatToolException('參數 tradeType 不合法: $typeRaw');
      }
    }
    final sampleLimit = limit(params['limit']);

    final matched = d.trades.where((t) {
      if (!s.matches(t.accountId, t.market, t.symbol)) return false;
      if (types != null && !types.contains(t.tradeType)) return false;
      final key = HoldingTrade.dateKey(t.tradeDate);
      if (range.start != null && key.compareTo(range.start!) < 0) return false;
      if (range.end != null && key.compareTo(range.end!) > 0) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        final c = b.tradeDate.compareTo(a.tradeDate);
        return c != 0 ? c : (b.id).compareTo(a.id);
      });

    if (matched.isEmpty) {
      return {
        ...emptyResult(s, '符合條件的股票交易'),
        'range': _rangeJson(range),
        'matchedCount': 0,
      };
    }

    final totals = <String, Map<String, num>>{};
    final byType = <String, int>{};
    for (final t in matched) {
      final ccy = d.currencyOf(t.currency, t.market);
      final m = totals.putIfAbsent(
          ccy,
          () => {
                'buyAmount': 0.0,
                'buyCount': 0,
                'sellAmount': 0.0,
                'sellCount': 0,
                'openingCost': 0.0,
                'fee': 0.0,
                'tax': 0.0,
                'dividendFeeAndTax': 0.0,
              });
      byType.update(t.tradeType, (v) => v + 1, ifAbsent: () => 1);
      if (t.tradeType == kStockTradeBuy) {
        m['buyAmount'] = m['buyAmount']! + t.amount;
        m['buyCount'] = m['buyCount']! + 1;
      } else if (t.tradeType == kStockTradeSell) {
        m['sellAmount'] = m['sellAmount']! + t.amount;
        m['sellCount'] = m['sellCount']! + 1;
      } else if (t.tradeType == kStockTradeOpening) {
        m['openingCost'] = m['openingCost']! + t.amount;
      }
      // 手續費/交易稅總額只算買賣(含期初);股利的匯費/預扣稅另列,不混進去。
      if (_dividendTypes.contains(t.tradeType)) {
        m['dividendFeeAndTax'] = m['dividendFeeAndTax']! + t.fee + t.tax;
      } else {
        m['fee'] = m['fee']! + t.fee;
        m['tax'] = m['tax']! + t.tax;
      }
    }

    Map<String, dynamic> tradeJson(StockTrade t) => {
          'date': HoldingTrade.dateKey(t.tradeDate),
          'account': d.accountName(t.accountId),
          'market': t.market,
          'symbol': t.symbol,
          'name': t.securityName ?? d.nameOf(t.market, t.symbol),
          'type': t.tradeType,
          if (t.tradeType == kStockTradeSplit)
            'splitRatio': t.shares
          else
            'shares': _r(t.shares, 4),
          'price': t.price,
          'fee': _r(t.fee),
          'tax': _r(t.tax),
          'amount': _r(t.amount),
          'currency': d.currencyOf(t.currency, t.market),
          if (t.note != null && t.note!.isNotEmpty)
            'note': t.note!.length > 40 ? t.note!.substring(0, 40) : t.note,
        };

    final sample = matched.take(sampleLimit).toList();
    return {
      'filters': s.toJson(),
      'range': _rangeJson(range),
      'matchedCount': matched.length,
      'countByType': byType,
      'totalsByCurrency': {
        for (final e in totals.entries)
          e.key: {
            'buyAmount': _r(e.value['buyAmount']!.toDouble()),
            'buyCount': e.value['buyCount'],
            'sellAmount': _r(e.value['sellAmount']!.toDouble()),
            'sellCount': e.value['sellCount'],
            'openingCost': _r(e.value['openingCost']!.toDouble()),
            'feeTotal': _r(e.value['fee']!.toDouble()),
            'taxTotal': _r(e.value['tax']!.toDouble()),
            'feeAndTaxTotal':
                _r(e.value['fee']!.toDouble() + e.value['tax']!.toDouble()),
            'dividendFeeAndTax': _r(e.value['dividendFeeAndTax']!.toDouble()),
          },
      },
      'latestTrade': tradeJson(matched.first),
      'sample': {
        'count': sample.length,
        'isPartial': matched.length > sample.length,
        'trades': sample.map(tradeJson).toList(),
      },
      'note': 'matchedCount / countByType / totalsByCurrency 已涵蓋全部 '
          '${matched.length} 筆符合條件的明細,可直接引用;sample.trades 只是依日期新到舊的樣本,'
          '請勿自行加總。buyAmount 含手續費,sellAmount 是扣掉手續費與稅後的淨收入;'
          'feeTotal/taxTotal 只算買賣,股利的匯費與預扣稅另列在 dividendFeeAndTax;'
          '各幣別分開,不要跨幣別加總。',
    };
  }

  Map<String, dynamic> _rangeJson(({String? start, String? end}) r) => {
        'startDate': r.start,
        'endDate': r.end,
        'allTime': r.start == null && r.end == null,
      };

  // --------------------------------------------------------------------------
  // stock_realized_pnl
  // --------------------------------------------------------------------------

  Map<String, dynamic> realizedPnl(Map<String, dynamic> params) {
    final s = scope(params);
    final y = year(params);
    final allTrades = d.trades.map(holdingTradeOf).toList();
    final years = RealizedPnlReport.availableYears(allTrades);
    if (s.unmatched) {
      return {
        ...emptyResult(s, '已實現損益紀錄'),
        'year': y,
        'availableYears': years,
      };
    }

    // 帳戶/標的各可能比對到多個,逐組合各跑一次再合併(每筆賣出/股利只會落在
    // 一個組合裡,不會重複計入)。成本一律用全部明細算(RealizedPnlReport 內建)。
    final List<String?> accountKeys =
        s.accountIds?.map((e) => e.toString()).toList() ?? <String?>[null];
    final List<String?> symbolKeys =
        s.securityKeys?.toList() ?? <String?>[null];
    final totals = <String, RealizedCurrencyTotal>{};
    final groups = <RealizedSymbolGroup>[];
    for (final ak in accountKeys) {
      for (final sk in symbolKeys) {
        final report = RealizedPnlReport.build(
          allTrades,
          filter: RealizedFilter(year: y, accountKey: ak, symbolKey: sk),
        );
        report.totals.forEach((ccy, t) {
          final m = totals.putIfAbsent(ccy, RealizedCurrencyTotal.new);
          m.pnl += t.pnl;
          m.dividends += t.dividends;
        });
        groups.addAll(report.groups);
      }
    }
    // 同標的跨組合(帳戶分開跑)時合併成一組,避免同一檔出現兩列。
    final merged = <String, List<RealizedSymbolGroup>>{};
    for (final g in groups) {
      merged.putIfAbsent(g.key, () => []).add(g);
    }
    final mergedGroups = <RealizedSymbolGroup>[];
    for (final list in merged.values) {
      if (list.length == 1) {
        mergedGroups.add(list.first);
        continue;
      }
      final events = [for (final g in list) ...g.events]
        ..sort((a, b) => b.date.compareTo(a.date));
      mergedGroups.add(RealizedSymbolGroup(
        market: list.first.market,
        symbol: list.first.symbol,
        securityName: list.first.securityName,
        currency: list.first.currency,
        events: events,
        pnl: list.fold<double>(0, (a, g) => a + g.pnl),
        proceeds: list.fold<double>(0, (a, g) => a + g.proceeds),
        costBasis: list.fold<double>(0, (a, g) => a + g.costBasis),
        dividends: list.fold<double>(0, (a, g) => a + g.dividends),
      ));
    }

    if (mergedGroups.isEmpty) {
      return {
        ...emptyResult(s, '已實現損益紀錄(沒有賣出也沒有股利)'),
        'year': y,
        'availableYears': years,
      };
    }

    mergedGroups.sort((a, b) {
      final c = b.pnl.abs().compareTo(a.pnl.abs());
      return c != 0 ? c : a.key.compareTo(b.key);
    });

    final wins = <String, int>{},
        losses = <String, int>{},
        sells = <String, int>{};
    for (final g in mergedGroups) {
      for (final e in g.events) {
        sells.update(g.currency, (v) => v + 1, ifAbsent: () => 1);
        if (e.pnl > 0) {
          wins.update(g.currency, (v) => v + 1, ifAbsent: () => 1);
        }
        if (e.pnl < 0) {
          losses.update(g.currency, (v) => v + 1, ifAbsent: () => 1);
        }
      }
    }

    final capped = mergedGroups.take(kStockToolMaxGroups).toList();
    return {
      'filters': s.toJson(),
      'year': y,
      'availableYears': years,
      'totalsByCurrency': {
        for (final e in totals.entries)
          e.key: {
            'realizedPnl': _r(e.value.pnl),
            'dividends': _r(e.value.dividends),
            'realizedPnlPlusDividends': _r(e.value.pnl + e.value.dividends),
            'sellCount': sells[e.key] ?? 0,
            'winningSells': wins[e.key] ?? 0,
            'losingSells': losses[e.key] ?? 0,
          },
      },
      'symbolCount': mergedGroups.length,
      'groups': [
        for (final g in capped)
          {
            'market': g.market,
            'symbol': g.symbol,
            'name': g.securityName ?? d.nameOf(g.market, g.symbol),
            'currency': g.currency,
            'realizedPnl': _r(g.pnl),
            'proceeds': _r(g.proceeds),
            'costBasis': _r(g.costBasis),
            'dividends': _r(g.dividends),
            'sellCount': g.events.length,
            'sells': [
              for (final e in g.events.take(kStockToolMaxEventsPerGroup))
                {
                  'date': e.date,
                  'shares': _r(e.shares, 4),
                  'proceeds': _r(e.proceeds),
                  'costBasis': _r(e.costBasis),
                  'pnl': _r(e.pnl),
                },
            ],
            'sellsTruncated': g.events.length > kStockToolMaxEventsPerGroup,
          },
      ],
      'groupsTruncated': mergedGroups.length > capped.length,
      'note': 'totalsByCurrency 已涵蓋全部符合條件的資料。已實現損益 = 賣出淨收入(已扣手續費與'
          '證交稅)− 賣出當下的移動平均成本;dividends 是期間內現金股利 + 股利再投入金額。'
          '各幣別分開,不要跨幣別加總;groups 依損益絕對值排序,若 truncated 只是其中最大的幾檔。',
    };
  }

  // --------------------------------------------------------------------------
  // stock_dividends
  // --------------------------------------------------------------------------

  Future<Map<String, dynamic>> dividends(
    Map<String, dynamic> params,
    StockPendingDividendsLoader? pendingLoader,
  ) async {
    final s = scope(params);
    final y = year(params);
    final range = dateRange(params);
    String? start = range.start, end = range.end;
    if (y != null) {
      start = '$y-01-01';
      end = '$y-12-31';
    }

    bool inRange(String key) =>
        (start == null || key.compareTo(start) >= 0) &&
        (end == null || key.compareTo(end) <= 0);

    final divTrades = d.trades
        .where((t) =>
            _dividendTypes.contains(t.tradeType) &&
            s.matches(t.accountId, t.market, t.symbol))
        .toList();
    final matched = divTrades
        .where((t) => inRange(HoldingTrade.dateKey(t.tradeDate)))
        .toList()
      ..sort((a, b) => b.tradeDate.compareTo(a.tradeDate));

    // 近 12 個月(不受 year/起訖影響),殖利率與「最近一年領多少」用。
    final ttmStart =
        formatIsoDate(DateTime(d.now.year - 1, d.now.month, d.now.day));
    final ttmEnd = formatIsoDate(d.now);
    final ttm = <String, double>{};
    for (final t in divTrades) {
      if (t.tradeType == kStockTradeStockDividend) continue;
      final key = HoldingTrade.dateKey(t.tradeDate);
      if (key.compareTo(ttmStart) < 0 || key.compareTo(ttmEnd) > 0) continue;
      final ccy = d.currencyOf(t.currency, t.market);
      ttm.update(ccy, (v) => v + t.amount, ifAbsent: () => t.amount);
    }

    final totals = <String, Map<String, double>>{};
    final bySymbol = <String, _DivAcc>{};
    var stockDivCount = 0;
    for (final t in matched) {
      final ccy = d.currencyOf(t.currency, t.market);
      final m = totals.putIfAbsent(ccy,
          () => {'cashDividend': 0, 'reinvested': 0, 'stockDividendShares': 0});
      final key = securityKey(t.market, t.symbol);
      final acc = bySymbol.putIfAbsent(key, () => _DivAcc(ccy));
      acc.count += 1;
      if (t.tradeType == kStockTradeCashDividend) {
        m['cashDividend'] = m['cashDividend']! + t.amount;
        acc.amount += t.amount;
      } else if (t.tradeType == kStockTradeReinvest) {
        m['reinvested'] = m['reinvested']! + t.amount;
        acc.amount += t.amount;
      } else {
        m['stockDividendShares'] = m['stockDividendShares']! + t.shares;
        acc.stockShares += t.shares;
        stockDivCount += 1;
      }
    }

    // 待確認股利:只讀 App 已載入的快取(Cloud 專屬狀態)。
    final pending = await _pendingJson(pendingLoader, s);

    final result = <String, dynamic>{
      'filters': s.toJson(),
      'range': {
        'year': y,
        'startDate': start,
        'endDate': end,
        'allTime': start == null && end == null,
      },
      'pendingDividends': pending,
    };
    if (matched.isEmpty) {
      return {
        ...result,
        'matchedCount': 0,
        'trailing12MonthsByCurrency': {
          for (final e in ttm.entries) e.key: _r(e.value),
        },
        'note': s.unmatched
            ? '篩選條件沒有比對到股票標的/帳戶,沒有任何股利紀錄。'
            : '這個條件下沒有已入帳的股利紀錄。不要編造股利金額。',
      };
    }

    final symbolEntries = bySymbol.entries.toList()
      ..sort((a, b) => b.value.amount.compareTo(a.value.amount));
    return {
      ...result,
      'matchedCount': matched.length,
      'stockDividendCount': stockDivCount,
      'totalsByCurrency': {
        for (final e in totals.entries)
          e.key: {
            'cashDividend': _r(e.value['cashDividend']!),
            'reinvested': _r(e.value['reinvested']!),
            'totalDividends':
                _r(e.value['cashDividend']! + e.value['reinvested']!),
            'stockDividendShares': _r(e.value['stockDividendShares']!, 4),
          },
      },
      'trailing12MonthsByCurrency': {
        for (final e in ttm.entries) e.key: _r(e.value),
      },
      'bySymbol': [
        for (final e in symbolEntries.take(kStockToolMaxGroups))
          {
            'market': e.key.split(':').first,
            'symbol': e.key.substring(e.key.indexOf(':') + 1),
            'name': d.nameOf(e.key.split(':').first,
                e.key.substring(e.key.indexOf(':') + 1)),
            'currency': e.value.currency,
            'totalAmount': _r(e.value.amount),
            'stockDividendShares': _r(e.value.stockShares, 4),
            'count': e.value.count,
          },
      ],
      'bySymbolTruncated': symbolEntries.length > kStockToolMaxGroups,
      'recent': [
        for (final t in matched.take(15))
          {
            'date': HoldingTrade.dateKey(t.tradeDate),
            'account': d.accountName(t.accountId),
            'market': t.market,
            'symbol': t.symbol,
            'name': t.securityName ?? d.nameOf(t.market, t.symbol),
            'type': t.tradeType,
            'shares': _r(t.shares, 4),
            'amount': _r(t.amount),
            'currency': d.currencyOf(t.currency, t.market),
          },
      ],
      'note': 'totalsByCurrency / matchedCount 已涵蓋全部符合條件的股利紀錄;現金股利金額是'
          '實際入帳金額(已扣手續費/預扣稅/二代健保);reinvested 是股利再投入的金額;'
          'trailing12MonthsByCurrency 是近 12 個月現金股利 + 再投入(不含配股),不受篩選區間影響。'
          '各幣別分開,不要跨幣別加總。',
    };
  }

  Future<Map<String, dynamic>> _pendingJson(
    StockPendingDividendsLoader? loader,
    _Scope s,
  ) async {
    if (loader == null) {
      return {
        'available': false,
        'note': '待確認股利存在雲端,這裡讀不到;請使用者到「投資」頁的待確認股利區塊查看。',
      };
    }
    List<Map<String, dynamic>> rows;
    try {
      rows = await loader();
    } catch (_) {
      return {'available': false, 'note': '待確認股利讀取失敗,請使用者到投資頁查看。'};
    }
    final filtered = rows.where((r) {
      if (r['status'] != null && r['status'] != 'pending') return false;
      final market = (r['market'] ?? '').toString();
      final symbol = (r['symbol'] ?? '').toString();
      if (!s.matchesSecurity(market, symbol)) return false;
      if (s.accountIds != null) {
        final name = (r['accountName'] ?? '').toString();
        if (!s.accountNames.contains(name)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => (b['exDate'] ?? '')
          .toString()
          .compareTo((a['exDate'] ?? '').toString()));
    return {
      'available': true,
      'count': filtered.length,
      'items': filtered.take(10).toList(),
      'truncated': filtered.length > 10,
      'note': '以 App 目前已載入的快取為準(可能不是最新);預估實收請看 estNet(已扣預估費用),'
          '這些還沒確認入帳,不計入累計股利。',
    };
  }

  // --------------------------------------------------------------------------
  // stock_settings
  // --------------------------------------------------------------------------

  Map<String, dynamic> settings(Map<String, dynamic> params) {
    final s = scope(params, withSymbol: false);
    final investments = d.accounts
        .where((a) => a.type == 'investment' && s.matchesAccount(a.id))
        .toList();
    if (investments.isEmpty) {
      return {
        'filters': s.toJson(),
        'accounts': const [],
        'note': s.unmatched
            ? '找不到名稱相近的投資理財帳戶。'
            : '目前沒有任何投資理財帳戶。請使用者先在帳戶頁新增「投資理財」類型帳戶。',
      };
    }
    final bySyncId = {
      for (final a in d.accounts)
        if (a.syncId != null) a.syncId!: a,
    };

    String marketFor(Account a, InvestmentSettings st) {
      if (st.market != null) return st.market!;
      final counts = <String, int>{};
      for (final t in d.trades) {
        if (t.accountId == a.id) {
          counts.update(t.market, (v) => v + 1, ifAbsent: () => 1);
        }
      }
      if (counts.isNotEmpty) {
        return (counts.entries.toList()
              ..sort((x, y) => y.value.compareTo(x.value)))
            .first
            .key;
      }
      switch (a.currency.toUpperCase()) {
        case 'USD':
          return 'US';
        case 'TWD':
          return 'TW';
        default:
          return 'TW';
      }
    }

    Map<String, dynamic> nonNull(Map<String, dynamic> m) => {
          for (final e in m.entries)
            if (e.value != null) e.key: e.value
        };

    final accounts = <Map<String, dynamic>>[];
    for (final a in investments) {
      final st = InvestmentSettings.parse(a.investmentSettingsJson);
      final market = marketFor(a, st);
      final r = st.resolvedFor(market);
      final settlement = r.settlementAccountId == null
          ? null
          : bySyncId[r.settlementAccountId!]?.name;
      accounts.add({
        'account': a.name,
        'currency': a.currency,
        'includeInNetWorth': a.includeInTotal,
        'usingAllDefaults': st.isEmpty,
        'customized': st.toJson(),
        'effectiveForMarket': market,
        'effective': nonNull({
          'feeRate': r.feeRate,
          'feeDiscount': r.feeDiscount,
          'effectiveFeeRate': (r.feeRate ?? 0) * (r.feeDiscount ?? 1),
          'feeMin': r.feeMin,
          'oddLotFeeMin': r.oddLotFeeMin,
          'sellTaxRate': r.sellTaxRate,
          'etfSellTaxRate': r.etfSellTaxRate,
          'bondEtfSellTaxRate': r.bondEtfSellTaxRate,
          'dividendFeeFixed': r.dividendFeeFixed,
          'dividendFeeRate': r.dividendFeeRate,
          'dividendWithholdingRate': r.dividendWithholdingRate,
          'nhiSupplementRate': r.nhiSupplementRate,
          'nhiThreshold': r.nhiThreshold,
          'reinvestDividendsByDefault': r.reinvestDividends,
          'pnlAfterSellCosts': r.pnlAfterSellCosts,
          'defaultSettlementAccount': settlement,
        }),
      });
    }
    return {
      'filters': s.toJson(),
      'accounts': accounts,
      'note': 'customized 是使用者自己改過的項目,沒列出的項目沿用市場預設;effective 是實際生效值'
          '(費率類是小數,0.001425 = 0.1425%;feeDiscount 0.6 = 6 折)。'
          'pnlAfterSellCosts=true 代表持股的未實現損益已扣預估賣出手續費與證交稅。'
          '每筆交易都可以手動覆寫手續費/稅,所以這只是預填的預設值。',
    };
  }

  // --------------------------------------------------------------------------
  // stock_dca_plans
  // --------------------------------------------------------------------------

  Future<Map<String, dynamic>> dcaPlans(Map<String, dynamic> params) async {
    final s = scope(params);
    final includeDisabled = params['includeDisabled'] != false;
    final rules = (await repo.getAllRulesForExport())
        .where((r) => r.kind == 'stock_dca')
        .where((r) => includeDisabled || r.enabled)
        .where((r) =>
            s.matchesAccount(r.toAccountId) &&
            (r.market == null ||
                r.symbol == null ||
                s.matchesSecurity(r.market!, r.symbol!)))
        .toList()
      ..sort((a, b) => (a.symbol ?? '').compareTo(b.symbol ?? ''));

    if (rules.isEmpty) {
      return {
        ...emptyResult(s, '股票定期定額計畫'),
        'planCount': 0,
      };
    }

    final plans = <Map<String, dynamic>>[];
    for (final r in rules.take(20)) {
      plans.add(await _planJson(r));
    }
    return {
      'filters': s.toJson(),
      'planCount': rules.length,
      'activeCount': rules.where((r) => r.enabled).length,
      'plans': plans,
      'plansTruncated': rules.length > 20,
      'note': 'amountPerPeriod 的意思:台股(整數股)是「含手續費」的每期扣款上限,'
          '其它市場是成交價金、手續費另計(wholeShares 欄位標示)。'
          'executedPeriods / totalInvested 只算已發生的期數。'
          '定期定額手續費未覆寫時沿用投資帳戶的費用設定。',
    };
  }

  Future<Map<String, dynamic>> _planJson(RecurringTransaction r) async {
    Map<String, dynamic>? advanced;
    final rawAdv = r.advancedRuleJson;
    if (rawAdv != null && rawAdv.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawAdv);
        if (decoded is Map<String, dynamic>) advanced = decoded;
      } catch (_) {}
    }
    DateTime? upcoming;
    try {
      upcoming = nextPendingOccurrence(
        nextRunAt: r.nextRunAt,
        generatedUntilAt: r.generatedUntilAt,
        frequency: r.frequency,
        interval: r.interval,
        advancedRule: advanced,
      );
    } catch (_) {}
    if (upcoming != null && r.endAt != null && upcoming.isAfter(r.endAt!)) {
      upcoming = null;
    }

    var executed = 0;
    var gross = 0.0, fees = 0.0;
    String? last;
    if (r.syncId != null) {
      final occurrences = await repo.getOccurrencesForRule(r.syncId!);
      for (final tx in occurrences) {
        if (tx.happenedAt.isAfter(d.now)) continue;
        executed += 1;
        gross += tx.amount;
        fees += tx.feeAmount ?? 0;
        last = formatIsoDate(tx.happenedAt);
      }
    }

    final market = r.market ?? '';
    final investment = r.toAccountId == null ? null : d.accById[r.toAccountId!];
    final investSettings =
        InvestmentSettings.parse(investment?.investmentSettingsJson);
    return {
      'market': r.market,
      'symbol': r.symbol,
      'name': r.securityName ??
          (r.market != null && r.symbol != null
              ? d.nameOf(r.market!, r.symbol!)
              : null),
      'currency': stockMarketByCode(market)?.currency,
      'enabled': r.enabled,
      'investmentAccount': d.accountName(r.toAccountId),
      'settlementAccount': d.accountName(r.fromAccountId),
      'amountPerPeriod': _r(r.amount),
      'wholeShares': stockDcaWholeShares(r.market),
      'frequency': r.frequency,
      'interval': r.interval,
      'advancedRule': advanced,
      'firstRunAt': formatIsoDate(r.nextRunAt),
      'upcomingRunAt': upcoming == null ? null : formatIsoDate(upcoming),
      'endAt': r.endAt == null ? null : formatIsoDate(r.endAt!),
      'feeOverride': (r.stockFeeRate != null || r.stockFeeMin != null)
          ? {'feeRate': r.stockFeeRate, 'feeMin': r.stockFeeMin}
          : 'usesInvestmentAccountSettings',
      'accountDefaultFeeRate': investSettings.resolvedFor(r.market).feeRate,
      'executedPeriods': executed,
      'lastExecutedDate': last,
      'totalInvested': _r(gross),
      'totalFees': _r(fees),
    };
  }

  // --------------------------------------------------------------------------
  // stock_performance
  // --------------------------------------------------------------------------

  Map<String, dynamic> performance(Map<String, dynamic> params) {
    final s = scope(params);
    final all = viewsIn(s);
    if (s.unmatched || all.isEmpty) {
      return emptyResult(s, '股票持股或交易紀錄');
    }

    final totals = currencyTotals(all);
    // 每檔(跨帳戶合併)總報酬 = 未實現(有報價才算)+ 已實現 + 股利。
    final perSecurity = <String, _SecAcc>{};
    for (final v in all) {
      final key = securityKey(v.holding.market, v.holding.symbol);
      final a = perSecurity.putIfAbsent(key, () => _SecAcc(v.currency));
      a.name ??= v.name;
      a.realized += v.holding.realizedPnl;
      a.dividends += v.holding.dividends;
      if (v.holding.isOpen) {
        a.open = true;
        a.cost += v.holding.totalCost;
        final pnl = v.unrealizedPnl;
        if (pnl == null) {
          a.unpriced = true;
        } else {
          a.unrealized += pnl;
          a.pricedCost += v.holding.totalCost;
        }
      }
    }

    final byCcy = <String, List<MapEntry<String, _SecAcc>>>{};
    for (final e in perSecurity.entries) {
      byCcy.putIfAbsent(e.value.currency, () => []).add(e);
    }

    Map<String, dynamic> secJson(MapEntry<String, _SecAcc> e) {
      final a = e.value;
      final total = a.unrealized + a.realized + a.dividends;
      return {
        'market': e.key.split(':').first,
        'symbol': e.key.substring(e.key.indexOf(':') + 1),
        'name': a.name,
        'isOpen': a.open,
        'unrealizedPnl':
            a.unpriced && a.pricedCost == 0 ? null : _r(a.unrealized),
        'realizedPnl': _r(a.realized),
        'dividends': _r(a.dividends),
        'totalReturn': _r(total),
        'totalReturnPercentOnCost':
            a.open && a.pricedCost > 0 ? _r(total / a.pricedCost * 100) : null,
        if (a.unpriced) 'quoteMissing': true,
      };
    }

    final currencyOut = <String, dynamic>{};
    for (final entry in byCcy.entries) {
      final ccy = entry.key;
      final list = entry.value
        ..sort((x, y) {
          final tx = x.value.unrealized + x.value.realized + x.value.dividends;
          final ty = y.value.unrealized + y.value.realized + y.value.dividends;
          return ty.compareTo(tx);
        });
      final t = totals[ccy]!;
      final unrealized = (t['unrealizedPnl'] as double);
      final realized = t['realizedPnl'] as double;
      final div = t['dividends'] as double;
      final ranking = list.length <= 15
          ? list
          : [...list.take(8), ...list.sublist(list.length - 7)];
      currencyOut[ccy] = {
        'unrealizedPnl': unrealized,
        'unrealizedPnlPercent': t['unrealizedPnlPercent'],
        'realizedPnl': realized,
        'dividends': div,
        'totalReturn': _r(unrealized + realized + div),
        'pnlBasis': t['pnlBasis'],
        'unpricedCount': t['unpricedCount'],
        'staleQuoteCount': t['staleQuoteCount'],
        'oldestQuoteTime': t['oldestQuoteTime'],
        'securityCount': list.length,
        'ranking': ranking.map(secJson).toList(),
        'rankingTruncated': list.length > 15,
        'dividendYield': _yieldJson(ccy, s),
      };
    }

    return {
      'asOf': _stamp(d.now),
      'filters': s.toJson(),
      'byCurrency': currencyOut,
      'note': '$kStockToolDataScopeNote totalReturn = unrealizedPnl(未平倉、有報價才算)+ '
          'realizedPnl + dividends;ranking 依總報酬由高到低(若 truncated 只列前 8 與後 7)。'
          'totalReturnPercentOnCost 僅未平倉且有報價的標的有值。'
          'dividendYield 的 trailing12MonthsDividends 為近 12 個月現金股利 + 再投入;'
          '持有不到一年或剛買進時會低估,請如實說明這是估算。',
    };
  }

  /// 殖利率估算(只針對目前仍持有的標的):近 12 個月股利 ÷ 持股成本、÷ 持股市值。
  Map<String, dynamic> _yieldJson(String ccy, _Scope s) {
    final openViews = viewsIn(s, includeClosed: false)
        .where((v) => v.currency == ccy)
        .toList();
    final openKeys = {
      for (final v in openViews)
        securityKey(v.holding.market, v.holding.symbol),
    };
    final ttmStart =
        formatIsoDate(DateTime(d.now.year - 1, d.now.month, d.now.day));
    final ttmEnd = formatIsoDate(d.now);
    var ttm = 0.0;
    for (final t in d.trades) {
      if (t.tradeType != kStockTradeCashDividend &&
          t.tradeType != kStockTradeReinvest) {
        continue;
      }
      if (!s.matchesAccount(t.accountId)) continue;
      if (!openKeys.contains(securityKey(t.market, t.symbol))) continue;
      if (d.currencyOf(t.currency, t.market) != ccy) continue;
      final key = HoldingTrade.dateKey(t.tradeDate);
      if (key.compareTo(ttmStart) < 0 || key.compareTo(ttmEnd) > 0) continue;
      ttm += t.amount;
    }
    var cost = 0.0, pricedCost = 0.0, mv = 0.0;
    for (final v in openViews) {
      cost += v.holding.totalCost;
      final value = v.marketValue;
      if (value != null) {
        pricedCost += v.holding.totalCost;
        mv += value;
      }
    }
    return {
      'trailing12MonthsDividends': _r(ttm),
      'yieldOnCostPercent': cost > 0 ? _r(ttm / cost * 100) : null,
      'yieldOnMarketValuePercent': mv > 0 ? _r(ttm / mv * 100) : null,
      'costBase': _r(cost),
      'marketValueBase': _r(mv),
      if (pricedCost < cost) 'warning': '部分持股沒有報價,市值殖利率只以有報價的市值計算,僅供參考',
      'note': '只計目前仍持有的標的;已出清標的的股利不計入',
    };
  }

  // --------------------------------------------------------------------------
  // stock_portfolio_analysis
  // --------------------------------------------------------------------------

  Map<String, dynamic> portfolioAnalysis(Map<String, dynamic> params) {
    final s = scope(params, withSymbol: false);
    final all = viewsIn(s);
    final open = all.where((v) => v.holding.isOpen).toList();
    if (s.unmatched || open.isEmpty) {
      return {
        ...emptyResult(s, '未平倉的股票持股'),
        'disclaimerRequired': true,
        'hasHoldings': false,
      };
    }

    final byCcy = <String, List<HoldingView>>{};
    for (final v in open) {
      byCcy.putIfAbsent(v.currency, () => []).add(v);
    }
    final totals = currencyTotals(all);

    final out = <String, dynamic>{};
    for (final entry in byCcy.entries) {
      final ccy = entry.key;
      final views = entry.value;
      final observations = <String>[];

      final priced = views.where((v) => v.marketValue != null).toList();
      final unpriced = views.where((v) => v.marketValue == null).toList();
      final totalMv = priced.fold<double>(0, (a, v) => a + v.marketValue!);

      double weight(double x) => totalMv > 0 ? x / totalMv * 100 : 0;

      // 標的集中度(跨帳戶合併同標的)。
      final bySec = <String, double>{};
      final secName = <String, String?>{};
      for (final v in priced) {
        final key = securityKey(v.holding.market, v.holding.symbol);
        bySec.update(key, (x) => x + v.marketValue!,
            ifAbsent: () => v.marketValue!);
        secName[key] ??= v.name;
      }
      final secList = bySec.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top3 =
          secList.take(3).fold<double>(0, (a, e) => a + weight(e.value));
      if (secList.isNotEmpty && secList.length >= 2) {
        final topW = weight(secList.first.value);
        if (topW >= kConcentrationSingleWeightPercent) {
          observations.add(
              '單一標的 ${secList.first.key}${secName[secList.first.key] == null ? '' : '(${secName[secList.first.key]})'}'
              '佔 $ccy 持股市值 ${_r(topW, 1)}%,集中度偏高');
        }
        if (secList.length >= 4 && top3 >= kConcentrationTop3WeightPercent) {
          observations.add('前三大標的合計佔 $ccy 持股市值 ${_r(top3, 1)}%,持股集中在少數標的');
        }
      } else if (secList.length == 1) {
        observations.add('$ccy 持股只有一檔標的(${secList.first.key}),完全沒有標的分散');
      }

      // 帳戶分布。
      final byAcc = <String, double>{};
      for (final v in priced) {
        byAcc.update(d.accountName(v.accountId), (x) => x + v.marketValue!,
            ifAbsent: () => v.marketValue!);
      }
      final accList = byAcc.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (accList.length >= 2 && weight(accList.first.value) >= 80) {
        observations.add(
            '$ccy 持股有 ${_r(weight(accList.first.value), 1)}% 集中在帳戶「${accList.first.key}」');
      }

      // 市場分布。
      final byMarket = <String, double>{};
      for (final v in priced) {
        byMarket.update(v.holding.market, (x) => x + v.marketValue!,
            ifAbsent: () => v.marketValue!);
      }

      // ETF / 個股(台股才能由代號判斷,其它市場列 unclassified)。
      final kind = {
        'stock': 0.0,
        'etf': 0.0,
        'bondEtf': 0.0,
        'unclassified': 0.0
      };
      final kindCount = {'stock': 0, 'etf': 0, 'bondEtf': 0, 'unclassified': 0};
      for (final v in priced) {
        final m = v.holding.market.toUpperCase();
        final String bucket;
        if (m != 'TW' && m != 'TWO') {
          bucket = 'unclassified';
        } else {
          switch (securityKindOf(m, v.holding.symbol)) {
            case SecurityKind.etf:
              bucket = 'etf';
            case SecurityKind.bondEtf:
              bucket = 'bondEtf';
            case SecurityKind.stock:
              bucket = 'stock';
          }
        }
        kind[bucket] = kind[bucket]! + v.marketValue!;
        kindCount[bucket] = kindCount[bucket]! + 1;
      }

      // 虧損標的。
      final longLoss = <Map<String, dynamic>>[];
      final deepLoss = <Map<String, dynamic>>[];
      for (final v in views) {
        final pct = v.unrealizedPnlPercent;
        if (pct == null) continue;
        final first = DateTime.tryParse(v.holding.firstTradeDate ?? '');
        final days = first == null ? null : d.now.difference(first).inDays;
        final item = {
          'market': v.holding.market,
          'symbol': v.holding.symbol,
          'name': v.name,
          'account': d.accountName(v.accountId),
          'holdDays': days,
          'unrealizedPnlPercent': _r(pct),
          'unrealizedPnl': _rn(v.unrealizedPnl),
        };
        if (pct <= kDeepLossPercent) deepLoss.add(item);
        if (pct <= kLongLossPercent &&
            days != null &&
            days >= kLongLossHoldDays) {
          longLoss.add(item);
        }
      }
      if (longLoss.isNotEmpty) {
        observations
            .add('$ccy 有 ${longLoss.length} 檔持有超過 $kLongLossHoldDays 天且未實現虧損超過 '
                '${kLongLossPercent.abs().toInt()}% 的標的');
      }
      if (deepLoss.isNotEmpty) {
        observations.add(
            '$ccy 有 ${deepLoss.length} 檔未實現虧損超過 ${kDeepLossPercent.abs().toInt()}%');
      }

      // 手續費/交易稅佔投入比例(帳戶/幣別範圍內全部明細)。
      var buyAmount = 0.0, fee = 0.0, tax = 0.0, sellAmount = 0.0;
      for (final t in d.trades) {
        if (!s.matchesAccount(t.accountId)) continue;
        if (d.currencyOf(t.currency, t.market) != ccy) continue;
        if (t.tradeType == kStockTradeBuy) {
          buyAmount += t.amount;
          fee += t.fee;
        } else if (t.tradeType == kStockTradeSell) {
          sellAmount += t.amount;
          fee += t.fee;
          tax += t.tax;
        }
      }
      final feeTaxPct = buyAmount > 0 ? (fee + tax) / buyAmount * 100 : null;
      if (feeTaxPct != null && feeTaxPct >= kFeeTaxHighPercentOfBuy) {
        observations
            .add('$ccy 累計手續費與交易稅佔累計買進金額 ${_r(feeTaxPct)}%,交易成本偏高(可能是小額/頻繁交易)');
      }

      // 股利概況。
      final yieldJ = _yieldJson(ccy, s);
      final totalsC = totals[ccy]!;
      final allTimeDividends = totalsC['dividends'] as double;
      if (allTimeDividends <= 0) {
        observations.add('$ccy 持股至今沒有任何已入帳的股利紀錄');
      }
      if (unpriced.isNotEmpty) {
        observations.add('$ccy 有 ${unpriced.length} 檔沒有報價,未納入佔比與市值計算'
            '(${unpriced.map((v) => v.holding.symbol).join('、')})');
      }
      final stale = totalsC['staleQuoteCount'] as int;
      if (stale > 0) {
        observations.add('$ccy 有 $stale 檔報價超過 72 小時沒有更新,市值僅供參考');
      }

      out[ccy] = {
        'openPositions': views.length,
        'securityCount': secList.length + unpriced.length,
        'marketValue': _r(totalMv),
        'unrealizedPnl': totalsC['unrealizedPnl'],
        'unrealizedPnlPercent': totalsC['unrealizedPnlPercent'],
        'pnlBasis': totalsC['pnlBasis'],
        'oldestQuoteTime': totalsC['oldestQuoteTime'],
        'concentration': {
          'weightBasis': '市值(只計有報價的持股)',
          'topPositions': [
            for (final e in secList.take(8))
              {
                'key': e.key,
                'name': secName[e.key],
                'marketValue': _r(e.value),
                'weightPercent': _r(weight(e.value), 1),
              },
          ],
          'topWeightPercent':
              secList.isEmpty ? null : _r(weight(secList.first.value), 1),
          'top3WeightPercent': secList.isEmpty ? null : _r(top3, 1),
        },
        'byAccount': [
          for (final e in accList)
            {
              'account': e.key,
              'marketValue': _r(e.value),
              'weightPercent': _r(weight(e.value), 1),
            },
        ],
        'byMarket': [
          for (final e
              in (byMarket.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value))))
            {
              'market': e.key,
              'marketValue': _r(e.value),
              'weightPercent': _r(weight(e.value), 1),
            },
        ],
        'byKind': {
          for (final k in kind.keys)
            k: {
              'count': kindCount[k],
              'marketValue': _r(kind[k]!),
              'weightPercent': _r(weight(kind[k]!), 1),
            },
        },
        'longTermLosers': longLoss.take(8).toList(),
        'deepLossPositions': deepLoss.take(8).toList(),
        'costs': {
          'buyAmount': _r(buyAmount),
          'sellAmount': _r(sellAmount),
          'feeTotal': _r(fee),
          'taxTotal': _r(tax),
          'feeAndTaxPercentOfBuyAmount': _rn(feeTaxPct),
        },
        'dividends': {
          'allTimeDividends': _r(allTimeDividends),
          ...yieldJ,
        },
        'realizedPnl': totalsC['realizedPnl'],
        'observations': observations,
      };
    }

    return {
      'asOf': _stamp(d.now),
      'filters': s.toJson(),
      'hasHoldings': true,
      'disclaimerRequired': true,
      'byCurrency': out,
      'thresholds': {
        'singleWeightPercent': kConcentrationSingleWeightPercent,
        'top3WeightPercent': kConcentrationTop3WeightPercent,
        'longLossHoldDays': kLongLossHoldDays,
        'longLossPercent': kLongLossPercent,
        'deepLossPercent': kDeepLossPercent,
        'feeTaxHighPercentOfBuy': kFeeTaxHighPercentOfBuy,
      },
      'note': '$kStockToolDataScopeNote 這份資料只描述使用者「目前持股的結構與風險」,'
          'observations 是依固定門檻客觀列出的觀察,不是買賣訊號。'
          'ETF/個股分類只有台股(代號 00 開頭 = ETF)能判斷,其它市場為 unclassified。'
          '回答時請客觀說明風險,不要對任何標的下「買進/賣出」的明確指令,結尾必須附免責聲明。',
    };
  }
}

// ============================================================================
// 內部累加器
// ============================================================================

class _CcyAcc {
  int positions = 0;
  double cost = 0, pricedCost = 0, marketValue = 0, netValue = 0, valuation = 0;
  double realized = 0, dividends = 0;
  int unpriced = 0, staleCount = 0;
  DateTime? oldestQuote;
  final Set<bool> afterCostFlags = {};

  String get pnlBasis {
    if (afterCostFlags.isEmpty) return 'noPricedPositions';
    if (afterCostFlags.length > 1) return 'mixedByAccount';
    return afterCostFlags.first
        ? 'afterEstimatedSellCosts'
        : 'grossMarketValue';
  }
}

class _DivAcc {
  final String currency;
  double amount = 0, stockShares = 0;
  int count = 0;
  _DivAcc(this.currency);
}

class _SecAcc {
  final String currency;
  String? name;
  bool open = false, unpriced = false;
  double cost = 0, pricedCost = 0, unrealized = 0, realized = 0, dividends = 0;
  _SecAcc(this.currency);
}
