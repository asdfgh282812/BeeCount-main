import '../../data/db.dart';
import 'report_filter.dart';

/// 交易列表元件(`TransactionList`)吃的 record 形狀。
typedef ReportTxView = ({
  Transaction t,
  Category? category,
  Account? account,
  Account? toAccount,
});

/// 載入報表資料集的查詢條件,同時是 provider family 的 cache key。
class ReportQuery {
  final int ledgerId;

  /// 半開區間 [start, end)。
  final DateTime start;
  final DateTime end;
  final ReportFilter filter;

  const ReportQuery({
    required this.ledgerId,
    required this.start,
    required this.end,
    this.filter = ReportFilter.none,
  });

  @override
  bool operator ==(Object other) =>
      other is ReportQuery &&
      other.ledgerId == ledgerId &&
      other.start == start &&
      other.end == end &&
      other.filter == filter;

  @override
  int get hashCode => Object.hash(ledgerId, start, end, filter);
}

/// 聚合的最小單位:一般交易一筆 = 一條 leg;拆帳交易每筆明細各一條 leg
/// (分類不同、金額按本位幣折算比例縮放),其餘欄位沿用父交易。所有分頁都
/// 從同一份 leg 清單算出來,口徑自然一致。
class ReportEntry {
  final Transaction tx;

  /// 統計方向:expense / income / transfer / adjustment ...。一般交易同
  /// [Transaction.type];退款單是反方向(收入型退款 → expense,金額為負),
  /// 見 `utils/refund_netting.dart`。
  final String type;

  /// 本位幣金額(已按拆帳比例縮放)。一般交易為正;退款沖銷 leg 為負。
  final double amount;

  /// happenedAt 轉本地時間。
  final DateTime at;

  /// 分類 id:本地分類是正數,共享帳本 Owner 分類是 synthetic 負數,null =
  /// 未分類。可直接查 [ReportDataset.categories]。
  final int? categoryId;

  /// 自己 + 父分類的 key(篩選「選一級分類 = 含子分類」用)。
  final List<String> categoryKeys;

  final String? accountKey;
  final String? toAccountKey;
  final String? projectKey;

  /// 名稱(= 記帳表單的名稱欄,實際存 [Transaction.note]),已 trim,空字串
  /// 轉 null。
  final String? name;
  final String? merchant;

  /// 對象(欠款的 counterpartyName)。
  final String? counterparty;
  final List<String> tagKeys;
  final bool isSplitLeg;

  /// 退款沖銷 leg(`tx.refundOfSyncId` 非空):[type] 已翻成反方向、[amount]
  /// 為負。排行/筆數不算它。
  final bool isRefund;

  const ReportEntry({
    required this.tx,
    required this.type,
    required this.amount,
    required this.at,
    required this.categoryId,
    required this.categoryKeys,
    required this.accountKey,
    required this.toAccountKey,
    required this.projectKey,
    required this.name,
    required this.merchant,
    required this.counterparty,
    required this.tagKeys,
    this.isSplitLeg = false,
    this.isRefund = false,
  });

  /// 套用篩選。金額範圍比對整筆交易,不是明細。
  bool matches(ReportFilter f) {
    if (!f.recordTypes.contains(reportRecordTypeGroup(type))) return false;
    if (f.accounts.isActive &&
        !f.accounts.matchesAny([
          if (accountKey != null) accountKey!,
          if (toAccountKey != null) toAccountKey!,
        ])) {
      return false;
    }
    if (!f.projects.matchesSingle(projectKey)) return false;
    if (!f.categories.matchesAny(categoryKeys)) return false;
    if (!f.tags.matchesAny(tagKeys)) return false;
    if (!f.counterparties.matchesSingle(counterparty)) return false;
    if (!f.names.matchesSingle(name)) return false;
    if (!f.merchants.matchesSingle(merchant)) return false;
    if (f.hasAmountRange) {
      final whole = (tx.nativeAmount ?? tx.amount).abs();
      if (f.minAmount != null && whole < f.minAmount!) return false;
      if (f.maxAmount != null && whole > f.maxAmount!) return false;
    }
    return true;
  }
}

/// 報表資料集:篩選後的 legs + 渲染需要的實體索引。
class ReportDataset {
  final List<ReportEntry> entries;

  /// 交易 id → 列表元件用的 record(分類/帳戶已解析,含共享帳本 synthetic)。
  final Map<int, ReportTxView> txViews;

  /// 本地分類 + 共享帳本 synthetic 分類(負 id)。
  final Map<int, Category> categories;
  final Map<String, Account> accountsByKey;
  final Map<String, Tag> tagsByKey;
  final Map<String, Project> projectsByKey;

  const ReportDataset({
    required this.entries,
    required this.txViews,
    required this.categories,
    required this.accountsByKey,
    required this.tagsByKey,
    required this.projectsByKey,
  });

  static const empty = ReportDataset(
    entries: [],
    txViews: {},
    categories: {},
    accountsByKey: {},
    tagsByKey: {},
    projectsByKey: {},
  );
}

/// 篩選器可選項目。[key] 跟 [ReportEntry] 上的 key 同一套(見
/// `reportEntityKey`),[indent] = 1 表示子項目(二級分類 / 主帳戶下的子卡)。
class ReportFilterOption {
  final String key;
  final String label;

  /// 分段標題(分類的支出/收入)。
  final String? section;
  final int indent;

  const ReportFilterOption(this.key, this.label,
      {this.section, this.indent = 0});
}

class ReportFilterOptions {
  final List<ReportFilterOption> accounts;
  final List<ReportFilterOption> projects;
  final List<ReportFilterOption> categories;
  final List<ReportFilterOption> tags;
  final List<ReportFilterOption> counterparties;
  final List<ReportFilterOption> names;
  final List<ReportFilterOption> merchants;

  /// 一級分類 key → 子分類 key,勾父分類時編輯器一併勾子分類的顯示用。
  final Map<String, List<String>> childCategoryKeys;

  const ReportFilterOptions({
    required this.accounts,
    required this.projects,
    required this.categories,
    required this.tags,
    required this.counterparties,
    required this.names,
    required this.merchants,
    required this.childCategoryKeys,
  });
}
