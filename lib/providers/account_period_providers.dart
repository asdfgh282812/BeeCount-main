import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/account_repository.dart';
import '../utils/month_range.dart';
import 'database_providers.dart';
import 'statistics_providers.dart';
import 'sync_providers.dart';

/// 一般帳戶明細頁的期間切換 offset 狀態。key=accountId,value=往回第幾期
/// (0=當期,1=上一期...)。跟 `project_providers.dart` 的
/// `projectPeriodOffsetProvider` 是同一套慣例。
class AccountPeriodOffsetNotifier extends StateNotifier<Map<int, int>> {
  AccountPeriodOffsetNotifier() : super({});

  void setOffset(int accountId, int offset) =>
      state = {...state, accountId: offset};
}

final accountPeriodOffsetProvider =
    StateNotifierProvider<AccountPeriodOffsetNotifier, Map<int, int>>(
        (ref) => AccountPeriodOffsetNotifier());

/// [offset] 對應的月週期範圍(半開區間 `[start, end)`,見 `month_range.dart`
/// 文件註解),依帳本 [monthStartDay] 切——跟專案「monthly」週期同一套算法
/// (`project_providers.dart::_projectPeriodAnchor`),只是這裡只有 monthly
/// 一種粒度,不用像專案那樣依 periodType 分支。
DateRange accountPeriodRange(int offset, int monthStartDay) {
  final now = DateTime.now();
  final currentLabel = labelForDate(now, monthStartDay);
  final targetLabel =
      DateTime(currentLabel.year, currentLabel.month - offset, 1);
  return periodForLabel(targetLabel.year, targetLabel.month, monthStartDay);
}

/// [range] 是半開區間 `[start, end)`,既有 repository 方法
/// (`getAccountTransactions`/`getAccountDailyBalances`/
/// `getAccountPeriodSummary`)的 `endDate` 語意都是「含當天整個自然日」,
/// 兩者不能直接混用——呼叫前用這個把 `end` 換算回「含端點」的最後一天。
DateTime inclusiveEnd(DateRange range) =>
    range.end.subtract(const Duration(days: 1));

typedef AccountPeriodSummaryParams = ({
  int accountId,
  DateTime start,
  DateTime end,
});

/// 一般帳戶明細頁摘要卡(轉出/轉入/總計橫條,比照 moze)用,見
/// [AccountRepository.getAccountPeriodSummary]。
final accountPeriodSummaryProvider = FutureProvider.family
    .autoDispose<AccountPeriodSummary, AccountPeriodSummaryParams>(
  (ref, params) async {
    ref.watch(syncGenerationProvider);
    // 任何地方(TransactionEditorPage/快速操作/AI 記帳...)新增/編輯一筆交易
    // 存檔後都會 bump 這顆 tick,不用每個呼叫端各自手動 invalidate 這個
    // provider(同 `statistics_providers.dart` 既有慣例)。
    ref.watch(statsRefreshProvider);
    final repo = ref.watch(repositoryProvider);
    return repo.getAccountPeriodSummary(
      params.accountId,
      startDate: params.start,
      endDate: params.end,
    );
  },
);

typedef AccountBalanceTrendParams = ({
  int accountId,
  DateTime start,
  DateTime end,
});

/// 一般帳戶明細頁小趨勢折線圖(該帳戶餘額走勢)用,見
/// [AccountRepository.getAccountDailyBalances]。
final accountBalanceTrendProvider = FutureProvider.family.autoDispose<
    List<({DateTime date, double balance})>, AccountBalanceTrendParams>(
  (ref, params) async {
    ref.watch(syncGenerationProvider);
    ref.watch(statsRefreshProvider);
    final repo = ref.watch(repositoryProvider);
    return repo.getAccountDailyBalances(
      params.accountId,
      startDate: params.start,
      endDate: params.end,
    );
  },
);
