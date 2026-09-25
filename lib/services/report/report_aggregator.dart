/// 統計報表的純聚合邏輯:輸入 [ReportDataset](已篩選的 legs),輸出各分頁
/// 需要的數字。不依賴 Riverpod/Drift/Flutter,可直接單元測試。
///
/// 口徑:
/// - 收入/支出只看 `type == 'income' / 'expense'` 的 legs;轉帳、餘額調整等
///   不計入收支(同舊洞察頁、首頁、帳戶統計)。
/// - 拆帳交易的每筆明細各自是一條 leg,分類統計自然分開;列表/排行顯示時
///   把同一筆交易的 legs 合回一筆,金額 = 命中篩選的 legs 加總。
/// - 維度分頁與排行可切 [ReportFlow]:支出/收入/轉帳/回饋金。回饋金是信用卡
///   回饋規則的估算值(跟回饋明細頁同一份算法),由呼叫端以
///   `{交易 id: 回饋金}` 傳入,這裡只負責按 leg 金額比例分到各維度。
library;

import '../../data/db.dart';
import '../../models/report/report_dataset.dart';
import '../../models/report/report_period.dart';
import '../../utils/month_range.dart';

/// 跟 `CategoryPieChart` 的 `PieCategoryItem`、`CategoryRankRow` 同一個
/// record 形狀(Dart record 是結構型別,可直接互傳)。
typedef ReportCategoryItem = ({
  int? id,
  String name,
  Category? category,
  double total,
  List<({int id, Category category, String name, double total})> subCategories,
});

/// 維度分頁/排行的切換項目。
abstract final class ReportFlow {
  static const expense = 'expense';
  static const income = 'income';
  static const transfer = 'transfer';
  static const reward = 'reward';
  static const all = [expense, income, transfer, reward];
}

class ReportSummary {
  final double income;
  final double expense;
  final int incomeCount;
  final int expenseCount;

  /// 轉帳(`type == 'transfer'`,不含餘額調整)金額與筆數。
  final double transfer;
  final int transferCount;

  /// 所有類型(含轉帳)的交易筆數。
  final int txCount;

  const ReportSummary({
    required this.income,
    required this.expense,
    required this.incomeCount,
    required this.expenseCount,
    required this.txCount,
    this.transfer = 0,
    this.transferCount = 0,
  });

  double get balance => income - expense;

  double amountFor(String flow) => switch (flow) {
        ReportFlow.income => income,
        ReportFlow.transfer => transfer,
        _ => expense,
      };
}

class ReportSeriesPoint {
  final DateTime bucket;
  final double value;
  const ReportSeriesPoint(this.bucket, this.value);
}

enum ReportDimension {
  account,
  accountGroup,
  project,
  name,
  merchant,
  tag,
  counterparty,
}

class DimensionRow {
  /// null =「(無)」/「未分組」。
  final String? key;

  /// 顯示名稱;[key] 為 null 或實體已刪除時為 null,由 UI 補文案。
  final String? label;
  double expense = 0;
  double income = 0;
  double transferIn = 0;
  double transferOut = 0;

  /// 轉帳金額:帳戶/帳戶分組 = 轉入 + 轉出;其他維度 = 該維度值的轉帳合計。
  double transfer = 0;

  /// 估算回饋金(見 [ReportAggregator.byDimension] 的 rewards)。
  double reward = 0;
  final Set<int> expenseTx = {};
  final Set<int> incomeTx = {};
  final Set<int> transferTx = {};
  final Set<int> rewardTx = {};

  DimensionRow(this.key, this.label);

  double amountFor(String flow) => switch (flow) {
        ReportFlow.income => income,
        ReportFlow.transfer => transfer,
        ReportFlow.reward => reward,
        _ => expense,
      };
  int countFor(String flow) => switch (flow) {
        ReportFlow.income => incomeTx.length,
        ReportFlow.transfer => transferTx.length,
        ReportFlow.reward => rewardTx.length,
        _ => expenseTx.length,
      };
}

class RankedTx {
  final ReportTxView view;
  final double amount;
  const RankedTx(this.view, this.amount);
}

class ReportAggregator {
  final ReportDataset ds;

  ReportAggregator(this.ds);

  static bool _isFlow(String type) => type == 'expense' || type == 'income';

