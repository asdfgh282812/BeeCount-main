import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:drift/drift.dart';
import '../l10n/app_localizations.dart';
import '../services/data/category_service.dart';
import '../services/data/seed_service.dart';
import '../services/system/logger_service.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'db.g.dart';

// --- Tables ---

class Ledgers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get currency => text().withDefault(const Constant('CNY'))();
  TextColumn get type =>
      text().withDefault(const Constant('personal'))(); // personal / shared
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // 跨设备同步唯一标识：跟 accounts/categories/tags 的 syncId 同语义，
  // 对齐 BeeCount Cloud server 的 ledger.external_id。device B 首次登录
  // 通过 readLedgers() 拉到的 ext_id 会写到这里，后续 push/pull 都用这个
  // 做设备间的 ledger 匹配，而不是本地 autoIncrement id（A/B 本地 id 必然
  // 不一致）。v21 migration 里已为旧数据把 id 回填成 syncId 以兼容。
  TextColumn get syncId => text().nullable()();
  // v24: 共享账本字段 — server 端 LedgerMember.role 同步下来
  TextColumn get myRole =>
      text().withDefault(const Constant('owner'))(); // owner / editor
  IntColumn get memberCount => integer().withDefault(const Constant(1))();
  BoolColumn get isShared => boolean().withDefault(const Constant(false))();
  TextColumn get ownerUserId => text().nullable()(); // 当前 Owner 是谁
  // v27: 自定义每月起始日(1-28),统计/预算/小部件按 [当月N日, 次月N日) 聚合,
  // 1=自然月。随 sync 跨设备(payload key `monthStartDay`,server 列
  // ledgers.month_start_day)。见 .docs/period-start-date/design.md。
  IntColumn get monthStartDay => integer().withDefault(const Constant(1))();
}

class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ledgerId => integer()(); // 保留用于v2迁移，后续会移除
  TextColumn get name => text()();
  TextColumn get type => text().withDefault(const Constant('cash'))();
  TextColumn get currency =>
      text().withDefault(const Constant('CNY'))(); // v1.15.0新增：币种
  RealColumn get initialBalance => real().withDefault(const Constant(0.0))();
  DateTimeColumn get createdAt =>
      dateTime().nullable()(); // v1.15.0: 改为可空，避免迁移问题
  DateTimeColumn get updatedAt => dateTime().nullable()();
  IntColumn get sortOrder =>
      integer().withDefault(const Constant(0))(); // 排序顺序，数字越小越靠前
  RealColumn get creditLimit => real().nullable()(); // 信用额度
  IntColumn get billingDay => integer().nullable()(); // 账单日 (1-28)
  IntColumn get paymentDueDay => integer().nullable()(); // 还款日 (1-28)
  TextColumn get bankName => text().nullable()(); // 开户行
  TextColumn get cardLastFour => text().nullable()(); // 卡号后四位
  TextColumn get note => text().nullable()(); // 备注
  TextColumn get syncId => text().nullable()(); // 跨设备同步唯一标识 (UUID)
  /// 隐藏:true 时该账户不再出现在记账/转账/周期选择器,账户管理页移入「已隐藏」分区。
  /// 仍计入账户余额、净资产、资产构成、净值趋势(.docs/account-archive/01 §二 D1)。
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();

  /// v32 主帳戶(合併帳單):子卡/附卡指向主卡的 syncId,null = 沒有掛在任何
  /// 主卡下。跟 BeeCount Cloud server `accounts.parent_account_id` 對齊
  /// (docs/MOZE_FEATURE_GAP_SD.md §2.9 Phase 4)。
  TextColumn get parentAccountId => text().nullable()();

  /// v47 SwipeSmart 信用卡對照:對應 SwipeSmart 卡片目錄的 cardId,null =
  /// 尚未對照。跟 BeeCount Cloud server `accounts.swipesmart_card_id` 對齊
  /// (docs/superpowers/specs/2026-08-30-swipesmart-integration-design.md §3.1)。
  TextColumn get swipesmartCardId => text().nullable()();

  /// v32 帳戶頭像本地相對路徑(如 "custom_icons/<fileId>.png"),跟
  /// Categories.customIconPath 同一套目錄/存取邏輯(CustomIconService)。
  /// 上傳到雲端拿到的 fileId/sha256 不落本地欄位 —— push 時即時上傳算,
  /// 對齊分類自訂圖標的做法(見 entity_serializer.dart serializeCategory)。
  TextColumn get avatarPath => text().nullable()();

  /// v43 不納入總餘額(對齊 Moze「balance included」+ BeeCount Cloud
  /// `include_in_total`,正極性、預設 true=納入,避免同步邊界雙重否定)。
  /// 只影響淨資產/資產構成/淨值趨勢等「總額」統計與合併帳單主卡的子卡
  /// 加總 —— 帳戶本身仍正常出現在清單/選擇器,可正常記帳(跟 hidden 是
  /// 兩個獨立維度,見 lib/data/db.dart 的 hidden 註解與
  /// Debts.excludedFromTotal 的先例)。
  BoolColumn get includeInTotal =>
      boolean().withDefault(const Constant(true))();
}

/// 自动汇率本地缓存。日期键 append-only;可随时整表重建 → **不进同步**(README D2)。
/// 方向:1 quote = rate base(rate 为 decimal 字符串)。
class ExchangeRates extends Table {
  TextColumn get baseCurrency => text()();
  TextColumn get quoteCurrency => text()();
  TextColumn get rateDate => text()(); // 'YYYY-MM-DD',取源数据自带日期
  TextColumn get rate => text()();
  TextColumn get source => text()(); // 'server'|'fawazahmed0'|'frankfurter'
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {baseCurrency, quoteCurrency, rateDate};
}

/// 手动汇率覆盖:固定生效直到删除(README D9)。user-global 同步实体,
/// 字段约定对齐 Accounts(syncId UUID)。方向同 ExchangeRates:1 quote = rate base。
/// 业务唯一键 (baseCurrency, quoteCurrency),唯一索引在 v28 迁移建。
class ExchangeRateOverrides extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get syncId => text().nullable()();
  TextColumn get baseCurrency => text()();
  TextColumn get quoteCurrency => text()();
  TextColumn get rate => text()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get kind => text()(); // expense / income
  TextColumn get icon => text().nullable()();
  IntColumn get sortOrder =>
      integer().withDefault(const Constant(0))(); // 排序顺序，数字越小越靠前
  IntColumn get parentId => integer().nullable()(); // 父分类ID，null 表示一级分类
  IntColumn get level =>
      integer().withDefault(const Constant(1))(); // 层级：1=一级，2=二级
  // v13: 自定义图标支持
  TextColumn get iconType => text().withDefault(
      const Constant('material'))(); // material / custom / community
  TextColumn get customIconPath => text().nullable()(); // 自定义图标本地路径
  TextColumn get communityIconId => text().nullable()(); // 社区图标ID（预留）
  TextColumn get syncId => text().nullable()(); // 跨设备同步唯一标识 (UUID)
}

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ledgerId => integer()();
  TextColumn get type => text()(); // expense / income / transfer
  RealColumn get amount => real()();
  IntColumn get categoryId => integer().nullable()();
  IntColumn get accountId => integer().nullable()();
  IntColumn get toAccountId => integer().nullable()();
  DateTimeColumn get happenedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get note => text().nullable()();
  TextColumn get syncId => text().nullable()(); // 跨设备同步唯一标识 (UUID)
  // v24: 共享账本"谁记的"显示
  TextColumn get createdByUserId => text().nullable()();
  TextColumn get lastEditedByUserId => text().nullable()();
  // v25: 共享账本 sync_id override(§7 决策)
  // Editor 在共享账本下记 tx 时,选 Owner 的 SharedLedger{Categories,Accounts,Tags}
  // 行,但本地 Categories/Accounts/Tags 主表没有对应 int id。这些 override
  // 字段直接存 Owner 的 syncId 字符串,categoryId / accountId 留 null;sync push
  // 时序列化优先用 override(server LWW key 是 syncId,主表 syncId 也是 string)。
  // Owner / 单人账本场景:override 字段为 null,走老路径(categoryId int 反查
  // Categories.syncId)。
  TextColumn get categorySyncIdOverride => text().nullable()();
  TextColumn get accountSyncIdOverride => text().nullable()();
  TextColumn get toAccountSyncIdOverride => text().nullable()();
  TextColumn get tagSyncIdsOverride => text().nullable()(); // JSON list

  /// 不计入收支:true 时从收支统计/图表/月年汇总剔除,但仍计入账户余额、净资产、
  /// 账单列表(.docs/transaction-flags/01 §二 D1)。
  BoolColumn get excludeFromStats =>
      boolean().withDefault(const Constant(false))();

  /// 不计入预算:true 时从预算用量剔除。与 excludeFromStats 完全独立(D2)。
  BoolColumn get excludeFromBudget =>
      boolean().withDefault(const Constant(false))();

  /// v30 交易级多币种(.docs/multi-currency-ledger):交易币种(ISO 大写)。
  /// 有账户 → 恒等于账户 currency(账户内不混币);无账户 → 用户所选(L12,
  /// 默认账本本位币)。显式存让交易自包含(同步/统计不必每次 join 账户)。
  TextColumn get currencyCode => text().nullable()();

  /// v30:折算到账本本位币的金额快照(按记账时汇率,保存即定,不随汇率重算)。
  /// 单币种/未折算 == amount(隐含汇率 1.0)。账本维度统计读本列(?? amount),
  /// 账户维度(余额等)仍读 amount。
  RealColumn get nativeAmount => real().nullable()();

  /// v33:商家名称。与 note 独立的自由文本字段,BeeCount Cloud 的
  /// read_tx_projection.merchant / _LEDGER_MERGE_SPECS["transaction"] 已支持
  /// 同名 wire 字段 merchant,这里补齐本地列即可直接接上同步。
  TextColumn get merchant => text().nullable()();

  /// v34:退款关联——存原交易的 syncId(而非本地 int id,因为本地 id 跨设备不
  /// 稳定)。BeeCount Cloud 服务端已有对应的 refund_of_sync_id 列/业务规则
  /// (一笔交易只能被退一次、退款单不能再被退款),wire 字段名 refundOfId,
  /// 见 sync_applier.py 的 merge spec。
  TextColumn get refundOfSyncId => text().nullable()();

  /// v35:信用卡紅利回饋——使用者記帳當下手動勾選的回饋規則 syncId 列表
  /// (JSON list,同 [tagSyncIdsOverride] 那种"JSON list 存 string"写法)。
  /// BeeCount Cloud 端字段是 read_tx_projection.reward_rule_sync_ids_json,
  /// wire 字段名 rewardRuleIds(见 sync_applier.py merge spec)。2026-08-06
  /// 改版后规则不再靠 category_ids 自动比对,这里是权威的"哪笔消费适用哪个
  /// 回馈方案"来源。
  TextColumn get rewardRuleIdsJson => text().nullable()();

  /// v36 週期性收支(recurring_rule):这笔交易是哪条規則生成的 occurrence,
  /// 存規則的 **syncId**(不是本地 int id——本地 id 跨装置不稳定,同
  /// [refundOfSyncId] 的模式)。null = 单次交易(非週期生成)。BeeCount Cloud
  /// 端字段是 read_tx_projection.recurring_rule_sync_id,wire 字段名
  /// recurringRuleId,见 sync_applier.py 的 transaction merge spec。
  TextColumn get recurringRuleId => text().nullable()();

  /// v36:这期是否被「修改此記錄」单独编辑过——true 时,規則之后的「修改/
  /// 刪除連同未來週期」批次操作要跳过这一笔,不能被批次覆盖。BeeCount Cloud
  /// 端字段是 read_tx_projection.recurring_occurrence_overridden,wire 字段
  /// 名 recurringOccurrenceOverridden。
  BoolColumn get recurringOccurrenceOverridden =>
      boolean().withDefault(const Constant(false))();

  /// v37 對帳模式(§2.10 MOZE_FEATURE_GAP_SD.md,對齊
  /// doc.moze.app/reconciliation/statement-mode):使用者在對帳模式裡勾選
  /// 確認過「這筆交易確實在這期信用卡帳單上」的時間戳。null = 尚未核對。
  /// BeeCount Cloud 端字段是 read_tx_projection.reconciled_at,wire 字段名
  /// reconciledAt(恆發,不是「有值才發」——因為有明確的清空/取消確認動作,
  /// 見 entity_serializer.dart serializeTransaction 的註解)。
  DateTimeColumn get reconciledAt => dateTime().nullable()();

  /// v37 延後入帳(對帳模式的必要前置,§2.10):有值 = 這筆交易處於「延後入帳」
  /// 狀態,值是使用者填的實際入帳日;null = 正常,沿用 happenedAt。對帳/信用卡
  /// 帳單彙總等需要「入帳歸屬日」的地方一律用
  /// `lib/utils/reconciliation.dart` 的 `effectiveDate()`(等同 Cloud
  /// `deferred_posting_at ?? happened_at` 的 COALESCE 語意),不要各自重寫。
  /// BeeCount Cloud 端字段是 read_tx_projection.deferred_posting_at,wire
  /// 字段名 deferredPostingAt(同樣恆發)。
  DateTimeColumn get deferredPostingAt => dateTime().nullable()();

  /// v38 拆帳(對齊 doc.moze.app/record/split-categories 與 BeeCount Cloud
  /// §2.4 拆分類別):true 時這筆交易的金額拆成多筆分類明細記在
  /// [TransactionSplits],此欄位的 categoryId/categorySyncIdOverride 強制為
  /// null(明細本身才有分類)。BeeCount Cloud 端字段是
  /// read_tx_projection.has_splits,wire 字段名 hasSplits。
  BoolColumn get hasSplits => boolean().withDefault(const Constant(false))();

  /// v39 借還款(對齐 doc.moze.app/record/payables-receivables 與 BeeCount
  /// Cloud debt entity):這筆交易是某個 [Debts] 的一筆還款/收款時,存該欠款
  /// 的 syncId。刻意跟 recurringRuleId 同款存 syncId 字串(不是本地 int
  /// FK)——欠款是 ledger-scoped 實體,本地 int id 跨裝置不保證一致,存
  /// syncId 才能在 pull 尚未把對端新建的欠款同步下來時仍正確引用(對比
  /// categoryId/accountId 那組 user-global 實體需要額外的
  /// *SyncIdOverride 欄位處理共享帳本場景,這裡不需要)。BeeCount Cloud 端
  /// 字段是 read_tx_projection.debt_sync_id,wire 字段名 debtId。恆發
  /// (同 reconciledAt)——清空欠款關聯是明確動作,null 必須能傳達給 server。
  TextColumn get debtSyncId => text().nullable()();

  /// v49 分期付款(對齐 doc.moze.app/record/installment 與 BeeCount Cloud
  /// installment_plan sync entity):這筆交易是某個 [InstallmentPlans] 建立時
  /// 生成的一期時,存該計畫的 syncId。跟 [debtSyncId]/[recurringRuleId] 同款
  /// 存 syncId 字串(不是本地 int FK)——分期計畫是 ledger-scoped 實體,本地
  /// int id 跨裝置不保證一致。BeeCount Cloud 端字段是
  /// read_tx_projection.installment_plan_sync_id,wire 字段名
  /// installmentPlanId。恆發(同 debtSyncId)——目前沒有清空這個關聯的操作,
  /// 但恆發跟既有慣例一致,避免以後加了清空操作又要回頭補。
  TextColumn get installmentPlanSyncId => text().nullable()();

  /// v45 跨幣別轉帳(對齐 BeeCount Cloud `to_amount`,alembic
  /// 0044_tx_transfer_to_amount):`type == 'transfer'` 且轉出/轉入帳戶幣別
  /// 不同時,存轉入帳戶自己幣別的金額;同幣別轉帳/非轉帳一律維持 null(不要
  /// 為同幣別轉帳也塞 `toAmount = amount`——`toAmount ?? amount` 這個
  /// COALESCE 慣例才能同時當「轉入金額」跟「是否跨幣別」的單一事實來源)。
  /// BeeCount Cloud 端字段是 read_tx_projection.to_amount,wire 字段名
  /// toAmount(camelCase,對齊 sync_applier.py 的 merge spec)。
  RealColumn get toAmount => real().nullable()();

  /// v44 專案(對齐 BeeCount Cloud project sync entity,取代分類預算):這筆
  /// 交易關聯的 [Projects] 的 syncId。跟 [debtSyncId]/[recurringRuleId]
  /// 同款存 syncId 字串(不是本地 int FK)——專案是 ledger-scoped 實體,
  /// 本地 int id 跨裝置不保證一致。BeeCount Cloud 端字段是
  /// read_tx_projection.project_sync_id,wire 字段名 projectId。恆發(同
  /// debtSyncId)——記帳表單「選擇專案」的取消連結是明確動作,必須讓 null
  /// 能傳達給 server。
  TextColumn get projectSyncId => text().nullable()();

  /// v40:這筆交易找不到帳戶、且當下沒有 UI 可以攔截使用者選(背景截圖/
  /// 通知監聽、週期性交易產生、CSV 匯入)時,交易仍照常建立(accountId 保持
  /// null,帳戶餘額計算完全不受影響),但打這個旗標讓使用者能在「待確認
  /// 帳戶」列表裡事後補選。有 UI 可攔截的路徑(記帳表單/AI 對話/照片/語音)
  /// 不會用到這個旗標——那些路徑要求使用者當場選,選不了就直接不建立這筆
  /// 交易。
  BoolColumn get needsAccountAssignment =>
      boolean().withDefault(const Constant(false))();

  /// v46 轉帳手續費/折損(對齐 BeeCount Cloud `read_tx_projection.fee_amount`
  /// / `fee_label` / `discount_amount` / `discount_label`,`0039_tx_fee_
  /// discount.py`——Cloud 該組欄位本來就存在,只是原本只放行
  /// expense/income,本次解除 transfer 的硬性拒絕,App/Cloud 直接共用同一組
  /// wire key,不需要新 migration):`type == 'transfer'` 時,`feeAmount` 是
  /// 轉出側額外扣款(轉出帳戶幣別),`discountAmount` 是轉入側到帳前折損
  /// (轉入帳戶幣別)。皆為 null = 沒有手續費/折損,餘額計算退化回原本行為
  /// (見 [LocalAccountRepository] 的 `_transferOutEffect`/
  /// `_transferInEffect`)。**周期性轉帳(`RecurringTransactions`)不支援**,
  /// 範圍比照現有 Web 版 recurring rule 不支援 fee/discount。
  RealColumn get feeAmount => real().nullable()();
  TextColumn get feeLabel => text().nullable()();
  RealColumn get discountAmount => real().nullable()();
  TextColumn get discountLabel => text().nullable()();

  /// v51 支出/收入手續費/折扣(對齐 BeeCount Cloud `read_tx_projection.
  /// base_amount`,`0039_tx_fee_discount.py`——這是該遷移原本就支援
  /// expense/income 的部分,App 這次才補上):`type` 是 `expense`/`income`
  /// 時,`baseAmount` 是使用者輸入的原始金額(信用卡回饋計算的權威基準),
  /// `amount` 則是套用 [feeAmount]/[discountAmount] 後、實際入帳驅動餘額
  /// /統計的淨額——`amount = baseAmount + feeAmount - discountAmount`
  /// (expense)或 `baseAmount - feeAmount + discountAmount`(income),寫入
  /// 路徑統一重算(見 `LocalTransactionRepository`)。`baseAmount` 為 null
  /// 代表沒有使用手續費/折扣,`amount` 就是使用者輸入的原始金額,行為退化回
  /// 既有邏輯。**周期性交易(`RecurringTransactions`)/拆帳不支援**,範圍比照
  /// 既有 transfer 手續費/折損的排除項。
  RealColumn get baseAmount => real().nullable()();
}

