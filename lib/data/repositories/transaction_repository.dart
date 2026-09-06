import '../db.dart';
import '../../models/note_history.dart';
import '../../models/merchant_history.dart';
import '../../models/category_suggestion.dart';

/// 批量按 syncId 更新交易时的单条 update payload。
class TransactionUpdateBySyncIdData {
  final String syncId;
  final String type;
  final double amount;
  final int? categoryId;
  final int? accountId;
  final int? toAccountId;
  final DateTime happenedAt;
  final String? note;

  const TransactionUpdateBySyncIdData({
    required this.syncId,
    required this.type,
    required this.amount,
    this.categoryId,
    this.accountId,
    this.toAccountId,
    required this.happenedAt,
    this.note,
  });
}

/// 一笔拆帳明細的輸入(新增/更新交易時傳入)。對齊 BeeCount Cloud
/// `WriteTxSplitItem`:分類 + 金額 + 備註,不含帳戶(拆帳只拆分類,見
/// db.dart TransactionSplits 的註解)。
class TransactionSplitInput {
  final int? categoryId;
  // 共享账本 §7 场景:分类是 Owner 的虚拟分类时用这个,同
  // Transactions.categorySyncIdOverride。
  final String? categorySyncIdOverride;
  final double amount;
  final String? note;

  const TransactionSplitInput({
    this.categoryId,
    this.categorySyncIdOverride,
    required this.amount,
    this.note,
  });
}

/// 批量插入交易时附带的附件元数据。交易行还没插入,txId 未知,
/// repo 内部按 batch 内 index 找到刚插入的 txId 再组装 AttachmentsCompanion。
class BatchAttachmentData {
  final String fileName;
  final String? originalName;
  final int? fileSize;
  final int? width;
  final int? height;
  final int sortOrder;
  final String? cloudFileId;
  final String? cloudSha256;

  const BatchAttachmentData({
    required this.fileName,
    this.originalName,
    this.fileSize,
    this.width,
    this.height,
    this.sortOrder = 0,
    this.cloudFileId,
    this.cloudSha256,
  });
}

/// 交易Repository接口
/// 定义交易相关的所有数据操作
abstract class TransactionRepository {
  /// 获取最近的交易记录
  Stream<List<Transaction>> watchRecentTransactions({
    required int ledgerId,
    int limit = 20,
  });

  /// 获取指定月份的交易记录
  ///
  /// [month] 为周期标签,约定传 DateTime(year, month, 1);实际范围由账本
  /// monthStartDay 决定:[y-m-起始日, y-(m+1)-起始日)。
  Stream<List<Transaction>> watchTransactionsInMonth({
    required int ledgerId,
    required DateTime month,
  });

  /// 获取所有交易记录（带分类信息）
  /// [ledgerId] 可选，不传则获取所有账本的交易
  Stream<
      List<
          ({
            Transaction t,
            Category? category,
            Account? account,
            Account? toAccount
          })>> watchTransactionsWithCategoryAll({
    int? ledgerId,
  });

  /// 获取所有交易记录（带分类信息）- 非 Stream 版本
  /// [ledgerId] 可选，不传则获取所有账本的交易
  Stream<
      List<
          ({
            Transaction t,
            Category? category,
            Account? account,
            Account? toAccount
          })>> transactionsWithCategoryAll({
    int? ledgerId,
  });

  /// 获取最近的交易记录（带分类信息）- 用于预加载
  Future<
      List<
          ({
            Transaction t,
            Category? category,
            Account? account,
            Account? toAccount
          })>> getRecentTransactionsWithCategory({
    required int ledgerId,
    required int limit,
  });

  /// 聚合指定账本的历史备注。
  ///
  /// [categoryId] 和 [categorySyncId] 都为空时查询账本全部分类；共享账本中
  /// Owner 分类没有本地 ID 时，调用方传入 [categorySyncId] 精确匹配 override。
  Future<List<NoteHistoryEntry>> getNoteHistory({
    required int ledgerId,
    int? categoryId,
    String? categorySyncId,
    required NoteHistorySort sort,
    int limit = 20,
  });