  ReportSummary summary() {
    double income = 0, expense = 0, transfer = 0;
    final incomeTx = <int>{}, expenseTx = <int>{}, all = <int>{};
    final transferTx = <int>{};
    for (final e in ds.entries) {
      all.add(e.tx.id);
      if (e.type == 'transfer') {
        transfer += e.amount;
        transferTx.add(e.tx.id);
      }
      // 退款沖銷 leg 只扣金額,不算進收入/支出筆數。
      if (e.type == 'income') {
        income += e.amount;
        if (!e.isRefund) incomeTx.add(e.tx.id);
      } else if (e.type == 'expense') {
        expense += e.amount;
        if (!e.isRefund) expenseTx.add(e.tx.id);
      }
    }
    return ReportSummary(
      income: income,
      expense: expense,
      incomeCount: incomeTx.length,
      expenseCount: expenseTx.length,
      txCount: all.length,
      transfer: transfer,
      transferCount: transferTx.length,
    );
  }

  /// 這條 leg 分到的回饋金:只有非退款的支出 leg 有,按 leg 金額佔整筆交易
  /// 金額的比例分攤(拆帳且被篩選時只算命中的明細)。
  static double rewardShare(ReportEntry e, Map<int, double> rewards) {
    if (e.type != 'expense' || e.isRefund) return 0;
    final r = rewards[e.tx.id];
    if (r == null || r == 0) return 0;
    final whole = (e.tx.nativeAmount ?? e.tx.amount).abs();
    return whole == 0 ? r : r * e.amount / whole;
  }

  /// 篩選後的估算回饋金合計。
  double rewardTotal(Map<int, double> rewards) =>
      ds.entries.fold(0.0, (a, e) => a + rewardShare(e, rewards));

  /// 一級分類排行(二級分類併入父分類並保留明細),金額降序。移植自舊
  /// `analytics_page.dart::_aggregateTopLevelCategories`,差別:父分類查不到的
  /// 二級分類改當成一級分類自己成一列,不再被靜默丟掉。
  List<ReportCategoryItem> categoryHierarchy(String type) {
    final byCategory = <int?, double>{};
    for (final e in ds.entries) {
      if (e.type != type) continue;
      byCategory.update(e.categoryId, (v) => v + e.amount,
          ifAbsent: () => e.amount);
    }

    final topTotals = <int?, double>{};
    final subs = <int?,
        List<({int id, Category category, String name, double total})>>{};
    for (final kv in byCategory.entries) {
      final id = kv.key;
      final c = id == null ? null : ds.categories[id];
      final parent = (c != null && c.level >= 2 && c.parentId != null)
          ? ds.categories[c.parentId!]
          : null;
      if (c == null) {
        topTotals.update(null, (v) => v + kv.value, ifAbsent: () => kv.value);
      } else if (parent != null) {
        topTotals.update(parent.id, (v) => v + kv.value,
            ifAbsent: () => kv.value);
        subs
            .putIfAbsent(parent.id, () => [])
            .add((id: c.id, category: c, name: c.name, total: kv.value));
      } else {
        topTotals.update(c.id, (v) => v + kv.value, ifAbsent: () => kv.value);
      }
    }
    for (final list in subs.values) {
      list.sort((a, b) => b.total.compareTo(a.total));
    }
    final out = <ReportCategoryItem>[
      for (final kv in topTotals.entries)
        (
          id: kv.key,
          name:
              kv.key == null ? '未分类' : (ds.categories[kv.key!]?.name ?? '未分类'),
          category: kv.key == null ? null : ds.categories[kv.key!],
          total: kv.value,
          subCategories: subs[kv.key] ??
              const <({
                int id,
                Category category,
                String name,
                double total
              })>[],
        ),
    ]..sort((a, b) => b.total.compareTo(a.total));
    return out;
  }

