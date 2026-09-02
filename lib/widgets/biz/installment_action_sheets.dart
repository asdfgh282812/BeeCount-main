import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../ui/ui.dart' show showToast;
import 'account_card_picker.dart';

/// 子專案 2 狀態變更操作的輸入表單(彈窗),角色對齐
/// `recurring_rule_advanced_sheet.dart` 分期 tab 的欄位收集方式——這裡只
/// 收集使用者輸入,回傳一個結果物件,
/// 實際呼叫 `repo.updatePeriodOverride`/`rebalanceFrom`/`earlyRepayPrincipal`/
/// `payoff` 由呼叫端(`installment_list_page.dart`)負責,錯誤處理/toast/
/// refresh 也是呼叫端的事,這裡刻意保持「純輸入表單」不碰 repository。

/// [PeriodOverrideSheet] 的輸入結果——三個欄位都一定有值(表單以目前值
/// 預填,使用者存檔即視為確認這三個值,對齐一般「編輯表單」的既有慣例;
/// `updatePeriodOverride` 本身雖然支援三者獨立可選的部分更新,但 UI 全欄位
/// 編輯表單一律送出目前顯示的值,不特別追蹤「使用者是否真的改過某欄位」)。
class PeriodOverrideInput {
  final double amount;
  final DateTime dueAt;
  final String? note;
  const PeriodOverrideInput({
    required this.amount,
    required this.dueAt,
    this.note,
  });
}

class PeriodOverrideSheet {
  static Future<PeriodOverrideInput?> show(
    BuildContext context, {
    required InstallmentPeriod period,
    required String? currentNote,
    required String currencySymbol,
  }) {
    return showModalBottomSheet<PeriodOverrideInput?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BeeTokens.surfaceSheet(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _PeriodOverrideSheetBody(
        period: period,
        currentNote: currentNote,
        currencySymbol: currencySymbol,
      ),
    );
  }
}

class _PeriodOverrideSheetBody extends StatefulWidget {
  final InstallmentPeriod period;
  final String? currentNote;
  final String currencySymbol;

  const _PeriodOverrideSheetBody({
    required this.period,
    required this.currentNote,
    required this.currencySymbol,
  });

  @override
  State<_PeriodOverrideSheetBody> createState() =>
      _PeriodOverrideSheetBodyState();
}