  /// 聚合指定账本的历史商家(依类别记住常用商家,新增交易页商家欄位歷史
  /// 圖示用)。跟 [getNoteHistory] 同款查询形狀,但沒有 scope/sort 使用者
  /// 可調設定——[categoryId]/[categorySyncId] 都为空时查询账本全部分类,
  /// 恆按使用次数由高到低排序。
  Future<List<MerchantHistoryEntry>> getMerchantHistory({
    required int ledgerId,
    int? categoryId,
    String? categorySyncId,
    int limit = 20,
  });

  /// 该分类下最近使用过的 distinct 金额(新增交易页「常用金額」列用)，
  /// 按最后一次使用时间倒序。共享账本 Owner 分类(仅 syncId override、没有
  /// 本地 categoryId 的场景)暂不支持，直接返回空列表(该场景下这排快捷
  /// chips 不显示，不影响其余记账流程)。
  Future<List<double>> getRecentDistinctAmounts({
    required int ledgerId,
    required int categoryId,
    int limit = 8,
  });

  /// 「建議」分頁排序演算法用的原始使用訊號:最近一段時間內的支出交易
  /// (分類、發生時間、帳戶、備註)，按時間倒序，供
  /// [CategorySuggestionService] 在記憶體中計算分數。
  Future<List<CategoryUsageSignal>> getCategoryUsageSignals({
    required int ledgerId,
    required String kind,
    required DateTime since,
    int limit = 500,
  });

  /// 該分類歷史上最常使用的帳戶(依筆數、同筆數再依最近使用時間排序)，
  /// 用於選類別時靜默預帶帳戶。沒有歷史紀錄時回傳 null。
  Future<int?> getMostUsedAccountForCategory({
    required int ledgerId,
    required int categoryId,
  });

  /// 該帳本最近一筆轉帳交易使用的來源/目的帳戶，用於開新轉帳時預帶「最近
  /// 用過的兩個帳戶」。沒有歷史轉帳紀錄時回傳 null。
  Future<({int fromAccountId, int toAccountId})?> getLastTransferAccounts({
    required int ledgerId,
  });

  /// 根据ID获取单条交易
  Future<Transaction?> getTransactionById(int id);

  /// 获取指定月份的交易记录（带分类信息）
  ///
  /// [month] 为周期标签,约定传 DateTime(year, month, 1);实际范围由账本
  /// monthStartDay 决定:[y-m-起始日, y-(m+1)-起始日)。
  Stream<
      List<
          ({
            Transaction t,
            Category? category,
            Account? account,
            Account? toAccount
          })>> watchTransactionsWithCategoryInMonth({
    required int ledgerId,
    required DateTime month,
  });

  /// 获取指定年份的交易记录（带分类信息）
  Stream<
      List<
          ({
            Transaction t,
            Category? category,
            Account? account,
            Account? toAccount
          })>> watchTransactionsWithCategoryInYear({
    required int ledgerId,
    required int year,
  });

  /// 获取指定分类和时间范围的交易记录（带分类信息）
  Stream<
      List<
          ({
            Transaction t,
            Category? category,
            Account? account,
            Account? toAccount
          })>> watchTransactionsForCategoryInRange({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
    int? categoryId,
    required String type,
  });

