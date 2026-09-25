import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/db.dart';
import '../models/report/report_dataset.dart';
import '../models/report/report_definition.dart';
import 'card_reward_rule_providers.dart';
import 'database_providers.dart';
import 'statistics_providers.dart';

/// 統計報表資料集。同一個 [ReportQuery](帳本 + 區間 + 篩選)在報表頁的
/// 各分頁間共用同一份快取;記帳/編輯後 [statsRefreshProvider] +1 自動重載。
final reportDatasetProvider = FutureProvider.autoDispose
    .family<ReportDataset, ReportQuery>((ref, query) async {
  ref.watch(statsRefreshProvider);
  final repo = ref.watch(repositoryProvider);
  return repo.loadReportDataset(query);
});

/// 統計報表「回饋金」:資料集裡非退款支出的估算回饋金 `{交易 id: 金額}`,
/// 算法同回饋明細頁(見 [estimateCardRewardsForTransactions])。只有切到回饋金
/// 時才 watch,不拖慢其他分頁。
final reportRewardsProvider = FutureProvider.autoDispose
    .family<Map<int, double>, ReportQuery>((ref, query) async {
  final ds = await ref.watch(reportDatasetProvider(query).future);
  final repo = ref.watch(repositoryProvider);
  final txs = <int, Transaction>{
    for (final e in ds.entries)
      if (e.type == 'expense' && !e.isRefund && e.tx.rewardRuleIds.isNotEmpty)
        e.tx.id: e.tx,
  };
  return estimateCardRewardsForTransactions(repo, txs.values);
});

/// 篩選編輯器的可選項目(依目前帳本)。
final reportFilterOptionsProvider =
    FutureProvider.autoDispose<ReportFilterOptions>((ref) async {
  final repo = ref.watch(repositoryProvider);
  final ledgerId = ref.watch(currentLedgerIdProvider);
  return repo.loadReportFilterOptions(ledgerId);
});

class ReportStoreState {
  final bool loaded;
  final List<ReportDefinition> reports;

  const ReportStoreState({required this.loaded, required this.reports});

  ReportDefinition? byId(String id) {
    for (final r in reports) {
      if (r.id == id) return r;
    }
    return null;
  }
}

/// 已儲存的統計報表清單。純本機(SharedPreferences),不做雲端同步——
/// 理由與日後要同步時的做法見 docs/changes/2026-09-25-statistics-report.md。
class ReportStoreNotifier extends StateNotifier<ReportStoreState> {
  ReportStoreNotifier({bool autoLoad = true})
      : super(const ReportStoreState(loaded: false, reports: [])) {
    if (autoLoad) load();
  }

  static const prefsKey = 'statistics_reports_v1';

  Future<void> load() async {
    List<ReportDefinition> reports;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null) {
        reports = ReportDefinition.builtIns();
        await _persist(reports);
      } else {
        final decoded = jsonDecode(raw);
        final list = decoded is Map ? decoded['reports'] : null;
        reports = [
          for (final j in (list is List ? list : const []))
            if (ReportDefinition.fromJson(j) case final r?) r,
        ];
      }
    } catch (_) {
      // JSON 損毀:退回內建範本,但不覆寫原資料(下次存檔才會蓋掉)。
      reports = ReportDefinition.builtIns();
    }
    if (mounted) state = ReportStoreState(loaded: true, reports: reports);
  }

  Future<void> _persist(List<ReportDefinition> reports) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        prefsKey,
        jsonEncode({
          'version': 1,
          'reports': [for (final r in reports) r.toJson()],
        }),
      );
    } catch (_) {
      // 寫入失敗只影響持久化,記憶體狀態仍正確。
    }
  }

  Future<void> _set(List<ReportDefinition> reports) async {
    state = ReportStoreState(loaded: true, reports: reports);
    await _persist(reports);
  }

  static String newId() => const Uuid().v4();

  Future<void> add(ReportDefinition def) => _set([...state.reports, def]);

  Future<void> update(ReportDefinition def) => _set([
        for (final r in state.reports) r.id == def.id ? def : r,
      ]);

  /// 複製一份放在原報表後面。[name] 由呼叫端用 l10n 組好(「xx 副本」)。
  Future<ReportDefinition?> duplicate(String id, String name) async {
    final src = state.byId(id);
    if (src == null) return null;
    final copy =
        src.copyWith(id: newId(), name: () => name, builtInKey: () => null);
    final list = [...state.reports];
    list.insert(list.indexWhere((r) => r.id == id) + 1, copy);
    await _set(list);
    return copy;
  }

  Future<void> delete(String id) => _set([
        for (final r in state.reports)
          if (r.id != id) r
      ]);

  /// [newIndex] 是移除 [oldIndex] 之後的目標位置(同
  /// `ReorderableListView.onReorderItem` 的語意)。
  Future<void> reorder(int oldIndex, int newIndex) async {
    final list = [...state.reports];
    list.insert(newIndex, list.removeAt(oldIndex));
    await _set(list);
  }

  /// 把被刪掉的內建範本加回來(已存在的不動)。
  Future<void> restoreBuiltIns() async {
    final existing = {
      for (final r in state.reports)
        if (r.builtInKey != null) r.builtInKey
    };
    await _set([
      ...state.reports,
      for (final b in ReportDefinition.builtIns())
        if (!existing.contains(b.builtInKey))
          b.copyWith(id: state.byId(b.id) == null ? b.id : newId()),
    ]);
  }
}

final reportStoreProvider =
    StateNotifierProvider<ReportStoreNotifier, ReportStoreState>(
        (ref) => ReportStoreNotifier());

/// 各報表目前切到第幾期(0 = 當期,-1 = 上一期…)。純記憶體,跟
/// `accountPeriodOffsetProvider` 同一套慣例;刻意不共用首頁的
/// `selectedMonthProvider`,報表翻期不會牽動首頁月份。
class ReportOffsetNotifier extends StateNotifier<Map<String, int>> {
  ReportOffsetNotifier() : super(const {});

  void set(String reportId, int offset) => state = {...state, reportId: offset};
}

final reportOffsetProvider =
    StateNotifierProvider<ReportOffsetNotifier, Map<String, int>>(
        (ref) => ReportOffsetNotifier());

/// 帳本第一筆交易的時間。報表的期間選單只列到這一期、「上一期」也停在這一期,
/// 不會翻到還沒開始記帳的空月份。無交易回 null。
final reportFirstTxDateProvider =
    FutureProvider.autoDispose.family<DateTime?, int>((ref, ledgerId) async {
  final repo = ref.watch(repositoryProvider);
  ref.watch(statsRefreshProvider);
  return (await repo.getFirstTransactionByLedger(ledgerId))?.happenedAt;
});
