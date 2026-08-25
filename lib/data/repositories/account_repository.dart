import '../db.dart';

/// 账户Repository接口
/// 定义账户相关的所有数据操作
abstract class AccountRepository {
  /// 获取指定账本下的所有账户（Stream版本）
  Stream<List<Account>> watchAccountsForLedger(int ledgerId);

  /// 获取所有账户（不限账本，Stream版本）
  Stream<List<Account>> watchAllAccounts();

  /// 获取所有账户（不限账本，Future版本）
  Future<List<Account>> getAllAccounts();

  /// 获取单个账户信息
  Future<Account?> getAccount(int accountId);

  /// 按 syncId 查普通账户;通知中心等跨端 syncId → 本地实体的场景用。
  Future<Account?> getAccountBySyncId(String syncId);

  /// 获取账本可用的账户（通过币种过滤）
  Future<List<Account>> getAvailableAccountsForLedger(int ledgerId);

  /// 获取某币种的所有账户
  Future<List<Account>> getAccountsByCurrency(String currency);

  /// 按币种分组获取账户统计
  Future<Map<String, List<Account>>> getAccountsGroupedByCurrency();

  /// 创建账户。撞同名抛 [DuplicateNameException](name 全局唯一)。
  /// 静默路径(import / app-link 等)请用 [upsertAccount](get-or-create 语义)。
  /// [syncId] 可选:seed 类路径显式塞确定性 id,UI 不传走 auto v4。
  Future<int> createAccount({
    required int ledgerId,
    required String name,
    String type = 'cash',
    String currency = 'CNY',
    double initialBalance = 0.0,
    double? creditLimit,
    int? billingDay,
    int? paymentDueDay,
    String? bankName,
    String? cardLastFour,
    String? note,
    String? syncId,
    String? parentAccountId,
    String? avatarPath,
    bool includeInTotal = true,
  });

  /// 按 name 取账户(name 全局唯一,账户跨账本可用);不存在则建一条。
  /// 给 import / app-link 等 get-or-create 语义的静默路径用 —— 不会抛
  /// [DuplicateNameException]。
  ///
  /// [ledgerId] 是 legacy 字段(早期 schema 残留),账户实际跨账本可用,默认 0。
  Future<int> upsertAccount({
    required String name,
    int ledgerId = 0,
    String type = 'cash',
    String currency = 'CNY',
    double initialBalance = 0.0,
  });

  /// 更新账户
  ///
  /// [hidden]、[includeInTotal] 为 null 表示不改动(见 [setAccountHidden] 便捷
  /// 法)。true/false 显式传入才会写库,配合同步 apply 的「缺键保留」语义
  /// (账户隐藏 #240;不納入總餘額同理)。
  Future<void> updateAccount(
    int id, {
    String? name,
    String? type,
    String? currency,
    double? initialBalance,
    double? creditLimit,
    int? billingDay,
    int? paymentDueDay,
    bool clearCreditCardFields = false,
    String? bankName,
    String? cardLastFour,
    String? note,
    bool clearMetadataFields = false,
    bool? hidden,
    String? parentAccountId,
    bool clearParentAccount = false,
    String? avatarPath,
    bool clearAvatar = false,
    bool? includeInTotal,
  });

  /// 隐藏 / 恢复账户(账户隐藏 #240)。内部走 [updateAccount] → 记
  /// user-global 'update' change → 同步。**不要**绕过它直接改列,否则隐藏
  /// 状态不会 push 到云端(同 `updateAccountSortOrders` / `updateAccountValuation`
  /// 的教训)。
  Future<void> setAccountHidden(int id, bool hidden);

  /// 获取所有信用卡账户
  Future<List<Account>> getCreditCardAccounts();

