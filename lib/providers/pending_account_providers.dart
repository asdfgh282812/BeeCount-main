import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import '../providers.dart';

/// 手動刷新計數器——needsAccountAssignment 是直接寫欄位而非透過某個會被
/// watch 的 stream 更新,所以要靠這個計數器讓列表在補選帳戶後重新查詢。
final pendingAccountRefreshProvider = StateProvider<int>((ref) => 0);

final pendingAccountTransactionsProvider =
    FutureProvider.family<List<Transaction>, int>((ref, ledgerId) async {
  ref.watch(pendingAccountRefreshProvider);
  final repo = ref.watch(repositoryProvider);
  return repo.getTransactionsNeedingAccountAssignment(ledgerId);
});
