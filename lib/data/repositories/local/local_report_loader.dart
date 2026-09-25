import 'package:drift/drift.dart';

import '../../db.dart';
import '../../../models/report/report_dataset.dart';
import '../../../models/report/report_filter.dart';
import '../../../utils/refund_netting.dart';
import '../../../utils/shared_ledger_picker_filter.dart';

/// 統計報表資料集載入器(`StatisticsRepository.loadReportDataset` 的實作)。
///
/// 設計取捨(docs/changes/2026-09-25-statistics-report.md):一次 SELECT 期間
/// 內交易 + 批次預載分類/帳戶/標籤/專案/欠款,展開成 [ReportEntry] legs 後
/// 在 Dart 套用篩選。統計口徑刻意跟 `LocalStatisticsRepository` 的
/// totalsByCategory* 完全一致:
/// - `excludeFromStats` 排除、金額 `nativeAmount ?? amount`
/// - 拆帳交易每筆明細一條 leg,金額乘 `nativeAmount/amount` 折算比例
/// - 本地分類查不到時用 `categorySyncIdOverride` 對共享帳本 Owner 分類
///   (synthetic 負 id)兜底
/// - 退款沖銷(2026-09-25,見 `utils/refund_netting.dart`):退款單記成反方向
///   的負值 leg,分類扣回原交易的分類(原交易拆帳就按明細比例分攤),專案/
///   商家自己沒填就沿用原交易的;原交易不計入統計時退款也跳過
class LocalReportLoader {
  final BeeDatabase db;

  LocalReportLoader(this.db);

  static const _chunk = 500;

  Future<List<T>> _inChunks<T, K>(
      List<K> keys, Future<List<T>> Function(List<K> part) fetch) async {
    if (keys.isEmpty) return const [];
    final out = <T>[];
    for (var i = 0; i < keys.length; i += _chunk) {
      out.addAll(await fetch(keys.sublist(
          i, i + _chunk > keys.length ? keys.length : i + _chunk)));
    }
    return out;
  }

  Future<ReportDataset> load(
    ReportQuery q, {
    required Future<Map<int, Category>> Function(int ledgerId)
        sharedSyntheticCategories,
  }) async {
    final ledger = await (db.select(db.ledgers)
          ..where((l) => l.id.equals(q.ledgerId)))
        .getSingleOrNull();
    final ledgerSyncId = ledger?.syncId;

    final txs = await (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(q.ledgerId) &
              t.excludeFromStats.equals(false) &
              t.happenedAt.isBiggerOrEqualValue(q.start) &
              t.happenedAt.isSmallerThanValue(q.end)))
        .get();

    // ---- 退款原交易(不限日期,退款常跟原交易不在同一期) ----
    final refundTargets = <String, Transaction>{
      for (final o in await _inChunks<Transaction, String>(
          {
            for (final t in txs)
              if (isRefundOf(t.refundOfSyncId)) t.refundOfSyncId!
          }.toList(),
          (part) => (db.select(db.transactions)
                ..where((t) =>
                    t.ledgerId.equals(q.ledgerId) & t.syncId.isIn(part)))
              .get()))
        o.syncId!: o,
    };

    // ---- 分類(本地 + 共享 synthetic) ----
    final categories = <int, Category>{
      for (final c in await db.select(db.categories).get()) c.id: c,
    };
    final sharedCats = await sharedSyntheticCategories(q.ledgerId);
    categories.addAll(sharedCats);
    final sharedCatBySyncId = <String, Category>{
      for (final c in sharedCats.values)
        if (c.syncId != null) c.syncId!: c,
    };
    String catKey(Category c) => reportEntityKey(c.syncId, c.id);

    Category? resolveCategory(int? localId, String? overrideSyncId) {
      if (localId != null) {
        final c = categories[localId];
        if (c != null && c.id > 0) return c;
      }
      if (overrideSyncId != null && overrideSyncId.isNotEmpty) {
        return sharedCatBySyncId[overrideSyncId];
      }
      return null;
    }