  /// 添加交易
  ///
  /// §7 v25 共享账本:Editor 选 Owner 的 SharedLedger* 行时,categoryId /
  /// accountId / toAccountId 留 null,改填 *SyncIdOverride 字符串。
  /// Owner / 单人账本场景:走 categoryId int(老路径),override 留 null。
  Future<int> addTransaction({
    required int ledgerId,
    required String type,
    required double amount,
    int? categoryId,
    int? accountId,
    int? toAccountId,
    required DateTime happenedAt,
    String? note,
    // v33:商家(独立于 note 的自由文本字段,BeeCount Cloud 已有对应 wire 字段)。
    String? merchant,
    String? syncId,
    String? categorySyncIdOverride,
    String? accountSyncIdOverride,
    String? toAccountSyncIdOverride,
    bool excludeFromStats = false,
    bool excludeFromBudget = false,
    // v30 交易级多币种:未传时聚合层兜底(currencyCode=账户币种/本位币;
    // nativeAmount 外币先按有效汇率折算,取不到才 =amount,详设计 02 §六)。
    String? currencyCode,
    double? nativeAmount,
    // v34:退款关联(存原交易 syncId)。只在新建这笔交易当下写入,后续编辑不改。
    String? refundOfSyncId,
    // v35:信用卡紅利回饋——使用者手动勾选的规则 syncId 列表(不是本地 int
    // id,原因同 refundOfSyncId:本地 id 跨设备不稳定)。null/空 = 不挂任何
    // 回饋规则。
    List<String>? rewardRuleIds,
    // v36:週期性收支——這筆交易是哪條規則生成的 occurrence,存規則的
    // syncId。只在生成當下寫入,後續編輯不改(overridden 標記走專用方法)。
    String? recurringRuleId,
    // v38 拆帳:非空時這筆交易記為 hasSplits=true,categoryId/
    // categorySyncIdOverride 強制為 null,改插入這些明細到
    // TransactionSplits。null/空列表 = 普通單分類交易。呼叫方(表單)負責先
    // 驗證 ≥2 筆、金額和等於 amount、type 為 expense/income。
    List<TransactionSplitInput>? splits,
    // v39 借還款:這筆交易是某個 Debt 的還款/收款時,存該欠款的 syncId。
    // 只在新建時填(還款對話框/交易表單「關聯欠款」建立新交易時);既有交易
    // 改連結走 [setTransactionDebtLink]。
    String? debtSyncId,
    // v44 專案:這筆交易關聯的 Project 的 syncId。跟 debtSyncId 同款存
    // syncId 字串,可在新建/編輯時直接傳,也可透過交易編輯表單事後改。
    String? projectSyncId,
    bool needsAccountAssignment = false,
    // v45 跨幣別轉帳:轉入帳戶自己幣別的金額。只有 type == 'transfer' 且
    // 轉出/轉入帳戶幣別不同時才傳非 null;同幣別轉帳/非轉帳留 null。
    double? toAmount,
    // v46 轉帳手續費/折損:只在 type == 'transfer' 時有意義。feeAmount 是
    // 轉出側額外扣款(轉出帳戶幣別),discountAmount 是轉入側到帳前折損
    // (轉入帳戶幣別)。皆為 null = 沒有手續費/折損。
    double? feeAmount,
    String? feeLabel,
    double? discountAmount,
    String? discountLabel,
    // v51 支出/收入手續費/折扣:只在 type 為 expense/income 時有意義。
    // baseAmount 是使用者輸入的原始金額;呼叫方(交易表單)負責用
    // [computeFeeDiscountNetAmount] 算好淨額傳給上面的 [amount] 參數——
    // 本層不重算,語意跟轉帳的 feeAmount/discountAmount 一致(表單算好、
    // repository 只負責存)。為 null 代表沒有使用手續費/折扣。
    double? baseAmount,
  });

  /// 批量新增交易，单事务内插入，返回插入条数。
  ///
  /// [recordChanges] 默认 true,会逐条登记 changeTracker.recordLedgerChange。
  /// FullPull 路径需要传 false 避免"从云端拉下来的数据又被反向 push 回去"。
  Future<int> insertTransactionsBatch(
    List<TransactionsCompanion> items, {
    bool recordChanges = true,
  });

  /// 插入单条交易（使用 Companion 对象）
  ///
  /// [recordChanges] 同 [insertTransactionsBatch]。
  Future<int> insertTransactionCompanion(
    TransactionsCompanion item, {
    bool recordChanges = true,
  });

