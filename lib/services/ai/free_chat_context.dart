import '../../data/repositories/base_repository.dart';
import '../investment/holdings_calculator.dart';
import '../investment/markets.dart';
import '../../providers/securities_providers.dart' show holdingTradeOf;

/// 自由對話 routing 階段要用的**精簡**帳本上下文。
///
/// 目前有分類名稱與帳戶名稱。修掉意圖路由的誤判之後,這是最大的剩餘失敗模式 ——
/// 模型不知道「復健科」是分類名、商家名、還是隨手寫的備註,也不知道「星展英雄
/// 聯盟卡」是帳戶名而不是關鍵字,只能瞎猜要填 `categoryName`/`accountName`
/// 還是 `keyword`。給了清單它就能選對參數、不會發明不存在的分類/帳戶名,甚至能
/// 在帳本裡根本沒有那個分類/帳戶時直接回答而**不呼叫工具**(反而省下一次往返)。
///
/// **刻意不重用 [AiExtractionContext]**:那個是記帳側的,順帶讀 SharedPreferences
/// 裡的自訂 prompt 模板、讀專案指派模式 —— routing 一個都不需要,而且會把
/// SharedPreferences 拉進每一則訊息的路徑。
///
/// **不做快取**:每則訊息多一次小查詢可以忽略;而快取一份過期的分類/帳戶清單
/// (使用者剛新增分類/帳戶卻查不到)是比多一次查詢糟得多的 bug。
class FreeChatContext {
  final List<String> expenseCategories;
  final List<String> incomeCategories;
  final List<String> accountNames;

  /// 投資理財帳戶名稱(`accountNames` 的子集,另外列一行讓模型知道股票工具
  /// 的 `account` 參數該填哪些名字)。
  final List<String> investmentAccountNames;

  /// 有交易過的股票標的,格式 `2330 台積電`(目前持有的排前面)。幫模型把使用者
  /// 講的名稱/代號對上實際標的,控制在 [maxSecurities] 檔內。
  final List<String> securities;

  const FreeChatContext({
    required this.expenseCategories,
    required this.incomeCategories,
    this.accountNames = const [],
    this.investmentAccountNames = const [],
    this.securities = const [],
  });

  static const empty = FreeChatContext(
    expenseCategories: [],
    incomeCategories: [],
    accountNames: [],
  );

  /// 單一 kind 最多列幾個名稱,避免超大帳本把 prompt 撐爆。
  static const maxNamesPerKind = 60;

  /// 最多列幾檔股票標的。
  static const maxSecurities = 30;

  static Future<FreeChatContext> forLedger({
    required BaseRepository repo,
  }) async {
    final expense = await repo.getUsableCategories('expense');
    final income = await repo.getUsableCategories('income');
    // 排除 `account_group`(合併帳單用的管理容器,從來不是任何交易真正的
    // 記帳帳戶)——與 `ai_extraction_context.dart` 挑記帳候選帳戶時的過濾一致。
    final accounts = await repo.getAllAccounts();
    final investmentNames = accounts
        .where((a) => a.type == 'investment')
        .map((a) => a.name)
        .toList();
    final securities = investmentNames.isEmpty
        ? const <String>[]
        : await _loadSecurities(repo);
    return FreeChatContext(
      expenseCategories: expense.map((c) => c.name).toList(),
      incomeCategories: income.map((c) => c.name).toList(),
      accountNames: accounts
          .where((a) => a.type != 'account_group')
          .map((a) => a.name)
          .toList(),
      investmentAccountNames: investmentNames,
      securities: securities,
    );
  }

  /// 有股票明細的標的:持有中的優先,其次已出清;名稱取該標的最新的明細名稱。
  /// 沒有任何投資理財帳戶時呼叫端直接略過(不多讀一次明細表)。
  static Future<List<String>> _loadSecurities(BaseRepository repo) async {
    final trades = await repo.getAllStockTrades();
    if (trades.isEmpty) return const [];
    final names = <String, String>{};
    final sorted = [...trades]
      ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
    for (final t in sorted) {
      final key = securityKey(t.market, t.symbol);
      final n = t.securityName;
      if (n != null && n.isNotEmpty) names[key] = n;
      names.putIfAbsent(key, () => '');
    }
    final open = <String>{
      for (final h in HoldingsCalculator.compute(trades.map(holdingTradeOf)))
        securityKey(h.market, h.symbol),
    };
    final keys = names.keys.toList()
      ..sort((a, b) {
        final oa = open.contains(a) ? 0 : 1;
        final ob = open.contains(b) ? 0 : 1;
        return oa != ob ? oa.compareTo(ob) : a.compareTo(b);
      });
    return [
      for (final k in keys)
        names[k]!.isEmpty ? k : '${k.substring(k.indexOf(':') + 1)} ${names[k]}',
    ];
  }

  bool get isEmpty =>
      expenseCategories.isEmpty &&
      incomeCategories.isEmpty &&
      accountNames.isEmpty &&
      investmentAccountNames.isEmpty &&
      securities.isEmpty;

  /// 拼進 routing systemPrompt 的區塊。空的時候回空字串,呼叫端就不會加這一段。
  String toPromptSection({required bool isEn}) {
    if (isEmpty) return '';
    String line(String label, List<String> names) {
      if (names.isEmpty) return '';
      final shown = names.take(maxNamesPerKind).toList();
      final suffix = names.length > shown.length ? '…' : '';
      return '$label${shown.join('、')}$suffix';
    }

    final expenseLabel = isEn ? 'Expense categories: ' : '支出分類:';
    final incomeLabel = isEn ? 'Income categories: ' : '收入分類:';
    final accountLabel = isEn ? 'Accounts: ' : '帳戶:';
    final investLabel =
        isEn ? 'Investment accounts (stock tools): ' : '投資理財帳戶(股票工具用):';
    final securityLabel = isEn
        ? 'Stocks traded (held first): '
        : '交易過的股票(持有中的在前):';
    final shownSecurities = securities.take(maxSecurities).toList();
    final securityLine = shownSecurities.isEmpty
        ? ''
        : '$securityLabel${shownSecurities.join('、')}'
            '${securities.length > shownSecurities.length ? '…' : ''}';
    return [
      line(expenseLabel, expenseCategories),
      line(incomeLabel, incomeCategories),
      line(accountLabel, accountNames),
      line(investLabel, investmentAccountNames),
      securityLine,
    ].where((s) => s.isNotEmpty).join('\n');
  }
}