/// v39 借還款(§2.5 MOZE_FEATURE_GAP_SD.md,對齊 BeeCount Cloud `debt`
/// sync entity):ledger-scoped 實體,同 [Budgets]/[Ledgers] 那組模式。
///
/// **狀態不落地存**:remainingAmount/status 一律在讀取時即時算(掃
/// [Transactions.debtSyncId] 命中的還款交易加總),對齐 Cloud
/// `read_debt_projection` 的設計——理由同 installment_plan.paid_periods,
/// 避免多寫入路徑(mobile push / 之後可能的 web 直連)各自維護衍生欄位。
///
/// **principalAmount / direction 建立後不可修改**——語意上等同刪除重建,
/// 對齐 Cloud `WriteDebtUpdateRequest` 刻意不帶這兩個欄位。
///
/// 沒有幣別欄位:跟 Cloud 一致,欠款本金一律以帳本記帳幣別計,不支援欠款
/// 本身跨幣別(還款交易仍可用既有的 currencyCode/nativeAmount 多幣別機制)。
///
/// 字段/wire key 對照 BeeCount Cloud `sync_applier.py::_LEDGER_MERGE_SPECS
/// ["debt"]`——改字段前先去那邊核對,一字之差會讓整個字段靜默同步失敗。
class Debts extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 跨设备同步 syncId(UUID)。新建必须填(同 budget 的约定)。
  TextColumn get syncId => text().nullable()();

  /// 关联账本ID
  IntColumn get ledgerId => integer()();

  /// 'payable'(我欠款) / 'receivable'(別人欠我)。見
  /// [kDebtDirectionPayable]/[kDebtDirectionReceivable]。
  TextColumn get direction => text()();

  /// 對象名稱(人名/機構名),對齐 Cloud counterpartyName。
  TextColumn get counterpartyName => text()();

  /// 本金,建立後不可改。
  RealColumn get principalAmount => real()();

  /// 到期日,只取日期語意(同 deferredPostingAt 的處理慣例:一律用 UTC
  /// 年月日當日期的權威表示,不做時區位移)。null = 沒有到期日。
  DateTimeColumn get dueAt => dateTime().nullable()();

  TextColumn get note => text().nullable()();

  /// 非 null = 手動結案(見 [kDebtStatusClosed])。優先於金額判斷的狀態——
  /// 手動結案可以在未還清時發生(呆帳/不再追蹤)。
  DateTimeColumn get closedAt => dateTime().nullable()();

  /// v41:分類(原始設計刻意留空,使用者反饋後補上)。跟 [Transactions.categoryId]
  /// 一樣不宣告 FK,零存在性驗證。
  IntColumn get categoryId => integer().nullable()();

  /// v41:起點交易反查——建立欠款時 App 會同時寫一筆帳戶餘額起點交易,但那筆
  /// 交易刻意不帶 [Transactions.debtSyncId](避免被還款金額加總誤計入,見上方
  /// docstring),所以要存這個欄位才能反查回那筆交易。存 syncId 字串直連,
  /// 不解析成本地 id(那筆交易未必已經同步下來)。建立後不可改。
  TextColumn get originTransactionSyncId => text().nullable()();

  /// v42:排除計入總額(對齐 Moze「排除在帳戶總覽計算」)。只影響
  /// [DebtRepository.getNetDebtBalance]/[getDebtBalancesByLedgerForAllLedgers]
  /// 這兩個「總額」方法,不影響清單(getDebtsWithStatus/getAllDebts)或
  /// §5.5 通知中心的未結清清單——那兩者刻意不套用這個過濾。
  BoolColumn get excludedFromTotal =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// v49 分期付款(§2.12.1 MOZE_FEATURE_GAP_SD.md,對齐 BeeCount Cloud
/// `installment_plan` sync entity):ledger-scoped 實體,同 [Debts]/[Budgets]
/// 那組模式。
///
/// **不落地存的衍生欄位**:`paidPeriods`/`nextPeriodAt`/`periodAmount`——對齐
/// Cloud `list_installment_plans` 的即時算邏輯(見
/// `InstallmentRepository.getInstallmentPlansWithStatus`),讀取時從
/// [InstallmentPeriods] 掃出來,不寫欄位,理由同 [Debts] 沒有
/// remainingAmount/status 欄位:避免多寫入路徑各自維護衍生欄位漂移。
///
/// **`totalAmount`/`periods`/`firstPeriodAt` 建立後不可改**——分期排程
/// (期數/金額拆分)在建立當下就已經算好寫入 [InstallmentPeriods] 跟對應的
/// [Transactions],之後只有子專案 2 的「連同未來重算」操作能改動未到期期的
/// 金額,不會回頭改這三個計畫級欄位本身。
///
/// 沒有幣別欄位:跟 Cloud 一致,分期本金一律以帳本記帳幣別計,不支援分期
/// 本身跨幣別(對齐借還款的決策)。
///
/// 字段/wire key 對照 BeeCount Cloud `sync_applier.py::_LEDGER_MERGE_SPECS
/// ["installment_plan"]`——改字段前先去那邊核對,一字之差會讓整個字段靜默
/// 同步失敗。
class InstallmentPlans extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 跨设备同步 syncId(UUID)。新建必须填(同 budget/debt 的约定)。
  TextColumn get syncId => text().nullable()();

  /// 关联账本ID
  IntColumn get ledgerId => integer()();

  /// 分期總額,建立後不可改。
  RealColumn get totalAmount => real()();

  /// 總期數,1~600,建立後不可改。
  IntColumn get periods => integer()();

  /// 第一期到期日,建立後不可改。
  DateTimeColumn get firstPeriodAt => dateTime()();

  /// 掛靠帳戶(信用卡/現金皆可),可留空。不可為 account_group 的子卡
  /// (見 [InstallmentRepository.createInstallmentPlan] 的業務規則校驗)。
  IntColumn get accountId => integer().nullable()();

  /// 分類(必填,expense)——對齐 Cloud
  /// `_assert_category_required("expense", ...)`,分期屬於「使用者該手動
  /// 指定分類、系統不該代猜」的情境。
  IntColumn get categoryId => integer()();

  TextColumn get note => text().nullable()();

  /// 'active' / 'settled'(結清) / 'terminated'(終止未來,無結清交易)。
  TextColumn get status => text().withDefault(const Constant('active'))();

  /// 還款方式:'equal_installment'(等額本息) / 'equal_principal'(等額本金)
  /// / 'fixed_interest'(固定利息)。
  TextColumn get repaymentMethod =>
      text().withDefault(const Constant('equal_principal'))();

  /// 計息週期:'monthly'(月息) / 'daily'(日息)。跟還款週期(固定按月)是
  /// 獨立維度,只影響利息怎麼算,見
  /// `lib/services/installment/installment_amortization.dart` 的說明。
  TextColumn get interestPeriod =>
      text().withDefault(const Constant('monthly'))();

  /// 年利率,小數(如 0.06 = 6%)。
  RealColumn get interestRate => real().withDefault(const Constant(0.0))();

  /// 是否取整到整數元。
  BoolColumn get roundAmounts => boolean().withDefault(const Constant(true))();

  /// 取整尾差歸屬:'first'(第一個攤還期) / 'last'(最後一期)。
  TextColumn get remainderPosition =>
      text().withDefault(const Constant('last'))();

  /// 寬限期月數,`0 <= gracePeriodMonths < periods`。
  IntColumn get gracePeriodMonths => integer().withDefault(const Constant(0))();

  /// v50 帳單分期沖銷(子專案 4,對齐 Cloud
  /// `installment_plan.offset_breakdown_json`):建立分期計畫時若
  /// `offsetExistingBalance=true`,把「這筆分期對應到哪個帳戶的多少既有
  /// 欠款被沖銷」記在這裡,格式 `{accountSyncId: amount}`(JSON,鍵是帳戶
  /// [Accounts.syncId] 字串,不是本地 int id——這樣才能在跨裝置同步後仍
  /// 正確比對到同一張帳戶,同 Cloud 用 `child_account_sync_id` 當鍵的理由)。
  /// 純虛擬記帳調整,**不**對應任何一筆 [Transactions] 記錄(沖銷部分不產生
  /// 交易——見 `InstallmentRepository.createInstallmentPlan` 的
  /// `offsetExistingBalance` 參數說明)。目前 App 端只在單一非
  /// account_group 帳戶上支援沖銷,所以這個 map 恆為單一鍵值對,但沿用
  /// Cloud 的 map 形狀(而不是攤平成 accountSyncId/amount 兩個欄位)是為了
  /// 未來若要支援合併帳單群組的沖銷分攤時不必再改資料結構。
  ///
  /// 讀取信用卡帳單「應繳」金額時要扣掉這裡的加總,避免已轉分期的帳單
  /// 金額被重複計入——見 `credit_card_billing_providers.dart` 的
  /// `_dueAsOf`。刪除整筆分期計畫時這一欄跟著整列一起刪,沖銷自動失效,
  /// 不需要額外清理邏輯。
  TextColumn get offsetBreakdownJson => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// v49 分期付款期數明細(對齐 BeeCount Cloud `installment_period` sync
