import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db.dart' as db;
import '../utils/card_reward_period.dart';
import 'database_providers.dart';
import 'statistics_providers.dart';
import 'sync_providers.dart';

typedef ReconciliationCycleParams = ({
  int accountId,
  String extraIdsKey,
  int? billingDay,
  int cycleOffset,
});

/// 對帳模式(§2.10 MOZE_FEATURE_GAP_SD.md):「這期帳單」交易清單。查詢邏輯
/// 用 `BaseRepository.getAccountStatementTransactions`——SQL 層直接用
/// `COALESCE(deferred_posting_at, happened_at)` 當入帳歸屬日過濾週期,不論
/// 延後入帳跨了幾期(或呼叫方臨時選了很遠的日期)都能正確歸屬,不受「只抓
/// 前後各一期寬視窗」的距離限制(2026-08-18 二修:舊版在 Dart 端對 ±1 期
/// 寬視窗做 [effectiveDate] 過濾,原始 happened_at 落在視窗外的深度延後交易
/// 會直接查不到,對應 web 端對帳確認後幾期都能正確滾入的行為對不上)。
///
/// [cycleOffset]/[billingDay] 跟 `account_detail_page.dart` 最上方帳單彙總
/// 卡片用的是同一套 [billingCyclePeriod] offset 語意——呼叫端必須直接把帳單
/// 卡片目前選取的 offset 傳進來,才能保證兩處顯示同一期帳單(2026-08-18 修正:
/// 兩處各自維護獨立週期狀態、預設值不同導致畫面脫鉤的問題)。
final accountStatementTransactionsProvider = FutureProvider.family
    .autoDispose<List<db.Transaction>, ReconciliationCycleParams>(
  (ref, params) async {
    // 同步代数 bump 后重算——否则 web/其它裝置對帳確認後 pull 下來的
    // reconciledAt 寫進本地 Drift,這個 FutureProvider 不會自動重跑,UI
    // 仍顯示 pull 之前的舊快取(2026-08-18 修正)。
    ref.watch(syncGenerationProvider);
    // 2026-09-07 修正:本機編輯這期帳單裡的交易(對帳模式列表點鉛筆)時,
    // `account_reconciliation_page.dart` 的 `onEdit` 會先開啟一張「交易詳情
    // 卡片」,卡片內鉛筆再 push 完整編輯器——卡片在 push 編輯器*之前*就會把
    // 自己 pop 掉,導致 `onEdit` 裡 `await showTransactionDetailCard(...)`
    // 的 Future 在編輯器打開的當下就已經 resolve,呼叫端的
    // `_invalidate()` 等於在使用者真正按下儲存*之前*就白跑了一次,儲存
    // 之後沒有任何程式碼再通知這個 provider。改成額外 watch 這顆「任一
    // 交易寫入」全域 tick(`TransactionEditorPage._handleSubmit` 等所有寫入
    // 路徑都會 bump,同 `account_period_providers.dart` 既有慣例),不論呼叫
    // 端的 Navigator pop/push 時機多脆弱,存檔後都能可靠重算。
    ref.watch(statsRefreshProvider);
    final repo = ref.watch(repositoryProvider);
    final extraIds = params.extraIdsKey.isEmpty
        ? const <int>[]
        : params.extraIdsKey.split(',').map(int.parse).toList();

    final cycle = billingCyclePeriod(params.billingDay, params.cycleOffset);

    return repo.getAccountStatementTransactions(
      accountId: params.accountId,
      extraAccountIds: extraIds.isEmpty ? null : extraIds,
      cycleStart: cycle.start,
      cycleEnd: cycle.end,
    );
  },
);
