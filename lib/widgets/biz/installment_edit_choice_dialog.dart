import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';
import 'installment_action_sheets.dart'
    show SheetScaffold, sheetLabel, formatSheetDate;
import '../ui/ui.dart' show showToast;

/// 子專案 3(見設計文件 §5.3):交易明細頁點擊「編輯」時,若這筆交易
/// `installmentPlanSyncId != null`,彈出這個四選一對話框,取代子專案 1 的
/// 唯讀鎖定 banner。四個選項對應子專案 2 已經做好的操作:
/// - [thisRecordOnly]:單期覆寫(`updatePeriodOverride`,`PeriodOverrideSheet`)。
/// - [rebalanceFromHere]:連同未來重算(`rebalanceFrom`,`RebalanceFromSheet`)。
/// - [earlyRepayPrincipal]:提前還本(`earlyRepayPrincipal`,
///   `EarlyRepayPrincipalSheet`)。
/// - [payoff]:提前繳清(`payoff`,`PayoffSheet`)。
///
/// 呼叫端(`transaction_detail_card.dart`)負責找出這筆交易對應的
/// [InstallmentPlan]/[InstallmentPeriod]、依選擇結果打開對應 sheet、呼叫
/// repository 方法——這裡只負責「問使用者要做哪一種」。
enum InstallmentEditChoice {
  thisRecordOnly,
  rebalanceFromHere,
  earlyRepayPrincipal,
  payoff,
}

/// [planActive] 為 false(計畫已 settled/terminated)時不提供「提前還本」/
/// 「提前繳清」——這兩個操作只對還在還款中的計畫有意義,跟
/// `installment_list_page.dart` 卡片本身只在 `status==active` 才顯示這兩顆
/// 按鈕是同一個限制。單期覆寫/連同未來重算兩個選項不受這個限制(對齐
/// `_PeriodListSection` 的既有行為——展開後的單期編輯/重算圖示不論計畫狀態
/// 一律顯示)。
Future<InstallmentEditChoice?> showInstallmentEditChoiceSheet(
  BuildContext context, {
  required bool planActive,
}) {
  final l10n = AppLocalizations.of(context);
  return _showChoiceSheet<InstallmentEditChoice>(
    context,
    title: l10n.installmentEditChoiceTitle,
    options: [
      (
        label: l10n.installmentEditChoiceThisRecordOnly,
        value: InstallmentEditChoice.thisRecordOnly,
        destructive: false,
      ),
      (
        label: l10n.installmentEditChoiceRebalanceFromHere,
        value: InstallmentEditChoice.rebalanceFromHere,
        destructive: false,
      ),
      if (planActive) ...[
        (
          label: l10n.installmentEditChoiceEarlyRepay,
          value: InstallmentEditChoice.earlyRepayPrincipal,
          destructive: false,
        ),
        (
          label: l10n.installmentEditChoicePayoff,
          value: InstallmentEditChoice.payoff,
          destructive: false,
        ),
      ],
    ],
  );
}

/// 子專案 3:交易明細頁的退款入口,若這筆交易屬於分期計畫,彈出這個二選一
/// 對話框——「只退這一期」(`refundPeriod`)/「整筆退款」(直接呼叫既有的
/// `deleteInstallmentPlan`,連已發生期交易一起刪)。兩者互斥,見設計文件
/// §3.3。
enum InstallmentRefundChoice { periodOnly, wholePlan }

Future<InstallmentRefundChoice?> showInstallmentPeriodRefundChoiceSheet(
    BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return _showChoiceSheet<InstallmentRefundChoice>(
    context,
    title: l10n.installmentRefundChoiceTitle,
    options: [
      (
        label: l10n.installmentRefundChoicePeriodOnly,
        value: InstallmentRefundChoice.periodOnly,
        destructive: false,
      ),
      (
        label: l10n.installmentRefundChoiceWholePlan,
        value: InstallmentRefundChoice.wholePlan,
        destructive: true,
      ),
    ],
  );
}

/// 問題 A 修正(2026-09-03,見
/// docs/changes/2026-09-03-installment-tracking-delete-sync-fixes.md):
/// 交易明細頁(及其他共用 `TransactionEditUtils.deleteTransactionGuarded`
/// 入口)點擊「刪除」時,若這筆交易 `installmentPlanSyncId != null` 且對應
/// 計畫仍存在,彈出這個二選一對話框——取代子專案 1/2 的「請去分期頁操作」
/// 硬性攔截(那個攔截在整筆刪除計畫後偶爾殘留孤兒交易時會讓使用者卡死,無
/// 法刪除也無法在分期頁找到計畫)。
/// - [thisRecordOnly]:只刪這一筆(`InstallmentRepository.deletePeriod`,不
///   重算/不動其他期數金額)。
/// - [wholePlan]:刪除整個分期計畫(既有的 `deleteInstallmentPlan`,連已發生
///   期交易一起刪),呼叫端需要另外做一次破壞性操作二次確認(同
///   `InstallmentRefundChoice.wholePlan` 的既有 pattern)。
enum InstallmentTransactionDeleteChoice { thisRecordOnly, wholePlan }

