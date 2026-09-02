import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/repositories/installment_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../styles/tokens.dart';
import '../../utils/currencies.dart';
import '../../widgets/biz/installment_action_sheets.dart';
import '../../widgets/ui/ui.dart';
import 'installment_editor_page.dart';

/// 分期付款列表頁。每卡片顯示總額/已繳期數/進度條/下一期日期/狀態徽章,
/// `active` 排前面(對齐 `getInstallmentPlansWithStatus` 的排序)。
///
/// 子專案 2:卡片可展開看各期明細(單期編輯/連同未來重算),卡片本身提供
/// 部分還本/提前結清/終止未來分期三個按鈕(見設計文件 §5.2)。
class InstallmentListPage extends ConsumerWidget {
  const InstallmentListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plansAsync = ref.watch(installmentPlansWithStatusProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.installmentsPageTitle,
            showBack: true,
          ),
          Expanded(
            child: plansAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text(e.toString())),
              data: (plans) {
                if (plans.isEmpty) {
                  return _buildEmptyState(context, l10n);
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: plans.length,
                  itemBuilder: (context, index) =>
                      _InstallmentCard(entry: plans[index]),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const InstallmentEditorPage()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_view_month,
              size: 64, color: BeeTokens.textTertiary(context)),
          const SizedBox(height: 16),
          Text(
            l10n.installmentsEmptyMessage,
            style: TextStyle(
                fontSize: 14, color: BeeTokens.textSecondary(context)),
          ),
        ],
      ),
    );
  }
}

class _InstallmentCard extends ConsumerStatefulWidget {
  final InstallmentPlanWithStatus entry;

  const _InstallmentCard({required this.entry});

  @override
  ConsumerState<_InstallmentCard> createState() => _InstallmentCardState();
}

class _InstallmentCardState extends ConsumerState<_InstallmentCard> {
  bool _expanded = false;

