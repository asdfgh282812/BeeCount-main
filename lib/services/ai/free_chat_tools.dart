import '../../data/db.dart' show Category, Transaction;
import '../../data/repositories/base_repository.dart';
import '../../data/repositories/budget_repository.dart' show BudgetUsage;
import '../../utils/zh_variants.dart';

/// 自由對話唯讀查詢工具:metadata + executor。
///
/// 只做「查資料、整理成好餵給 LLM 的 Map」,不碰任何寫入操作 —— 這批工具全部
/// 唯讀,沒有授權彈窗的必要(見 design doc「明確排除」)。
///
/// **口徑**(與統計頁一致,見 `local_statistics_repository.dart` 的 `totalsInRange`):
/// 所有彙總都排除 `excludeFromStats` 的交易,也排除 `type == 'transfer'`。
/// 這對 `query_transactions` 是行為變更 —— 舊版走
/// `getTransactionsByLedgerInRange`,該方法完全沒有 `excludeFromStats` 過濾,
/// 導致它跟 `get_spending_summary` 對同一個區間的認知不一致。
///
/// **已知缺口**(刻意不在本輪處理,見 changes doc):拆帳交易(`hasSplits`)的
/// 子分類不會被分類過濾命中;共享帳本裡 `categoryId` 為 null、分類放在
/// `categorySyncIdOverride` 的交易同樣查不到分類。

/// 單一工具參數的說明,純資料,用來拼進 routing systemPrompt。
class FreeChatToolParam {
  final String name;
  final String type; // 'date' | 'bool' | 'string' | 'int' | 'string|array'
  final bool required;
  final String description;

  const FreeChatToolParam({
    required this.name,
    required this.type,
    this.required = false,
    required this.description,
  });
}

/// 單一工具的 metadata。
class FreeChatToolSpec {
  final String name;
  final String description;
  final List<FreeChatToolParam> params;

  const FreeChatToolSpec({
    required this.name,
    required this.description,
    this.params = const [],
  });
}

/// 日期參數的共用說明 —— 省略即該側無界。
///
/// 刻意**不用哨兵值**(`"all"` / `"1970-01-01"`):模型會發明 `"ALL"` `"*"`
/// `"9999-12-31"` 之類的變體,要嘛 parse 失敗讓使用者看到「暫時處理不了」,
/// 要嘛 parse 成一個合法但錯誤的日期而靜默給錯答案。「少填一個欄位」是所有
/// JSON 行為裡最穩的一個。
const _startDateDesc = '區間開始日期,格式 YYYY-MM-DD。'
    '省略代表不限開始時間(從最早一筆算起)';
const _endDateDesc = '區間結束日期(含當天),格式 YYYY-MM-DD。'
    '省略代表到今天為止';
const _allTimeDesc = 'true 代表查詢全部期間,會忽略 startDate/endDate';

