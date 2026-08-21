import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/repositories/debt_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../styles/tokens.dart';
import '../../utils/currencies.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/account_selector.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';

/// 借還款新增/編輯頁面。direction / principalAmount 建立後不可改(對齐
/// BeeCount Cloud `WriteDebtUpdateRequest` 刻意不帶這兩個欄位——語意上等同
/// 刪除重建),編輯時這兩個欄位鎖住只顯示。
class DebtEditorPage extends ConsumerStatefulWidget {
  final Debt? debt;

  const DebtEditorPage({this.debt, super.key});

  @override
  ConsumerState<DebtEditorPage> createState() => _DebtEditorPageState();
}

class _DebtEditorPageState extends ConsumerState<DebtEditorPage> {
  final _counterpartyController = TextEditingController();
  final _principalController = TextEditingController();
  final _noteController = TextEditingController();
  late String _direction;
  DateTime? _dueAt;
  bool _isLoading = false;
  int? _accountId;

  bool get _isEditing => widget.debt != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final debt = widget.debt!;
      _direction = debt.direction;
      _counterpartyController.text = debt.counterpartyName;
      _principalController.text = debt.principalAmount.toStringAsFixed(0);
      _dueAt = debt.dueAt;
      _noteController.text = debt.note ?? '';
    } else {
      _direction = kDebtDirectionPayable;
    }
  }

  @override
  void dispose() {
    _counterpartyController.dispose();
    _principalController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currencyCode =
        ref.watch(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    final currencySymbol = getCurrencySymbol(currencyCode);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: _isEditing ? l10n.debtEditTitle : l10n.debtAddTitle,
            showBack: true,
            compact: true,
            actions: [
              if (_isEditing)
                IconButton(
                  onPressed: _deleteDebt,
                  icon: const Icon(Icons.delete_outline),
                ),
              TextButton(
                onPressed: _isLoading ? null : _saveDebt,
                child: Text(
                  l10n.commonSave,
                  style: TextStyle(
                    color: BeeTokens.textPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: 12.0.scaled(context, ref),
                vertical: 8.0.scaled(context, ref),
              ),
              children: [
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.debtDirectionLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                      SizedBox(height: 12.0.scaled(context, ref)),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDirectionOption(
                              context,
                              l10n.debtDirectionPayableLabel,
                              kDebtDirectionPayable,
                              Icons.arrow_upward,
                            ),
                          ),
                          SizedBox(width: 12.0.scaled(context, ref)),
                          Expanded(
                            child: _buildDirectionOption(
                              context,
                              l10n.debtDirectionReceivableLabel,
                              kDebtDirectionReceivable,
                              Icons.arrow_downward,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.0.scaled(context, ref)),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.debtCounterpartyLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                      SizedBox(height: 12.0.scaled(context, ref)),
                      TextField(
                        controller: _counterpartyController,
                        style: TextStyle(
                            fontSize: 16, color: BeeTokens.textPrimary(context)),
                        decoration: InputDecoration(
                          hintText: l10n.debtCounterpartyHint,
                          hintStyle:
                              TextStyle(color: BeeTokens.textTertiary(context)),
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.0.scaled(context, ref)),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.debtPrincipalAmountLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                      SizedBox(height: 12.0.scaled(context, ref)),
                      TextField(
                        controller: _principalController,
                        enabled: !_isEditing,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d+\.?\d{0,2}')),
                        ],
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: _isEditing
                              ? BeeTokens.textTertiary(context)
                              : BeeTokens.textPrimary(context),
                        ),
                        decoration: InputDecoration(
                          prefixText: '$currencySymbol ',
                          prefixStyle: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: BeeTokens.textPrimary(context),
                          ),
                          hintText: l10n.debtPrincipalAmountHint,
                          hintStyle: TextStyle(
                              fontSize: 24, color: BeeTokens.textTertiary(context)),
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.0.scaled(context, ref)),
                if (!_isEditing) ...[
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.debtRepaymentAccountLabel,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: BeeTokens.textSecondary(context),
                          ),
                        ),
                        SizedBox(height: 12.0.scaled(context, ref)),
                        AccountSelector(
                          ledgerId: ref.watch(currentLedgerIdProvider),
                          selectedAccountId: _accountId,
                          onAccountSelected: (id) =>
                              setState(() => _accountId = id),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12.0.scaled(context, ref)),
                ],
                SectionCard(
                  child: InkWell(
                    onTap: _pickDueDate,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.debtDueDateLabel,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: BeeTokens.textSecondary(context),
                                ),
                              ),
                              SizedBox(height: 6.0.scaled(context, ref)),
                              Text(
                                _dueAt != null
                                    ? _formatDate(_dueAt!)
                                    : l10n.debtDueDateNone,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _dueAt != null
                                      ? BeeTokens.textPrimary(context)
                                      : BeeTokens.textTertiary(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_dueAt != null)
                          IconButton(
                            onPressed: () => setState(() => _dueAt = null),
                            icon: Icon(Icons.close,
                                color: BeeTokens.iconTertiary(context)),
                            tooltip: l10n.debtDueDateClear,
                          )
                        else
                          Icon(Icons.chevron_right,
                              color: BeeTokens.iconTertiary(context)),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 12.0.scaled(context, ref)),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.debtNoteLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                      SizedBox(height: 12.0.scaled(context, ref)),
                      TextField(
                        controller: _noteController,
                        maxLines: 3,
                        style: TextStyle(
                            fontSize: 15, color: BeeTokens.textPrimary(context)),
                        decoration: InputDecoration(
                          hintText: l10n.commonNoteHint,
                          hintStyle:
                              TextStyle(color: BeeTokens.textTertiary(context)),
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _buildDirectionOption(
    BuildContext context,
    String label,
    String direction,
    IconData icon,
  ) {
    final isSelected = _direction == direction;
    final disabled = _isEditing;
    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: disabled ? null : () => setState(() => _direction = direction),
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: disabled && !isSelected ? 0.4 : 1.0,
        child: Container(
          padding: EdgeInsets.all(16.0.scaled(context, ref)),
          decoration: BoxDecoration(
            color: isSelected ? primary.withValues(alpha: 0.1) : BeeTokens.surface(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? primary : BeeTokens.border(context),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 28.0.scaled(context, ref),
                  color: isSelected ? primary : BeeTokens.iconSecondary(context)),
              SizedBox(height: 8.0.scaled(context, ref)),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? primary : BeeTokens.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _dueAt = picked);
    }
  }

  Future<void> _saveDebt() async {
    final l10n = AppLocalizations.of(context);
    final counterpartyName = _counterpartyController.text.trim();
    if (counterpartyName.isEmpty) {
      showToast(context, l10n.debtCounterpartyHint);
      return;
    }

    final principalText = _principalController.text.trim();
    final principalAmount = double.tryParse(principalText);
    if (!_isEditing && (principalAmount == null || principalAmount <= 0)) {
      showToast(context, l10n.debtPrincipalAmountHint);
      return;
    }

    if (!_isEditing && _accountId == null) {
      showToast(context, l10n.debtRepaymentAccountRequired);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(repositoryProvider);
      final ledgerId = ref.read(currentLedgerIdProvider);
      final note = _noteController.text.trim();

      if (_isEditing) {
        await repo.updateDebt(
          widget.debt!.id,
          counterpartyName: counterpartyName,
          dueAt: _dueAt,
          clearDueAt: _dueAt == null,
          note: note.isEmpty ? null : note,
          clearNote: note.isEmpty,
        );
      } else {
        await repo.createDebtWithOriginTransaction(
          ledgerId: ledgerId,
          direction: _direction,
          counterpartyName: counterpartyName,
          principalAmount: principalAmount!,
          accountId: _accountId!,
          dueAt: _dueAt,
          note: note.isEmpty ? null : note,
        );
      }

      ref.read(debtsRefreshProvider.notifier).state++;
      unawaited(PostProcessor.sync(ref, ledgerId: ledgerId));

      if (mounted) {
        showToast(context, l10n.debtSaveSuccess);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteDebt() async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(repositoryProvider);

    if (await repo.hasRepayments(widget.debt!.id)) {
      if (mounted) showToast(context, l10n.debtDeleteBlockedMessage);
      return;
    }
    if (!mounted) return;

    final confirmed = await AppDialog.confirm<bool>(
          context,
          title: l10n.commonDelete,
          message: l10n.debtDeleteConfirmMessage,
        ) ??
        false;
    if (!confirmed) return;

    try {
      final ledgerId = ref.read(currentLedgerIdProvider);
      await repo.deleteDebt(widget.debt!.id);
      ref.read(debtsRefreshProvider.notifier).state++;
      unawaited(PostProcessor.sync(ref, ledgerId: ledgerId));

      if (mounted) {
        showToast(context, l10n.debtDeleteSuccess);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showToast(context, e.toString());
    }
  }
}
