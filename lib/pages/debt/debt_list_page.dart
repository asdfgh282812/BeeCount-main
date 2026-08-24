import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/debt_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../styles/tokens.dart';
import '../../utils/currencies.dart';
import '../../widgets/ui/ui.dart';
import 'debt_editor_page.dart';
import 'debt_repayment_page.dart';

/// 借還款列表頁。對齐 doc.moze.app/record/payables-receivables 的呈現方式:
/// 每筆欠款一張卡片(對象/方向/狀態/剩餘金額+進度條+還款記錄),依到期日排序。
class DebtListPage extends ConsumerWidget {
  const DebtListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final debtsAsync = ref.watch(debtsWithStatusProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.debtsPageTitle,
            showBack: true,
          ),
          Expanded(
            child: debtsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text(e.toString())),
              data: (debts) {
                if (debts.isEmpty) {
                  return _buildEmptyState(context, l10n);
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: debts.length,
                  itemBuilder: (context, index) =>
                      _DebtCard(entry: debts[index]),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DebtEditorPage()),
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
          Icon(Icons.handshake_outlined,
              size: 64, color: BeeTokens.textTertiary(context)),
          const SizedBox(height: 16),
          Text(
            l10n.debtsEmptyMessage,
            style:
                TextStyle(fontSize: 14, color: BeeTokens.textSecondary(context)),
          ),
        ],
      ),
    );
  }
}

class _DebtCard extends ConsumerStatefulWidget {
  final DebtWithStatus entry;

  const _DebtCard({required this.entry});

  @override
  ConsumerState<_DebtCard> createState() => _DebtCardState();
}

class _DebtCardState extends ConsumerState<_DebtCard> {
  bool _expanded = false;

  bool get _isPayable => widget.entry.debt.direction == kDebtDirectionPayable;

  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case kDebtStatusSettled:
        return BeeTokens.success(context);
      case kDebtStatusPartial:
        return BeeTokens.warning(context);
      case kDebtStatusClosed:
        return BeeTokens.textTertiary(context);
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  String _statusLabel(AppLocalizations l10n, String status) {
    switch (status) {
      case kDebtStatusSettled:
        return l10n.debtStatusSettled;
      case kDebtStatusPartial:
        return l10n.debtStatusPartial;
      case kDebtStatusClosed:
        return l10n.debtStatusClosed;
      default:
        return l10n.debtStatusOpen;
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final debt = widget.entry.debt;
    final currencyCode =
        ref.watch(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    final currencySymbol = getCurrencySymbol(currencyCode);
    final progress = debt.principalAmount > 0
        ? (widget.entry.repaidAmount / debt.principalAmount).clamp(0.0, 1.0)
        : 0.0;
    final canRepay = widget.entry.status != kDebtStatusSettled &&
        widget.entry.status != kDebtStatusClosed;

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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (_isPayable
                            ? BeeTokens.expenseColor(context, ref)
                            : BeeTokens.incomeColor(context, ref))
                        .withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPayable ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 20,
                    color: _isPayable
                        ? BeeTokens.expenseColor(context, ref)
                        : BeeTokens.incomeColor(context, ref),
                  ),
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
                              debt.counterpartyName,
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
                        [
                          _isPayable
                              ? l10n.debtDirectionPayableLabel
                              : l10n.debtDirectionReceivableLabel,
                          if (debt.dueAt != null) _formatDate(debt.dueAt!),
                        ].join(' · '),
                        style: TextStyle(
                            fontSize: 12.5,
                            color: BeeTokens.textSecondary(context)),
                      ),
                    ],
                  ),
                ),
              ],
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
                      '${l10n.debtRemainingLabel} $currencySymbol${widget.entry.remainingAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: BeeTokens.textPrimary(context),
                      ),
                    ),
                    Text(
                      '$currencySymbol${debt.principalAmount.toStringAsFixed(2)}',
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
                    color: _statusColor(context, widget.entry.status),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded
                      ? l10n.commonClose
                      : l10n.debtRepaymentRecordsLabel),
                ),
                if (widget.entry.status == kDebtStatusClosed)
                  TextButton(
                    onPressed: () => _reopen(context),
                    child: Text(l10n.debtReopenButton),
                  )
                else
                  TextButton(
                    onPressed: () => _close(context),
                    child: Text(l10n.debtCloseButton),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DebtEditorPage(debt: debt),
                    ),
                  ),
                  child: Text(l10n.commonEdit),
                ),
                if (canRepay)
                  FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DebtRepaymentPage(
                          debt: debt,
                          suggestedAmount: widget.entry.remainingAmount,
                        ),
                      ),
                    ),
                    child: Text(_isPayable
                        ? l10n.debtRepayButtonPayable
                        : l10n.debtRepayButtonReceivable),
                  ),
              ],
            ),
          ),
          if (_expanded) ...[
            if (debt.originTransactionSyncId != null)
              _OriginRecordSection(originSyncId: debt.originTransactionSyncId!),
            _RepaymentList(debtId: debt.id),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, AppLocalizations l10n) {
    final color = _statusColor(context, widget.entry.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _statusLabel(l10n, widget.entry.status),
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }

  Future<void> _close(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialog.confirm<bool>(
          context,
          title: l10n.debtCloseConfirmTitle,
          message: l10n.debtCloseConfirmMessage,
        ) ??
        false;
    if (!confirmed) return;
    final repo = ref.read(repositoryProvider);
    final ledgerId = ref.read(currentLedgerIdProvider);
    await repo.closeDebt(widget.entry.debt.id);
    ref.read(debtsRefreshProvider.notifier).state++;
    unawaited(PostProcessor.sync(ref, ledgerId: ledgerId));
  }

  Future<void> _reopen(BuildContext context) async {
    final repo = ref.read(repositoryProvider);
    final ledgerId = ref.read(currentLedgerIdProvider);
    await repo.reopenDebt(widget.entry.debt.id);
    ref.read(debtsRefreshProvider.notifier).state++;
    unawaited(PostProcessor.sync(ref, ledgerId: ledgerId));
  }
}