    List<String> categoryKeysOf(Category? c) {
      if (c == null) return const [];
      final keys = [catKey(c)];
      final p = c.parentId == null ? null : categories[c.parentId!];
      if (p != null) keys.add(catKey(p));
      return keys;
    }

    // ---- 帳戶(本地 + 共享鏡像) ----
    final accountsByKey = <String, Account>{};
    final accountKeyById = <int, String>{};
    for (final a in await db.select(db.accounts).get()) {
      final k = reportEntityKey(a.syncId, a.id);
      accountsByKey[k] = a;
      accountKeyById[a.id] = k;
    }
    if (ledgerSyncId != null && ledgerSyncId.isNotEmpty) {
      final shared = await (db.select(db.sharedLedgerAccounts)
            ..where((t) => t.ledgerSyncId.equals(ledgerSyncId)))
          .get();
      for (final s in shared) {
        accountsByKey.putIfAbsent(s.syncId, () => _syntheticAccount(s));
      }
    }
    String? accountKeyOf(int? localId, String? overrideSyncId) {
      if (localId != null) {
        final k = accountKeyById[localId];
        if (k != null) return k;
      }
      if (overrideSyncId != null && overrideSyncId.isNotEmpty) {
        return overrideSyncId;
      }
      return null;
    }

    // ---- 專案 / 欠款(ledger-scoped) ----
    final projectsByKey = <String, Project>{
      for (final p in await (db.select(db.projects)
            ..where((p) => p.ledgerId.equals(q.ledgerId)))
          .get())
        reportEntityKey(p.syncId, p.id): p,
    };
    final debts = await (db.select(db.debts)
          ..where((d) => d.ledgerId.equals(q.ledgerId)))
        .get();
    final counterpartyByDebt = <String, String>{};
    final counterpartyByOriginTx = <String, String>{};
    for (final d in debts) {
      final name = d.counterpartyName.trim();
      if (name.isEmpty) continue;
      if (d.syncId != null) counterpartyByDebt[d.syncId!] = name;
      if (d.originTransactionSyncId != null) {
        counterpartyByOriginTx[d.originTransactionSyncId!] = name;
      }
    }

    // ---- 拆帳明細 / 標籤(批次) ----
    final splitIds = [
      for (final t in [...txs, ...refundTargets.values])
        if (t.hasSplits) t.id
    ];
    final splitsByTx = <int, List<TransactionSplit>>{};
    for (final s in await _inChunks<TransactionSplit, int>(
        splitIds,
        (part) => (db.select(db.transactionSplits)
              ..where((s) => s.transactionId.isIn(part)))
            .get())) {
      splitsByTx.putIfAbsent(s.transactionId, () => []).add(s);
    }
    final tagsByKey = <String, Tag>{};
    final tagKeysByTx = await _loadTagKeys(txs, tagsByKey);