/// entity):每期一列,ledger-scoped。
///
/// `overridden` 狀態的期數不參與任何後續自動重算(子專案 2),也不能被重算
/// 隱性挪用其本金份額——見設計文件 §0 的核心不變量。
///
/// 字段/wire key 對照 BeeCount Cloud `sync_applier.py::_LEDGER_MERGE_SPECS
/// ["installment_period"]`——改字段前先去那邊核對。
class InstallmentPeriods extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get syncId => text().nullable()();

  IntColumn get ledgerId => integer()();

  /// 反查所屬計畫,存 [InstallmentPlans.syncId] 字串——同 debt 的模式
  /// (對端還沒 pull 到 plan 時仍能正確引用,不用本地 int FK)。
  TextColumn get planSyncId => text()();

  /// 從 1 開始。
  IntColumn get periodNo => integer()();

  DateTimeColumn get dueAt => dateTime()();

  RealColumn get principalAmount => real()();
  RealColumn get interestAmount => real()();

  /// principal + interest。
  RealColumn get totalAmount => real()();

  /// 'generated'(正常) / 'overridden'(手動改過) / 'refunded'(已退款)。
  TextColumn get status => text().withDefault(const Constant('generated'))();

  /// 反查生成的交易——**本地 int**(同一裝置內本地資料,不必比照
  /// planSyncId 走字串反查)。
  IntColumn get txId => integer().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// v38 拆帳明細:一筆 [Transactions] 拆成多筆分類分攤,每次存檔整組刪除重建
/// (同 [TransactionTags]/[TransactionAttachments] 的做法),不是獨立的 sync
/// entity——明細隨父交易的 `splits` payload 陣列一起推/拉(見
/// entity_serializer.dart serializeTransaction、sync_engine_apply.dart
/// _applyTransactionChange)。BeeCount Cloud 端對應
/// read_tx_split_projection,wire 字段名 categoryId/categoryName/amount/note。
class TransactionSplits extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get transactionId => integer()(); // 关联的交易ID
  IntColumn get categoryId => integer().nullable()();
  // 共享账本 §7 场景:分类是 Owner 的虚拟分类,本地无 int id 时存 syncId,
  // 同 Transactions.categorySyncIdOverride 的做法。
  TextColumn get categorySyncIdOverride => text().nullable()();
  RealColumn get amount => real()();
  TextColumn get note => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

/// v35:信用卡紅利回饋規則。user-global 实体(同 Accounts/Categories/Tags 那组
/// 白名单),不挂 ledgerId。字段/wire key 对照 BeeCount Cloud
/// `sync_applier.py` 的 `_MergeSpec["card_reward_rule"]`——改字段前先去那边
/// 核对,一字之差会让整个字段静默同步失败。
///
/// `locked`(规则已有交易/入帐纪录挂着时,计算类字段不可再编辑)不是本表的列:
/// server 端这个语义只在 web 专用 REST read endpoint 计算返回,不在这张表
/// 对应的 generic sync 投影里。App 端在 UI 层用本地代理判断(本地是否有交易
/// 的 rewardRuleIdsJson 命中这条规则),见
/// lib/pages/account/card_reward_rule_editor_page.dart。
class CardRewardRules extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 绑定的信用卡帐户(本地 int id)。server 端建立后不可改(wire 字段
  /// accountId 只在 create payload 送,update 不送这个 key)。
  IntColumn get accountId => integer()();

  TextColumn get syncId => text().nullable()();
  TextColumn get label => text()();

  /// 保留字段,JSON list of category syncId。2026-08-06 起不参与回馈资格
  /// 自动比对(改成使用者记账时手动勾选 rewardRuleIds),这里纯粹用于编辑页
  /// 显示/筛选。
  TextColumn get categoryIdsJson => text().nullable()();

  TextColumn get rateType => text()
      .withDefault(const Constant('percentage'))(); // percentage / fixed_amount
  RealColumn get rateValue => real()();
  TextColumn get rounding =>
      text().withDefault(const Constant('round'))(); // floor/round/ceil/keep
  TextColumn get totalRounding => text().withDefault(const Constant('round'))();
  TextColumn get calcBasis => text().withDefault(
      const Constant('transaction_date'))(); // transaction_date/settlement_date
  TextColumn get interval => text().withDefault(
      const Constant('billing_cycle'))(); // billing_cycle/calendar_month

  RealColumn get minSpendThreshold => real().nullable()();
  RealColumn get minTxAmount => real().nullable()();
  RealColumn get capAmount => real().nullable()();
  TextColumn get capSharedKey => text().nullable()();

  DateTimeColumn get startsAt => dateTime().nullable()();
  DateTimeColumn get endsAt => dateTime().nullable()();

  TextColumn get settlementType => text().withDefault(const Constant(
      'manual'))(); // immediate_after_tx/after_posting_date/period_end/manual
  IntColumn get settlementDays => integer().nullable()();
  IntColumn get settlementMonthOffset => integer().nullable()();
  IntColumn get settlementDayOfMonth => integer().nullable()();

  /// 回饋入帳帐户(本地 int id,nullable——manual 结算类型允许不设)。
  IntColumn get rewardAccountId => integer().nullable()();

  TextColumn get note => text().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

/// [Transaction.rewardRuleIdsJson] 的解码辅助——JSON list of card_reward_rule
/// syncId。放这里而不是各调用点各自 jsonDecode,避免格式错误处理散落各处。
extension TransactionRewardRuleIds on Transaction {
  List<String> get rewardRuleIds {
    final raw = rewardRuleIdsJson;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (_) {
      // 忽略格式错误的旧数据,当作没有勾选。
    }
    return const [];
  }
}

/// [CardRewardRule.categoryIdsJson] 的解码辅助,同 [TransactionRewardRuleIds]。
extension CardRewardRuleCategoryIds on CardRewardRule {
  List<String> get categoryIds {
    final raw = categoryIdsJson;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (_) {
      // 忽略格式错误的旧数据。
    }
    return const [];
  }
}

/// v36 週期性收支規則。redesign 前(v3-v35)是純本地功能,不接
/// [ChangeTracker],Web/其它裝置看不到。v36 起对齐 BeeCount Cloud 的
/// `recurring_rule` sync entity(ledger-scoped,同 [Transactions]/[Budgets]
/// 那组),字段/wire key 对照 `BeeCount-Cloud/src/sync_applier.py` 的
/// `_LEDGER_MERGE_SPECS["recurring_rule"]`——改字段前先去那边核对。
///
/// **没有独立的"单期(occurrence)"表**:規則只定义"要怎么循环",每一期实际
/// 发生的交易就是 [Transactions] 里的普通列,靠
/// [Transaction.recurringRuleId] 反查回本表的 [syncId]、靠
/// [Transaction.recurringOccurrenceOverridden] 标记这期是否被单独编辑过。
/// v1 范围**不做** `project` 关联与手续费/折扣(feeAmount/feeLabel/
/// discountAmount/discountLabel)——同 BeeCount Cloud 已有的字段集但刻意
/// 缩小范围,見 docs/changes/2026-08-17-recurring-transactions-cloud-sync.md。
class RecurringTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 跨设备同步 syncId(UUID)。本地建规则时就地产生(同 transaction/account
  /// 的产生时机),不等 server 回传。
  TextColumn get syncId => text().nullable()();

  IntColumn get ledgerId => integer()();
  TextColumn get type => text()(); // expense / income / transfer
  RealColumn get amount => real()();
  IntColumn get categoryId => integer().nullable()(); // 转账时为null
  IntColumn get accountId => integer().nullable()(); // expense/income 的账户

  /// 轉帳來源帳戶。跟 Cloud `recurring_rule` 一样把 accountId(收支用)跟
  /// fromAccountId(转帐来源)分开存,不像 [Transactions] 表本身转账时借用
  /// accountId 当来源——這張規則表序列化/反序列化时要各自对应正确的 key。
  IntColumn get fromAccountId => integer().nullable()();
  IntColumn get toAccountId => integer().nullable()(); // 转账的目标账户
  TextColumn get note => text().nullable()();

  /// 商家名称,同 [Transaction.merchant] 语意,规则生成的每期 occurrence 都
  /// 继承这个值。wire 字段 merchant。
  TextColumn get merchant => text().nullable()();

  /// JSON list of tag syncId,规则生成的每期 occurrence 都带上这些标签。
  /// wire 字段 tagIds,同 [TransactionRewardRuleIds] 那种"JSON list 存
  /// string"写法,配 [RecurringTransactionTagIds] extension 用。
  TextColumn get tagSyncIdsJson => text().nullable()();

  /// JSON list of card_reward_rule syncId,同 [Transaction.rewardRuleIdsJson]
  /// 语意,规则生成的每期 occurrence 都带上。wire 字段 rewardRuleIds。
  TextColumn get rewardRuleIdsJson => text().nullable()();

  // 重复规则
  TextColumn get frequency => text()(); // daily / weekly / monthly / yearly
  IntColumn get interval =>
      integer().withDefault(const Constant(1))(); // 间隔（每1天、每2周等）

  /// 進階規則(JSON),只支援兩種、不過度泛化,对齐 Cloud
  /// `services/recurring_schedule.py` 的 `advanced_rule`:
  /// - `{"type":"weekly_days","days":[0,6]}`:每週指定星期几(Dart
  ///   `DateTime.weekday` 惯例转换过的 Monday=0..Sunday=6,注意**跟 Dart
  ///   原生 `weekday`(Monday=1..Sunday=7)不同**,存取都要过一层转换,不要
  ///   直接拿 `DateTime.weekday` 存进来)。
  /// - `{"type":"monthly_day","day":10}`:每隔 interval 个月的第 N 天,超过
  ///   当月天数会夹断到月底。
  /// null = 不用進階規則,单纯"每 interval 个 frequency"重复(如"每2周")。
  /// wire 字段 advancedRuleJson。
  TextColumn get advancedRuleJson => text().nullable()();

  /// 規則定義的循环起点(建规则当下就固定,之后不会被续产生逻辑推进——同
  /// Cloud `recurring_rule.next_run_at` 语意)。取代旧版 `startDate`。
  DateTimeColumn get nextRunAt => dateTime()();

  /// 為空表示無限期。取代旧版 `endDate`(改名对齐 wire 字段 endAt)。
  DateTimeColumn get endAt => dateTime().nullable()();

  /// 已經生成到哪个时间点(視窗批次预生成的进度指标)。取代旧版
  /// "最后一次生成交易的日期"(`lastGeneratedDate`)语意上从"上次生成
  /// 日"变成"已生成到哪"——续产生逻辑靠这个欄位判断要不要补窗口。wire 字段
  /// generatedUntilAt。
  DateTimeColumn get generatedUntilAt => dateTime().nullable()();

  // 状态。fully_generated(有 endAt 且已经生成到底)或使用者手动「刪除連同
  // 未來週期」时会被设成 false,規則列表页「進行中/已結束」两个分组純用这
  // 个欄位现算,不额外存状态。
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// [RecurringTransaction.tagSyncIdsJson] 的解码辅助,同
/// [TransactionRewardRuleIds] 那套写法。
extension RecurringTransactionTagIds on RecurringTransaction {
  List<String> get tagSyncIds {
    final raw = tagSyncIdsJson;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (_) {
      // 忽略格式错误的旧数据,当作没有勾选。
    }
    return const [];
  }
}

/// [RecurringTransaction.rewardRuleIdsJson] 的解码辅助,同
/// [TransactionRewardRuleIds] 那套写法。
extension RecurringTransactionRewardRuleIds on RecurringTransaction {
  List<String> get rewardRuleIds {
    final raw = rewardRuleIdsJson;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (_) {
      // 忽略格式错误的旧数据,当作没有勾选。
    }
    return const [];
  }
}

// AI 对话表
class Conversations extends Table {
  IntColumn get id => integer().autoIncrement()();
  @Deprecated('对话已改为全局，不再与账本关联')
  IntColumn get ledgerId => integer().nullable()();
  TextColumn get title => text().withDefault(const Constant('AI对话'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

// AI 消息表
class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get conversationId => integer()();
  TextColumn get role => text()(); // 'user' | 'assistant'
  TextColumn get content => text()();
  TextColumn get messageType => text()(); // 'text' | 'bill_card'
  TextColumn get metadata => text().nullable()(); // JSON (BillInfo 数据)
  IntColumn get transactionId => integer().nullable()(); // 关联的交易ID(撤销用)
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// 标签表
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()(); // 标签名称
  TextColumn get color => text().nullable()(); // 颜色值（如 #FF5722）
  IntColumn get sortOrder => integer().withDefault(const Constant(0))(); // 排序
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get syncId => text().nullable()(); // 跨设备同步唯一标识 (UUID)
}

// 本地变更追踪表（用于增量同步）
class LocalChanges extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()(); // transaction/account/category/tag
  IntColumn get entityId => integer()(); // 本地实体ID
  TextColumn get entitySyncId => text()(); // 实体的 syncId (UUID)
  IntColumn get ledgerId => integer()(); // 关联账本ID
  TextColumn get action => text()(); // create/update/delete
  TextColumn get payloadJson => text().nullable()(); // 变更后的完整 JSON
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get pushedAt => dateTime().nullable()(); // 非null表示已推送
}

// 同步状态表
class SyncState extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get deviceId => text()(); // 设备唯一标识
  TextColumn get providerType => text().withDefault(
      const Constant('beecount_cloud'))(); // 防止不同 provider 的 cursor 冲突
  IntColumn get serverCursor =>
      integer().withDefault(const Constant(0))(); // 服务端变更游标
  DateTimeColumn get lastPushAt => dateTime().nullable()();
  DateTimeColumn get lastPullAt => dateTime().nullable()();
}

// 交易-标签关联表
class TransactionTags extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get transactionId => integer()(); // 交易ID
  IntColumn get tagId => integer()(); // 标签ID
}

// v27: 共享账本 §7 — 交易标签 sync_id override
// Editor 在共享账本下记 tx 选 Owner 的 tag,Tag 主表没该行(SharedLedgerTags
// 才有),传统 transaction_tags.tag_id 没法存 (本地 int id 不存在)。这张
// override 表按 (transaction_id, tag_sync_id) 存,sync push 时 union 进 tagIds
// payload;tx 反查 / 编辑回显时 union 主表 transaction_tags + 本表。
class TransactionTagOverrides extends Table {
  TextColumn get transactionSyncId => text()(); // tx.syncId(全局唯一)
  TextColumn get tagSyncId => text()(); // Owner tag syncId
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {transactionSyncId, tagSyncId};
}

// v26: sync pull 时 server 端下发的 change 在本地 apply 抛错的持久化记录。
// 健康用户这张表是空的;只在出错时写入,供 UI 暴露 + 用户重试/跳过 + 开发者
// 远程诊断。详见 .docs/full-pull-refactor/04-data-model.md。
class SyncPullErrors extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get changeId => integer().unique()(); // server change_id,唯一
  TextColumn get ledgerExternalId =>
      text().nullable()(); // user-global change 可空
  TextColumn get entityType => text()();
  TextColumn get entitySyncId => text()();
  TextColumn get action => text()(); // upsert / delete
  TextColumn get rawChangeJson => text()(); // 完整 change JSON,供诊断 + 复制给用户
  TextColumn get errorClass => text().nullable()(); // Dart exception 类名
  TextColumn get errorMessage => text().nullable()(); // exception.toString() 首行
  TextColumn get stackTrace => text().nullable()(); // 截断到 ~2KB
  DateTimeColumn get firstSeenAt => dateTime()();
  DateTimeColumn get lastAttemptAt => dateTime()();
  IntColumn get attemptCount => integer().withDefault(const Constant(1))();
  TextColumn get userAction =>
      text().nullable()(); // null / 'skip' / 'retry_requested'
  DateTimeColumn get resolvedAt => dateTime().nullable()();
}

