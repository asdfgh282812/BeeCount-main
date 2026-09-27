import '../../data/repositories/base_repository.dart';

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

  const FreeChatContext({
    required this.expenseCategories,
    required this.incomeCategories,
    this.accountNames = const [],
  });

  static const empty = FreeChatContext(
    expenseCategories: [],
    incomeCategories: [],
    accountNames: [],
  );

  /// 單一 kind 最多列幾個名稱,避免超大帳本把 prompt 撐爆。
  static const maxNamesPerKind = 60;

  static Future<FreeChatContext> forLedger({
    required BaseRepository repo,
  }) async {
    final expense = await repo.getUsableCategories('expense');
    final income = await repo.getUsableCategories('income');
    // 排除 `account_group`(合併帳單用的管理容器,從來不是任何交易真正的
    // 記帳帳戶)——與 `ai_extraction_context.dart` 挑記帳候選帳戶時的過濾一致。
    final accounts = await repo.getAllAccounts();
    return FreeChatContext(
      expenseCategories: expense.map((c) => c.name).toList(),
      incomeCategories: income.map((c) => c.name).toList(),
      accountNames: accounts
          .where((a) => a.type != 'account_group')
          .map((a) => a.name)
          .toList(),
    );
  }

  bool get isEmpty =>
      expenseCategories.isEmpty &&
      incomeCategories.isEmpty &&
      accountNames.isEmpty;

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
    return [
      line(expenseLabel, expenseCategories),
      line(incomeLabel, incomeCategories),
      line(accountLabel, accountNames),
    ].where((s) => s.isNotEmpty).join('\n');
  }
}