/// 目前支援的 4 個唯讀查詢工具。
const List<FreeChatToolSpec> freeChatTools = [
  FreeChatToolSpec(
    name: 'get_spending_summary',
    description: '取得指定區間的收支總額,groupByCategory=true 時額外回傳各分類佔比。'
        '適合「這個月花多少」「今年收支如何」這種不限定關鍵字的整體提問',
    params: [
      FreeChatToolParam(
          name: 'startDate', type: 'date', description: _startDateDesc),
      FreeChatToolParam(
          name: 'endDate', type: 'date', description: _endDateDesc),
      FreeChatToolParam(
          name: 'allTime', type: 'bool', description: _allTimeDesc),
      FreeChatToolParam(
        name: 'groupByCategory',
        type: 'bool',
        description: '是否額外回傳各分類金額,預設 false',
      ),
    ],
  ),
  FreeChatToolSpec(
    name: 'get_budget_status',
    description: '取得指定月份的總預算與各分類預算的額度/已用/剩餘',
    params: [
      FreeChatToolParam(
        name: 'month',
        type: 'date',
        description: '月份錨點,格式 YYYY-MM-DD,省略則用今天所在月份',
      ),
    ],
  ),
  FreeChatToolSpec(
    name: 'query_transactions',
    description: '查詢符合條件的交易,回傳**完整彙總**(總筆數/總金額/各分類小計)'
        '加上一小段明細樣本。適合「我在復健科總共花多少」「上個月餐飲幾筆」'
        '這種帶關鍵字或分類的提問',
    params: [
      FreeChatToolParam(
          name: 'startDate', type: 'date', description: _startDateDesc),
      FreeChatToolParam(
          name: 'endDate', type: 'date', description: _endDateDesc),
      FreeChatToolParam(
          name: 'allTime', type: 'bool', description: _allTimeDesc),
      FreeChatToolParam(
        name: 'keyword',
        type: 'string|array',
        description: '比對備註/商家/分類名稱的關鍵字。可以給一個字串,也可以給'
            '陣列同時列出簡繁變體與同義詞,任一命中即算,'
            '例如 ["復健","复健","物理治療"]。省略則不過濾',
      ),
      FreeChatToolParam(
        name: 'categoryName',
        type: 'string',
        description: '限定分類名稱。完全相同優先,沒有完全相同時退化為包含比對;'
            '指定父分類會自動含所有子分類。省略則不限分類',
      ),
      FreeChatToolParam(
        name: 'type',
        type: 'string',
        description: "'expense' 只看支出,'income' 只看收入,省略則兩者都算",
      ),
      FreeChatToolParam(
        name: 'limit',
        type: 'int',
        description: '明細樣本最多回傳幾筆,0~50,預設 20。給 0 代表只要彙總數字。'
            '注意:這個值只影響樣本,不影響 matchedCount 與各項總額',
      ),
    ],
  ),
  FreeChatToolSpec(
    name: 'get_recurring_transactions',
    description: '目前帳本啟用中的週期性交易/訂閱清單',
  ),
];

/// 拼進 routing systemPrompt 的工具說明區塊。
String buildFreeChatToolsPromptSection() {
  final buffer = StringBuffer();
  for (final tool in freeChatTools) {
    buffer.writeln('- ${tool.name}: ${tool.description}');
    for (final p in tool.params) {
      final requiredLabel = p.required ? '必填' : '選填';
      buffer.writeln(
          '  - ${p.name}(${p.type}, $requiredLabel): ${p.description}');
    }
  }
  return buffer.toString().trimRight();
}

/// `YYYY-MM-DD` 格式化,與 [PromptBuilder] 的 `{{CURRENT_DATE}}` 做法一致。
String formatIsoDate(DateTime date) {
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${pad(date.month)}-${pad(date.day)}';
}

/// 工具名不存在 / 參數格式錯誤時拋出,供 [FreeChatRouter] 捕捉並降級成固定文案,
/// 不是靜默回空結果。
class FreeChatToolException implements Exception {
  final String message;
  FreeChatToolException(this.message);

  @override
  String toString() => 'FreeChatToolException: $message';
}

/// 執行單一工具呼叫,回傳可直接 `jsonEncode` 進 prompt 的結果。
class FreeChatToolExecutor {
  const FreeChatToolExecutor();

  Future<Map<String, dynamic>> execute(
    String toolName,
    Map<String, dynamic> params, {
    required BaseRepository repo,
    required int ledgerId,
  }) async {
    switch (toolName) {
      case 'get_spending_summary':
        return _getSpendingSummary(params, repo, ledgerId);
      case 'get_budget_status':
        return _getBudgetStatus(params, repo, ledgerId);
      case 'query_transactions':
        return _queryTransactions(params, repo, ledgerId);
      case 'get_recurring_transactions':
        return _getRecurringTransactions(repo, ledgerId);
      default:
        throw FreeChatToolException('未知工具: $toolName');
    }
  }

  // ============================================================
  // get_spending_summary
  // ============================================================

  Future<Map<String, dynamic>> _getSpendingSummary(
    Map<String, dynamic> params,
    BaseRepository repo,
    int ledgerId,
  ) async {
    final range = _resolveRange(params);
    final groupByCategory = params['groupByCategory'] == true;

    final (income, expense) = await repo.totalsInRange(
      ledgerId: ledgerId,
      start: range.queryStart,
      end: range.queryEnd,
    );

    final result = <String, dynamic>{
      'range': range.toJson(),
      'income': income,
      'expense': expense,
    };

    if (groupByCategory) {
      final expenseCategories = await repo.totalsByCategory(
        ledgerId: ledgerId,
        type: 'expense',
        start: range.queryStart,
        end: range.queryEnd,
      );
      final incomeCategories = await repo.totalsByCategory(
        ledgerId: ledgerId,
        type: 'income',
        start: range.queryStart,
        end: range.queryEnd,
      );
      result['expenseByCategory'] = expenseCategories
          .map((c) => {'name': c.name, 'total': c.total})
          .toList();
      result['incomeByCategory'] = incomeCategories
          .map((c) => {'name': c.name, 'total': c.total})
          .toList();
    }

    return result;
  }

