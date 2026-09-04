import 'package:flutter/material.dart';

import '../../styles/tokens.dart';

/// 手續費/折扣(折損)展開互動共用的「+」toggle 按鈕(圓形 icon button)。
/// 原本只有 `transfer_form.dart`(v46 轉帳手續費/折損)在用;v51 支出/收入
/// 手續費/折扣加入後抽成共用元件,行為/外觀不變,兩邊各自傳入 tooltip 文案。
class AdjustmentToggleButton extends StatelessWidget {
  const AdjustmentToggleButton({
    super.key,
    required this.enabled,
    required this.tooltip,
    required this.onPressed,
  });

  final bool enabled;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(
        enabled ? Icons.remove_circle_outline : Icons.add_circle_outline,
        size: 20,
        color: enabled
            ? Theme.of(context).colorScheme.primary
            : BeeTokens.iconSecondary(context),
      ),
    );
  }
}

/// 手續費/折扣(折損)一列的「可自訂名稱欄(上排)+ 幣別徽章與金額欄(下排)」,
/// 從 `transfer_form.dart` 原本內嵌在 `_buildAdjustmentPanel` 裡的佈局抽出。
/// 原本轉出/轉入兩側各自一份完整面板、各自在名稱列尾巴放「移除」連結;v51
/// 支出/收入手續費/折扣要在同一個面板裡疊兩列(手續費+折扣共用一個「移除」),
/// 所以「移除」連結改成外部可選的 [labelRowTrailing] 插槽,轉帳沿用時把
/// 「移除」連結傳進來即可,行為/外觀不變。
class AdjustmentFieldRow extends StatelessWidget {
  const AdjustmentFieldRow({
    super.key,
    this.labelFieldKey,
    this.amountFieldKey,
    required this.labelCtrl,
    required this.labelFocus,
    this.amountCtrl,
    this.amountFocus,
    required this.currency,
    required this.labelHint,
    this.amountHint,
    this.labelRowTrailing,
    this.onAmountChanged,
    this.amountCellOverride,
  }) : assert(
          amountCellOverride != null ||
              (amountCtrl != null && amountFocus != null && amountHint != null),
          '沒有 amountCellOverride 時,amountCtrl/amountFocus/amountHint 三者必填'
          '(系統鍵盤輸入模式需要)。',
        );

  final Key? labelFieldKey;
  final Key? amountFieldKey;
  final TextEditingController labelCtrl;
  final FocusNode labelFocus;
  final TextEditingController? amountCtrl;
  final FocusNode? amountFocus;
  final String currency;
  final String labelHint;
  final String? amountHint;
  final Widget? labelRowTrailing;
  // 支出/收入手續費/折扣面板要即時預覽淨額(轉帳沒有這個需求,留空即可,
  // 行為不變)。
  final ValueChanged<String>? onAmountChanged;
  // v51:支出/收入手續費/折扣改用跟主金額一致的計算機鍵盤輸入(不再跳系統
  // 鍵盤),非 null 時取代原本的金額 TextField——呼叫端(transaction_entry_
  // form.dart)自行組出「點金額文字才叫出鍵盤」的 tap 目標,這裡只負責把它
  // 靠右放進金額列。轉帳沿用系統鍵盤輸入,不傳這個參數,行為不變。
  final Widget? amountCellOverride;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: labelFieldKey,
                controller: labelCtrl,
                focusNode: labelFocus,
                style: TextStyle(
                    color: BeeTokens.textPrimary(context), fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: labelHint,
                  hintStyle: TextStyle(
                      color: BeeTokens.textTertiary(context), fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (labelRowTrailing != null) labelRowTrailing!,
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: BeeTokens.surfaceKeySecondary(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                currency.toUpperCase(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: BeeTokens.textSecondary(context),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: amountCellOverride != null
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: amountCellOverride,
                    )
                  : TextField(
                      key: amountFieldKey,
                      controller: amountCtrl,
                      focusNode: amountFocus,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.end,
                      onChanged: onAmountChanged,
                      style: TextStyle(
                        color: BeeTokens.textPrimary(context),
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: amountHint,
                        hintStyle:
                            TextStyle(color: BeeTokens.textTertiary(context)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}