  InstallmentPlanWithStatus get entry => widget.entry;

  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case kInstallmentPlanStatusSettled:
        return BeeTokens.success(context);
      case kInstallmentPlanStatusTerminated:
        return BeeTokens.textTertiary(context);
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  String _statusLabel(AppLocalizations l10n, String status) {
    switch (status) {
      case kInstallmentPlanStatusSettled:
        return l10n.installmentStatusSettled;
      case kInstallmentPlanStatusTerminated:
        return l10n.installmentStatusTerminated;
      default:
        return l10n.installmentStatusActive;
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final plan = entry.plan;
    final currencyCode =
        ref.watch(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    final currencySymbol = getCurrencySymbol(currencyCode);
    final progress = plan.periods > 0
        ? (entry.paidPeriods / plan.periods).clamp(0.0, 1.0)
        : 0.0;
    final isActive = plan.status == kInstallmentPlanStatusActive;
    // 問題 C(對標 Moze):卡片摘要區塊(collapse 狀態就看得到)加上本金/
    // 利息的總計/已還/剩餘六個數字。用全部期數依 dueAt<=now(已還)/>now
    // (剩餘)分組加總——跟 `_openPayoff`/transaction_detail_card.dart
    // `_applyPayoff` 已有的「已過去/未過去」分組手法一致,這裡不共用函式
    // (純粹是風格一致,不涉及 §0 核心不變量的計算)。
    final periodsAsync = ref.watch(installmentPeriodsProvider(plan.id));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: BeeTokens.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BeeTokens.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.calendar_view_month,
                        size: 20, color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                plan.note?.isNotEmpty == true
                                    ? plan.note!
                                    : l10n.installmentPaidProgressLabel(
                                        entry.paidPeriods, plan.periods),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: BeeTokens.textPrimary(context),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            _buildStatusBadge(context, l10n),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${l10n.installmentPaidProgressLabel(entry.paidPeriods, plan.periods)} · ${l10n.installmentNextPeriodLabel} ${_formatDate(entry.nextPeriodAt)}',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: BeeTokens.textSecondary(context)),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: BeeTokens.iconTertiary(context),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${l10n.installmentTotalAmountLabel} $currencySymbol${plan.totalAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: BeeTokens.textPrimary(context),
                      ),
                    ),
                    Text(
                      '$currencySymbol${entry.periodAmount.toStringAsFixed(2)}/${l10n.installmentPeriodsLabel}',
                      style: TextStyle(
                          fontSize: 13, color: BeeTokens.textTertiary(context)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: BeeTokens.divider(context),
                    color: _statusColor(context, plan.status),
                  ),
                ),
                periodsAsync.maybeWhen(
                  data: (periods) => _buildPrincipalInterestSummary(
                      context, l10n, currencySymbol, periods),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          if (_expanded) _PeriodListSection(planId: plan.id, plan: plan),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 6),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (isActive) ...[
                  TextButton(
                    onPressed: () => _openEarlyRepay(context),
                    child: Text(l10n.installmentActionPartialRepay),
                  ),
                  TextButton(
                    onPressed: () => _openPayoff(context),
                    child: Text(l10n.installmentActionPayoff),
                  ),
                  TextButton(
                    onPressed: () => _confirmTerminateFuture(context),
                    child: Text(l10n.installmentActionTerminateFuture),
                  ),
                ],
                TextButton(
                  onPressed: () => _confirmDelete(context),
                  child: Text(l10n.commonDelete),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 問題 C:本金/利息拆分摘要——總計/已還/剩餘各自加總,依
  /// `dueAt <= now` 算已還、`dueAt > now` 算剩餘(跟 `_openPayoff` 的分組
  /// 手法一致,這裡獨立算一份,不共用函式)。
  Widget _buildPrincipalInterestSummary(
    BuildContext context,
    AppLocalizations l10n,
    String currencySymbol,
    List<InstallmentPeriod> periods,
  ) {
    if (periods.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    double principalPaid = 0;
    double principalRemaining = 0;
    double interestPaid = 0;
    double interestRemaining = 0;
    for (final p in periods) {
      if (!p.dueAt.isAfter(now)) {
        principalPaid += p.principalAmount;
        interestPaid += p.interestAmount;
      } else {
        principalRemaining += p.principalAmount;
        interestRemaining += p.interestAmount;
      }
    }
    final principalTotal = principalPaid + principalRemaining;
    final interestTotal = interestPaid + interestRemaining;
    String fmt(double v) => '$currencySymbol${v.toStringAsFixed(2)}';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.installmentPrincipalSummaryLine(
              fmt(principalTotal),
              fmt(principalPaid),
              fmt(principalRemaining),
            ),
            style:
                TextStyle(fontSize: 11.5, color: BeeTokens.textTertiary(context)),
          ),
          Text(
            l10n.installmentInterestSummaryLine(
              fmt(interestTotal),
              fmt(interestPaid),
              fmt(interestRemaining),
            ),
            style:
                TextStyle(fontSize: 11.5, color: BeeTokens.textTertiary(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, AppLocalizations l10n) {
    final color = _statusColor(context, entry.plan.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _statusLabel(l10n, entry.plan.status),
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }

  void _refreshAndSync() {
    final ledgerId = ref.read(currentLedgerIdProvider);
    ref.read(installmentsRefreshProvider.notifier).state++;
    unawaited(PostProcessor.sync(ref, ledgerId: ledgerId));
  }

  void _showOperationError(Object e) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    // StateError/ArgumentError 的 toString() 帶有 "Bad state:"/"Invalid
    // argument(s):" 之類的前綴,不特別剝掉——跟 installment_editor_page.dart
    // 既有的錯誤提示手法一致(直接顯示 e.toString()),這裡多包一層通用前綴
    // 純粹是給使用者一個「這是分期操作失敗」的上下文。
    showToast(context, l10n.installmentOperationFailed(e.toString()));
  }

  Future<void> _openEarlyRepay(BuildContext context) async {
    final plan = entry.plan;
    final ledgerId = ref.read(currentLedgerIdProvider);
    final currencyCode =
        ref.read(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    final input = await EarlyRepayPrincipalSheet.show(
      context,
      ledgerId: ledgerId,
      currencySymbol: getCurrencySymbol(currencyCode),
      initialAccountId: plan.accountId,
    );
    if (input == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(repositoryProvider).earlyRepayPrincipal(
            plan.id,
            paymentAmount: input.paymentAmount,
            accountId: input.accountId,
            happenedAt: input.happenedAt,
          );
      _refreshAndSync();
      if (mounted) showToast(context, l10n.installmentEarlyRepaySuccess);
    } catch (e) {
      _showOperationError(e);
    }
  }

  Future<void> _openPayoff(BuildContext context) async {
    final plan = entry.plan;
    final ledgerId = ref.read(currentLedgerIdProvider);
    final currencyCode =
        ref.read(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    // 預覽用的估算結清金額——跟 repo 內部 payoff() 的算法一致(已過去期數
    // 以外的剩餘本金 + 下一個未到期期的原排程利息近似值),純粹是 UI 給
    // 使用者一個心理準備,不是權威值(權威計算永遠以 repo 實際執行時為準)。
    final periods = await ref.read(installmentPeriodsProvider(plan.id).future);
    final now = DateTime.now();
    double happenedPrincipal = 0;
    for (final p in periods) {
      if (!p.dueAt.isAfter(now)) happenedPrincipal += p.principalAmount;
    }
    final futurePeriods = periods.where((p) => p.dueAt.isAfter(now)).toList();
    final accruedInterest =
        futurePeriods.isEmpty ? 0.0 : futurePeriods.first.interestAmount;
    final previewAmount = double.parse(
        (plan.totalAmount - happenedPrincipal + accruedInterest)
            .toStringAsFixed(2));

    if (!mounted) return;
    final input = await PayoffSheet.show(
      context,
      ledgerId: ledgerId,
      previewSettleAmount: previewAmount,
      currencySymbol: getCurrencySymbol(currencyCode),
      initialAccountId: plan.accountId,
    );
    if (input == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(repositoryProvider).payoff(
            plan.id,
            accountId: input.accountId,
            happenedAt: input.happenedAt,
          );
      _refreshAndSync();
      if (mounted) showToast(context, l10n.installmentPayoffSuccess);
    } catch (e) {
      _showOperationError(e);
    }
  }

  Future<void> _confirmTerminateFuture(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialog.confirm<bool>(
          context,
          title: l10n.installmentTerminateFutureConfirmTitle,
          message: l10n.installmentTerminateFutureConfirmMessage,
        ) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(repositoryProvider)
          .terminateFutureInstallments(entry.plan.id);
      _refreshAndSync();
      if (mounted) showToast(context, l10n.installmentTerminateFutureSuccess);
    } catch (e) {
      _showOperationError(e);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialog.confirm<bool>(
          context,
          title: l10n.installmentDeleteConfirmTitle,
          message: l10n.installmentDeleteConfirmMessage,
        ) ??
        false;
    if (!confirmed) return;
    final repo = ref.read(repositoryProvider);
    await repo.deleteInstallmentPlan(entry.plan.id);
    _refreshAndSync();
    if (context.mounted) {
      showToast(context, l10n.installmentDeleteSuccess);
    }
  }
}

/// 展開後的各期明細——單期「編輯」(單期覆寫)/「連同未來重算」兩個動作,
/// 用普通 IconButton(不是 PopupMenuButton——`PopupMenuButton.onSelected`
/// 裡直接觸發 showDialog/Navigator.push 在 macOS target 上會 crash,這是
/// 本專案既有的教訓)。
class _PeriodListSection extends ConsumerWidget {
  final int planId;
  final InstallmentPlan plan;

  const _PeriodListSection({required this.planId, required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodsAsync = ref.watch(installmentPeriodsProvider(planId));
    final currencyCode =
        ref.watch(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    final currencySymbol = getCurrencySymbol(currencyCode);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: BeeTokens.surfaceSecondary(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: periodsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, st) => Padding(
          padding: const EdgeInsets.all(12),
          child: Text(e.toString()),
        ),
        data: (periods) => Column(
          children: [
            for (final period in periods)
              _PeriodRow(
                plan: plan,
                period: period,
                currencySymbol: currencySymbol,
              ),
          ],
        ),
      ),
    );
  }
}

class _PeriodRow extends ConsumerWidget {
  final InstallmentPlan plan;
  final InstallmentPeriod period;
  final String currencySymbol;

  const _PeriodRow({
    required this.plan,
    required this.period,
    required this.currencySymbol,
  });

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isOverridden = period.status == kInstallmentPeriodStatusOverridden;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              l10n.installmentPeriodNoLabel(period.periodNo),
              style: TextStyle(
                  fontSize: 12.5, color: BeeTokens.textSecondary(context)),
            ),
          ),
          Expanded(
            child: Text(
              _formatDate(period.dueAt),
              style: TextStyle(
                  fontSize: 12.5, color: BeeTokens.textSecondary(context)),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$currencySymbol${period.totalAmount.toStringAsFixed(2)}',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: BeeTokens.textPrimary(context)),
                ),
                // 問題 C(對標 Moze):每期同時顯示本金/利息拆分,不是只有
                // 合計金額。principalAmount/interestAmount 欄位本來就存在,
                // 純 UI 呈現。
                Text(
                  l10n.installmentPeriodPrincipalInterestLabel(
                    '$currencySymbol${period.principalAmount.toStringAsFixed(2)}',
                    '$currencySymbol${period.interestAmount.toStringAsFixed(2)}',
                  ),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                      fontSize: 11, color: BeeTokens.textTertiary(context)),
                ),
              ],
            ),
          ),
          if (isOverridden)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                l10n.installmentPeriodStatusOverriddenLabel,
                style: TextStyle(
                    fontSize: 11, color: BeeTokens.textTertiary(context)),
              ),
            ),
          IconButton(
            tooltip: l10n.installmentPeriodEditTooltip,
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _editPeriod(context, ref),
          ),
          IconButton(
            tooltip: l10n.installmentPeriodRebalanceTooltip,
            icon: const Icon(Icons.calculate_outlined, size: 18),
            onPressed: () => _rebalanceFromHere(context, ref),
          ),
        ],
      ),
    );
  }

  Future<String?> _currentTxNote(WidgetRef ref) async {
    if (period.txId == null) return null;
    final tx =
        await ref.read(repositoryProvider).getTransactionById(period.txId!);
    return tx?.note;
  }

  Future<void> _editPeriod(BuildContext context, WidgetRef ref) async {
    final currencyCode =
        ref.read(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    final currentNote = await _currentTxNote(ref);
    if (!context.mounted) return;
    final input = await PeriodOverrideSheet.show(
      context,
      period: period,
      currentNote: currentNote,
      currencySymbol: getCurrencySymbol(currencyCode),
    );
    if (input == null || !context.mounted) return;
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(repositoryProvider).updatePeriodOverride(
            period.id,
            amount: input.amount,
            dueAt: input.dueAt,
            note: input.note,
          );
      ref.read(installmentsRefreshProvider.notifier).state++;
      final ledgerId = ref.read(currentLedgerIdProvider);
      unawaited(PostProcessor.sync(ref, ledgerId: ledgerId));
      if (context.mounted) {
        showToast(context, l10n.installmentPeriodEditSuccess);
      }
    } catch (e) {
      if (context.mounted) {
        showToast(context, l10n.installmentOperationFailed(e.toString()));
      }
    }
  }

  Future<void> _rebalanceFromHere(BuildContext context, WidgetRef ref) async {
    final input = await RebalanceFromSheet.show(
      context,
      periodNo: period.periodNo,
      currentInterestRate: plan.interestRate,
      currentRepaymentMethod: plan.repaymentMethod,
    );
    if (input == null || !context.mounted) return;
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(repositoryProvider).rebalanceFrom(
            plan.id,
            period.periodNo,
            interestRate: input.interestRate,
            repaymentMethod: input.repaymentMethod,
          );
      ref.read(installmentsRefreshProvider.notifier).state++;
      final ledgerId = ref.read(currentLedgerIdProvider);
      unawaited(PostProcessor.sync(ref, ledgerId: ledgerId));
      if (context.mounted) {
        showToast(context, l10n.installmentRebalanceSuccess);
      }
    } catch (e) {
      if (context.mounted) {
        showToast(context, l10n.installmentOperationFailed(e.toString()));
      }
    }
  }
}