// 交易附件表
class TransactionAttachments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get transactionId => integer()(); // 关联的交易ID
  TextColumn get fileName => text()(); // 文件名（不含路径）
  TextColumn get originalName => text().nullable()(); // 原始文件名
  IntColumn get fileSize => integer().nullable()(); // 文件大小（bytes）
  IntColumn get width => integer().nullable()(); // 图片宽度
  IntColumn get height => integer().nullable()(); // 图片高度
  IntColumn get sortOrder => integer().withDefault(const Constant(0))(); // 排序序号
  TextColumn get cloudFileId => text().nullable()(); // 云端文件ID
  TextColumn get cloudSha256 => text().nullable()(); // 云端文件SHA256
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// 预算表
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 跨设备同步 syncId(UUID)。v22 新增,migration 给老行补 UUID;之后每次 create
  /// 都必须填。server 端按此做 entity_sync_id,跨设备 LWW 合并。
  TextColumn get syncId => text().nullable()();

  /// 关联账本ID
  IntColumn get ledgerId => integer()();

  /// 预算类型：total-总预算, category-分类预算
  TextColumn get type => text().withDefault(const Constant('total'))();

  /// 关联分类ID（仅分类预算有值）
  IntColumn get categoryId => integer().nullable()();

  /// 预算金额
  RealColumn get amount => real()();

  /// 预算周期：monthly-月度, weekly-周度, yearly-年度
  TextColumn get period => text().withDefault(const Constant('monthly'))();

  /// 周期起始日（1-31，月度预算；1-7，周度预算）
  IntColumn get startDay => integer().withDefault(const Constant(1))();

  /// 是否启用
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// 创建时间
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// 更新时间
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// v44 專案(對齐 BeeCount Cloud `project` sync entity,取代分類預算):
/// ledger-scoped 實體,同 [Budgets]/[Debts] 那組模式。
///
/// **花費/進度不落地存**,讀取時即時算(Phase 2/3 才會加用量計算邏輯,本
/// 表本身只是骨架)——對齐 Cloud `read_project_projection` 的設計。
///
/// 字段/wire key 對照 BeeCount Cloud `sync_applier.py::_MERGE_SPECS
/// ["project"]`——改字段前先去那邊核對,一字之差會讓整個字段靜默同步失敗。
class Projects extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 跨设备同步 syncId(UUID)。新建必须填(同 budget/debt 的约定)。
  TextColumn get syncId => text().nullable()();

  /// 关联账本ID
  IntColumn get ledgerId => integer()();

  TextColumn get name => text().withDefault(const Constant(''))();

  /// emoji icon,可留空。
  TextColumn get icon => text().nullable()();

  /// 預算金額,null = 純記錄型(不設預算上限)。
  RealColumn get budgetAmount => real().nullable()();

  /// 週期類型:'monthly' / 'yearly' / 'fixed'。
  TextColumn get periodType => text().withDefault(const Constant('monthly'))();

  /// 起訖日,僅 periodType='fixed' 使用。
  DateTimeColumn get periodStart => dateTime().nullable()();
  DateTimeColumn get periodEnd => dateTime().nullable()();

  /// 結轉(僅 monthly/yearly 有意義,fixed 週期忽略)。
  BoolColumn get carryoverEnabled =>
      boolean().withDefault(const Constant(false))();

  /// 顯示於首頁。
  BoolColumn get visibleOnHome => boolean().withDefault(const Constant(true))();

  /// 啟用/封存旗標(軟刪除)。刪除規則:有交易關聯 → 設 false(封存);沒有
  /// → 直接刪除整列。見 [ProjectRepository.deleteProject]。
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// 使用者自訂排序。
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

// ============================================================================
// 共享账本(v24)
// ============================================================================

/// 账本成员镜像表。server `LedgerMember` 表的本地副本,用于"X 记的"显示 +
/// 离线渲染。`GET /api/v1/ledgers/{id}/members` 拉来后写入;`member_change`
/// WS 事件触发增量更新。
class LedgerMembers extends Table {
  TextColumn get ledgerSyncId => text()(); // ledger.syncId(全 user 唯一)
  TextColumn get userId => text()();
  TextColumn get email => text().nullable()();
  TextColumn get displayName => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get role => text()(); // owner / editor
  DateTimeColumn get joinedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()(); // 本地更新时间,用于 cache 失效

  @override
  Set<Column> get primaryKey => {ledgerSyncId, userId};
}

/// 共享账本里 Owner 的 user-global 分类镜像。Editor 在共享账本下打开"选分类"
/// 弹窗读这表(而非自己的 Categories)。`GET /api/v1/ledgers/{id}/shared-resources`
/// 拉来落库;`shared_resource_change` WS 事件增量更新。
class SharedLedgerCategories extends Table {
  TextColumn get ledgerSyncId => text()();
  TextColumn get syncId => text()(); // Owner 的 user-global category sync_id
  TextColumn get name => text()();
  TextColumn get kind => text()(); // expense / income
  TextColumn get icon => text().nullable()();
  TextColumn get iconType => text().withDefault(const Constant('material'))();
  TextColumn get iconCloudFileId =>
      text().nullable()(); // 自定义图标:attachment UUID
  TextColumn get iconCloudSha256 =>
      text().nullable()(); // 自定义图标:sha256(本地 cache 去重)
  TextColumn get color => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get level => integer().withDefault(const Constant(1))();
  TextColumn get parentName => text().nullable()();
  // v25 共享账本二级分类:parent 的 syncId,用于 picker 建稳定父子链
  // (parent_name 兜底/显示,parent_sync_id 主)。
  TextColumn get parentSyncId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ledgerSyncId, syncId};
}

/// 共享账本里 Owner 的 user-global 账户镜像。
class SharedLedgerAccounts extends Table {
  TextColumn get ledgerSyncId => text()();
  TextColumn get syncId => text()();
  TextColumn get name => text()();
  TextColumn get accountType => text().withDefault(const Constant('cash'))();
  TextColumn get currency => text().withDefault(const Constant('CNY'))();
  TextColumn get note => text().nullable()();
  RealColumn get initialBalance => real().nullable()();
  RealColumn get creditLimit => real().nullable()();
  IntColumn get billingDay => integer().nullable()();
  IntColumn get paymentDueDay => integer().nullable()();
  TextColumn get bankName => text().nullable()();
  TextColumn get cardLastFour => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ledgerSyncId, syncId};
}

/// 共享账本里 Owner 的 user-global 标签镜像。
class SharedLedgerTags extends Table {
  TextColumn get ledgerSyncId => text()();
  TextColumn get syncId => text()();
  TextColumn get name => text()();
  TextColumn get color => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ledgerSyncId, syncId};
}

// ============================================================================
// 回饋規則學習快取(v48)
// ============================================================================

/// 記帳表單「同帳戶+同類別自動代入回饋規則」的本機學習快取。只在使用者手動
/// 於回饋規則選單選擇/清空時寫入(見 [TransactionEntryFormState._openRewardRuleSelector]),
/// SwipeSmart 雲端卡片推薦點選不寫入此表——它只能代入帳戶,沒有對應到本機
/// [CardRewardRules.syncId],無從得知使用者「選了哪條回饋規則」。
class RewardChoiceCaches extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ledgerId => integer()();
  IntColumn get categoryId => integer()();
  IntColumn get accountId => integer()();

  /// JSON 陣列,元素為 [CardRewardRules.syncId]。這欄只會存非空陣列——使用者
  /// 清空選取時 [RewardChoiceCacheRepository.clearRewardChoice] 直接刪掉整
  /// 列,不會存一筆空陣列(呼叫端把「從未設定」跟「空選取」一視同仁)。
  TextColumn get rewardRuleIdsJson => text()();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [
  Ledgers,
  Accounts,
  Categories,
  Transactions,
  RecurringTransactions,
  Conversations,
  Messages,
  Tags,
  TransactionTags,
  Budgets,
  TransactionAttachments,
  LocalChanges,
  SyncState,
  LedgerMembers,
  SharedLedgerCategories,
  SharedLedgerAccounts,
  SharedLedgerTags,
  TransactionTagOverrides,
  SyncPullErrors,
  ExchangeRates,
  ExchangeRateOverrides,
  CardRewardRules,
  TransactionSplits,
  Debts,
  Projects,
  RewardChoiceCaches,
  InstallmentPlans,
  InstallmentPeriods,
])
class BeeDatabase extends _$BeeDatabase {
  BeeDatabase() : super(_openConnection());

