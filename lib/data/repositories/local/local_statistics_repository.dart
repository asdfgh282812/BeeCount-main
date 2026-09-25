import 'dart:math' as math;

import 'package:drift/drift.dart' as d;

import '../../db.dart';
import '../../../utils/month_range.dart';
import '../../../utils/refund_netting.dart';
import '../../../utils/shared_ledger_picker_filter.dart';
import '../statistics_repository.dart';
import '../../../models/report/report_dataset.dart';
import 'local_report_loader.dart';

typedef _CategoryInfo = ({
  int? id,
  String name,
  String? icon,
  int? parentId,
  int level,
});

/// 本地统计Repository实现
/// 基于 Drift 数据库实现
///
/// 退款沖銷(2026-09-25,docs/changes/2026-09-25-refund-netting.md):所有
/// 收支口徑的方法都把退款單當成反方向的負值(見 [statFlowOf]),分類歸屬
/// 扣回原交易的分類;原交易本身不計入統計(excludeFromStats)時退款也跳過。
class LocalStatisticsRepository implements StatisticsRepository {
  final BeeDatabase db;

  LocalStatisticsRepository(this.db);

  static const _uncategorized =
      (id: null, name: '未分类', icon: null, parentId: null, level: 1);

  @override
  Future<List<({int? id, String name, String? icon, double total})>>
      totalsByCategory({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final legs = await _categoryLegs(
        ledgerId: ledgerId, type: type, start: start, end: end);
    final map = <int?, double>{};
    final info = <int?, _CategoryInfo>{};
    for (final l in legs) {
      info[l.category.id] = l.category;
      map.update(l.category.id, (v) => v + l.amount, ifAbsent: () => l.amount);
    }
    return map.entries
        .map((e) => (
              id: e.key,
              name: info[e.key]?.name ?? '未分类',
              icon: info[e.key]?.icon,
              total: e.value,
            ))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
  }

  @override
  Future<
      List<
          ({
            int? id,
            String name,
            String? icon,
            int? parentId,
            int level,
            double total
          })>> totalsByCategoryWithHierarchy({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final legs = await _categoryLegs(
        ledgerId: ledgerId, type: type, start: start, end: end);
    final map = <int?, double>{};
    final info = <int?, _CategoryInfo>{};
    for (final l in legs) {
      info[l.category.id] = l.category;
      map.update(l.category.id, (v) => v + l.amount, ifAbsent: () => l.amount);
    }
    return map.entries.map((e) {
      final c = info[e.key]!;
      return (
        id: e.key,
        name: c.name,
        icon: c.icon,
        parentId: c.parentId,
        level: c.level,
        total: e.value,
      );
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
  }

  /// [totalsByCategory]/[totalsByCategoryWithHierarchy] 共用:把區間內計入
  /// [type] 統計的交易展開成 (分類, 帶正負號金額) legs。
  /// - 拆帳交易:每筆明細一條 leg,金額按 nativeAmount/amount 折算比例縮放;
  ///   查不到明細就不貢獻金額(v38 起的既有口徑)。
  /// - 本地分類查不到時用 categorySyncIdOverride 對共享帳本 Owner 分類
  ///   (synthetic 負 id)兜底。
  /// - 退款單:負值,分類扣回原交易的分類(原交易有拆帳就按明細比例分攤);
  ///   查不到原交易才用退款單自己的分類。
  Future<List<({_CategoryInfo category, double amount})>> _categoryLegs({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = await (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.type.isIn(statTypesFor(type)) &
              t.excludeFromStats.equals(false) &
              t.happenedAt.isBiggerOrEqualValue(start) &
              t.happenedAt.isSmallerThanValue(end)))
        .get();
    final targets = await _loadRefundTargets(ledgerId, rows);
    final shared = await _loadSharedCategoriesForLedger(ledgerId);
    final catsById = {
      for (final c in await db.select(db.categories).get()) c.id: c,
    };
    // v38 拆帳:批量预抓(含退款原交易的)明細,避免逐笔 await。
    final splitsByTx = await _loadSplitsForTransactions([
      for (final t in [...rows, ...targets.values])
        if (t.hasSplits) t.id
    ]);

    final out = <({_CategoryInfo category, double amount})>[];
    void spread(Transaction src, double total, {required bool scaleByRatio}) {
      if (src.hasSplits) {
        final splits = splitsByTx[src.id] ?? const <TransactionSplit>[];
        if (scaleByRatio) {
          final native = src.nativeAmount ?? src.amount;
          final ratio = src.amount == 0 ? 1.0 : native / src.amount;
          final sign = total < 0 ? -1.0 : 1.0;
          for (final s in splits) {
            out.add((
              category: _resolveCategory(
                  s.categoryId, s.categorySyncIdOverride, shared, catsById),
              amount: sign * s.amount * ratio,
            ));
          }
          return;
        }
        // 退款扣回原交易:按原交易明細的比例分攤退款金額。
        final base = splits.fold<double>(0, (a, s) => a + s.amount);
        if (splits.isNotEmpty && base != 0) {
          for (final s in splits) {
            out.add((
              category: _resolveCategory(
                  s.categoryId, s.categorySyncIdOverride, shared, catsById),
              amount: total * s.amount / base,
            ));
          }
          return;
        }
        out.add((category: _uncategorized, amount: total));
        return;
      }
      out.add((
        category: _resolveCategory(
            src.categoryId, src.categorySyncIdOverride, shared, catsById),
        amount: total,
      ));
    }

    for (final t in rows) {
      final signed = _signedAmount(t, type, targets);
      if (signed == null) continue;
      final target = signed < 0 ? targets[t.refundOfSyncId] : null;
      if (target != null) {
        spread(target, signed, scaleByRatio: false);
      } else {
        spread(t, signed, scaleByRatio: true);
      }
    }
    return out;
  }

  /// 這筆交易在 [flow] 統計下的帶正負號本位幣金額;不計入 → null。退款單
  /// 的原交易本身不計入統計時,退款也不計入(不然會憑空多出一筆負數)。
  double? _signedAmount(
      Transaction t, String flow, Map<String, Transaction> targets) {
    final f = statFlowOf(t.type, t.refundOfSyncId);
    if (f == null || f.flow != flow) return null;
    if (f.sign < 0 && (targets[t.refundOfSyncId]?.excludeFromStats ?? false)) {
      return null;
    }
    return f.sign * (t.nativeAmount ?? t.amount);
  }

  /// 批次查一批交易裡退款單指向的原交易(同帳本,不限日期——退款常常跟原
  /// 交易不在同一期),key = 原交易 syncId。
  Future<Map<String, Transaction>> _loadRefundTargets(
      int ledgerId, Iterable<Transaction> txs) async {
    final ids = {
      for (final t in txs)
        if (isRefundOf(t.refundOfSyncId)) t.refundOfSyncId!
    }.toList();
    if (ids.isEmpty) return const {};
    final out = <String, Transaction>{};
    for (var i = 0; i < ids.length; i += 500) {
      final part = ids.sublist(i, math.min(i + 500, ids.length));
      final found = await (db.select(db.transactions)
            ..where((t) => t.ledgerId.equals(ledgerId) & t.syncId.isIn(part)))
          .get();
      for (final o in found) {
        out[o.syncId!] = o;
      }
    }
    return out;
  }

  /// v38 拆帳:批量抓一批交易 id 的拆帳明細(只需传 hasSplits=true 的 id),
  /// 減少逐筆 await 造成的 N+1。
  Future<Map<int, List<TransactionSplit>>> _loadSplitsForTransactions(
      List<int> hasSplitsIds) async {
    if (hasSplitsIds.isEmpty) return const {};
    final map = <int, List<TransactionSplit>>{};
    for (var i = 0; i < hasSplitsIds.length; i += 500) {
      final part =
          hasSplitsIds.sublist(i, math.min(i + 500, hasSplitsIds.length));
      final rows = await (db.select(db.transactionSplits)
            ..where((s) => s.transactionId.isIn(part)))
          .get();
      for (final s in rows) {
        map.putIfAbsent(s.transactionId, () => []).add(s);
      }
    }
    return map;
  }

  /// 反查分类 id/name/icon/parentId/level:本地 categoryId 优先,查无再看
  /// categorySyncIdOverride(共享账本 Owner 分类,synthetic 负 id)兜底,
  /// 再查无就算未分类。交易主表与拆帳明細共用。
  _CategoryInfo _resolveCategory(
    int? categoryId,
    String? overrideSyncId,
    Map<String, SharedLedgerCategory> shared,
    Map<int, Category> catsById,
  ) {
    if (categoryId != null) {
      final c = catsById[categoryId];
      if (c != null) {
        return (
          id: c.id,
          name: c.name,
          icon: c.icon,
          parentId: c.parentId,
          level: c.level,
        );
      }
    }
    if (overrideSyncId != null) {
      final sh = shared[overrideSyncId];
      if (sh != null) {
        final pSyncId = sh.parentSyncId;
        return (
          id: syntheticIdForSyncId(sh.syncId),
          name: sh.name,
          icon: sh.icon,
          // §7 二级分类 hierarchy:父分类 syncId 转 synthetic 负 id,让
          // analytics 的 L2→L1 rollup 正确累加。
          parentId: (pSyncId != null && pSyncId.isNotEmpty)
              ? syntheticIdForSyncId(pSyncId)
              : null,
          level: sh.level,
        );
      }
    }
    return _uncategorized;
  }

  /// 加载当前账本的 SharedLedger 分类索引(by syncId)。单人账本返回空 map,
  /// 共享账本返回 Owner user-global 的镜像。
  Future<Map<String, SharedLedgerCategory>> _loadSharedCategoriesForLedger(
      int ledgerId) async {
    final ledger = await (db.select(db.ledgers)
          ..where((l) => l.id.equals(ledgerId)))
        .getSingleOrNull();
    final syncId = ledger?.syncId;
    if (syncId == null || syncId.isEmpty) return const {};
    final rows = await (db.select(db.sharedLedgerCategories)
          ..where((t) => t.ledgerSyncId.equals(syncId)))
        .get();
    return {for (final r in rows) r.syncId: r};
  }

  @override
  Future<Map<int, Category>> getSharedSyntheticCategoriesForLedger(
      int ledgerId) async {
    final shared = await _loadSharedCategoriesForLedger(ledgerId);
    if (shared.isEmpty) return const {};
    return {
      for (final s in shared.values)
        syntheticIdForSyncId(s.syncId): Category(
          id: syntheticIdForSyncId(s.syncId),
          name: s.name,
          kind: s.kind,
          icon: s.icon,
          sortOrder: s.sortOrder,
          // §7 二级分类 hierarchy:转 synthetic 父 id,让 analytics 的
          // L2→L1 rollup 找到 SharedLedger* 父分类(主表查不到这些 negative id)。
          parentId: (s.parentSyncId != null && s.parentSyncId!.isNotEmpty)
              ? syntheticIdForSyncId(s.parentSyncId!)
              : null,
          level: s.level,
          iconType: s.iconType,
          customIconPath: s.iconType == 'custom' && s.iconCloudSha256 != null
              ? 'custom_icons/shared_${s.iconCloudSha256}.png'
              : null,
          communityIconId: null,
          syncId: s.syncId,
        )
    };
  }

  /// [totalsByDay]/[totalsByMonth]/[totalsByYearSeries] 共用:撈計入 [type]
  /// 統計的交易(含反向類型裡的退款單),回傳 (本地時間, 帶正負號金額)。
  Future<List<({DateTime at, double amount})>> _signedRows({
    required int ledgerId,
    required String type,
    DateTime? start,
    DateTime? end,
  }) async {
    final rows = await (db.select(db.transactions)
          ..where((t) {
            var w = t.ledgerId.equals(ledgerId) &
                t.type.isIn(statTypesFor(type)) &
                t.excludeFromStats.equals(false);
            if (start != null) w = w & t.happenedAt.isBiggerOrEqualValue(start);
            if (end != null) w = w & t.happenedAt.isSmallerThanValue(end);
            return w;
          }))
        .get();
    final targets = await _loadRefundTargets(ledgerId, rows);
    return [
      for (final t in rows)
        if (_signedAmount(t, type, targets) case final v?)
          (at: t.happenedAt.toLocal(), amount: v),
    ];
  }

  @override
  Future<List<({DateTime day, double total})>> totalsByDay({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = await _signedRows(
        ledgerId: ledgerId, type: type, start: start, end: end);
    final map = <DateTime, double>{};
    for (final r in rows) {
      final day = DateTime(r.at.year, r.at.month, r.at.day);
      map.update(day, (v) => v + r.amount, ifAbsent: () => r.amount);
    }
    // ensure full range continuity
    final result = <({DateTime day, double total})>[];
    for (DateTime d = DateTime(start.year, start.month, start.day);
        d.isBefore(end);
        d = d.add(const Duration(days: 1))) {
      result.add((day: d, total: map[d] ?? 0));
    }
    return result;
  }

  @override
  Future<List<({DateTime month, double total})>> totalsByMonth({
    required int ledgerId,
    required String type,
    required int year,
  }) async {
    final sd = await _monthStartDayOf(ledgerId);
    final yr = yearRangeFor(year, sd);
    final rows = await _signedRows(
        ledgerId: ledgerId, type: type, start: yr.start, end: yr.end);
    final map = <int, double>{};
    for (final r in rows) {
      // 年范围 [当年1月周期起点, 次年1月周期起点) 内的标签必属 year,直接取 month
      final label = labelForDate(r.at, sd);
      map.update(label.month, (v) => v + r.amount, ifAbsent: () => r.amount);
    }
    final result = <({DateTime month, double total})>[];
    for (int m = 1; m <= 12; m++) {
      result.add((month: DateTime(year, m, 1), total: map[m] ?? 0));
    }
    return result;
  }

  @override
  Future<List<({int year, double total})>> totalsByYearSeries({
    required int ledgerId,
    required String type,
  }) async {
    final rows = await _signedRows(ledgerId: ledgerId, type: type);
    if (rows.isEmpty) return const [];
    final sd = await _monthStartDayOf(ledgerId);
    final map = <int, double>{};
    int minYear = 9999, maxYear = 0;
    for (final r in rows) {
      final y = labelForDate(r.at, sd).year;
      if (y < minYear) minYear = y;
      if (y > maxYear) maxYear = y;
      map.update(y, (v) => v + r.amount, ifAbsent: () => r.amount);
    }
    final out = <({int year, double total})>[];
    for (int y = minYear; y <= maxYear; y++) {
      out.add((year: y, total: map[y] ?? 0));
    }
    return out;
  }

  /// [totalsInRange]/[monthlyTotals]/[yearlyTotals] 共用的 SQL 聚合(比查出
  /// 全部資料再累加快得多)。退款單記成反方向的負值;原交易本身不計入統計
  /// 時退款也不計入(子查詢走 idx_transactions_sync_id)。
  Future<(double income, double expense)> _rangeTotals(
      int ledgerId, DateTime start, DateTime end) async {
    final result = await db.customSelect(
      '''
      SELECT
        COALESCE(SUM(CASE
          WHEN r = 0 AND type = 'income' THEN amt
          WHEN r = 1 AND type = 'expense' AND ox = 0 THEN -amt
          ELSE 0 END), 0) AS income,
        COALESCE(SUM(CASE
          WHEN r = 0 AND type = 'expense' THEN amt
          WHEN r = 1 AND type = 'income' AND ox = 0 THEN -amt
          ELSE 0 END), 0) AS expense
      FROM (
        SELECT
          t.type AS type,
          COALESCE(t.native_amount, t.amount) AS amt,
          CASE WHEN COALESCE(t.refund_of_sync_id, '') = '' THEN 0 ELSE 1 END AS r,
          CASE WHEN COALESCE(t.refund_of_sync_id, '') = '' THEN 0 ELSE COALESCE(
            (SELECT o.exclude_from_stats FROM transactions o
              WHERE o.sync_id = t.refund_of_sync_id AND o.ledger_id = t.ledger_id
              LIMIT 1), 0) END AS ox
        FROM transactions t
        WHERE t.ledger_id = ?1 AND t.happened_at >= ?2 AND t.happened_at < ?3
          AND t.exclude_from_stats = 0
          AND t.type IN ('income', 'expense')
      )
      ''',
      variables: [
        d.Variable<int>(ledgerId),
        d.Variable<DateTime>(start),
        d.Variable<DateTime>(end),
      ],
      readsFrom: {db.transactions},
    ).getSingle();

    final income = (result.data['income'] as num?)?.toDouble() ?? 0.0;
    final expense = (result.data['expense'] as num?)?.toDouble() ?? 0.0;
    return (income, expense);
  }

  @override
  Future<(double income, double expense)> totalsInRange({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
  }) =>
      _rangeTotals(ledgerId, start, end);

  /// 读取账本的自定义每月起始日(1-28);账本缺失或查询异常时按 1(自然月)降级
  /// —— watch 流经 Stream.fromFuture 包裹,这里抛错会让流永久进 error 态。
  Future<int> _monthStartDayOf(int ledgerId) async {
    try {
      final row = await (db.select(db.ledgers)
            ..where((l) => l.id.equals(ledgerId)))
          .getSingleOrNull();
      return (row?.monthStartDay ?? 1).clamp(1, 28);
    } catch (_) {
      return 1;
    }
  }

  @override
  Future<(double income, double expense)> monthlyTotals({
    required int ledgerId,
    required DateTime month,
  }) async {
    final sd = await _monthStartDayOf(ledgerId);
    final range = periodForLabel(month.year, month.month, sd);
    return _rangeTotals(ledgerId, range.start, range.end);
  }

  @override
  Future<(double income, double expense)> yearlyTotals({
    required int ledgerId,
    required int year,
  }) async {
    final sd = await _monthStartDayOf(ledgerId);
    final range = yearRangeFor(year, sd);
    return _rangeTotals(ledgerId, range.start, range.end);
  }

  @override
  Future<ReportDataset> loadReportDataset(ReportQuery query) =>
      LocalReportLoader(db).load(query,
          sharedSyntheticCategories: getSharedSyntheticCategoriesForLedger);

  @override
  Future<ReportFilterOptions> loadReportFilterOptions(int ledgerId) =>
      LocalReportLoader(db).loadFilterOptions(ledgerId,
          sharedSyntheticCategories: getSharedSyntheticCategoriesForLedger);
}