  /// 趨勢序列。[type] = expense / income / balance。[openStart] 時從第一筆
  /// 資料所在的桶開始(避免「全部」從 1970 年畫起)。
  List<ReportSeriesPoint> series({
    required String type,
    required ReportGranularity granularity,
    required DateTime start,
    required DateTime end,
    int monthStartDay = 1,
    bool openStart = false,
  }) {
    DateTime bucketOf(DateTime d) {
      switch (granularity) {
        case ReportGranularity.day:
          return DateTime(d.year, d.month, d.day);
        case ReportGranularity.month:
          return labelForDate(d, monthStartDay);
        case ReportGranularity.year:
          return DateTime(labelForDate(d, monthStartDay).year, 1, 1);
      }
    }

    DateTime next(DateTime b) {
      switch (granularity) {
        case ReportGranularity.day:
          return DateTime(b.year, b.month, b.day + 1);
        case ReportGranularity.month:
          return DateTime(b.year, b.month + 1, 1);
        case ReportGranularity.year:
          return DateTime(b.year + 1, 1, 1);
      }
    }

    final sums = <DateTime, double>{};
    DateTime? earliest;
    for (final e in ds.entries) {
      if (!_isFlow(e.type)) continue;
      double v;
      if (type == 'balance') {
        v = e.type == 'income' ? e.amount : -e.amount;
      } else if (e.type == type) {
        v = e.amount;
      } else {
        continue;
      }
      final b = bucketOf(e.at);
      sums.update(b, (x) => x + v, ifAbsent: () => v);
      if (earliest == null || b.isBefore(earliest)) earliest = b;
    }

    var first = bucketOf(start);
    if (openStart) {
      if (earliest == null) return const [];
      if (earliest.isAfter(first)) first = earliest;
    }
    final lastDay = DateTime(end.year, end.month, end.day - 1);
    final last = bucketOf(lastDay);
    final out = <ReportSeriesPoint>[];
    for (var b = first; !b.isAfter(last); b = next(b)) {
      out.add(ReportSeriesPoint(b, sums[b] ?? 0));
      if (out.length > 5000) break; // 防呆:異常區間不要無限展開
    }
    return out;
  }

  String? _labelFor(ReportDimension d, String key) {
    switch (d) {
      case ReportDimension.account:
      case ReportDimension.accountGroup:
        return ds.accountsByKey[key]?.name;
      case ReportDimension.project:
        return ds.projectsByKey[key]?.name;
      case ReportDimension.tag:
        return ds.tagsByKey[key]?.name;
      case ReportDimension.name:
      case ReportDimension.merchant:
      case ReportDimension.counterparty:
        return key;
    }
  }

  /// 帳戶 key → 帳戶分組 key(主帳戶 account_group 的 key);未歸組 → null。
  String? groupOf(String? accountKey) {
    if (accountKey == null) return null;
    final a = ds.accountsByKey[accountKey];
    if (a == null) return null;
    final parent = a.parentAccountId;
    if (parent != null && parent.isNotEmpty) return parent;
    if (a.type == 'account_group') return accountKey;
    return null;
  }

  /// 依維度分組。標籤是多值:一筆交易有兩個標籤就兩列都算(各列加總可能
  /// 大於總額)。[rewards] = `{交易 id: 估算回饋金}`,沒傳時回饋金都是 0。
  List<DimensionRow> byDimension(ReportDimension d,
      {Map<int, double> rewards = const {}}) {
    final rows = <String?, DimensionRow>{};
    DimensionRow rowFor(String? key) => rows.putIfAbsent(
        key, () => DimensionRow(key, key == null ? null : _labelFor(d, key)));

    for (final e in ds.entries) {
      final flow = _isFlow(e.type);
      if (d == ReportDimension.account || d == ReportDimension.accountGroup) {
        String? keyOf(String? acc) =>
            d == ReportDimension.account ? acc : groupOf(acc);
        if (flow) {
          final r = rowFor(keyOf(e.accountKey));
          _addFlow(r, e, rewardShare(e, rewards));
        } else if (e.type == 'transfer') {
          final from = rowFor(keyOf(e.accountKey));
          from.transferOut += e.amount;
          from.transfer += e.amount;
          from.transferTx.add(e.tx.id);
          if (e.toAccountKey != null) {
            final to = rowFor(keyOf(e.toAccountKey));
            to.transferIn += e.amount;
            to.transfer += e.amount;
            to.transferTx.add(e.tx.id);
          }
        }
        continue;
      }
      if (!flow && e.type != 'transfer') continue;
      final reward = rewardShare(e, rewards);
      switch (d) {
        case ReportDimension.project:
          _addFlow(rowFor(e.projectKey), e, reward);
        case ReportDimension.name:
          _addFlow(rowFor(e.name), e, reward);
        case ReportDimension.merchant:
          _addFlow(rowFor(e.merchant), e, reward);
        case ReportDimension.counterparty:
          _addFlow(rowFor(e.counterparty), e, reward);
        case ReportDimension.tag:
          if (e.tagKeys.isEmpty) {
            _addFlow(rowFor(null), e, reward);
          } else {
            for (final k in e.tagKeys) {
              _addFlow(rowFor(k), e, reward);
            }
          }
        case ReportDimension.account:
        case ReportDimension.accountGroup:
          break;
      }
    }
    return rows.values.toList();
  }

