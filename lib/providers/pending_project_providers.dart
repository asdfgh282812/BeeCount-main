import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import '../providers.dart';

/// 手動刷新計數器——needsProjectAssignment 是直接寫欄位而非透過某個會被
/// watch 的 stream 更新,所以要靠這個計數器讓列表在補選專案後重新查詢
/// (同 [pendingAccountRefreshProvider] 慣例,design 2026-09-11)。
final pendingProjectRefreshProvider = StateProvider<int>((ref) => 0);

final pendingProjectTransactionsProvider =
    FutureProvider.family<List<Transaction>, int>((ref, ledgerId) async {
  ref.watch(pendingProjectRefreshProvider);
  final repo = ref.watch(repositoryProvider);
  return repo.getTransactionsNeedingProjectAssignment(ledgerId);
});