  /// 批量插入交易 + 关联数据(tag / attachment),全部在单事务内完成。
  ///
  /// 用于带标签 / 带附件的 import 路径 — 原本的"单条 insert + 单条
  /// updateTransactionTags + 单条 createAttachment"会引发 N+1 + 嵌套事务,
  /// 1 万条带标签数据耗时数十分钟;本方法把 N 次单条事务折叠成 1 次,
  /// 并用 `db.batch` 合并 tag / attachment / local_changes 的 INSERT。
  ///
  /// [tagIdsByIndex] - 批次内 index → tagId 列表。调用方需保证 tagIds 去重
  ///   (TransactionTags 表无 UNIQUE 约束,本方法不做 select 防重)。
  /// [attachmentsByIndex] - 批次内 index → 附件元数据列表。
  /// [recordChanges] - 同 [insertTransactionsBatch]。
  ///
  /// 返回插入的 tx id 列表,顺序跟 [transactions] 输入对齐。
  Future<List<int>> insertTransactionsBatchWithRelations({
    required List<TransactionsCompanion> transactions,
    Map<int, List<int>> tagIdsByIndex = const {},
    Map<int, List<BatchAttachmentData>> attachmentsByIndex = const {},
    bool recordChanges = true,
  });

  /// 更新交易
  Future<void> updateTransaction({
    required int id,
    required String type,
    required double amount,
    int? categoryId,
    String? note,
    // v33:商家,语义同 note——null 会显式清空既有值(调用方需自行传当前值以保留)。
    String? merchant,
    DateTime? happenedAt,
    dynamic accountId,
    String? categorySyncIdOverride,
    String? accountSyncIdOverride,
    String? toAccountSyncIdOverride,
    bool? excludeFromStats,
    bool? excludeFromBudget,
    // v30 交易级多币种:未传(null)= 不改动既有值;聚合层对 amount/账户变化
    // 做折算兜底。
    String? currencyCode,
    double? nativeAmount,
    // v35:语义同 merchant——null 会显式清空既有勾选(调用方需自行传当前值
    // 以保留)。
    List<String>? rewardRuleIds,
    // v38 拆帳:null = 不動既有拆帳明細;空列表 = 明確清空(還原成單一分類,
    // 這時 categoryId 參數才會生效寫回主表);非空列表 = 整組刪除重建。
    List<TransactionSplitInput>? splits,
    // v45 跨幣別轉帳:語意同 [accountId]——不傳(null)= 不動既有值;傳
    // `d.Value<double?>(null)` 顯式清空(如帳戶對改回同幣別);傳
    // `d.Value(x)` 或直接傳 double 寫入新值。呼叫方若不知道這個欄位(一般
    // 收支更新)一律不傳,行為不變。
    dynamic toAmount,
    // v46 轉帳手續費/折損:tri-state 同 [toAmount]——不傳 = 不動既有值;
    // 傳 `d.Value<double?>(null)`/`d.Value<String?>(null)` 顯式清空;傳值
    // 更新。呼叫方若不知道這組欄位(一般收支更新)一律不傳,行為不變。
    dynamic feeAmount,
    dynamic feeLabel,
    dynamic discountAmount,
    dynamic discountLabel,
    // v51 支出/收入手續費/折扣:tri-state 同 [feeAmount]。呼叫方負責用
    // [computeFeeDiscountNetAmount] 算好淨額傳給上面必填的 [amount] 參數。
    dynamic baseAmount,
  });

  /// 获取一笔交易的拆帳明細(依 sortOrder),非拆帳交易返回空列表。
  Future<List<TransactionSplit>> getTransactionSplits(int transactionId);

  /// 删除交易
  Future<void> deleteTransaction(int id);

  /// 获取指定类型和时间范围内的交易数量
  Future<int> countByTypeInRange({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  });

  /// 获取账本的所有交易记录
  Future<List<Transaction>> getTransactionsByLedger(int ledgerId);

  /// 「待確認帳戶」列表用:回傳這個帳本裡 [needsAccountAssignment] 為 true
  /// 的交易(背景自動記帳/週期性交易/CSV 匯入找不到帳戶時建立的)。
  Future<List<Transaction>> getTransactionsNeedingAccountAssignment(
      int ledgerId);