    // ---- 展開 legs ----
    final entries = <ReportEntry>[];
    final txViews = <int, ReportTxView>{};
    for (final t in txs) {
      final native = t.nativeAmount ?? t.amount;
      final ownCategory =
          resolveCategory(t.categoryId, t.categorySyncIdOverride);
      final accountKey = accountKeyOf(t.accountId, t.accountSyncIdOverride);
      final toAccountKey =
          accountKeyOf(t.toAccountId, t.toAccountSyncIdOverride);
      txViews[t.id] = (
        t: t,
        category: ownCategory,
        account: accountKey == null ? null : accountsByKey[accountKey],
        toAccount: toAccountKey == null ? null : accountsByKey[toAccountKey],
      );
      final flow = statFlowOf(t.type, t.refundOfSyncId);
      final isRefund = flow != null && flow.sign < 0;
      final target = isRefund ? refundTargets[t.refundOfSyncId] : null;
      if (target != null && target.excludeFromStats) continue;
      final note = t.note?.trim();
      String? nonEmpty(String? v) =>
          (v == null || v.trim().isEmpty) ? null : v.trim();
      final merchant = nonEmpty(t.merchant) ?? nonEmpty(target?.merchant);
      final project = nonEmpty(t.projectSyncId) ?? nonEmpty(target?.projectSyncId);
      final counterparty =
          (t.debtSyncId != null ? counterpartyByDebt[t.debtSyncId!] : null) ??
              (t.syncId != null ? counterpartyByOriginTx[t.syncId!] : null);
      final tagKeys = tagKeysByTx[t.id] ?? const <String>[];

      ReportEntry leg(Category? c, double amount, bool isSplit) => ReportEntry(
            tx: t,
            type: isRefund ? flow.flow : t.type,
            amount: isRefund ? -amount : amount,
            isRefund: isRefund,
            at: t.happenedAt.toLocal(),
            categoryId: c?.id,
            categoryKeys: categoryKeysOf(c),
            accountKey: accountKey,
            toAccountKey: toAccountKey,
            projectKey: project,
            name: (note == null || note.isEmpty) ? null : note,
            merchant: merchant,
            counterparty: counterparty,
            tagKeys: tagKeys,
            isSplitLeg: isSplit,
          );

      if (target != null) {
        // 退款扣回原交易的分類:原交易拆帳就按明細比例分攤退款金額。
        final splits = target.hasSplits
            ? (splitsByTx[target.id] ?? const <TransactionSplit>[])
            : const <TransactionSplit>[];
        final base = splits.fold<double>(0, (a, s) => a + s.amount);
        if (target.hasSplits && splits.isNotEmpty && base != 0) {
          for (final s in splits) {
            final c = resolveCategory(s.categoryId, s.categorySyncIdOverride);
            final l = leg(c, native * s.amount / base, true);
            if (l.matches(q.filter)) entries.add(l);
          }
        } else {
          final c = target.hasSplits
              ? null
              : resolveCategory(
                  target.categoryId, target.categorySyncIdOverride);
          final l = leg(c, native, false);
          if (l.matches(q.filter)) entries.add(l);
        }
      } else if (t.hasSplits) {
        // 同 totalsByCategory:拆帳交易只看明細,查不到明細就不貢獻金額。
        final ratio = t.amount == 0 ? 1.0 : native / t.amount;
        for (final s in splitsByTx[t.id] ?? const <TransactionSplit>[]) {
          final c = resolveCategory(s.categoryId, s.categorySyncIdOverride);
          final l = leg(c, s.amount * ratio, true);
          if (l.matches(q.filter)) entries.add(l);
        }
      } else {
        final l = leg(ownCategory, native, false);
        if (l.matches(q.filter)) entries.add(l);
      }
    }