  /// 获取信用卡已用额度（负余额 = 欠款额度）
  ///
  /// [asOf] 不传时口径为「现在」；传入时只计入 `happenedAt <= asOf` 的交易，
  /// 用于信用卡帳單彙總卡片算「上期欠款」「剩餘帳款」这类某个帳期结束当下
  /// 的终身跑动余额快照（`getAccountBalance` 同参数语意）。
  Future<double> getCreditCardUsedAmount(int accountId, {DateTime? asOf});

  /// 信用卡帳單口徑「已刷卡金額」:Σexpense − Σincome,`COALESCE(deferredPostingAt,
  /// happenedAt) <= [asOf]`(未传 = 现在;若晚于现在一律 clamp 到现在,即使
  /// 调用方显式传了未来时间点——对齐 BeeCount Cloud `compute_cycle_period_billing`
  /// 对「本期尚未结束」的 `min(cycle_end_dt, now)` clamp)。**用入帳歸屬日
  /// (延後入帳後的日期)而非原始交易日做帳期截斷**——对齐 Cloud `_ATTR_DATE`
  /// 与 App 既有 [getAccountStatementTransactions] 的入帳歸屬日口径,否则会跟
  /// 「新增花費」等已经用歸屬日過濾的口径对不上(2026-08-18 使用者实测:
  /// 一笔已標記延後入帳的交易被算进原帳期,导致「已繳金額」倒推出异常负数)。
  /// **不含** initialBalance / transfer / adjustment——这三者在 Cloud 的信用卡
  /// 帳單公式里都不存在,混进来会让 App 端算出的欠款跟 Server 对不上
  /// (`getAccountBalance` 是给一般资产余额用的,别复用在信用卡帳單口径上)。
  Future<double> getCreditCardChargedAsOf(int accountId, {DateTime? asOf});

  /// 信用卡帳單口徑「历史累计已繳金額」:Σ transfer.amount(toAccountId=
  /// accountId),真·终身、不设任何 cutoff——镜像 Cloud
  /// `compute_cycle_period_billing` 的 `paid_total`:不论繳款发生在哪个帳期,
  /// 一律先套用在最早未清偿的帳期上(FIFO watermark),所以这里不能只算
  /// 「本期」或「asOf 之前」。
  Future<double> getCreditCardPaidTotal(int accountId);

  /// 「繳款記錄」清單顯示用:這張卡收到的全部繳款交易明細,跟
  /// [getCreditCardPaidTotal] 同一個查詢範圍,只是回傳明細列而非加總,依
  /// 入帳歸屬日由舊到新排序。搭配 [getCreditCardFirstActivityAt] 餵給
  /// `attributePaymentsToPeriods`(`credit_card_payment.dart`)做 FIFO 期別
  /// 歸屬——**這是 App 端專屬行為,不是鏡射 Cloud**(`get_account_statement`
  /// 沒有這種歸屬概念,對帳模式/`getAccountStatementTransactions` 不受這個
  /// 方法影響),範圍刻意收窄成只給帳戶詳情頁的「繳款記錄」小節用。
  Future<List<Transaction>> getCreditCardPaymentTransactions(int accountId);

  /// 這張卡「有史以來」第一筆會影響帳單口徑的交易(expense/income/轉入的
  /// transfer)入帳歸屬日,沒有任何交易時回傳 null。用途見
  /// [getCreditCardPaymentTransactions] 的文件註解。
  Future<DateTime?> getCreditCardFirstActivityAt(int accountId);

  /// 删除账户
  Future<void> deleteAccount(int id);

  /// 获取账户余额（收入 - 支出 + 转入 - 转出）
  ///
  /// [asOf] 不传时口径为「现在」（`happenedAt <= DateTime.now()`）；传入时
  /// 换成 `happenedAt <= asOf`，用来算「截至某个帳期结束日」的终身跑动余额
  /// 快照，不是新开一个方法名——所有既有呼叫端不传这个参数,行为完全不变。
  Future<double> getAccountBalance(int accountId, {DateTime? asOf});

  /// 获取账户全局余额（跨所有账本）
  Future<double> getAccountGlobalBalance(int accountId);

