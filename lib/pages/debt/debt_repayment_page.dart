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

/// 借還款的還款/收款記錄頁。對齐 BeeCount Cloud 的設計:還款「沒有獨立的
/// 實體」,就是一筆帶 debtSyncId 的普通 expense/income 交易——這裡是一個
/// 獨立的小頁面(同 Cloud web 的 repayment dialog,不是走完整交易表單),
/// 只收金額/帳戶/日期/備註,分類留空(還款不需要分類)。
class DebtRepaymentPage extends ConsumerStatefulWidget {
  final Debt debt;
  final double suggestedAmount;

  const DebtRepaymentPage({
    required this.debt,
    required this.suggestedAmount,
    super.key,
  });

  @override
  ConsumerState<DebtRepaymentPage> createState() => _DebtRepaymentPageState();
}

class _DebtRepaymentPageState extends ConsumerState<DebtRepaymentPage> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  int? _accountId;
  DateTime _happenedAt = DateTime.now();
  bool _isLoading = false;

  bool get _isPayable => widget.debt.direction == kDebtDirectionPayable;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.suggestedAmount.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final currencyCode =
        ref.watch(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    final currencySymbol = getCurrencySymbol(currencyCode);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: _isPayable
                ? l10n.debtRepaymentPageTitlePayable
                : l10n.debtRepaymentPageTitleReceivable,
            showBack: true,
            compact: true,
            actions: [
              TextButton(
                onPressed: _isLoading ? null : _save,
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
                        l10n.debtPrincipalAmountLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                      SizedBox(height: 12.0.scaled(context, ref)),
                      TextField(
                        controller: _amountController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d+\.?\d{0,2}')),
                        ],
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: BeeTokens.textPrimary(context),
                        ),
                        decoration: InputDecoration(
                          prefixText: '$currencySymbol ',
                          prefixStyle: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: BeeTokens.textPrimary(context),
                          ),
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
                        l10n.debtRepaymentAccountLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                      SizedBox(height: 8.0.scaled(context, ref)),
                      AccountSelector(
                        ledgerId: ledgerId,
                        selectedAccountId: _accountId,
                        onAccountSelected: (id) =>
                            setState(() => _accountId = id),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.0.scaled(context, ref)),
                SectionCard(
                  child: InkWell(
                    onTap: _pickDate,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.debtRepaymentDateLabel,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: BeeTokens.textSecondary(context),
                                ),
                              ),
                              SizedBox(height: 6.0.scaled(context, ref)),
                              Text(
                                _formatDate(_happenedAt),
                                style: TextStyle(
                                    fontSize: 16,
                                    color: BeeTokens.textPrimary(context)),
                              ),
                            ],
                          ),
                        ),
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
                        l10n.debtRepaymentNoteLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                      SizedBox(height: 12.0.scaled(context, ref)),
                      TextField(
                        controller: _noteController,
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _happenedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _happenedAt = DateTime(
            picked.year,
            picked.month,
            picked.day,
            _happenedAt.hour,
            _happenedAt.minute,
          ));
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      showToast(context, l10n.debtRepaymentAmountInvalid);
      return;
    }
    if (_accountId == null) {
      showToast(context, l10n.debtRepaymentAccountRequired);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(repositoryProvider);
      final ledgerId = ref.read(currentLedgerIdProvider);
      final note = _noteController.text.trim();

      await repo.addTransaction(
        ledgerId: ledgerId,
        type: _isPayable ? 'expense' : 'income',
        amount: amount,
        accountId: _accountId,
        happenedAt: _happenedAt,
        note: note.isEmpty ? null : note,
        debtSyncId: widget.debt.syncId,
      );

      ref.read(debtsRefreshProvider.notifier).state++;
      ref.read(statsRefreshProvider.notifier).state++;
      unawaited(PostProcessor.sync(ref, ledgerId: ledgerId));

      if (mounted) {
        showToast(context, l10n.debtRepaymentSuccess);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
