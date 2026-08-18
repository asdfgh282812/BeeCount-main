import 'package:drift/drift.dart' as d;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart' as db;
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../utils/credit_card_payment.dart';
import '../../utils/currencies.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/account_card_picker.dart';
import '../../widgets/biz/biz.dart';
import '../../widgets/ui/ui.dart';

/// MOZE 對標:合併帳單主帳戶(`account_type=='account_group'`)一次繳款,
/// 自動按 [allocateCardPayment] 的規則分攤到各子卡。演算法照抄 BeeCount
/// Cloud `src/services/credit_card_billing.py::compute_card_payment_allocations`
/// (足額付清+溢繳歸群組本身、不足額按比例+最後一筆吃餘數)。
///
/// 明確排除範圍:子卡跨幣別時不做匯率換算(來源帳戶幣別 = [currencyCode]
/// 篩選,同幣別假設);送出後每筆 transfer 各自獨立(可個別編輯/刪除),
/// 不建立額外的「批次」關聯實體。
class CreditCardGroupPaymentPage extends ConsumerStatefulWidget {
  final db.Account account;
  final List<db.Account> children;
  final ({DateTime start, DateTime end}) period;
  final String currencyCode;

  const CreditCardGroupPaymentPage({
    super.key,
    required this.account,
    required this.children,
    required this.period,
    required this.currencyCode,
  });

  @override
  ConsumerState<CreditCardGroupPaymentPage> createState() =>
      _CreditCardGroupPaymentPageState();
}

