import 'ledger_repository.dart';
import 'transaction_repository.dart';
import 'category_repository.dart';
import 'account_repository.dart';
import 'statistics_repository.dart';
import 'recurring_rule_repository.dart';
import 'ai_repository.dart';
import 'tag_repository.dart';
import 'budget_repository.dart';
import 'attachment_repository.dart';
import 'exchange_rate_repository.dart';
import 'card_reward_rule_repository.dart';
import 'debt_repository.dart';
import 'project_repository.dart';
import 'reward_choice_cache_repository.dart';

/// 基础 Repository 抽象类
/// 组合所有 Repository 接口，用于类型约束
/// LocalRepository、CloudRepository、ApiRepository 等都应该实现这个抽象类
///
/// 设计原则：
/// - 不包含任何具体实现细节（如数据库访问）
/// - 仅定义数据访问的抽象接口
/// - 支持无缝切换不同的数据源实现
abstract class BaseRepository
    implements
        LedgerRepository,
        TransactionRepository,
        CategoryRepository,
        AccountRepository,
        StatisticsRepository,
        RecurringRuleRepository,
        AIRepository,
        TagRepository,
        BudgetRepository,
        AttachmentRepository,
        ExchangeRateRepository,
        CardRewardRuleRepository,
        DebtRepository,
        ProjectRepository,
        RewardChoiceCacheRepository {
  // -------------------------------------------------------------------
  // v30 交易级多币种(.docs/multi-currency-ledger):重算 / 检测。
  // 声明在聚合层而非 TransactionRepository:这些方法要同时访问交易表与
  // 有效汇率(ExchangeRateRepository),交易子仓拿不到汇率。
  // -------------------------------------------------------------------

  /// 本位币变更后全量重算该账本交易的 nativeAmount(用当前有效汇率,历史
  /// 汇率不可得)。逐笔记 change(L13:不记则云端投影永远旧值、full_pull 会
  /// 把重算成果冲回)。返回实际改动条数。
  Future<int> recalcNativeAmountsForLedger(int ledgerId, String newBase);

  /// 存量补折算(L11):只重算「currencyCode≠本位币 且 nativeAmount==amount」
  /// 的外币交易(迁移回填后从没折算过的)。缺汇率的跳过留待用户。逐笔记 change。
  /// 返回实际改动条数。
  Future<int> recomputeForeignTxForLedger(int ledgerId);

  /// 检测:该账本「未折算外币交易」条数(currencyCode≠本位币 且
  /// nativeAmount==amount;currency_code IS NULL 的行 join 账户币种兜底判定)。
  /// 统计页横幅按 >0 显示。
  Future<int> countUnconvertedForeignTx(int ledgerId);

  /// 该账本外币交易条数(currencyCode≠本位币,含已折算)。统计页折算脚注
  /// 按 >0 显示(01 §五:「含外币,已按各笔记账时汇率折算为 {本位币}」)。
  Future<int> countForeignCurrencyTx(int ledgerId);

  /// 该账本交易涉及的全部外币币种集合(重算前并入汇率拉取 extraQuotes)。
  Future<Set<String>> getLedgerForeignCurrencies(int ledgerId);

  /// 按 picker 账户 id 解析币种:正数=主表账户;负数=共享账本 synthetic id。
  Future<String?> getAccountCurrencyByAnyId(int accountId);

  // -------------------------------------------------------------------
  // v44 專案功能上線遷移:分類預算 → 專案的歷史交易回填。聲明在聚合層
  // (而非 ProjectRepository)——理由同 recalcNativeAmountsForLedger:
  // 同時要碰 Transactions 與 changeTracker,子仓库拿不到 changeTracker。
  // -------------------------------------------------------------------

  /// 把 [ledgerId] 底下、`categoryId=[categoryId]`、`type='expense'`、且
  /// 目前 `projectSyncId IS NULL` 的交易,批次(最多 [limit] 筆)設定
  /// `projectSyncId=[projectSyncId]`。單一 db.transaction() 包一批,逐筆記
  /// change(理由同 recalcNativeAmountsForLedger)。呼叫端
  /// (ProjectMigrationService)應該迴圈呼叫直到回傳 0——已回填過的行因
  /// `projectSyncId IS NULL` 條件自然被排除,不需要額外的 offset 追蹤。
  /// 回傳實際改動的筆數。
  Future<int> backfillProjectForCategoryBatch({
    required int ledgerId,
    required int categoryId,
    required String projectSyncId,
    required int limit,
  });
}