  // ============================================================
  // get_budget_status
  // ============================================================

  Future<Map<String, dynamic>> _getBudgetStatus(
    Map<String, dynamic> params,
    BaseRepository repo,
    int ledgerId,
  ) async {
    final month = _optionalDate(params, 'month') ?? DateTime.now();
    final overview = await repo.getBudgetOverview(ledgerId, month);

    Map<String, dynamic> usageJson(BudgetUsage usage) => {
          'used': usage.used,
          'budget': usage.budget,
          'remaining': usage.remaining,
          'rate': usage.rate,
          'status': usage.status,
        };

    return {
      'month': formatIsoDate(DateTime(month.year, month.month, 1)),
      'totalBudget': overview.totalBudget == null
          ? null
          : usageJson(overview.totalBudget!),
      'categoryBudgets': overview.categoryBudgets
          .map((c) => {
                'categoryName': c.categoryName,
                ...usageJson(c.usage),
              })
          .toList(),
      'daysRemaining': overview.daysRemaining,
      'dailyAvailable': overview.dailyAvailable,
    };
  }

  // ============================================================
  // query_transactions
  // ============================================================

  Future<Map<String, dynamic>> _queryTransactions(
    Map<String, dynamic> params,
    BaseRepository repo,
    int ledgerId,
  ) async {
    final range = _resolveRange(params);
    final keywords = _optionalStringList(params, 'keyword');
    final categoryName = _optionalString(params, 'categoryName');
    final typeFilter = _optionalType(params, 'type');
    final limit = _clampLimit(params['limit']);

    final transactions = await repo.getTransactionsByLedgerInRange(
      ledgerId: ledgerId,
      start: range.queryStart,
      end: range.queryEnd,
    );

    // 分類表只有幾十列,一次載入建 Map —— 取代舊版在迴圈裡逐筆
    // `getCategoryById` / `getAccount` 的 N+1 查詢(而且舊版的
    // `getCategoryById` 還跑在 categoryName 過濾之前,指定分類時絕大多數是白查)。
    final categories = await repo.getAllCategoriesIncludingShared();
    final catById = {for (final c in categories) c.id: c};

    final resolved = _resolveCategories(
      categories: categories,
      query: categoryName,
      typeFilter: typeFilter,
    );

    final matched = <Transaction>[];
    for (final t in transactions) {
      if (t.excludeFromStats) continue;
      if (t.type != 'expense' && t.type != 'income') continue;
      if (typeFilter != null && t.type != typeFilter) continue;

      final cat = t.categoryId == null ? null : catById[t.categoryId!];

      if (resolved != null && !resolved.ids.contains(t.categoryId)) continue;

      if (keywords != null && !_matchesKeyword(t, cat, keywords)) continue;

      matched.add(t);
    }

    // ── 彙總涵蓋全部命中,**在套用 limit 之前算完** ──
    // 舊版把完整的過濾結果直接 `take(limit)` 丟掉,只回明細不回總額,模型只好
    // 自己加總樣本 —— 一旦截斷就默默算錯。這是本次修正的核心。
    var totalExpense = 0.0;
    var totalIncome = 0.0;
    DateTime? firstDate;
    DateTime? lastDate;
    final byCategory = <String, ({String type, double total, int count})>{};

    for (final t in matched) {
      final amount = t.nativeAmount ?? t.amount;
      if (t.type == 'expense') {
        totalExpense += amount;
      } else {
        totalIncome += amount;
      }
      if (firstDate == null || t.happenedAt.isBefore(firstDate)) {
        firstDate = t.happenedAt;
      }
      if (lastDate == null || t.happenedAt.isAfter(lastDate)) {
        lastDate = t.happenedAt;
      }
      final name =
          (t.categoryId == null ? null : catById[t.categoryId!]?.name) ?? '未分類';
      final key = '$name|${t.type}';
      final prev = byCategory[key];
      byCategory[key] = (
        type: t.type,
        total: (prev?.total ?? 0) + amount,
        count: (prev?.count ?? 0) + 1,
      );
    }

    // 帳戶名稱只有樣本用得到,limit == 0 時完全不必載入
    final sample = matched.take(limit).toList();
    Map<int, String> accById = const {};
    if (sample.isNotEmpty) {
      accById = {
        for (final a in await repo.getAllAccounts()) a.id: a.name,
      };
    }

    return {
      'range': range.toJson(
        actualFirstDate: firstDate,
        actualLastDate: lastDate,
      ),
      'filters': {
        'keyword': keywords,
        'categoryName': categoryName,
        'resolvedCategories': resolved?.names,
        'type': typeFilter,
      },
      'matchedCount': matched.length,
      'totalExpense': totalExpense,
      'totalIncome': totalIncome,
      'byCategory': byCategory.entries
          .map((e) => {
                'name': e.key.substring(0, e.key.lastIndexOf('|')),
                'type': e.value.type,
                'total': e.value.total,
                'count': e.value.count,
              })
          .toList()
        ..sort(
            (a, b) => (b['total'] as double).compareTo(a['total'] as double)),
      'sample': {
        'count': sample.length,
        'isPartial': matched.length > sample.length,
        'transactions': [
          for (final t in sample)
            {
              'date': formatIsoDate(t.happenedAt),
              'type': t.type,
              'amount': t.nativeAmount ?? t.amount,
              'category':
                  t.categoryId == null ? null : catById[t.categoryId!]?.name,
              'account': t.accountId == null ? null : accById[t.accountId!],
              'note': t.note,
              'merchant': t.merchant,
            },
        ],
      },
      // 這行直接進第二階段的 prompt。放在 payload 裡比放在 systemPrompt 有效,
      // 因為它跟資料在同一個位置,能擋下「看到陣列就想加總」的反射。
      'note': 'matchedCount / totalExpense / totalIncome / byCategory 已涵蓋全部 '
          '${matched.length} 筆,可以直接引用。'
          'sample.transactions 只是其中的樣本,請勿自行加總樣本。',
    };
  }