  /// 获取账户在某账本的余额
  Future<double> getAccountBalanceInLedger(int accountId, int ledgerId);

  /// 批量获取所有账户余额
  Future<Map<int, double>> getAllAccountBalances(int ledgerId);

  /// 获取账户的交易数量
  Future<int> getTransactionCountByAccount(int accountId);

  /// 获取单个账户的消费金额
  Future<double> getAccountExpense(int accountId);

  /// 获取单个账户的收入金额
  Future<double> getAccountIncome(int accountId);

  /// 获取单个账户的统计信息（余额、消费金额、收入金额）
  Future<({double balance, double expense, double income})> getAccountStats(
      int accountId);

  /// 批量获取所有账户的统计信息
  Future<Map<int, ({double balance, double expense, double income})>>
      getAllAccountStats();

  /// 获取所有账户的汇总统计（总余额、总支出、总收入）
  Future<({double totalBalance, double totalExpense, double totalIncome})>
      getAllAccountsTotalStats();

  /// 获取账户在多个账本中的使用情况
  Future<Map<int, int>> getAccountUsageInLedgers(int accountId);

  /// 账户迁移（将fromAccountId的所有交易迁移到toAccountId）
  Future<int> migrateAccount({
    required int fromAccountId,
    required int toAccountId,
  });

  /// 检查账户是否有交易记录
  Future<bool> hasTransactions(int accountId);

  /// 响应式监听账户信息变化
  Stream<Account?> watchAccount(int accountId);

  /// 响应式监听账户相关的所有交易
  Stream<List<Transaction>> watchAccountTransactions(int accountId);

  /// 批量插入账户
  Future<void> batchInsertAccounts(List<AccountsCompanion> accounts);

  /// 批量获取账户信息（通过ID列表）
  Future<List<Account>> getAccountsByIds(List<int> accountIds);

  /// 批量更新账户排序顺序
  Future<void> updateAccountSortOrders(List<({int id, int sortOrder})> updates);

  /// 分页获取账户交易
  ///
  /// [flow] 按资金流向过滤:
  /// - 'expense':支出 + 转出(资金流出该账户)
  /// - 'income':收入 + 转入(资金流入该账户)
  /// - null:全部交易
  ///
  /// [extraAccountIds] 主帳戶(合併帳單分組)聚合視圖用:非空時把這些子帳戶的
  /// 交易也一併拉出來(跟 accountId 合併按 account_id IN (...) 查),用於帳戶
  /// 詳情頁「交易明細」tab 顯示主卡+所有子卡的合併流水。
  ///
  /// [startDate]/[endDate] 帳單週期篩選(信用卡「交易明細」tab 按帳單日切期
  /// 用),含端點所在的整個自然日(endDate 當天 23:59:59 前都算,不用調用方
  /// 自己補時分秒),null 代表不限制。比對的是原始發生日 `happened_at`——
  /// 信用卡帳單彙總卡片下方的交易列表改用「入帳歸屬日」口徑時請改呼叫
  /// [getAccountStatementTransactions],不要在這裡加參數分岔。
  Future<List<Transaction>> getAccountTransactions(
    int accountId, {
    int limit = 50,
    int offset = 0,
    String? flow,
    List<int>? extraAccountIds,
    DateTime? startDate,
    DateTime? endDate,
  });

