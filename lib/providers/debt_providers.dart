import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import '../data/repositories/debt_repository.dart';
import '../providers.dart';

/// 借還款列表刷新觸發器。同 [budgetRefreshProvider] 的做法——[DebtWithStatus]
/// 的 remainingAmount/status 是跨表算出來的(Debts + Transactions.debtSyncId),
/// 單純 watch Debts 表的變化(watchDebtsProvider)不會在還款交易新增/編輯/刪除
/// 時重新計算,所以需要一個顯式的刷新計數器——寫入端(建立/編輯/結案/刪除
/// 欠款,以及新增/編輯/刪除帶 debtSyncId 的還款交易)都要 bump 這個 provider。
final debtsRefreshProvider = StateProvider<int>((ref) => 0);

/// 當前帳本的欠款列表 + 即時算出的還款進度/狀態,依 dueAt 升冪排序。
final debtsWithStatusProvider =
    FutureProvider<List<DebtWithStatus>>((ref) async {
  ref.watch(debtsRefreshProvider);
  final ledgerId = ref.watch(currentLedgerIdProvider);
  final repo = ref.watch(repositoryProvider);
  return repo.getDebtsWithStatus(ledgerId);
});

/// 單筆欠款(含即時狀態)。
final debtWithStatusProvider =
    FutureProvider.family<DebtWithStatus?, int>((ref, debtId) async {
  ref.watch(debtsRefreshProvider);
  final repo = ref.watch(repositoryProvider);
  return repo.getDebtWithStatus(debtId);
});

/// 單筆欠款關聯的還款交易(依 happenedAt 由新到舊)。
final debtRepaymentTransactionsProvider =
    FutureProvider.family<List<Transaction>, int>((ref, debtId) async {
  ref.watch(debtsRefreshProvider);
  final repo = ref.watch(repositoryProvider);
  return repo.getDebtRepaymentTransactions(debtId);
});

/// 當前帳本的淨欠款餘額(Σreceivable − Σpayable 未結餘額)。
final netDebtBalanceProvider = FutureProvider<double>((ref) async {
  ref.watch(debtsRefreshProvider);
  final ledgerId = ref.watch(currentLedgerIdProvider);
  final repo = ref.watch(repositoryProvider);
  return repo.getNetDebtBalance(ledgerId);
});

/// 跨所有帳本的淨欠款餘額。帳戶列表頁的虛擬入口卡片用這個(不是
/// [netDebtBalanceProvider])——因為它旁邊的淨資產卡([netWorthBreakdownProvider])
/// 本來就是跨帳本聚合的(accounts 是 user-global),兩者範圍要一致,否則卡片
/// 數字對不上淨資產卡裡含的欠款部分。
final netDebtBalanceAllLedgersProvider = FutureProvider<double>((ref) async {
  ref.watch(debtsRefreshProvider);
  final repo = ref.watch(repositoryProvider);
  final balances = await repo.getDebtBalancesByLedgerForAllLedgers();
  double net = 0;
  for (final b in balances) {
    net += b.receivableRemaining - b.payableRemaining;
  }
  return net;
});