  bool _matchesKeyword(Transaction t, Category? cat, List<String> keywords) {
    final note = t.note ?? '';
    final merchant = t.merchant ?? '';
    // 分類名稱套簡繁摺疊(表小、零邊際成本);note/merchant 不摺疊,
    // 改由模型在 keyword 一次給多個變體來覆蓋。見 zh_variants.dart 的說明。
    final foldedCat = cat == null ? null : foldZh(cat.name);
    for (final k in keywords) {
      if (note.contains(k) || merchant.contains(k)) return true;
      if (foldedCat != null && foldedCat.contains(foldZh(k))) return true;
    }
    return false;
  }

  /// 分級解析分類名稱。回傳 null 代表呼叫端沒指定分類(不過濾)。
  ///
  /// 完全相等優先、有命中就不再往下,是避免模糊比對發散的關鍵:
  /// `categoryName: "餐飲"` 只會回餐飲,不會誤拉早餐;而 `"餐"` 因為沒有完全
  /// 相等的分類,才退化成雙向包含,回出餐飲/餐廳/早餐並在 resolvedCategories
  /// 裡列出來讓使用者看得見。
  ({Set<int?> ids, List<String> names})? _resolveCategories({
    required List<Category> categories,
    required String? query,
    required String? typeFilter,
  }) {
    if (query == null) return null;

    final pool = typeFilter == null
        ? categories
        : categories.where((c) => c.kind == typeFilter).toList();
    final folded = foldZh(query);

    List<Category> pick(bool Function(String name) test) =>
        pool.where((c) => test(foldZh(c.name))).toList();

    var hits = pick((n) => n == folded);
    if (hits.isEmpty) hits = pick((n) => n.contains(folded));
    if (hits.isEmpty) hits = pick((n) => folded.contains(n));

    // 父分類要自動含子分類,否則「醫療總共花多少」會漏掉所有二級分類。
    final ids = <int?>{};
    final names = <String>[];
    for (final c in hits) {
      if (ids.add(c.id)) names.add(c.name);
    }
    for (final c in pool) {
      if (c.parentId != null && ids.contains(c.parentId) && ids.add(c.id)) {
        names.add(c.name);
      }
    }
    return (ids: ids, names: names);
  }

