import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import '../data/repositories/installment_repository.dart';
import '../providers.dart';

/// 分期付款列表刷新觸發器。同 [debtsRefreshProvider]/[budgetRefreshProvider]
/// 的做法——[InstallmentPlanWithStatus] 的 paidPeriods/nextPeriodAt/
/// periodAmount 是跨表(InstallmentPeriods)即時算出的,單純 watch
/// InstallmentPlans 表的變化不會在期數被改動時重算,所以需要一個顯式的刷新
/// 計數器(建立/刪除計畫都要 bump 這個 provider)。
final installmentsRefreshProvider = StateProvider<int>((ref) => 0);

/// 當前帳本的分期計畫列表 + 即時算出的進度,`active` 排前面。
final installmentPlansWithStatusProvider =
    FutureProvider<List<InstallmentPlanWithStatus>>((ref) async {
  ref.watch(installmentsRefreshProvider);
  final ledgerId = ref.watch(currentLedgerIdProvider);
  final repo = ref.watch(repositoryProvider);
  return repo.getInstallmentPlansWithStatus(ledgerId);
});

/// 單筆分期計畫(含即時狀態)。
final installmentPlanWithStatusProvider =
    FutureProvider.family<InstallmentPlanWithStatus?, int>((ref, planId) async {
  ref.watch(installmentsRefreshProvider);
  final repo = ref.watch(repositoryProvider);
  return repo.getInstallmentPlanWithStatus(planId);
});

/// 單筆分期計畫的全部期數,依 periodNo 排序。
final installmentPeriodsProvider =
    FutureProvider.family<List<InstallmentPeriod>, int>((ref, planId) async {
  ref.watch(installmentsRefreshProvider);
  final repo = ref.watch(repositoryProvider);
  return repo.getInstallmentPeriods(planId);
});

/// 跨所有帳本的「尚有未繳分期本金」加總,供帳戶列表頁的虛擬入口卡片使用。
final installmentOutstandingPrincipalAllLedgersProvider =
    FutureProvider<double>((ref) async {
  ref.watch(installmentsRefreshProvider);
  final repo = ref.watch(repositoryProvider);
  return repo.getOutstandingPrincipalAllLedgers();
});