  /// 获取账本在指定时间范围内的交易记录
  Future<List<Transaction>> getTransactionsByLedgerInRange({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
  });

  /// 最近 [limit] 笔交易(按 happenedAt 降序),纯 [Transaction] 行、无分类/账户
  /// join、不做任何 exclude 过滤。
  ///
  /// 供桌面小组件「最近交易」类型取数用(`WidgetDataService.gatherRecent`,
  /// `.docs/home-widget/plan.md` §一.3)。需要分类名/图标/账户名时由调用方
  /// 按交易的 categoryId / accountId 自行查 CategoryRepository.getCategoryById /
  /// AccountRepository.getAccount —— 与 [getRecentTransactionsWithCategory] 的
  /// 区别:后者额外做了共享账本 override 的 synthetic 分类/账户 hydration,
  /// 语义更重,小组件场景不需要。
  Future<List<Transaction>> getRecentTransactions(
    int ledgerId, {
    int limit = 10,
  });

  /// 更新交易(通过 ID 和字段)。
  /// accountId / toAccountId 接 dynamic:dart `null` = absent(不更新);
  /// `d.Value<int?>(null)` = 显式清空;`int` = 写值。共享账本 Editor 写
  /// synthetic 账户时,accountId 写 null,通过 writeAccountSyncIdOverride
  /// + accountSyncIdOverride 写 Owner 账户的 syncId override。
  Future<void> updateTransactionFields({
    required int id,
    dynamic accountId,
    dynamic toAccountId,
    String? accountSyncIdOverride,
    String? toAccountSyncIdOverride,
    bool writeAccountSyncIdOverride,
    bool writeToAccountSyncIdOverride,
  });

  /// 對帳模式(§2.10 MOZE_FEATURE_GAP_SD.md,對齊
  /// doc.moze.app/reconciliation/statement-mode):設定/清除這筆交易的「已
  /// 確認對帳」時間戳。[reconciled]=true 寫入目前時間(對應原文右滑「完成
  /// 對帳確認」),false 清空(取消確認)。
  Future<void> setTransactionReconciled({
    required int id,
    required bool reconciled,
  });

  /// 延後入帳(對帳模式的必要前置)。[deferredPostingAt]=null 代表取消延後,
  /// 交易的入帳歸屬日恢復用 happenedAt。
  Future<void> setTransactionDeferredPosting({
    required int id,
    DateTime? deferredPostingAt,
  });

  /// 設定/清除這筆交易的欠款關聯(v39 借還款,交易表單「關聯欠款」下拉用)。
  /// [debtSyncId]=null 代表取消關聯。
  Future<void> setTransactionDebtLink({
    required int id,
    String? debtSyncId,
  });

  /// 設定/清除這筆交易的專案關聯(v44 專案,交易表單「選擇專案」用)。跟
  /// [setTransactionDebtLink] 同款分工——只在新建當下用 [addTransaction]
  /// 的 projectSyncId 參數填,既有交易改連結走這個專用方法。
  /// [projectSyncId]=null 代表取消關聯。
  Future<void> setTransactionProjectLink({
    required int id,
    String? projectSyncId,
  });

  /// 「待確認帳戶」列表裡使用者補選帳戶:寫入 [accountId] 並清除
  /// [needsAccountAssignment] 旗標。
  Future<void> setTransactionAccountAssignment({
    required int id,
    required int accountId,
  });

  /// 對帳模式選單「取消全部選取」:批次把一組交易的 reconciledAt 清空
  /// (呼叫方負責只傳目前週期內已確認的 id,確保只清除指定週期)。
  Future<void> clearReconciliationBatch({required List<int> ids});

  /// 获取账本的首笔交易（按时间排序）
  Future<Transaction?> getFirstTransactionByLedger(int ledgerId);

  /// 获取账本的末笔交易（按时间排序）
  Future<Transaction?> getLastTransactionByLedger(int ledgerId);

  /// 全局最早一笔交易的发生时间（不限账本，用于净值趋势「全部」范围的起点）。无交易返回 null。
  Future<DateTime?> getEarliestTransactionDate();