  /// 下鑽用:某個維度值、某個 [flow] 命中哪些 legs(跟 [byDimension] 的分組
  /// 規則一致)。回饋金只列有回饋的支出([rewards] 裡金額非 0 的交易)。
  bool Function(ReportEntry e) dimensionPredicate(
    ReportDimension d,
    String? key, {
    String flow = ReportFlow.expense,
    Map<int, double> rewards = const {},
  }) {
    bool flowMatch(ReportEntry e) => switch (flow) {
          ReportFlow.transfer => e.type == 'transfer',
          ReportFlow.reward => rewardShare(e, rewards) != 0,
          _ => e.type == flow,
        };
    final bool Function(ReportEntry e) keyMatch;
    switch (d) {
      case ReportDimension.account:
        keyMatch = (e) =>
            e.accountKey == key ||
            (e.type == 'transfer' && e.toAccountKey == key);
      case ReportDimension.accountGroup:
        keyMatch = (e) =>
            groupOf(e.accountKey) == key ||
            (e.type == 'transfer' &&
                e.toAccountKey != null &&
                groupOf(e.toAccountKey) == key);
      case ReportDimension.project:
        keyMatch = (e) => e.projectKey == key;
      case ReportDimension.name:
        keyMatch = (e) => e.name == key;
      case ReportDimension.merchant:
        keyMatch = (e) => e.merchant == key;
      case ReportDimension.counterparty:
        keyMatch = (e) => e.counterparty == key;
      case ReportDimension.tag:
        keyMatch =
            (e) => key == null ? e.tagKeys.isEmpty : e.tagKeys.contains(key);
    }
    return (e) => flowMatch(e) && keyMatch(e);
  }

  static void _addFlow(DimensionRow r, ReportEntry e, double reward) {
    if (e.type == 'income') {
      r.income += e.amount;
      r.incomeTx.add(e.tx.id);
    } else if (e.type == 'expense') {
      r.expense += e.amount;
      r.expenseTx.add(e.tx.id);
    } else if (e.type == 'transfer') {
      r.transfer += e.amount;
      r.transferTx.add(e.tx.id);
    }
    if (reward != 0) {
      r.reward += reward;
      r.rewardTx.add(e.tx.id);
    }
  }

  /// 指定 [flow] 的交易(合併拆帳 legs),依金額排序。退款單不列入排行;
  /// 回饋金排行的金額是估算回饋金(見 [rewardShare])。
  List<RankedTx> rankedTransactions(String flow,
      {bool ascending = false, Map<int, double> rewards = const {}}) {
    final sums = <int, double>{};
    for (final e in ds.entries) {
      if (e.isRefund) continue;
      final double v;
      if (flow == ReportFlow.reward) {
        v = rewardShare(e, rewards);
        if (v == 0) continue;
      } else {
        if (e.type != flow) continue;
        v = e.amount;
      }
      sums.update(e.tx.id, (x) => x + v, ifAbsent: () => v);
    }
    final out = <RankedTx>[
      for (final kv in sums.entries)
        if (ds.txViews[kv.key] != null) RankedTx(ds.txViews[kv.key]!, kv.value),
    ]..sort((a, b) => ascending
        ? a.amount.compareTo(b.amount)
        : b.amount.compareTo(a.amount));
    return out;
  }

  /// 命中條件的交易(至少一條 leg 命中),依時間新→舊。
  List<ReportTxView> transactions([bool Function(ReportEntry e)? where]) {
    final seen = <int>{};
    final out = <ReportTxView>[];
    for (final e in ds.entries) {
      if (where != null && !where(e)) continue;
      if (!seen.add(e.tx.id)) continue;
      final v = ds.txViews[e.tx.id];
      if (v != null) out.add(v);
    }
    out.sort((a, b) => b.t.happenedAt.compareTo(a.t.happenedAt));
    return out;
  }
}