class _CreditCardGroupPaymentPageState
    extends ConsumerState<CreditCardGroupPaymentPage> {
  bool _loadingDue = true;
  Map<int, double> _remainingDueByChild = {};
  int? _fromAccountId;
  db.Account? _fromAccount;
  final TextEditingController _amountController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadDue();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadDue() async {
    final repo = ref.read(repositoryProvider);
    final cutoff = endOfDay(widget.period.end);
    final due = <int, double>{};
    for (final child in widget.children) {
      // 跟帳單彙總卡片同一套 Cloud-對齊公式(charged - 終身 paidTotal,不能用
      // getCreditCardUsedAmount——那個方法混入了 initialBalance/adjustment,
      // 對不上 Server 端的信用卡帳單口徑)。
      final charged =
          await repo.getCreditCardChargedAsOf(child.id, asOf: cutoff);
      final paidTotal = await repo.getCreditCardPaidTotal(child.id);
      final amount = creditCardDueAsOf(charged: charged, paidTotal: paidTotal);
      if (amount > 0.005) due[child.id] = amount;
    }
    if (!mounted) return;
    final total = due.values.fold(0.0, (a, b) => a + b);
    setState(() {
      _remainingDueByChild = due;
      _loadingDue = false;
      _amountController.text = total.toStringAsFixed(2);
    });
  }

  Map<int, double> get _allocations {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) return const {};
    return allocateCardPayment(
      remainingDueByChild: _remainingDueByChild,
      amount: amount,
      groupAccountId: widget.account.id,
    );
  }

  Future<void> _pickFromAccount() async {
    final currentLedger = ref.read(currentLedgerProvider).asData?.value;
    if (currentLedger == null) return;
    final result = await AccountCardPicker.show(
      context,
      ledgerId: currentLedger.id,
      selectedAccountId: _fromAccountId,
      filterCurrency: widget.currencyCode,
      excludeAccountId: widget.account.id,
      allowNull: false,
    );
    final accountId = result?.accountId;
    if (accountId == null) return;
    final repo = ref.read(repositoryProvider);
    final account = await repo.getAccount(accountId);
    if (!mounted) return;
    setState(() {
      _fromAccountId = accountId;
      _fromAccount = account;
    });
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final fromId = _fromAccountId;
    final allocations = _allocations;
    if (fromId == null || allocations.isEmpty) return;

    final currentLedger = ref.read(currentLedgerProvider).asData?.value;
    if (currentLedger == null) return;

    setState(() => _submitting = true);
    final repo = ref.read(repositoryProvider);
    final now = DateTime.now();
    final note = creditCardPaymentNote(billingDay: widget.account.billingDay);
    final overflowNote = creditCardPaymentNote(
      billingDay: widget.account.billingDay,
      isOverflowToGroup: true,
    );
    final fromCurrency = _fromAccount?.currency ?? widget.currencyCode;

    final companions = [
      for (final entry in allocations.entries)
        db.TransactionsCompanion.insert(
          ledgerId: currentLedger.id,
          type: 'transfer',
          amount: entry.value,
          accountId: d.Value(fromId),
          toAccountId: d.Value(entry.key),
          happenedAt: d.Value(now),
          note: d.Value(entry.key == widget.account.id ? overflowNote : note),
          currencyCode: d.Value(fromCurrency),
          nativeAmount: d.Value(entry.value),
        ),
    ];

    await repo.insertTransactionsBatch(companions);
    if (!mounted) return;
    setState(() => _submitting = false);
    showToast(context, l10n.creditCardGroupPaymentSuccess(companions.length));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allocations = _allocations;
    final totalDue = _remainingDueByChild.values.fold(0.0, (a, b) => a + b);
    final childNameById = {for (final c in widget.children) c.id: c.name};

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.creditCardGroupPaymentPageTitle,
            subtitle: widget.account.name,
            showBack: true,
            compact: true,
          ),
          Expanded(
            child: _loadingDue
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: EdgeInsets.all(16.0.scaled(context, ref)),
                    children: [
                      SectionCard(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: EdgeInsets.all(16.0.scaled(context, ref)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.creditCardGroupPaymentSourceAccount,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: BeeTokens.textSecondary(context)),
                              ),
                              SizedBox(height: 6.0.scaled(context, ref)),
                              InkWell(
                                onTap: _pickFromAccount,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 12.0.scaled(context, ref),
                                    vertical: 12.0.scaled(context, ref),
                                  ),
                                  decoration: BoxDecoration(
                                    color: BeeTokens.surfaceInput(context),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _fromAccount?.name ??
                                              l10n.creditCardGroupPaymentSourceAccount,
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: _fromAccount == null
                                                ? BeeTokens.textTertiary(
                                                    context)
                                                : BeeTokens.textPrimary(
                                                    context),
                                          ),
                                        ),
                                      ),
                                      Icon(Icons.chevron_right,
                                          size: 18,
                                          color:
                                              BeeTokens.iconSecondary(context)),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(height: 16.0.scaled(context, ref)),
                              Text(
                                l10n.creditCardGroupPaymentTotalAmount,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: BeeTokens.textSecondary(context)),
                              ),
                              SizedBox(height: 6.0.scaled(context, ref)),
                              TextFormField(
                                controller: _amountController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d*\.?\d{0,2}')),
                                ],
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w600),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: BeeTokens.surfaceInput(context),
                                  prefixText:
                                      '${getCurrencySymbol(widget.currencyCode)} ',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 12.0.scaled(context, ref)),
                      SectionCard(
                        margin: EdgeInsets.zero,
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  EdgeInsets.all(12.0.scaled(context, ref)),
                              child: Text(
                                l10n.creditCardGroupPaymentAllocationPreview,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: BeeTokens.textPrimary(context),
                                ),
                              ),
                            ),
                            for (final entry
                                in _remainingDueByChild.entries) ...[
                              BeeTokens.cardDivider(context),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12.0.scaled(context, ref),
                                  vertical: 10.0.scaled(context, ref),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        childNameById[entry.key] ?? '',
                                        style: TextStyle(
                                            fontSize: 14,
                                            color:
                                                BeeTokens.textPrimary(context)),
                                      ),
                                    ),
                                    AmountText(
                                      value: allocations[entry.key] ?? 0,
                                      signed: false,
                                      showCurrency: false,
                                      currencyCode: widget.currencyCode,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: BeeTokens.textPrimary(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (allocations.containsKey(widget.account.id)) ...[
                              BeeTokens.cardDivider(context),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12.0.scaled(context, ref),
                                  vertical: 10.0.scaled(context, ref),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        l10n.creditCardGroupPaymentOverflowTo(
                                            widget.account.name),
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: BeeTokens.textSecondary(
                                                context)),
                                      ),
                                    ),
                                    AmountText(
                                      value:
                                          allocations[widget.account.id] ?? 0,
                                      signed: false,
                                      showCurrency: false,
                                      currencyCode: widget.currencyCode,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: BeeTokens.textSecondary(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(height: 4.0.scaled(context, ref)),
                      Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 4.0.scaled(context, ref)),
                        child: Text(
                          totalDue <= 0
                              ? l10n.billingSummaryPaidOff
                              : l10n.creditCardGroupPaymentTotalDueHint(
                                  totalDue.toStringAsFixed(2)),
                          style: TextStyle(
                              fontSize: 12,
                              color: BeeTokens.textTertiary(context)),
                        ),
                      ),
                    ],
                  ),
          ),
          if (!_loadingDue)
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.all(16.0.scaled(context, ref)),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _fromAccountId == null ||
                            allocations.isEmpty ||
                            _submitting
                        ? null
                        : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(l10n.creditCardGroupPaymentSubmit),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
