import '../../data/repositories/base_repository.dart';
import '../../data/repositories/budget_repository.dart' show BudgetUsage;

/// 自由對話唯讀查詢工具:metadata + executor。
///
/// 只做「查資料、整理成好餵給 LLM 的 Map」,不碰任何寫入操作 —— 這批工具全部
/// 唯讀,沒有授權彈窗的必要(見 design doc「明確排除」)。

/// 單一工具參數的說明,純資料,用來拼進 routing systemPrompt。
class FreeChatToolParam {
  final String name;
  final String type; // 'date' | 'bool' | 'string' | 'int'
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

/// 目前支援的 4 個唯讀查詢工具。
const List<FreeChatToolSpec> freeChatTools = [
  FreeChatToolSpec(
    name: 'get_spending_summary',
    description: '取得指定區間的收支總額,groupByCategory=true 時額外回傳各分類佔比',
    params: [
      FreeChatToolParam(
        name: 'startDate',
        type: 'date',
        required: true,
        description: '區間開始日期,格式 YYYY-MM-DD',
      ),
      FreeChatToolParam(
        name: 'endDate',
        type: 'date',
        required: true,
        description: '區間結束日期(含當天),格式 YYYY-MM-DD',
      ),
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
    description: '列出指定區間內符合條件的交易明細(含分類/帳戶名稱)',
    params: [
      FreeChatToolParam(
        name: 'startDate',
        type: 'date',
        required: true,
        description: '區間開始日期,格式 YYYY-MM-DD',
      ),
      FreeChatToolParam(
        name: 'endDate',
        type: 'date',
        required: true,
        description: '區間結束日期(含當天),格式 YYYY-MM-DD',
      ),
      FreeChatToolParam(
        name: 'categoryName',
        type: 'string',
        description: '只看這個分類名稱的交易,省略則不限分類',
      ),
      FreeChatToolParam(
        name: 'keyword',
        type: 'string',
        description: '比對備註/商家名稱的關鍵字,省略則不過濾',
      ),
      FreeChatToolParam(
        name: 'limit',
        type: 'int',
        description: '最多回傳筆數,預設 20,上限 50',
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

/// 工具名不存在 / 缺必填參數時拋出,供 [FreeChatRouter] 捕捉並降級成固定文案,
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

  Future<Map<String, dynamic>> _getSpendingSummary(
    Map<String, dynamic> params,
    BaseRepository repo,
    int ledgerId,
  ) async {
    final start = _requireDate(params, 'startDate');
    final endDateOnly = _requireDate(params, 'endDate');
    final exclusiveEnd = _startOfNextDay(endDateOnly);
    final groupByCategory = params['groupByCategory'] == true;

    final (income, expense) = await repo.totalsInRange(
      ledgerId: ledgerId,
      start: start,
      end: exclusiveEnd,
    );

    final result = <String, dynamic>{
      'startDate': formatIsoDate(start),
      'endDate': formatIsoDate(endDateOnly),
      'income': income,
      'expense': expense,
    };

    if (groupByCategory) {
      final expenseCategories = await repo.totalsByCategory(
        ledgerId: ledgerId,
        type: 'expense',
        start: start,
        end: exclusiveEnd,
      );
      final incomeCategories = await repo.totalsByCategory(
        ledgerId: ledgerId,
        type: 'income',
        start: start,
        end: exclusiveEnd,
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

  Future<Map<String, dynamic>> _queryTransactions(
    Map<String, dynamic> params,
    BaseRepository repo,
    int ledgerId,
  ) async {
    final start = _requireDate(params, 'startDate');
    final endDateOnly = _requireDate(params, 'endDate');
    final exclusiveEnd = _startOfNextDay(endDateOnly);
    final categoryName = _optionalString(params, 'categoryName');
    final keyword = _optionalString(params, 'keyword');
    final limit = _clampLimit(params['limit']);

    final transactions = await repo.getTransactionsByLedgerInRange(
      ledgerId: ledgerId,
      start: start,
      end: exclusiveEnd,
    );

    final items = <Map<String, dynamic>>[];
    for (final t in transactions) {
      if (keyword != null &&
          !(t.note ?? '').contains(keyword) &&
          !(t.merchant ?? '').contains(keyword)) {
        continue;
      }

      String? catName;
      if (t.categoryId != null) {
        catName = (await repo.getCategoryById(t.categoryId!))?.name;
      }
      if (categoryName != null && catName != categoryName) {
        continue;
      }

      String? accName;
      if (t.accountId != null) {
        accName = (await repo.getAccount(t.accountId!))?.name;
      }

      items.add({
        'date': formatIsoDate(t.happenedAt),
        'type': t.type,
        'amount': t.nativeAmount ?? t.amount,
        'category': catName,
        'account': accName,
        'note': t.note,
        'merchant': t.merchant,
      });
    }

    final truncated = items.length > limit;
    return {
      'startDate': formatIsoDate(start),
      'endDate': formatIsoDate(endDateOnly),
      'count': truncated ? limit : items.length,
      'truncated': truncated,
      'transactions': items.take(limit).toList(),
    };
  }

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

  DateTime _requireDate(Map<String, dynamic> params, String key) {
    final date = _optionalDate(params, key);
    if (date == null) {
      throw FreeChatToolException('缺少必填參數: $key');
    }
    return date;
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
    if (raw is! String || raw.isEmpty) return null;
    return raw;
  }

  DateTime _startOfNextDay(DateTime dateOnly) =>
      DateTime(dateOnly.year, dateOnly.month, dateOnly.day + 1);

  int _clampLimit(dynamic raw) {
    var limit = 20;
    if (raw is int) {
      limit = raw;
    } else if (raw is String) {
      limit = int.tryParse(raw) ?? 20;
    }
    if (limit > 50) return 50;
    if (limit < 1) return 1;
    return limit;
  }
}