Future<InstallmentTransactionDeleteChoice?>
    showInstallmentTransactionDeleteChoiceSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return _showChoiceSheet<InstallmentTransactionDeleteChoice>(
    context,
    title: l10n.installmentDeleteChoiceTitle,
    options: [
      (
        label: l10n.installmentDeleteChoiceThisRecordOnly,
        value: InstallmentTransactionDeleteChoice.thisRecordOnly,
        destructive: true,
      ),
      (
        label: l10n.installmentDeleteChoiceWholePlan,
        value: InstallmentTransactionDeleteChoice.wholePlan,
        destructive: true,
      ),
    ],
  );
}

/// 通用「標題 + N 個選項 + 取消」底部彈窗殼——跟
/// `recurring_occurrence_dialogs.dart` 的 `_showChoiceSheet`(週期規則的
/// 編輯/刪除範圍二選一)版面完全一致,這裡沒有直接 import 重用(那個是私有
/// 函式),獨立複製一份小的殼子,不引入跨檔案的私有耦合。
Future<T?> _showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<({String label, T value, bool destructive})> options,
}) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: BeeTokens.surfaceSheet(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: BeeTokens.divider(ctx),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: BeeTokens.textSecondary(ctx),
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final o in options)
            ListTile(
              title: Text(
                o.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: o.destructive
                      ? BeeTokens.error(ctx)
                      : BeeTokens.textPrimary(ctx),
                ),
              ),
              onTap: () => Navigator.pop(ctx, o.value),
            ),
          const Divider(height: 1),
          ListTile(
            title: Text(
              l10n.commonCancel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: BeeTokens.textSecondary(ctx),
              ),
            ),
            onTap: () => Navigator.pop(ctx),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

/// [InstallmentPeriodRefundSheet] 的輸入結果。
class InstallmentPeriodRefundInput {
  final double amount;
  final String? note;
  final DateTime happenedAt;
  const InstallmentPeriodRefundInput({
    required this.amount,
    this.note,
    required this.happenedAt,
  });
}

/// 「只退這一期」選擇後的輸入表單——金額預填該期 `totalAmount`(可覆寫,
/// 天然支援部分退款)、備註留空(repo 端預設「分期退款」)、日期預設今天。
/// 版面殼子沿用 `installment_action_sheets.dart` 的 `SheetScaffold`/
/// `sheetLabel`/`formatSheetDate`,不重新畫一份。
class InstallmentPeriodRefundSheet {
  static Future<InstallmentPeriodRefundInput?> show(
    BuildContext context, {
    required double defaultAmount,
    required String currencySymbol,
  }) {
    return showModalBottomSheet<InstallmentPeriodRefundInput?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BeeTokens.surfaceSheet(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _InstallmentPeriodRefundSheetBody(
        defaultAmount: defaultAmount,
        currencySymbol: currencySymbol,
      ),
    );
  }
}

class _InstallmentPeriodRefundSheetBody extends StatefulWidget {
  final double defaultAmount;
  final String currencySymbol;

  const _InstallmentPeriodRefundSheetBody({
    required this.defaultAmount,
    required this.currencySymbol,
  });

  @override
  State<_InstallmentPeriodRefundSheetBody> createState() =>
      _InstallmentPeriodRefundSheetBodyState();
}

class _InstallmentPeriodRefundSheetBodyState
    extends State<_InstallmentPeriodRefundSheetBody> {
  late final TextEditingController _amountCtrl;
  final _noteCtrl = TextEditingController();
  DateTime _happenedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _amountCtrl =
        TextEditingController(text: widget.defaultAmount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
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

  void _confirm() {
    final l10n = AppLocalizations.of(context);
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      showToast(context, l10n.installmentPeriodRefundAmountHint);
      return;
    }
    final note = _noteCtrl.text.trim();
    Navigator.of(context).pop(InstallmentPeriodRefundInput(
      amount: amount,
      note: note.isEmpty ? null : note,
      happenedAt: _happenedAt,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SheetScaffold(
      title: l10n.installmentPeriodRefundSheetTitle,
      onConfirm: _confirm,
      children: [
        sheetLabel(context, l10n.installmentPeriodRefundAmountLabel),
        TextField(
          controller: _amountCtrl,
          autofocus: true,
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
        sheetLabel(context, l10n.installmentPeriodRefundDateLabel),
        InkWell(
          onTap: _pickDate,
          child: InputDecorator(
            decoration: const InputDecoration(border: OutlineInputBorder()),
            child: Text(formatSheetDate(_happenedAt)),
          ),
        ),
        const SizedBox(height: 12),
        sheetLabel(context, l10n.installmentPeriodRefundNoteLabel),
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