    return ReportDataset(
      entries: entries,
      txViews: txViews,
      categories: categories,
      accountsByKey: accountsByKey,
      tagsByKey: tagsByKey,
      projectsByKey: projectsByKey,
    );
  }

  /// 交易 id → 標籤 key 列表。同 `LocalTagRepository.getTagsForTransactions`
  /// 的語意(本地 TransactionTags + 共享帳本 TransactionTagOverrides),但分段
  /// 查詢避免 SQLite 變數上限。
  Future<Map<int, List<String>>> _loadTagKeys(
      List<Transaction> txs, Map<String, Tag> tagsByKey) async {
    final result = <int, List<String>>{};
    if (txs.isEmpty) return result;
    final allTags = await db.select(db.tags).get();
    final tagById = {for (final t in allTags) t.id: t};

    final links = await _inChunks<TransactionTag, int>(
        [for (final t in txs) t.id],
        (part) => (db.select(db.transactionTags)
              ..where((l) => l.transactionId.isIn(part)))
            .get());
    for (final l in links) {
      final tag = tagById[l.tagId];
      if (tag == null) continue;
      final k = reportEntityKey(tag.syncId, tag.id);
      tagsByKey[k] = tag;
      result.putIfAbsent(l.transactionId, () => []).add(k);
    }

    final txIdBySyncId = <String, int>{
      for (final t in txs)
        if (t.syncId != null) t.syncId!: t.id,
    };
    final overrides = await _inChunks<TransactionTagOverride, String>(
        txIdBySyncId.keys.toList(),
        (part) => (db.select(db.transactionTagOverrides)
              ..where((o) => o.transactionSyncId.isIn(part)))
            .get());
    if (overrides.isNotEmpty) {
      final shared = await _inChunks<SharedLedgerTag, String>(
          overrides.map((o) => o.tagSyncId).toSet().toList(),
          (part) => (db.select(db.sharedLedgerTags)
                ..where((t) => t.syncId.isIn(part)))
              .get());
      final sharedBySyncId = {for (final s in shared) s.syncId: s};
      for (final o in overrides) {
        final txId = txIdBySyncId[o.transactionSyncId];
        final s = sharedBySyncId[o.tagSyncId];
        if (txId == null || s == null) continue;
        tagsByKey.putIfAbsent(
            s.syncId,
            () => Tag(
                  id: syntheticIdForSyncId(s.syncId),
                  name: s.name,
                  color: s.color,
                  sortOrder: 0,
                  createdAt: DateTime.now(),
                  syncId: s.syncId,
                ));
        final list = result.putIfAbsent(txId, () => []);
        if (!list.contains(s.syncId)) list.add(s.syncId);
      }
    }
    return result;
  }

  /// 篩選編輯器的可選項目:帳戶(主帳戶下的子卡縮排)、分類(支出/收入分段、
  /// 二級縮排)、標籤、本帳本的專案/對象,以及本帳本出現過的名稱/商家
  /// (依使用次數排序,各取前 300 個)。
  Future<ReportFilterOptions> loadFilterOptions(
    int ledgerId, {
    required Future<Map<int, Category>> Function(int ledgerId)
        sharedSyntheticCategories,
  }) async {
    final ledger = await (db.select(db.ledgers)
          ..where((l) => l.id.equals(ledgerId)))
        .getSingleOrNull();
    final ledgerSyncId = ledger?.syncId;

    // 帳戶:主帳戶(account_group)在前,子卡縮排跟在後面。
    final accounts = [...await db.select(db.accounts).get()]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (ledgerSyncId != null && ledgerSyncId.isNotEmpty) {
      final shared = await (db.select(db.sharedLedgerAccounts)
            ..where((t) => t.ledgerSyncId.equals(ledgerSyncId)))
          .get();
      final have = {for (final a in accounts) a.syncId};
      accounts.addAll([
        for (final s in shared)
          if (!have.contains(s.syncId)) _syntheticAccount(s)
      ]);
    }
    final childrenOf = <String, List<Account>>{};
    for (final a in accounts) {
      final p = a.parentAccountId;
      if (p != null && p.isNotEmpty) childrenOf.putIfAbsent(p, () => []).add(a);
    }
    final accountOpts = <ReportFilterOption>[];
    for (final a in accounts) {
      final p = a.parentAccountId;
      if (p != null && p.isNotEmpty && accounts.any((x) => x.syncId == p)) {
        continue; // 放在主帳戶底下
      }
      accountOpts
          .add(ReportFilterOption(reportEntityKey(a.syncId, a.id), a.name));
      for (final c in childrenOf[a.syncId] ?? const <Account>[]) {
        accountOpts.add(ReportFilterOption(
            reportEntityKey(c.syncId, c.id), c.name,
            indent: 1));
      }
    }

    // 分類
    final cats = <Category>[
      ...await db.select(db.categories).get(),
      ...(await sharedSyntheticCategories(ledgerId)).values,
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final byId = {for (final c in cats) c.id: c};
    final childCats = <int, List<Category>>{};
    for (final c in cats) {
      if (c.level >= 2 && c.parentId != null && byId[c.parentId!] != null) {
        childCats.putIfAbsent(c.parentId!, () => []).add(c);
      }
    }
    final categoryOpts = <ReportFilterOption>[];
    final childKeys = <String, List<String>>{};
    for (final kind in const ['expense', 'income']) {
      for (final c in cats) {
        if (c.kind != kind) continue;
        if (c.level >= 2 && c.parentId != null && byId[c.parentId!] != null) {
          continue;
        }
        final k = reportEntityKey(c.syncId, c.id);
        categoryOpts.add(ReportFilterOption(k, c.name, section: kind));
        for (final ch in childCats[c.id] ?? const <Category>[]) {
          final ck = reportEntityKey(ch.syncId, ch.id);
          categoryOpts
              .add(ReportFilterOption(ck, ch.name, section: kind, indent: 1));
          childKeys.putIfAbsent(k, () => []).add(ck);
        }
      }
    }

    final tags = [...await db.select(db.tags).get()]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final tagOpts = [
      for (final t in tags)
        ReportFilterOption(reportEntityKey(t.syncId, t.id), t.name),
    ];
    if (ledgerSyncId != null && ledgerSyncId.isNotEmpty) {
      final shared = await (db.select(db.sharedLedgerTags)
            ..where((t) => t.ledgerSyncId.equals(ledgerSyncId)))
          .get();
      final have = {for (final t in tags) t.syncId};
      tagOpts.addAll([
        for (final s in shared)
          if (!have.contains(s.syncId)) ReportFilterOption(s.syncId, s.name)
      ]);
    }

    final projects = await (db.select(db.projects)
          ..where((p) => p.ledgerId.equals(ledgerId)))
        .get();
    final debts = await (db.select(db.debts)
          ..where((d) => d.ledgerId.equals(ledgerId)))
        .get();
    final counterparties = <String>{
      for (final d in debts)
        if (d.counterpartyName.trim().isNotEmpty) d.counterpartyName.trim()
    }.toList()
      ..sort();

    Future<List<String>> distinct(String column) async {
      final rows = await db.customSelect(
        'SELECT TRIM($column) AS v, COUNT(*) AS n FROM transactions '
        'WHERE ledger_id = ?1 AND $column IS NOT NULL AND TRIM($column) <> \'\' '
        'GROUP BY TRIM($column) ORDER BY n DESC LIMIT 300',
        variables: [Variable<int>(ledgerId)],
        readsFrom: {db.transactions},
      ).get();
      return [for (final r in rows) r.read<String>('v')];
    }

    return ReportFilterOptions(
      accounts: accountOpts,
      projects: [
        for (final p in projects)
          ReportFilterOption(reportEntityKey(p.syncId, p.id), p.name),
      ],
      categories: categoryOpts,
      tags: tagOpts,
      counterparties: [
        for (final c in counterparties) ReportFilterOption(c, c),
      ],
      names: [for (final n in await distinct('note')) ReportFilterOption(n, n)],
      merchants: [
        for (final m in await distinct('merchant')) ReportFilterOption(m, m),
      ],
      childCategoryKeys: childKeys,
    );
  }

  /// 同 `LocalTransactionRepository._syntheticAccountFromShared`。
  Account _syntheticAccount(SharedLedgerAccount s) => Account(
        id: syntheticIdForSyncId(s.syncId),
        ledgerId: 0,
        name: s.name,
        type: s.accountType,
        currency: s.currency,
        initialBalance: s.initialBalance ?? 0.0,
        createdAt: null,
        updatedAt: null,
        sortOrder: 0,
        creditLimit: s.creditLimit,
        billingDay: s.billingDay,
        paymentDueDay: s.paymentDueDay,
        bankName: s.bankName,
        cardLastFour: s.cardLastFour,
        note: s.note,
        syncId: s.syncId,
        hidden: false,
        includeInTotal: true,
        autoPayEnabled: false,
        autoPayFromAccountId: null,
        hideAmount: false,
      );
}