  /// 對帳模式(§2.10 MOZE_FEATURE_GAP_SD.md)專用:依「入帳歸屬日」
  /// (`COALESCE(deferred_posting_at, happened_at)`)過濾交易落在哪一期帳單,
  /// 而不是像 [getAccountTransactions] 那樣按發生日 `happened_at` 過濾。
  ///
  /// 跟 [getAccountTransactions] 的差異不只是多一個 COALESCE:member 帳戶
  /// 判斷收窄成對帳清單的口徑——expense/income 只認 `account_id`,transfer
  /// 只認 `to_account_id`(轉出這張卡不算消費),其它 type(adjustment 等)
  /// 不收,跟 `reconciliation.dart` 的 `effectiveDate` + 呼叫方 belongs 判斷
  /// 語意一致(之前是 provider 端在 Dart 拿 ±1 期寬視窗再篩,延後入帳距離
  /// 超過一期或呼叫方臨時選了很遠的日期時,原始 `happened_at` 落在視窗外會
  /// 直接查不到那筆交易,SQL 層直接用 COALESCE 過濾才能不受延後距離限制)。
  /// 信用卡帳單彙總卡片/交易列表統一用這個方法(不再借用
  /// [getAccountTransactions] 另傳一個 `byEffectiveDate` 旗標),對帳清單/
  /// 彙總數字/交易列表三處共用同一份、同一個口徑的資料(2026-08-18 修正:
  /// 直接查證 BeeCount Cloud 正式資料庫核對後,確認這是唯一跟 Server
  /// `get_account_statement` 對得上的篩選口徑,不應該另外維護一份更寬鬆的
  /// 查詢給彙總卡片用)。
  Future<List<Transaction>> getAccountStatementTransactions({
    required int accountId,
    List<int>? extraAccountIds,
    required DateTime cycleStart,
    required DateTime cycleEnd,
  });

  /// 获取账户每日余额快照（用于余额趋势图）
  Future<List<({DateTime date, double balance})>> getAccountDailyBalances(
      int accountId,
      {required DateTime startDate,
      required DateTime endDate});

  /// 获取账户级分类统计（用于分类饼图）
  Future<List<({int? id, String name, String? icon, double total})>>
      getAccountCategoryStats(int accountId, {required String type});

  /// 获取净资产分解（总资产、总负债、净资产）
  Future<({double totalAssets, double totalLiabilities, double netWorth})>
      getNetWorthBreakdown();

  /// 按币种分组的净资产分解
  Future<
          Map<String,
              ({double totalAssets, double totalLiabilities, double netWorth})>>
      getNetWorthBreakdownByCurrency();

  /// 获取净资产每日余额快照（用于净资产趋势图）
  Future<List<({DateTime date, double balance})>> getNetWorthDailyBalances({
    required DateTime startDate,
    required DateTime endDate,
  });

  /// 净值趋势序列:每日 (资产合计, 负债合计, 净资产),已折算到主币种。
  /// [ratesToBase]:各币种 → 主币种汇率(主币种自身 1.0);缺汇率的币种整条剔除
  /// (与净资产卡 convertedNetWorth 同口径)。负债类(credit_card/loan)计入 liabilities。
  Future<List<({DateTime date, double assets, double liabilities, double net})>>
      getNetWorthTrendSeries({
    required DateTime startDate,
    required DateTime endDate,
    required Map<String, double> ratesToBase,
  });

  /// 获取资产构成（按账户类型分组的余额汇总）
  Future<List<({String type, double totalBalance})>>
      getAssetCompositionByType();

  /// 按 (账户类型, 币种) 聚合的资产构成(多币种折算用)。currency 已大写归一。
  Future<List<({String type, String currency, double totalBalance})>>
      getAssetCompositionByTypeAndCurrency();

  /// 更新估值账户的当前估值
  Future<void> updateAccountValuation(int accountId, double newValue);

  // ============================================
  // 共享账本(§7 / v25)— 跨设备共享的 SharedLedgerAccounts 表
  // ============================================

  /// 按 syncId 查 SharedLedgerAccounts 行;Editor 视角下 tx 的
  /// accountSyncIdOverride 走这条反查 → 上层再映射成 synthetic Account。
  Future<SharedLedgerAccount?> getSharedAccountBySyncId(String syncId);

  /// 账户使用中的币种集合(去重、大写)。多币种态判定与汇率页列表用。
  Future<Set<String>> getUsedCurrencies();
}