  /// 测试专用:直接注入 [QueryExecutor](通常是 NativeDatabase.memory()),
  /// 跳过 [_openConnection] 的文件系统 / 平台副作用。test/ 下的 unit test
  /// 用这个。
  BeeDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 52; // v52: 修补 base_amount 缺失的历史交易(见 v52 迁移注释)

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            // 添加 sortOrder 字段（使用原始 SQL，因为此时代码还未生成）
            await customStatement(
                'ALTER TABLE categories ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0;');

            // 为现有分类设置默认的 sortOrder（按 id 顺序）
            await customStatement('''
          UPDATE categories
          SET sort_order = (
            SELECT COUNT(*)
            FROM categories AS c2
            WHERE c2.id <= categories.id
          ) - 1;
        ''');
          }
          if (from < 3) {
            // 创建重复交易表
            await migrator.createTable(recurringTransactions);

            // 为 transactions 表添加 recurring_id 字段
            await customStatement(
                'ALTER TABLE transactions ADD COLUMN recurring_id INTEGER;');
          }
          if (from < 4) {
            // 为 accounts 表添加 initial_balance 字段
            await customStatement(
                'ALTER TABLE accounts ADD COLUMN initial_balance REAL NOT NULL DEFAULT 0.0;');
          }
          if (from < 5) {
            // v5: 账户独立改造
            // 注意：数据迁移逻辑在 MigrationService 中统一处理
            // 这里只添加必要的字段

            // 检查字段是否已存在，避免重复添加
            final tableInfo =
                await customSelect('PRAGMA table_info(accounts)').get();
            final hasCurrency =
                tableInfo.any((row) => row.data['name'] == 'currency');
            final hasCreatedAt =
                tableInfo.any((row) => row.data['name'] == 'created_at');
            final hasUpdatedAt =
                tableInfo.any((row) => row.data['name'] == 'updated_at');

            if (!hasCurrency) {
              await customStatement(
                  'ALTER TABLE accounts ADD COLUMN currency TEXT NOT NULL DEFAULT \'CNY\';');
            }

            if (!hasCreatedAt) {
              // SQLite 不支持非常量默认值，先添加可空字段，然后更新
              await customStatement(
                  'ALTER TABLE accounts ADD COLUMN created_at INTEGER;');
              await customStatement(
                  'UPDATE accounts SET created_at = strftime(\'%s\', \'now\') WHERE created_at IS NULL;');
            }

            if (!hasUpdatedAt) {
              await customStatement(
                  'ALTER TABLE accounts ADD COLUMN updated_at INTEGER;');
            }

            // 注意：不在onUpgrade中更新currency数据
            // 数据迁移统一由 MigrationService 处理，避免重复逻辑
          }
          if (from < 6) {
            // v6: 二级分类支持
            // 检查字段是否已存在，避免重复添加
            final tableInfo =
                await customSelect('PRAGMA table_info(categories)').get();
            final hasParentId =
                tableInfo.any((row) => row.data['name'] == 'parent_id');
            final hasLevel =
                tableInfo.any((row) => row.data['name'] == 'level');

            if (!hasParentId) {
              await customStatement(
                  'ALTER TABLE categories ADD COLUMN parent_id INTEGER;');
            }

            if (!hasLevel) {
              await customStatement(
                  'ALTER TABLE categories ADD COLUMN level INTEGER NOT NULL DEFAULT 1;');
            }

            // 确保所有现有分类的 level 都为 1（一级分类）
            await customStatement(
                'UPDATE categories SET level = 1 WHERE level IS NULL OR level = 0;');
          }
          if (from < 7) {
            print('[DB Migration] 开始迁移到 v7: 周期账单支持转账');
            // v7: 周期账单支持转账
            // 需要将 category_id 改为可空，并添加 to_account_id 字段
            // SQLite 不支持修改列约束，所以需要重建表

            // 1. 创建新表
            print('[DB Migration] 步骤1: 创建新表');
            await customStatement('''
              CREATE TABLE IF NOT EXISTS recurring_transactions_new (
                id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                ledger_id INTEGER NOT NULL,
                type TEXT NOT NULL,
                amount REAL NOT NULL,
                category_id INTEGER,
                account_id INTEGER,
                to_account_id INTEGER,
                note TEXT,
                frequency TEXT NOT NULL,
                interval INTEGER NOT NULL DEFAULT 1,
                day_of_month INTEGER,
                day_of_week INTEGER,
                month_of_year INTEGER,
                start_date INTEGER NOT NULL,
                end_date INTEGER,
                last_generated_date INTEGER,
                enabled INTEGER NOT NULL DEFAULT 1,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
              );
            ''');

            // 2. 复制数据
            print('[DB Migration] 步骤2: 复制数据');
            await customStatement('''
              INSERT INTO recurring_transactions_new
              (id, ledger_id, type, amount, category_id, account_id, to_account_id, note,
               frequency, interval, day_of_month, day_of_week, month_of_year,
               start_date, end_date, last_generated_date, enabled, created_at, updated_at)
              SELECT id, ledger_id, type, amount, category_id, account_id,
                     NULL as to_account_id, note,
                     frequency, interval, day_of_month, day_of_week, month_of_year,
                     start_date, end_date, last_generated_date, enabled, created_at, updated_at
              FROM recurring_transactions;
            ''');

            // 3. 删除旧表
            print('[DB Migration] 步骤3: 删除旧表');
            await customStatement('DROP TABLE recurring_transactions;');

            // 4. 重命名新表
            print('[DB Migration] 步骤4: 重命名新表');
            await customStatement(
                'ALTER TABLE recurring_transactions_new RENAME TO recurring_transactions;');
            print('[DB Migration] v7 迁移完成');
          }
          if (from < 8) {
            // v8: AI 对话助手
            print('[DB Migration] 开始迁移到 v8: AI 对话助手');
            await migrator.createTable(conversations);
            await migrator.createTable(messages);
            logger.info('DB', 'v8 迁移完成: AI Chat tables created');
            print('[DB Migration] v8 迁移完成');
          }
          if (from < 9) {
            // v9: 为 ledgers 表添加 type 字段（支持家庭账本）
            print('[DB Migration] 开始迁移到 v9: 添加 ledgers.type 字段');

            // 检查字段是否已存在，避免重复添加
            final tableInfo =
                await customSelect('PRAGMA table_info(ledgers)').get();
            final hasType = tableInfo.any((row) => row.data['name'] == 'type');

            if (!hasType) {
              await customStatement(
                  'ALTER TABLE ledgers ADD COLUMN type TEXT NOT NULL DEFAULT \'personal\';');
              logger.info('DB', 'v9 迁移完成: ledgers.type 字段已添加');
            } else {
              logger.info('DB', 'v9 迁移跳过: ledgers.type 字段已存在');
            }

            print('[DB Migration] v9 迁移完成');
          }
          if (from < 10) {
            // v10: 添加标签功能
            print('[DB Migration] 开始迁移到 v10: 添加标签功能');

            // 创建 tags 表
            await migrator.createTable(tags);
            logger.info('DB', 'v10: tags 表已创建');

            // 创建 transaction_tags 关联表
            await migrator.createTable(transactionTags);
            logger.info('DB', 'v10: transaction_tags 表已创建');

            // 创建索引以提高查询性能
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_transaction_tags_transaction ON transaction_tags(transaction_id)');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_transaction_tags_tag ON transaction_tags(tag_id)');
            logger.info('DB', 'v10: 索引已创建');

            print('[DB Migration] v10 迁移完成');
          }
          if (from < 11) {
            // v11: 添加预算功能
            print('[DB Migration] 开始迁移到 v11: 添加预算功能');

            // 创建 budgets 表
            await migrator.createTable(budgets);
            logger.info('DB', 'v11: budgets 表已创建');

            // 创建索引以提高查询性能
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_budgets_ledger ON budgets(ledger_id)');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_budgets_category ON budgets(category_id)');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_budgets_ledger_type ON budgets(ledger_id, type)');
            logger.info('DB', 'v11: 预算索引已创建');

            print('[DB Migration] v11 迁移完成');
          }
          if (from < 12) {
            // v12: 添加交易附件功能
            print('[DB Migration] 开始迁移到 v12: 添加交易附件功能');

            // 创建 transaction_attachments 表
            await migrator.createTable(transactionAttachments);
            logger.info('DB', 'v12: transaction_attachments 表已创建');

            // 创建索引以提高查询性能
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_attachments_transaction ON transaction_attachments(transaction_id)');
            logger.info('DB', 'v12: 附件索引已创建');

            print('[DB Migration] v12 迁移完成');
          }
          if (from < 13) {
            // v13: 分类自定义图标支持
            print('[DB Migration] 开始迁移到 v13: 分类自定义图标支持');

            // 检查字段是否已存在，避免重复添加
            final tableInfo =
                await customSelect('PRAGMA table_info(categories)').get();
            final hasIconType =
                tableInfo.any((row) => row.data['name'] == 'icon_type');
            final hasCustomIconPath =
                tableInfo.any((row) => row.data['name'] == 'custom_icon_path');
            final hasCommunityIconId =
                tableInfo.any((row) => row.data['name'] == 'community_icon_id');

            if (!hasIconType) {
              await customStatement(
                  "ALTER TABLE categories ADD COLUMN icon_type TEXT NOT NULL DEFAULT 'material';");
              logger.info('DB', 'v13: icon_type 字段已添加');
            }

            if (!hasCustomIconPath) {
              await customStatement(
                  'ALTER TABLE categories ADD COLUMN custom_icon_path TEXT;');
              logger.info('DB', 'v13: custom_icon_path 字段已添加');
            }

            if (!hasCommunityIconId) {
              await customStatement(
                  'ALTER TABLE categories ADD COLUMN community_icon_id TEXT;');
              logger.info('DB', 'v13: community_icon_id 字段已添加');
            }

            print('[DB Migration] v13 迁移完成');
          }
          if (from < 14) {
            // v14: 迁移转账记录到虚拟转账分类
            print('[DB Migration] 开始迁移到 v14: 迁移转账记录到虚拟转账分类');
            await SeedService.migrateTransferTransactions(this);
            logger.info('DB', 'v14 迁移完成: 转账记录已关联到虚拟转账分类');
            print('[DB Migration] v14 迁移完成');
          }
          if (from < 15) {
            // v15: 交易添加 syncId 用于云同步
            print('[DB Migration] 开始迁移到 v15: 添加 syncId 字段');

            // 1. 添加 sync_id 列
            await customStatement(
                'ALTER TABLE transactions ADD COLUMN sync_id TEXT;');
            logger.info('DB', 'v15: sync_id 字段已添加');

            // 2. 为所有已有交易生成 UUID v4
            // 使用 SQLite 内置函数生成简易唯一ID（hex + random）
            // 格式: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
            await customStatement('''
              UPDATE transactions SET sync_id =
                lower(hex(randomblob(4))) || '-' ||
                lower(hex(randomblob(2))) || '-4' ||
                substr(lower(hex(randomblob(2))),2) || '-' ||
                substr('89ab', abs(random()) % 4 + 1, 1) ||
                substr(lower(hex(randomblob(2))),2) || '-' ||
                lower(hex(randomblob(6)))
              WHERE sync_id IS NULL;
            ''');
            logger.info('DB', 'v15: 已为现有交易回填 syncId');

            // 3. 创建索引
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_transactions_sync_id ON transactions(sync_id);');
            logger.info('DB', 'v15: syncId 索引已创建');

            print('[DB Migration] v15 迁移完成');
          }
          if (from < 16) {
            // v16: 账户添加 sortOrder 排序字段
            print('[DB Migration] 开始迁移到 v16: 账户排序');

            await customStatement(
                'ALTER TABLE accounts ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0;');
            logger.info('DB', 'v16: sort_order 字段已添加');

            // 回填：按 type 分组，组内按 created_at 排序赋值 sortOrder
            await customStatement('''
              UPDATE accounts SET sort_order = (
                SELECT COUNT(*)
                FROM accounts AS a2
                WHERE a2.type = accounts.type
                  AND (a2.created_at < accounts.created_at
                       OR (a2.created_at = accounts.created_at AND a2.id < accounts.id)
                       OR (a2.created_at IS NULL AND accounts.created_at IS NOT NULL)
                       OR (a2.created_at IS NULL AND accounts.created_at IS NULL AND a2.id < accounts.id))
              );
            ''');
            logger.info('DB', 'v16: 已为现有账户回填 sortOrder');

            print('[DB Migration] v16 迁移完成');
          }
          if (from < 17) {
            // v17: 账户添加信用卡字段
            print('[DB Migration] 开始迁移到 v17: 信用卡字段');

            final tableInfo =
                await customSelect('PRAGMA table_info(accounts)').get();
            final hasCreditLimit =
                tableInfo.any((row) => row.data['name'] == 'credit_limit');
            final hasBillingDay =
                tableInfo.any((row) => row.data['name'] == 'billing_day');
            final hasPaymentDueDay =
                tableInfo.any((row) => row.data['name'] == 'payment_due_day');

            if (!hasCreditLimit) {
              await customStatement(
                  'ALTER TABLE accounts ADD COLUMN credit_limit REAL;');
              logger.info('DB', 'v17: credit_limit 字段已添加');
            }

            if (!hasBillingDay) {
              await customStatement(
                  'ALTER TABLE accounts ADD COLUMN billing_day INTEGER;');
              logger.info('DB', 'v17: billing_day 字段已添加');
            }

            if (!hasPaymentDueDay) {
              await customStatement(
                  'ALTER TABLE accounts ADD COLUMN payment_due_day INTEGER;');
              logger.info('DB', 'v17: payment_due_day 字段已添加');
            }

            print('[DB Migration] v17 迁移完成');
          }
          if (from < 18) {
            // v18: 账户添加元信息字段
            print('[DB Migration] 开始迁移到 v18: 账户元信息');

            final tableInfo =
                await customSelect('PRAGMA table_info(accounts)').get();
            final hasBankName =
                tableInfo.any((row) => row.data['name'] == 'bank_name');
            final hasCardLastFour =
                tableInfo.any((row) => row.data['name'] == 'card_last_four');
            final hasNote = tableInfo.any((row) => row.data['name'] == 'note');

            if (!hasBankName) {
              await customStatement(
                  'ALTER TABLE accounts ADD COLUMN bank_name TEXT;');
              logger.info('DB', 'v18: bank_name 字段已添加');
            }

            if (!hasCardLastFour) {
              await customStatement(
                  'ALTER TABLE accounts ADD COLUMN card_last_four TEXT;');
              logger.info('DB', 'v18: card_last_four 字段已添加');
            }

            if (!hasNote) {
              await customStatement(
                  'ALTER TABLE accounts ADD COLUMN note TEXT;');
              logger.info('DB', 'v18: note 字段已添加');
            }

            print('[DB Migration] v18 迁移完成');
          }
          if (from < 19) {
            // v19: 同步基础设施
            print('[DB Migration] 开始迁移到 v19: 同步基础设施');

            // 1. 为 accounts 添加 sync_id
            final accountInfo =
                await customSelect('PRAGMA table_info(accounts)').get();
            if (!accountInfo.any((row) => row.data['name'] == 'sync_id')) {
              await customStatement(
                  'ALTER TABLE accounts ADD COLUMN sync_id TEXT;');
              // 回填 UUID
              await customStatement('''
                UPDATE accounts SET sync_id =
                  lower(hex(randomblob(4))) || '-' ||
                  lower(hex(randomblob(2))) || '-4' ||
                  substr(lower(hex(randomblob(2))),2) || '-' ||
                  substr('89ab', abs(random()) % 4 + 1, 1) ||
                  substr(lower(hex(randomblob(2))),2) || '-' ||
                  lower(hex(randomblob(6)))
                WHERE sync_id IS NULL;
              ''');
              await customStatement(
                  'CREATE INDEX IF NOT EXISTS idx_accounts_sync_id ON accounts(sync_id);');
              logger.info('DB', 'v19: accounts.sync_id 已添加并回填');
            }

            // 2. 为 categories 添加 sync_id
            final categoryInfo =
                await customSelect('PRAGMA table_info(categories)').get();
            if (!categoryInfo.any((row) => row.data['name'] == 'sync_id')) {
              await customStatement(
                  'ALTER TABLE categories ADD COLUMN sync_id TEXT;');
              await customStatement('''
                UPDATE categories SET sync_id =
                  lower(hex(randomblob(4))) || '-' ||
                  lower(hex(randomblob(2))) || '-4' ||
                  substr(lower(hex(randomblob(2))),2) || '-' ||
                  substr('89ab', abs(random()) % 4 + 1, 1) ||
                  substr(lower(hex(randomblob(2))),2) || '-' ||
                  lower(hex(randomblob(6)))
                WHERE sync_id IS NULL;
              ''');
              await customStatement(
                  'CREATE INDEX IF NOT EXISTS idx_categories_sync_id ON categories(sync_id);');
              logger.info('DB', 'v19: categories.sync_id 已添加并回填');
            }

            // 3. 为 tags 添加 sync_id
            final tagInfo = await customSelect('PRAGMA table_info(tags)').get();
            if (!tagInfo.any((row) => row.data['name'] == 'sync_id')) {
              await customStatement(
                  'ALTER TABLE tags ADD COLUMN sync_id TEXT;');
              await customStatement('''
                UPDATE tags SET sync_id =
                  lower(hex(randomblob(4))) || '-' ||
                  lower(hex(randomblob(2))) || '-4' ||
                  substr(lower(hex(randomblob(2))),2) || '-' ||
                  substr('89ab', abs(random()) % 4 + 1, 1) ||
                  substr(lower(hex(randomblob(2))),2) || '-' ||
                  lower(hex(randomblob(6)))
                WHERE sync_id IS NULL;
              ''');
              await customStatement(
                  'CREATE INDEX IF NOT EXISTS idx_tags_sync_id ON tags(sync_id);');
              logger.info('DB', 'v19: tags.sync_id 已添加并回填');
            }

            // 4. 创建 local_changes 表
            await migrator.createTable(localChanges);
            logger.info('DB', 'v19: local_changes 表已创建');

            // 5. 创建 sync_state 表
            await migrator.createTable(syncState);
            logger.info('DB', 'v19: sync_state 表已创建');

            print('[DB Migration] v19 迁移完成');
          }
          if (from < 20) {
            // v20: 附件云端同步字段
            print('[DB Migration] 开始迁移到 v20: 附件云端同步字段');

            final tableInfo =
                await customSelect('PRAGMA table_info(transaction_attachments)')
                    .get();
            final hasCloudFileId =
                tableInfo.any((row) => row.data['name'] == 'cloud_file_id');
            final hasCloudSha256 =
                tableInfo.any((row) => row.data['name'] == 'cloud_sha256');

            if (!hasCloudFileId) {
              await customStatement(
                  'ALTER TABLE transaction_attachments ADD COLUMN cloud_file_id TEXT;');
              logger.info('DB', 'v20: cloud_file_id 字段已添加');
            }

            if (!hasCloudSha256) {
              await customStatement(
                  'ALTER TABLE transaction_attachments ADD COLUMN cloud_sha256 TEXT;');
              logger.info('DB', 'v20: cloud_sha256 字段已添加');
            }

            print('[DB Migration] v20 迁移完成');
          }
          if (from < 21) {
            // v21: ledgers 加 syncId（跨设备同步 ledger 匹配）
            print('[DB Migration] 开始迁移到 v21: ledgers.sync_id');

            final ledgerInfo =
                await customSelect('PRAGMA table_info(ledgers)').get();
            if (!ledgerInfo.any((row) => row.data['name'] == 'sync_id')) {
              await customStatement(
                  'ALTER TABLE ledgers ADD COLUMN sync_id TEXT;');
              // 把现有 ledger.id 回填成 syncId（转字符串）。这样旧 A 设备已推
              // 到 server 的 external_id（= 当时的 id.toString()）对得上新列，
              // 后续 push/pull 都走 syncId，无脑兼容。
              await customStatement(
                  "UPDATE ledgers SET sync_id = CAST(id AS TEXT) WHERE sync_id IS NULL;");
              await customStatement(
                  'CREATE INDEX IF NOT EXISTS idx_ledgers_sync_id ON ledgers(sync_id);');
              logger.info('DB', 'v21: ledgers.sync_id 已添加并回填');
            }

            print('[DB Migration] v21 迁移完成');
          }
          if (from < 22) {
            // v22: budgets 加 syncId(跨设备同步 budget 匹配)
            print('[DB Migration] 开始迁移到 v22: budgets.sync_id');

            final budgetInfo =
                await customSelect('PRAGMA table_info(budgets)').get();
            if (!budgetInfo.any((row) => row.data['name'] == 'sync_id')) {
              await customStatement(
                  'ALTER TABLE budgets ADD COLUMN sync_id TEXT;');
              // SQLite 没有原生 UUID。用 lower(hex(randomblob(16))) 造 32 位
              // 随机 hex,足够当 server entity_sync_id 用。格式跟 UUID 不是
              // 标准 36 位,但 server 侧校验只要求非空字符串。
              await customStatement(
                  "UPDATE budgets SET sync_id = lower(hex(randomblob(16))) WHERE sync_id IS NULL;");
              await customStatement(
                  'CREATE INDEX IF NOT EXISTS idx_budgets_sync_id ON budgets(sync_id);');
              logger.info('DB', 'v22: budgets.sync_id 已添加并回填');
            }

            print('[DB Migration] v22 迁移完成');
          }
          if (from < 23) {
            // v23: 清理"分类图标靠 getCategoryIconByName 运行时推导"的毒瘤代码。
            // 历史上 `category.icon` 允许为 null/空,渲染时走 `getCategoryIconByName`
            // 按中文关键字模糊匹配回退推导图标。这个方案:
            //   - 改名就换图标(用户会懵)
            //   - 只认中文,英语/繁中走不到
            //   - web/server 必须复刻同一套 40 条正则,维护两份
            // v23 一次性把 icon IS NULL/'' 的分类按 byName 推算出结果写回 DB,
            // 之后渲染层 getCategoryIconData 只认 icon 字段、不再 byName 推导。
            // 结合服务端 alembic 0002 的同名 backfill,两端同步"迁 read-time 到
            // write-time"。
            print(
                '[DB Migration] 开始迁移到 v23: backfill category icons via byName');

            // 取所有 icon 空的分类,按 name 推导图标字符串回填
            final rows = await customSelect(
              "SELECT id, name FROM categories WHERE icon IS NULL OR icon = ''",
            ).get();
            var updated = 0;
            for (final row in rows) {
              final id = row.data['id'] as int;
              final name = row.data['name'] as String? ?? '';
              // 用 CategoryService.resolveIconNameByName(类似原 getCategoryIconByName
              // 但返回字符串名)一次性固化到 DB。此后渲染不再 byName。
              final iconName = CategoryService.resolveIconNameByName(name);
              await customStatement(
                'UPDATE categories SET icon = ? WHERE id = ?',
                [iconName, id],
              );
              updated++;
            }
            logger.info('DB', 'v23: backfilled $updated categories');
            print('[DB Migration] v23 迁移完成: 回填 $updated 条分类');
          }
          if (from < 24) {
            // v24: 共享账本完整 schema(合并自 v24/v25/v26/v27 的迭代,测试阶段
            // 一次落地最终态)。
            //
            // 重要:所有 ALTER / createTable 都包"存在则跳过"防御 — 用户从
            // 3.1.3 升级到带 bug 的 3.2.0 时 v25 ALTER 失败,但 v24 的 DDL
            // 已经隐式 commit(SQLite DDL 不可回滚),user_version 仍 23。
            // 装新版本再跑 onUpgrade(from=23) 时 v24 第一句又会 duplicate column
            // 卡死。每条都要幂等。
            print('[DB Migration] 开始迁移到 v24: 共享账本完整 schema');

            await _addColumnIfMissing('ledgers', 'my_role',
                "ALTER TABLE ledgers ADD COLUMN my_role TEXT NOT NULL DEFAULT 'owner';");
            await _addColumnIfMissing('ledgers', 'member_count',
                "ALTER TABLE ledgers ADD COLUMN member_count INTEGER NOT NULL DEFAULT 1;");
            await _addColumnIfMissing('ledgers', 'is_shared',
                "ALTER TABLE ledgers ADD COLUMN is_shared INTEGER NOT NULL DEFAULT 0;");
            await _addColumnIfMissing('ledgers', 'owner_user_id',
                "ALTER TABLE ledgers ADD COLUMN owner_user_id TEXT;");

            await _addColumnIfMissing('transactions', 'created_by_user_id',
                "ALTER TABLE transactions ADD COLUMN created_by_user_id TEXT;");
            await _addColumnIfMissing('transactions', 'last_edited_by_user_id',
                "ALTER TABLE transactions ADD COLUMN last_edited_by_user_id TEXT;");
            await _addColumnIfMissing(
                'transactions',
                'category_sync_id_override',
                'ALTER TABLE transactions ADD COLUMN category_sync_id_override TEXT;');
            await _addColumnIfMissing(
                'transactions',
                'account_sync_id_override',
                'ALTER TABLE transactions ADD COLUMN account_sync_id_override TEXT;');
            await _addColumnIfMissing(
                'transactions',
                'to_account_sync_id_override',
                'ALTER TABLE transactions ADD COLUMN to_account_sync_id_override TEXT;');
            await _addColumnIfMissing('transactions', 'tag_sync_ids_override',
                'ALTER TABLE transactions ADD COLUMN tag_sync_ids_override TEXT;');

            await _createTableIfMissing(
                migrator, 'ledger_members', ledgerMembers);
            await _createTableIfMissing(
                migrator, 'shared_ledger_categories', sharedLedgerCategories);
            await _createTableIfMissing(
                migrator, 'shared_ledger_accounts', sharedLedgerAccounts);
            await _createTableIfMissing(
                migrator, 'shared_ledger_tags', sharedLedgerTags);
            await _createTableIfMissing(
                migrator, 'transaction_tag_overrides', transactionTagOverrides);

            // 重置 server_cursor — 强制下次启动全量重拉,确保 sync_engine_apply
            // 用最新的 override 写入逻辑填回 *SyncIdOverride 字段。
            await customStatement('UPDATE sync_state SET server_cursor = 0');

            print('[DB Migration] v24 迁移完成');
          }
          if (from < 25) {
            // v25: SharedLedgerCategories 加 parent_sync_id 列。
            // 注:v24 `createTable(sharedLedgerCategories)` 用**当前 schema**
            // 建表,已经带 parent_sync_id 列 — 干净 from=23 升级时这里 ALTER
            // 会 duplicate。用 helper PRAGMA 检查后再 ALTER。
            logger.info('DBMigration',
                '开始迁移到 v25: SharedLedgerCategories.parent_sync_id');
            await _addColumnIfMissing(
                'shared_ledger_categories',
                'parent_sync_id',
                'ALTER TABLE shared_ledger_categories ADD COLUMN parent_sync_id TEXT;');
            // 数据回填:对每个 level=2 行,在同 ledger_sync_id + kind 内按
            // parent_name 反查 level=1 行的 syncId 填进 parent_sync_id。
            // 用 IS NULL/'' 守护让 UPDATE 可幂等重跑。
            await customStatement('''
              UPDATE shared_ledger_categories AS child
              SET parent_sync_id = (
                SELECT parent.sync_id
                FROM shared_ledger_categories AS parent
                WHERE parent.ledger_sync_id = child.ledger_sync_id
                  AND parent.name = child.parent_name
                  AND parent.kind = child.kind
                  AND COALESCE(parent.level, 1) = 1
                LIMIT 1
              )
              WHERE COALESCE(child.level, 1) >= 2
                AND child.parent_name IS NOT NULL
                AND (child.parent_sync_id IS NULL OR child.parent_sync_id = '')
            ''');
            // reset server_cursor 让后续 pull 重拉 user-global category change。
            await customStatement('UPDATE sync_state SET server_cursor = 0');
            logger.info('DBMigration', 'v25 迁移完成');
          }
          if (from < 26) {
            // v26: 新增 sync_pull_errors 表。健康用户为空,只在 pull apply
            // 抛错时写入,UI 据此显示"同步异常"banner + 重试/跳过操作。
            // 详见 .docs/full-pull-refactor/04-data-model.md
            logger.info('DBMigration', '开始迁移到 v26: sync_pull_errors');
            await _createTableIfMissing(
                migrator, 'sync_pull_errors', syncPullErrors);
            logger.info('DBMigration', 'v26 迁移完成');
          }
          if (from < 27) {
            logger.info('DBMigration', '开始迁移到 v27: ledgers.month_start_day');
            // v27: 账本自定义每月起始日(1-28),默认 1=自然月
            await customStatement(
                'ALTER TABLE ledgers ADD COLUMN month_start_day INTEGER NOT NULL DEFAULT 1;');
            logger.info('DBMigration', 'v27 迁移完成');
          }
          if (from < 28) {
            logger.info('DBMigration',
                '开始迁移到 v28: 多币种 MVP(exchange_rates / exchange_rate_overrides)');
            await _createTableIfMissing(
                migrator, 'exchange_rates', exchangeRates);
            await _createTableIfMissing(
                migrator, 'exchange_rate_overrides', exchangeRateOverrides);
            await customStatement(
                'CREATE UNIQUE INDEX IF NOT EXISTS idx_rate_override_pair '
                'ON exchange_rate_overrides (base_currency, quote_currency);');
            logger.info('DBMigration', 'v28 迁移完成');
          }
          if (from < 29) {
            logger.info('DBMigration', '开始迁移到 v29: 账单标记(不计入收支/不计入预算)');
            await _addColumnIfMissing('transactions', 'exclude_from_stats',
                'ALTER TABLE transactions ADD COLUMN exclude_from_stats INTEGER NOT NULL DEFAULT 0;');
            await _addColumnIfMissing('transactions', 'exclude_from_budget',
                'ALTER TABLE transactions ADD COLUMN exclude_from_budget INTEGER NOT NULL DEFAULT 0;');
            logger.info('DBMigration', 'v29 迁移完成');
          }
          if (from < 30) {
            logger.info('DBMigration',
                '开始迁移到 v30: 交易级多币种(currency_code + native_amount)');
            await _addColumnIfMissing('transactions', 'currency_code',
                'ALTER TABLE transactions ADD COLUMN currency_code TEXT;');
            await _addColumnIfMissing('transactions', 'native_amount',
                'ALTER TABLE transactions ADD COLUMN native_amount REAL;');
            // 回填:currency_code = 账户币种(无账户 → 账本本位币);
            // native_amount = amount(隐含汇率 1.0)→ 单币种账本统计结果不变。
            // ⚠️ SQL 与 test/data/migration_v30_test.dart 的常量保持一字不差。
            await customStatement('''
    UPDATE transactions SET currency_code = COALESCE(
      (SELECT a.currency FROM accounts a WHERE a.id = transactions.account_id),
      (SELECT l.currency FROM ledgers l WHERE l.id = transactions.ledger_id),
      'CNY')
    WHERE currency_code IS NULL;''');
            await customStatement(
                'UPDATE transactions SET native_amount = amount WHERE native_amount IS NULL;');
            logger.info('DBMigration', 'v30 迁移完成');
          }
          if (from < 31) {
            logger.info('DBMigration', '开始迁移到 v31: 账户隐藏(hidden)');
            await _addColumnIfMissing('accounts', 'hidden',
                'ALTER TABLE accounts ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0;');
            logger.info('DBMigration', 'v31 迁移完成');
          }
          if (from < 32) {
            logger.info('DBMigration',
                '开始迁移到 v32: 账户主卡分组(parent_account_id) + 头像(avatar_path)');
            await _addColumnIfMissing('accounts', 'parent_account_id',
                'ALTER TABLE accounts ADD COLUMN parent_account_id TEXT;');
            await _addColumnIfMissing('accounts', 'avatar_path',
                'ALTER TABLE accounts ADD COLUMN avatar_path TEXT;');
            logger.info('DBMigration', 'v32 迁移完成');
          }
          if (from < 33) {
            logger.info('DBMigration', '开始迁移到 v33: 交易商家(merchant)');
            await _addColumnIfMissing('transactions', 'merchant',
                'ALTER TABLE transactions ADD COLUMN merchant TEXT;');
            logger.info('DBMigration', 'v33 迁移完成');
          }
          if (from < 34) {
            logger.info('DBMigration', '开始迁移到 v34: 退款关联(refund_of_sync_id)');
            await _addColumnIfMissing('transactions', 'refund_of_sync_id',
                'ALTER TABLE transactions ADD COLUMN refund_of_sync_id TEXT;');
            logger.info('DBMigration', 'v34 迁移完成');
          }
          if (from < 35) {
            logger.info('DBMigration', '开始迁移到 v35: 信用卡紅利回饋(card_reward_rules)');
            await _createTableIfMissing(
                migrator, 'card_reward_rules', cardRewardRules);
            await _addColumnIfMissing('transactions', 'reward_rule_ids_json',
                'ALTER TABLE transactions ADD COLUMN reward_rule_ids_json TEXT;');
            logger.info('DBMigration', 'v35 迁移完成');
          }
          if (from < 36) {
            logger.info('DBMigration',
                '开始迁移到 v36: 週期性收支對齐 BeeCount Cloud recurring_rule');

            // 1. transactions 新增两栏(旧的 recurring_id 整数栏保留在物理
            // 表里不动——Drift 不声明就不会读它,不需要冒险 DROP COLUMN)。
            await _addColumnIfMissing('transactions', 'recurring_rule_id',
                'ALTER TABLE transactions ADD COLUMN recurring_rule_id TEXT;');
            await _addColumnIfMissing(
                'transactions',
                'recurring_occurrence_overridden',
                'ALTER TABLE transactions ADD COLUMN recurring_occurrence_overridden '
                    'INTEGER NOT NULL DEFAULT 0;');

            // 2. recurring_transactions 整表 redesign(旧表字段跟新模型差异
            // 太大,SQLite 不支持改列约束/删列,沿用 v7 迁移同款"建新表→搬
            // 数据→删旧表→改名"套路)。
            await customStatement('''
              CREATE TABLE IF NOT EXISTS recurring_transactions_new (
                id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                sync_id TEXT,
                ledger_id INTEGER NOT NULL,
                type TEXT NOT NULL,
                amount REAL NOT NULL,
                category_id INTEGER,
                account_id INTEGER,
                from_account_id INTEGER,
                to_account_id INTEGER,
                note TEXT,
                merchant TEXT,
                tag_sync_ids_json TEXT,
                reward_rule_ids_json TEXT,
                frequency TEXT NOT NULL,
                interval INTEGER NOT NULL DEFAULT 1,
                advanced_rule_json TEXT,
                next_run_at INTEGER NOT NULL,
                end_at INTEGER,
                generated_until_at INTEGER,
                enabled INTEGER NOT NULL DEFAULT 1,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
              );
            ''');

            // id 原样保留(不重新编号)——下面回填 transactions.recurring_rule_id
            // 要靠旧 recurring_id 直接 join 新表的 id。舊 day_of_month/
            // day_of_week 换算成 advanced_rule_json(monthly_day 用天数原样;
            // weekly 用旧"1=周一..7=周日"减一换算成新"Monday=0..Sunday=6"),
            // monthOfYear 没有对应的进阶规则概念,直接丢弃(yearly 频率本来
            // 就靠 next_run_at 自身的月/日重复,这是历史小功能的可接受精度
            // 损失,不是遗漏)。旧 accountId 在 transfer 类型里当"来源账户"用,
            // 新表比照 Cloud 把它搬到独立的 from_account_id,让 accountId 只
            // 用于 expense/income。sync_id 用 SQLite 惯用的 randomblob UUID v4
            // 表达式当场产生(不留 null——留 null 会让"這條規則之前有沒有推過
            // 雲端"这个语意变得模糊)。
            await customStatement('''
              INSERT INTO recurring_transactions_new
              (id, sync_id, ledger_id, type, amount, category_id, account_id,
               from_account_id, to_account_id, note, merchant,
               tag_sync_ids_json, reward_rule_ids_json, frequency, interval,
               advanced_rule_json, next_run_at, end_at, generated_until_at,
               enabled, created_at, updated_at)
              SELECT
                id,
                lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' ||
                  substr(hex(randomblob(2)), 2) || '-' ||
                  substr('89ab', abs(random()) % 4 + 1, 1) ||
                  substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6))),
                ledger_id, type, amount, category_id,
                CASE WHEN type = 'transfer' THEN NULL ELSE account_id END,
                CASE WHEN type = 'transfer' THEN account_id ELSE NULL END,
                to_account_id, note, NULL, NULL, NULL,
                frequency, interval,
                CASE
                  WHEN frequency = 'monthly' AND day_of_month IS NOT NULL THEN
                    '{"type":"monthly_day","day":' || day_of_month || '}'
                  WHEN frequency = 'weekly' AND day_of_week IS NOT NULL THEN
                    '{"type":"weekly_days","days":[' || (day_of_week - 1) || ']}'
                  ELSE NULL
                END,
                start_date, end_date, last_generated_date,
                enabled, created_at, updated_at
              FROM recurring_transactions;
            ''');
            await customStatement('DROP TABLE recurring_transactions;');
            await customStatement(
                'ALTER TABLE recurring_transactions_new RENAME TO recurring_transactions;');

            // 3. 回填历史生成交易的 recurring_rule_id(旧 recurring_id 整数
            // 关联换成新的 syncId 字符串关联)。
            await customStatement('''
              UPDATE transactions
              SET recurring_rule_id = (
                SELECT sync_id FROM recurring_transactions rt
                WHERE rt.id = transactions.recurring_id
              )
              WHERE recurring_id IS NOT NULL
                AND EXISTS (
                  SELECT 1 FROM recurring_transactions rt
                  WHERE rt.id = transactions.recurring_id
                );
            ''');

            // 4. 这些規則/歷史交易之前从未接过 ChangeTracker,记一笔
            // local_changes 让它们在下次同步时当"新建"补推上云(没开雲端同步
            // 的使用者 push 循环本来就不会跑,这几行是 no-op)。push 时序列
            // 化会重新查询 live row 组 payload,这里不用填 payload_json。
            await customStatement('''
              INSERT INTO local_changes
                (entity_type, entity_id, entity_sync_id, ledger_id, action)
              SELECT 'recurring_rule', id, sync_id, ledger_id, 'upsert'
              FROM recurring_transactions
              WHERE sync_id IS NOT NULL;
            ''');
            await customStatement('''
              INSERT INTO local_changes
                (entity_type, entity_id, entity_sync_id, ledger_id, action)
              SELECT 'transaction', id, sync_id, ledger_id, 'upsert'
              FROM transactions
              WHERE recurring_rule_id IS NOT NULL AND sync_id IS NOT NULL;
            ''');

            logger.info('DBMigration', 'v36 迁移完成');
          }
          if (from < 37) {
            logger.info('DBMigration',
                '开始迁移到 v37: 對帳模式(reconciled_at) + 延後入帳(deferred_posting_at)');
            await _addColumnIfMissing('transactions', 'reconciled_at',
                'ALTER TABLE transactions ADD COLUMN reconciled_at INTEGER;');
            await _addColumnIfMissing('transactions', 'deferred_posting_at',
                'ALTER TABLE transactions ADD COLUMN deferred_posting_at INTEGER;');
            logger.info('DBMigration', 'v37 迁移完成');
          }
          if (from < 38) {
            logger.info('DBMigration', '开始迁移到 v38: 拆帳(transaction_splits)');
            await _addColumnIfMissing('transactions', 'has_splits',
                'ALTER TABLE transactions ADD COLUMN has_splits BOOLEAN NOT NULL DEFAULT 0;');
            await _createTableIfMissing(
                migrator, 'transaction_splits', transactionSplits);
            logger.info('DBMigration', 'v38 迁移完成');
          }
          if (from < 39) {
            logger.info('DBMigration', '开始迁移到 v39: 借還款(debts)');
            await _addColumnIfMissing('transactions', 'debt_sync_id',
                'ALTER TABLE transactions ADD COLUMN debt_sync_id TEXT;');
            await _createTableIfMissing(migrator, 'debts', debts);
            logger.info('DBMigration', 'v39 迁移完成');
          }
          if (from < 40) {
            logger.info(
                'DBMigration', '开始迁移到 v40: 待確認帳戶(needs_account_assignment)');
            await _addColumnIfMissing(
                'transactions',
                'needs_account_assignment',
                'ALTER TABLE transactions ADD COLUMN needs_account_assignment '
                    'BOOLEAN NOT NULL DEFAULT 0;');
            logger.info('DBMigration', 'v40 迁移完成');
          }
          if (from < 41) {
            logger.info('DBMigration',
                '开始迁移到 v41: 借還款分類 + 起點交易反查(debts.category_id / origin_transaction_sync_id)');
            await _addColumnIfMissing('debts', 'category_id',
                'ALTER TABLE debts ADD COLUMN category_id INTEGER;');
            await _addColumnIfMissing(
                'debts',
                'origin_transaction_sync_id',
                'ALTER TABLE debts ADD COLUMN origin_transaction_sync_id '
                    'TEXT;');
            logger.info('DBMigration', 'v41 迁移完成');
          }
          if (from < 42) {
            logger.info('DBMigration',
                '开始迁移到 v42: 欠款排除計入總額(debts.excluded_from_total)');
            await _addColumnIfMissing(
                'debts',
                'excluded_from_total',
                'ALTER TABLE debts ADD COLUMN excluded_from_total '
                    'BOOLEAN NOT NULL DEFAULT 0;');
            logger.info('DBMigration', 'v42 迁移完成');
          }
          if (from < 43) {
            logger.info('DBMigration',
                '开始迁移到 v43: 帳戶不納入總餘額(accounts.include_in_total)');
            await _addColumnIfMissing(
                'accounts',
                'include_in_total',
                'ALTER TABLE accounts ADD COLUMN include_in_total '
                    'BOOLEAN NOT NULL DEFAULT 1;');
            logger.info('DBMigration', 'v43 迁移完成');
          }
          if (from < 44) {
            logger.info('DBMigration',
                '开始迁移到 v44: 專案(projects) + 交易關聯(transactions.project_sync_id)');
            await _addColumnIfMissing('transactions', 'project_sync_id',
                'ALTER TABLE transactions ADD COLUMN project_sync_id TEXT;');
            await _createTableIfMissing(migrator, 'projects', projects);
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_projects_ledger ON projects(ledger_id)');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_projects_ledger_sort ON projects(ledger_id, sort_order)');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_projects_sync_id ON projects(sync_id)');
            logger.info('DBMigration', 'v44 迁移完成');
          }
          if (from < 45) {
            logger.info(
                'DBMigration', '开始迁移到 v45: 转账跨币别(transactions.to_amount)');
            await _addColumnIfMissing('transactions', 'to_amount',
                'ALTER TABLE transactions ADD COLUMN to_amount REAL;');
            logger.info('DBMigration', 'v45 迁移完成');
          }
          if (from < 46) {
            logger.info('DBMigration',
                '开始迁移到 v46: 转账手续费/折损(transactions.fee_amount 等)');
            await _addColumnIfMissing('transactions', 'fee_amount',
                'ALTER TABLE transactions ADD COLUMN fee_amount REAL;');
            await _addColumnIfMissing('transactions', 'fee_label',
                'ALTER TABLE transactions ADD COLUMN fee_label TEXT;');
            await _addColumnIfMissing('transactions', 'discount_amount',
                'ALTER TABLE transactions ADD COLUMN discount_amount REAL;');
            await _addColumnIfMissing('transactions', 'discount_label',
                'ALTER TABLE transactions ADD COLUMN discount_label TEXT;');
            logger.info('DBMigration', 'v46 迁移完成');
          }
          if (from < 47) {
            logger.info('DBMigration',
                '开始迁移到 v47: SwipeSmart 信用卡对照(accounts.swipesmart_card_id)');
            await _addColumnIfMissing('accounts', 'swipesmart_card_id',
                'ALTER TABLE accounts ADD COLUMN swipesmart_card_id TEXT;');
            logger.info('DBMigration', 'v47 迁移完成');
          }
          if (from < 48) {
            logger.info('DBMigration',
                '开始迁移到 v48: 建議分頁回饋學習快取(reward_choice_caches) + 交易排序索引');
            await _createTableIfMissing(
                migrator, 'reward_choice_caches', rewardChoiceCaches);
            await customStatement(
                'CREATE UNIQUE INDEX IF NOT EXISTS idx_reward_choice_caches_key '
                'ON reward_choice_caches(ledger_id, category_id, account_id);');
            // 建議分頁排序查詢 + 既有 note/amount 聚合查詢都是 WHERE ledger_id=?
            // (+type/happened_at)全表掃描,transactions 之前只有 sync_id 索引,
            // 這裡一併補上。
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_transactions_ledger_type_happened '
                'ON transactions(ledger_id, type, happened_at);');
            logger.info('DBMigration', 'v48 迁移完成');
          }
          if (from < 49) {
            logger.info('DBMigration',
                '开始迁移到 v49: 分期付款(installment_plans/installment_periods) + transactions.installment_plan_sync_id');
            await _addColumnIfMissing(
                'transactions',
                'installment_plan_sync_id',
                'ALTER TABLE transactions ADD COLUMN '
                    'installment_plan_sync_id TEXT;');
            await _createTableIfMissing(
                migrator, 'installment_plans', installmentPlans);
            await _createTableIfMissing(
                migrator, 'installment_periods', installmentPeriods);
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_installment_plans_ledger '
                'ON installment_plans(ledger_id);');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_installment_periods_plan '
                'ON installment_periods(plan_sync_id, period_no);');
            logger.info('DBMigration', 'v49 迁移完成');
          }
          if (from < 50) {
            logger.info('DBMigration',
                '开始迁移到 v50: 帳單分期沖銷(installment_plans.offset_breakdown_json)');
            await _addColumnIfMissing(
                'installment_plans',
                'offset_breakdown_json',
                'ALTER TABLE installment_plans ADD COLUMN '
                    'offset_breakdown_json TEXT;');
            logger.info('DBMigration', 'v50 迁移完成');
          }
          if (from < 51) {
            logger.info('DBMigration',
                '开始迁移到 v51: 支出/收入手续费/折扣(transactions.base_amount)');
            await _addColumnIfMissing('transactions', 'base_amount',
                'ALTER TABLE transactions ADD COLUMN base_amount REAL;');
            logger.info('DBMigration', 'v51 迁移完成');
          }
          if (from < 52) {
            // v52:一次性修补「fee/discount 已啟用卻 base_amount 缺失」的
            // 歷史交易。根因:v51 上線前(甚至上線後某些 BeeCount Cloud
            // 歷史寫入路徑)產生的 SyncChange 只帶了 feeAmount/discountAmount
            // 卻漏了 baseAmount 鍵——pull apply 端「缺鍵不覆蓋」語意下
            // base_amount 永遠停在 NULL,使用者只能一筆一筆手動在 web 端重新
            // 觸發「更新交易」才能補回來(見使用者回報,docs/changes/
            // 2026-09-04-sync-base-amount-backfill.md)。這裡直接用必然正確
            // 的 amount 反推(公式對齐 lib/utils/amount_calculator.dart
            // computeBaseAmountFromNet,兩邊不能各自發明),不依賴任何後續同
            // 步事件——sync_engine_apply.dart 的 _applyTransactionChange 已
            // 另外補上同款自愈邏輯擋住未來新進的 pull,這裡只处理遷移當下已
            // 經卡在本地的舊資料。
            logger.info('DBMigration', '开始迁移到 v52: 修补 base_amount 缺失的历史交易');
            await customStatement('''
              UPDATE transactions
              SET base_amount = CASE
                WHEN type = 'expense' THEN
                  ROUND(amount - COALESCE(fee_amount, 0) + COALESCE(discount_amount, 0), 2)
                ELSE
                  ROUND(amount + COALESCE(fee_amount, 0) - COALESCE(discount_amount, 0), 2)
              END
              WHERE base_amount IS NULL
                AND type IN ('expense', 'income')
                AND (COALESCE(fee_amount, 0) != 0 OR COALESCE(discount_amount, 0) != 0);
            ''');
            logger.info('DBMigration', 'v52 迁移完成');
          }
        },
        onCreate: (m) async {
          await m.createAll();
          await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_rate_override_pair '
              'ON exchange_rate_overrides (base_currency, quote_currency);');
          // v48 的兩個索引只在 onUpgrade 建,全新安裝(直接走 onCreate,不會
          // 跑 onUpgrade)漏掉——這裡補建,唯一索引那條同時也是資料正確性
          // 約束(reward_choice_caches 的「類別+帳戶」唯一性),不只是效能。
          await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_reward_choice_caches_key '
              'ON reward_choice_caches(ledger_id, category_id, account_id);');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_transactions_ledger_type_happened '
              'ON transactions(ledger_id, type, happened_at);');
          // v49 的兩個索引只在 onUpgrade 建,全新安裝補建(同上面 v48 的理由)。
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_installment_plans_ledger '
              'ON installment_plans(ledger_id);');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_installment_periods_plan '
              'ON installment_periods(plan_sync_id, period_no);');
        },
      );

  /// Migration helper: 列不存在再 ALTER ADD,避免 partial state 重跑时
  /// "duplicate column" 把启动卡死。
  ///
  /// SQLite DDL 隐式 commit 且不可回滚;上次 onUpgrade 跑到一半失败时,前面
  /// 已成功的 ALTER 已写入文件但 user_version 没更新,下次启动同一段重跑就
  /// 报 duplicate。每条 ALTER 都通过这里走 PRAGMA 检查可幂等。
  Future<void> _addColumnIfMissing(
      String table, String column, String ddl) async {
    final cols = await customSelect("PRAGMA table_info($table)").get();
    final exists = cols.any((r) => r.read<String>('name') == column);
    if (exists) {
      logger.info('DBMigration', '$table.$column 已存在,跳过 ALTER');
      return;
    }
    await customStatement(ddl);
  }

  /// Migration helper: 表不存在再 createTable,避免 partial state 重跑时
  /// "table already exists"。
  Future<void> _createTableIfMissing(
      Migrator m, String tableName, dynamic table) async {
    final row = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      variables: [Variable<String>(tableName)],
    ).getSingleOrNull();
    if (row != null) {
      logger.info('DBMigration', '$tableName 表已存在,跳过 createTable');
      return;
    }
    await m.createTable(table);
  }

  // Seed minimal data
  /// [l10n] 国际化对象，如果为null则使用英文作为默认语言
  /// [currency] 货币代码
  /// [useHierarchicalCategories] 是否使用二级分类
  ///
  /// 注意：此方法只应在真正的首次初始化时调用（欢迎页完成时）
  Future<void> ensureSeed({
    AppLocalizations? l10n,
    String currency = 'CNY',
    bool useHierarchicalCategories = false,
    bool skipCategories = false,
    bool createDefaultLedger = true,
  }) async {
    logger.info('db', 'ensureSeed 被调用');
    logger.info('db', 'l10n 是否提供: ${l10n != null}');
    logger.info('db', '货币: $currency');
    logger.info('db', '使用二级分类: $useHierarchicalCategories');
    logger.info('db', '跳过分类创建: $skipCategories');
    logger.info('db', '创建默认账本: $createDefaultLedger');

    // 如果没有提供l10n，使用Lookup创建默认的英文版本
    final effectiveL10n = l10n ?? lookupAppLocalizations(const Locale('en'));
    logger.info('db', '使用的语言环境: ${l10n != null ? "提供的l10n" : "默认英文"}');

    await SeedService.seedDatabase(
      this,
      effectiveL10n,
      currency: currency,
      useHierarchicalCategories: useHierarchicalCategories,
      skipCategories: skipCategories,
      createDefaultLedger: createDefaultLedger,
    );
    logger.info('db', '数据库初始化完成');
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'beecount.sqlite'));

    // 开发环境：如果检测到锁文件，尝试删除（仅用于调试）
    try {
      final shmFile = File(p.join(dir.path, 'beecount.sqlite-shm'));
      final walFile = File(p.join(dir.path, 'beecount.sqlite-wal'));

      if (shmFile.existsSync() || walFile.existsSync()) {
        logger.warning('db', '检测到 SQLite 临时文件，可能存在锁定');
        // 注意：只在开发环境中记录，不自动删除，因为可能正在使用
      }
    } catch (e) {
      logger.debug('db', '检查锁文件时出错: $e');
    }

    return NativeDatabase.createInBackground(file);
  });
}

/// 开发工具：清除数据库锁文件（仅在应用完全关闭后使用）
Future<void> clearDatabaseLockFiles() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final shmFile = File(p.join(dir.path, 'beecount.sqlite-shm'));
    final walFile = File(p.join(dir.path, 'beecount.sqlite-wal'));

    if (shmFile.existsSync()) {
      await shmFile.delete();
      logger.info('db', '已删除 .sqlite-shm 文件');
    }

    if (walFile.existsSync()) {
      await walFile.delete();
      logger.info('db', '已删除 .sqlite-wal 文件');
    }

    logger.info('db', '数据库锁文件清理完成');
  } catch (e) {
    logger.error('db', '清理锁文件失败', e);
  }
}
