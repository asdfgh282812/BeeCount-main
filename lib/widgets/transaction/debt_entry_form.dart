import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/debt_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../styles/tokens.dart';
import '../../utils/currencies.dart';
import '../../widgets/biz/account_selector.dart';
import '../../widgets/biz/section_card.dart';
import '../ui/ui.dart';

/// 記帳表單第 4 分頁「欠款」——新增欠款 + 起點交易(帳戶餘額立即變動)。
/// 對齐 `DebtEditorPage` 新增模式的欄位,唯一差異是這裡多了帳戶(必填)。
class DebtEntryForm extends ConsumerStatefulWidget {
  final VoidCallback onDebtCreated;

  const DebtEntryForm({super.key, required this.onDebtCreated});

  @override
  ConsumerState<DebtEntryForm> createState() => DebtEntryFormState();
}

class DebtEntryFormState extends ConsumerState<DebtEntryForm> {
  final _counterpartyController = TextEditingController();
  final _principalController = TextEditingController();
  final _noteController = TextEditingController();
  String _direction = kDebtDirectionPayable;
  int? _accountId;
  DateTime? _dueAt;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _counterpartyController.dispose();
    _principalController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dueAt = picked);
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final l10n = AppLocalizations.of(context);
    final counterpartyName = _counterpartyController.text.trim();
    if (counterpartyName.isEmpty) {
      showToast(context, l10n.debtCounterpartyHint);
      return;
    }
    final principalAmount = double.tryParse(_principalController.text.trim());
    if (principalAmount == null || principalAmount <= 0) {
      showToast(context, l10n.debtPrincipalAmountHint);
      return;
    }
    if (_accountId == null) {
      showToast(context, l10n.debtRepaymentAccountRequired);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(repositoryProvider);
      final ledgerId = ref.read(currentLedgerIdProvider);
      final note = _noteController.text.trim();

      await repo.createDebtWithOriginTransaction(
        ledgerId: ledgerId,
        direction: _direction,
        counterpartyName: counterpartyName,
        principalAmount: principalAmount,
        accountId: _accountId!,
        dueAt: _dueAt,
        note: note.isEmpty ? null : note,
      );

      ref.read(debtsRefreshProvider.notifier).state++;
      ref.read(statsRefreshProvider.notifier).state++;
      unawaited(PostProcessor.sync(ref, ledgerId: ledgerId));

      HapticFeedback.lightImpact();
      SystemSound.play(SystemSoundType.click);
      if (mounted) showToast(context, l10n.debtSaveSuccess);
      widget.onDebtCreated();
    } catch (e) {
      if (mounted) showToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: () => setState(() => _direction = direction),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
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
            Icon(icon, size: 28, color: isSelected ? primary : BeeTokens.iconSecondary(context)),
            const SizedBox(height: 8),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final currencyCode =
        ref.watch(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    final currencySymbol = getCurrencySymbol(currencyCode);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.debtDirectionLabel,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BeeTokens.textSecondary(context))),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _buildDirectionOption(context, l10n.debtDirectionPayableLabel,
                          kDebtDirectionPayable, Icons.arrow_upward)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _buildDirectionOption(context, l10n.debtDirectionReceivableLabel,
                          kDebtDirectionReceivable, Icons.arrow_downward)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.debtCounterpartyLabel,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BeeTokens.textSecondary(context))),
              const SizedBox(height: 12),
              TextField(
                controller: _counterpartyController,
                style: TextStyle(fontSize: 16, color: BeeTokens.textPrimary(context)),
                decoration: InputDecoration(
                  hintText: l10n.debtCounterpartyHint,
                  hintStyle: TextStyle(color: BeeTokens.textTertiary(context)),
                  border: InputBorder.none,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.debtPrincipalAmountLabel,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BeeTokens.textSecondary(context))),
              const SizedBox(height: 12),
              TextField(
                controller: _principalController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: BeeTokens.textPrimary(context)),
                decoration: InputDecoration(
                  prefixText: '$currencySymbol ',
                  prefixStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: BeeTokens.textPrimary(context)),
                  hintText: l10n.debtPrincipalAmountHint,
                  hintStyle: TextStyle(fontSize: 24, color: BeeTokens.textTertiary(context)),
                  border: InputBorder.none,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.debtRepaymentAccountLabel,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BeeTokens.textSecondary(context))),
              const SizedBox(height: 12),
              AccountSelector(
                ledgerId: ledgerId,
                selectedAccountId: _accountId,
                onAccountSelected: (id) => setState(() => _accountId = id),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: InkWell(
            onTap: _pickDueDate,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.debtDueDateLabel,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BeeTokens.textSecondary(context))),
                      const SizedBox(height: 6),
                      Text(
                        _dueAt != null ? _formatDate(_dueAt!) : l10n.debtDueDateNone,
                        style: TextStyle(
                            fontSize: 16,
                            color: _dueAt != null ? BeeTokens.textPrimary(context) : BeeTokens.textTertiary(context)),
                      ),
                    ],
                  ),
                ),
                if (_dueAt != null)
                  IconButton(
                    onPressed: () => setState(() => _dueAt = null),
                    icon: Icon(Icons.close, color: BeeTokens.iconTertiary(context)),
                    tooltip: l10n.debtDueDateClear,
                  )
                else
                  Icon(Icons.chevron_right, color: BeeTokens.iconTertiary(context)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.debtNoteLabel,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BeeTokens.textSecondary(context))),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                maxLines: 3,
                style: TextStyle(fontSize: 15, color: BeeTokens.textPrimary(context)),
                decoration: InputDecoration(
                  hintText: l10n.commonNoteHint,
                  hintStyle: TextStyle(color: BeeTokens.textTertiary(context)),
                  border: InputBorder.none,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(l10n.commonSave),
          ),
        ),
      ],
    );
  }
}