  // ============================================================
  // get_recurring_transactions
  // ============================================================

  Future<Map<String, dynamic>> _getRecurringTransactions(
    BaseRepository repo,
    int ledgerId,
  ) async {
    final rules = await repo.getRulesByLedger(ledgerId);
    final enabled = rules.where((r) => r.enabled).toList();
    return {
      'count': enabled.length,
      'rules': enabled
          .map((r) => {
                'type': r.type,
                'amount': r.amount,
                'note': r.note,
                'merchant': r.merchant,
                'frequency': r.frequency,
                'interval': r.interval,
                'nextRunAt': formatIsoDate(r.nextRunAt),
              })
          .toList(),
    };
  }

  // ============================================================
  // 參數解析
  // ============================================================

  _ResolvedRange _resolveRange(Map<String, dynamic> params) {
    final allTime = params['allTime'] == true;
    final start = allTime ? null : _optionalDate(params, 'startDate');
    final endDateOnly = allTime ? null : _optionalDate(params, 'endDate');
    return _ResolvedRange(
      allTime: allTime,
      requestedStart: start,
      requestedEnd: endDateOnly,
    );
  }

  DateTime? _optionalDate(Map<String, dynamic> params, String key) {
    final raw = params[key];
    if (raw == null) return null;
    if (raw is! String || raw.isEmpty) {
      throw FreeChatToolException('參數 $key 日期格式錯誤: $raw');
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw FreeChatToolException('參數 $key 日期格式錯誤: $raw');
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  String? _optionalString(Map<String, dynamic> params, String key) {
    final raw = params[key];
    if (raw is! String || raw.trim().isEmpty) return null;
    return raw.trim();
  }

  /// `keyword` 同時接受字串與陣列 —— 讓模型能一次給簡繁變體與同義詞。
  List<String>? _optionalStringList(Map<String, dynamic> params, String key) {
    final raw = params[key];
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
    throw FreeChatToolException('參數 $key 必須是字串或字串陣列: $raw');
  }

  String? _optionalType(Map<String, dynamic> params, String key) {
    final raw = _optionalString(params, key);
    if (raw == null) return null;
    final v = raw.toLowerCase();
    if (v != 'expense' && v != 'income') {
      throw FreeChatToolException("參數 $key 只能是 'expense' 或 'income': $raw");
    }
    return v;
  }

  int _clampLimit(dynamic raw) {
    var limit = 20;
    if (raw is int) {
      limit = raw;
    } else if (raw is String) {
      limit = int.tryParse(raw) ?? 20;
    }
    if (limit > 50) return 50;
    if (limit < 0) return 0;
    return limit;
  }
}

/// 解析後的查詢區間。
///
/// `queryStart` / `queryEnd` 是給 repository 的實際上下界 —— 目前底層方法都要求
/// 非 null,所以無界那側用極寬的哨兵日期頂著。Phase 4 換成 SQL 搜尋方法後,
/// 這裡會直接傳 null 下去(對應的測試不需要改)。
class _ResolvedRange {
  final bool allTime;
  final DateTime? requestedStart;
  final DateTime? requestedEnd;

  _ResolvedRange({
    required this.allTime,
    required this.requestedStart,
    required this.requestedEnd,
  });

  static final DateTime _minDate = DateTime(1900);

  DateTime get queryStart => requestedStart ?? _minDate;

  /// 參數語意是「含結束當天」,底層是 `[start, end)` 左閉右開,所以要 +1 天。
  DateTime get queryEnd {
    final e = requestedEnd;
    if (e == null) return DateTime(DateTime.now().year + 100);
    return DateTime(e.year, e.month, e.day + 1);
  }

  Map<String, dynamic> toJson({
    DateTime? actualFirstDate,
    DateTime? actualLastDate,
  }) =>
      {
        'allTime': allTime || (requestedStart == null && requestedEnd == null),
        'requestedStartDate':
            requestedStart == null ? null : formatIsoDate(requestedStart!),
        'requestedEndDate':
            requestedEnd == null ? null : formatIsoDate(requestedEnd!),
        if (actualFirstDate != null)
          'actualFirstDate': formatIsoDate(actualFirstDate),
        if (actualLastDate != null)
          'actualLastDate': formatIsoDate(actualLastDate),
      };
}