class _PeriodOverrideSheetBodyState extends State<_PeriodOverrideSheetBody> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  late DateTime _dueAt;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
        text: widget.period.totalAmount.toStringAsFixed(2));
    _noteCtrl = TextEditingController(text: widget.currentNote ?? '');
    _dueAt = widget.period.dueAt;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDueAt() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dueAt = picked);
  }

  void _confirm() {
    final l10n = AppLocalizations.of(context);
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      showToast(context, l10n.installmentTotalAmountHint);
      return;
    }
    final note = _noteCtrl.text.trim();
    Navigator.of(context).pop(PeriodOverrideInput(
      amount: amount,
      dueAt: _dueAt,
      note: note.isEmpty ? null : note,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SheetScaffold(
      title: l10n.installmentPeriodEditSheetTitle,
      onConfirm: _confirm,
      children: [
        sheetLabel(context, l10n.installmentPeriodAmountLabel),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
          ],
          decoration: InputDecoration(
            prefixText: '${widget.currencySymbol} ',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        sheetLabel(context, l10n.installmentPeriodDueAtLabel),
        InkWell(
          onTap: _pickDueAt,
          child: InputDecorator(
            decoration: const InputDecoration(border: OutlineInputBorder()),
            child: Text(formatSheetDate(_dueAt)),
          ),
        ),
        const SizedBox(height: 12),
        sheetLabel(context, l10n.installmentPeriodNoteLabel),
        TextField(
          controller: _noteCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: l10n.commonNoteHint,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

/// [RebalanceFromSheet] 的輸入結果。[repaymentMethod] 一律有值(選擇器永遠
/// 有選定項)——語意上等同「使用者確認的還款方式」,即使沒改動也等於原本的
/// `plan.repaymentMethod`,repo 端據此更新沒有副作用。
class RebalanceFromInput {
  final double interestRate; // 年利率,小數
  final String repaymentMethod;
  const RebalanceFromInput({
    required this.interestRate,
    required this.repaymentMethod,
  });
}

class RebalanceFromSheet {
  static Future<RebalanceFromInput?> show(
    BuildContext context, {
    required int periodNo,
    required double currentInterestRate,
    required String currentRepaymentMethod,
  }) {
    return showModalBottomSheet<RebalanceFromInput?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BeeTokens.surfaceSheet(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _RebalanceFromSheetBody(
        periodNo: periodNo,
        currentInterestRate: currentInterestRate,
        currentRepaymentMethod: currentRepaymentMethod,
      ),
    );
  }
}

class _RebalanceFromSheetBody extends StatefulWidget {
  final int periodNo;
  final double currentInterestRate;
  final String currentRepaymentMethod;

  const _RebalanceFromSheetBody({
    required this.periodNo,
    required this.currentInterestRate,
    required this.currentRepaymentMethod,
  });

  @override
  State<_RebalanceFromSheetBody> createState() =>
      _RebalanceFromSheetBodyState();
}

class _RebalanceFromSheetBodyState extends State<_RebalanceFromSheetBody> {
  late final TextEditingController _rateCtrl;
  late String _repaymentMethod;

  @override
  void initState() {
    super.initState();
    final ratePercent = widget.currentInterestRate * 100;
    _rateCtrl = TextEditingController(
        text: ratePercent == ratePercent.roundToDouble()
            ? ratePercent.toStringAsFixed(0)
            : ratePercent.toString());
    _repaymentMethod = widget.currentRepaymentMethod;
  }

  @override
  void dispose() {
    _rateCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    final ratePercent = double.tryParse(_rateCtrl.text.trim()) ?? 0.0;
    if (ratePercent < 0) {
      final l10n = AppLocalizations.of(context);
      showToast(context, l10n.installmentInterestRateHint);
      return;
    }
    Navigator.of(context).pop(RebalanceFromInput(
      // 內部存小數,對齐 Cloud interestRateToPercentDisplay/
      // percentDisplayToInterestRate 換算慣例,用 toStringAsFixed 再轉回
      // double 避免二進位浮點誤差殘留(同 installment_editor_page.dart/
      // installment_draft_sheet.dart 的既有手法)。
      interestRate: double.parse((ratePercent / 100).toStringAsFixed(6)),
      repaymentMethod: _repaymentMethod,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SheetScaffold(
      title: l10n.installmentRebalanceSheetTitle(widget.periodNo),
      onConfirm: _confirm,
      children: [
        sheetLabel(context, l10n.installmentRepaymentMethodLabel),
        sheetSegmentedRow(
          context,
          options: {
            'equal_principal': l10n.installmentMethodEqualPrincipal,
            'equal_installment': l10n.installmentMethodEqualInstallment,
            'fixed_interest': l10n.installmentMethodFixedInterest,
          },
          value: _repaymentMethod,
          onChanged: (v) => setState(() => _repaymentMethod = v),
        ),
        const SizedBox(height: 12),
        sheetLabel(context, l10n.installmentInterestRateLabel),
        TextField(
          controller: _rateCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          decoration: InputDecoration(
            suffixText: '%',
            helperText: l10n.installmentInterestRateHint,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

/// [EarlyRepayPrincipalSheet] 的輸入結果。[accountId]==null 代表沿用
/// `plan.accountId`(repo 端的預設行為)。
class EarlyRepayPrincipalInput {
  final double paymentAmount;
  final int? accountId;
  final DateTime happenedAt;
  const EarlyRepayPrincipalInput({
    required this.paymentAmount,
    required this.accountId,
    required this.happenedAt,
  });
}

class EarlyRepayPrincipalSheet {
  static Future<EarlyRepayPrincipalInput?> show(
    BuildContext context, {
    required int ledgerId,
    required String currencySymbol,
    int? initialAccountId,
  }) {
    return showModalBottomSheet<EarlyRepayPrincipalInput?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BeeTokens.surfaceSheet(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _EarlyRepayPrincipalSheetBody(
        ledgerId: ledgerId,
        currencySymbol: currencySymbol,
        initialAccountId: initialAccountId,
      ),
    );
  }
}

class _EarlyRepayPrincipalSheetBody extends ConsumerStatefulWidget {
  final int ledgerId;
  final String currencySymbol;
  final int? initialAccountId;

  const _EarlyRepayPrincipalSheetBody({
    required this.ledgerId,
    required this.currencySymbol,
    required this.initialAccountId,
  });

  @override
  ConsumerState<_EarlyRepayPrincipalSheetBody> createState() =>
      _EarlyRepayPrincipalSheetBodyState();
}

class _EarlyRepayPrincipalSheetBodyState
    extends ConsumerState<_EarlyRepayPrincipalSheetBody> {
  final _amountCtrl = TextEditingController();
  DateTime _happenedAt = DateTime.now();
  int? _accountId;
  Account? _account;

  @override
  void initState() {
    super.initState();
    _accountId = widget.initialAccountId;
    if (_accountId != null) {
      ref.read(repositoryProvider).getAccount(_accountId!).then((a) {
        if (mounted) setState(() => _account = a);
      });
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _happenedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _happenedAt = picked);
  }

  Future<void> _pickAccount() async {
    final result = await AccountCardPicker.show(
      context,
      ledgerId: widget.ledgerId,
      selectedAccountId: _accountId,
    );
    if (result?.accountId == null || !mounted) return;
    final account =
        await ref.read(repositoryProvider).getAccount(result!.accountId!);
    if (!mounted) return;
    setState(() {
      _accountId = result.accountId;
      _account = account;
    });
  }

  void _confirm() {
    final l10n = AppLocalizations.of(context);
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      showToast(context, l10n.installmentEarlyRepayAmountHint);
      return;
    }
    Navigator.of(context).pop(EarlyRepayPrincipalInput(
      paymentAmount: amount,
      accountId: _accountId,
      happenedAt: _happenedAt,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SheetScaffold(
      title: l10n.installmentEarlyRepaySheetTitle,
      onConfirm: _confirm,
      children: [
        sheetLabel(context, l10n.installmentEarlyRepayAmountLabel),
        TextField(
          controller: _amountCtrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
          ],
          decoration: InputDecoration(
            prefixText: '${widget.currencySymbol} ',
            hintText: l10n.installmentEarlyRepayAmountHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        sheetLabel(context, l10n.installmentEarlyRepayDateLabel),
        InkWell(
          onTap: _pickDate,
          child: InputDecorator(
            decoration: const InputDecoration(border: OutlineInputBorder()),
            child: Text(formatSheetDate(_happenedAt)),
          ),
        ),
        const SizedBox(height: 12),
        sheetLabel(context, l10n.installmentAccountLabel),
        InkWell(
          onTap: _pickAccount,
          child: InputDecorator(
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              helperText: l10n.installmentUseDefaultAccountHint,
            ),
            child: Text(_account?.name ?? l10n.installmentAccountNone),
          ),
        ),
      ],
    );
  }
}

/// [PayoffSheet] 的輸入結果。
class PayoffInput {
  final int? accountId;
  final DateTime happenedAt;
  const PayoffInput({required this.accountId, required this.happenedAt});
}

class PayoffSheet {
  static Future<PayoffInput?> show(
    BuildContext context, {
    required int ledgerId,
    double? previewSettleAmount,
    String? currencySymbol,
    int? initialAccountId,
  }) {
    return showModalBottomSheet<PayoffInput?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BeeTokens.surfaceSheet(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _PayoffSheetBody(
        ledgerId: ledgerId,
        previewSettleAmount: previewSettleAmount,
        currencySymbol: currencySymbol,
        initialAccountId: initialAccountId,
      ),
    );
  }
}

class _PayoffSheetBody extends ConsumerStatefulWidget {
  final int ledgerId;
  final double? previewSettleAmount;
  final String? currencySymbol;
  final int? initialAccountId;

  const _PayoffSheetBody({
    required this.ledgerId,
    required this.previewSettleAmount,
    required this.currencySymbol,
    required this.initialAccountId,
  });

  @override
  ConsumerState<_PayoffSheetBody> createState() => _PayoffSheetBodyState();
}

class _PayoffSheetBodyState extends ConsumerState<_PayoffSheetBody> {
  DateTime _happenedAt = DateTime.now();
  int? _accountId;
  Account? _account;

  @override
  void initState() {
    super.initState();
    _accountId = widget.initialAccountId;
    if (_accountId != null) {
      ref.read(repositoryProvider).getAccount(_accountId!).then((a) {
        if (mounted) setState(() => _account = a);
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _happenedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _happenedAt = picked);
  }

  Future<void> _pickAccount() async {
    final result = await AccountCardPicker.show(
      context,
      ledgerId: widget.ledgerId,
      selectedAccountId: _accountId,
    );
    if (result?.accountId == null || !mounted) return;
    final account =
        await ref.read(repositoryProvider).getAccount(result!.accountId!);
    if (!mounted) return;
    setState(() {
      _accountId = result.accountId;
      _account = account;
    });
  }

  void _confirm() {
    Navigator.of(context)
        .pop(PayoffInput(accountId: _accountId, happenedAt: _happenedAt));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SheetScaffold(
      title: l10n.installmentPayoffSheetTitle,
      onConfirm: _confirm,
      children: [
        if (widget.previewSettleAmount != null &&
            widget.currencySymbol != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: BeeTokens.surfaceSecondary(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.installmentPayoffPreviewLabel,
                    style: TextStyle(color: BeeTokens.textSecondary(context))),
                Text(
                  '${widget.currencySymbol}${widget.previewSettleAmount!.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        sheetLabel(context, l10n.installmentPayoffDateLabel),
        InkWell(
          onTap: _pickDate,
          child: InputDecorator(
            decoration: const InputDecoration(border: OutlineInputBorder()),
            child: Text(formatSheetDate(_happenedAt)),
          ),
        ),
        const SizedBox(height: 12),
        sheetLabel(context, l10n.installmentAccountLabel),
        InkWell(
          onTap: _pickAccount,
          child: InputDecorator(
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              helperText: l10n.installmentUseDefaultAccountHint,
            ),
            child: Text(_account?.name ?? l10n.installmentAccountNone),
          ),
        ),
      ],
    );
  }
}

// ==================== 共用小工具(僅供本檔案內的彈窗使用) ====================

/// 統一的彈窗外殼:標題列(含取消鍵)+ 內容 + 底部確認鍵,對齐
/// `installment_draft_sheet.dart` 的既有版面。
class SheetScaffold extends StatelessWidget {
  final String title;
  final VoidCallback onConfirm;
  final List<Widget> children;

  const SheetScaffold({
    super.key,
    required this.title,
    required this.onConfirm,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.commonCancel),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...children,
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onConfirm,
                  child: Text(l10n.commonConfirm),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget sheetLabel(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: BeeTokens.textSecondary(context)),
      ),
    );

Widget sheetSegmentedRow(
  BuildContext context, {
  required Map<String, String> options,
  required String value,
  required ValueChanged<String> onChanged,
}) {
  final primary = Theme.of(context).colorScheme.primary;
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final entry in options.entries)
        ChoiceChip(
          label: Text(entry.value),
          selected: value == entry.key,
          onSelected: (_) => onChanged(entry.key),
          selectedColor: primary.withValues(alpha: 0.15),
          labelStyle: TextStyle(
            color:
                value == entry.key ? primary : BeeTokens.textSecondary(context),
            fontWeight: value == entry.key ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
    ],
  );
}

String formatSheetDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