  /// 更新交易的账本
  Future<void> updateTransactionLedger({
    required int id,
    required int ledgerId,
  });

  // ==================== 日历功能相关 ====================

  /// 获取指定月份的每日交易统计
  /// 返回 Map<日期字符串, (收入, 支出)>
  /// 例: {"2025-01-15": (500.0, 1200.0), ...}
  Future<Map<String, (double income, double expense)>> getDailyTotalsByMonth({
    required int ledgerId,
    required DateTime month,
  });

  /// 获取指定日期的所有交易（含分类、标签、附件、账户）
  Future<
      List<
          ({
            Transaction t,
            Category? category,
            List<Tag> tags,
            List<TransactionAttachment> attachments,
            Account? account,
          })>> getTransactionsByDate({
    required int ledgerId,
    required DateTime date,
  });

  /// 获取指定时间范围的交易列表（用于日历当月列表）
  Future<
      List<
          ({
            Transaction t,
            Category? category,
            List<Tag> tags,
            List<TransactionAttachment> attachments,
            Account? account,
          })>> getTransactionsByDateRange({
    required int ledgerId,
    required DateTime startDate,
    required DateTime endDate,
  });

  /// 获取指定月份所有有交易的日期列表
  /// 返回 ["2025-01-15", "2025-01-16", ...]
  Future<List<String>> getTransactionDatesByMonth({
    required int ledgerId,
    required DateTime month,
  });

  /// 根据 syncId 获取交易
  Future<Transaction?> getTransactionBySyncId(String syncId);

  /// 查出所有「退款自 [originalSyncId] 这笔交易」的退款单(refundOfSyncId 指向它)。
  Future<List<Transaction>> getRefundsOf(String originalSyncId);

  /// v44:查出所有指定了某個專案(projectSyncId)的交易,依時間新到舊排序。
  /// 專案詳情頁交易列表用,同 [getRefundsOf] 的 syncId 過濾模式。[start]/[end]
  /// 都不傳時維持全時間範圍(v56 前的既有行為);有傳則加半開區間
  /// `[start, end)` 篩選,配合專案詳情頁的期間切換功能。
  Future<List<Transaction>> getTransactionsByProject(
    String projectSyncId, {
    DateTime? start,
    DateTime? end,
  });

  /// 根据 syncId 更新交易的全部字段
  Future<void> updateTransactionBySyncId({
    required String syncId,
    required String type,
    required double amount,
    int? categoryId,
    int? accountId,
    int? toAccountId,
    required DateTime happenedAt,
    String? note,
  });

  /// 根据 syncId 删除交易
  Future<void> deleteTransactionBySyncId(String syncId);

  /// 批量按 syncId 删除交易(WebDAV/Supabase 同步从远端拉账本时,如果本地有
  /// 旧账本 + 用户选择"以远端为准"覆盖,N 条 delete by syncId 单条 await 会
  /// 跑几分钟;本方法用单条 `DELETE WHERE syncId IN (...)` 一次性删除)。
  ///
  /// [recordChanges] 默认 true,wrapper 会批量补 transaction:delete change log。
  /// 返回实际删除的条数。
  Future<int> deleteTransactionsBatchBySyncIds(
    List<String> syncIds, {
    bool recordChanges = true,
  });

  /// 批量按 syncId 更新交易主表字段。同事务内逐条 UPDATE,N 次跨 isolate
  /// boundary 但 BEGIN/COMMIT 只跑一次。
  ///
  /// **不涉及 tag 更新** — caller 拿到 returned `Map<syncId, txId>` 后自己批量
  /// 调 `updateTransactionTags`(或者更高效的 batch 接口,如果将来加的话)。
  Future<Map<String, int>> updateTransactionsBatchBySyncId(
    List<TransactionUpdateBySyncIdData> updates, {
    bool recordChanges = true,
  });

  /// 创建估值调整交易
  Future<int> createAdjustmentTransaction({
    required int ledgerId,
    required int accountId,
    required double amount,
    required DateTime happenedAt,
    String? note,
  });
}