/// 欠款紀錄(起點交易)區塊——跟 [_RepaymentList] 平行,讓展開的卡片裡
/// 「還款紀錄」跟「欠款紀錄」都找得到。web 建立的欠款沒有起點交易概念,
/// 呼叫端已經在 [_DebtCardState.build] 檢查過 `originTransactionSyncId`
/// 非 null 才會渲染這個 widget。
class _OriginRecordSection extends ConsumerWidget {
  final String originSyncId;

  const _OriginRecordSection({required this.originSyncId});

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final txAsync = ref.watch(debtOriginTransactionProvider(originSyncId));

    return txAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
      data: (tx) {
        if (tx == null) return const SizedBox.shrink();
        return Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: BeeTokens.divider(context))),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.debtOriginRecordLabel,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: BeeTokens.textTertiary(context)),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    _fmtDate(tx.happenedAt),
                    style: TextStyle(
                        fontSize: 13, color: BeeTokens.textPrimary(context)),
                  ),
                  const Spacer(),
                  Text(
                    tx.amount.toStringAsFixed(2),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: BeeTokens.textPrimary(context)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RepaymentList extends ConsumerWidget {
  final int debtId;

  const _RepaymentList({required this.debtId});

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final txsAsync = ref.watch(debtRepaymentTransactionsProvider(debtId));

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: BeeTokens.divider(context))),
      ),
      child: txsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))),
        ),
        error: (e, st) => Padding(
          padding: const EdgeInsets.all(12),
          child: Text(e.toString()),
        ),
        data: (txs) {
          if (txs.isEmpty) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Text(
                l10n.debtRepaymentRecordsEmpty,
                style:
                    TextStyle(fontSize: 13, color: BeeTokens.textTertiary(context)),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    l10n.debtRepaymentRecordsLabel,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: BeeTokens.textTertiary(context)),
                  ),
                ),
                const SizedBox(height: 4),
                ...txs.map((t) => Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(
                        children: [
                          Text(
                            _fmtDate(t.happenedAt),
                            style: TextStyle(
                                fontSize: 13,
                                color: BeeTokens.textPrimary(context)),
                          ),
                          const Spacer(),
                          Text(
                            t.amount.toStringAsFixed(2),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: BeeTokens.textPrimary(context)),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          );
        },
      ),
    );
  }
}
