import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../styles/tokens.dart';

/// 金額輸入用計算機鍵盤(比照 Moze 參考圖):÷×−+ 常駐一整排(不像舊版
/// AmountEditorSheet 的鍵盤用長按切換加減/乘除),下面 4 行是 7-9/⌫、
/// 4-6/C(全部清除)、1-3/↵(等於的捷徑鍵)、./0/00/✓(送出)。
///
/// 純展示 + callback,不持有金額狀態(狀態留給外層 `TransactionEntryForm`),
/// 方便獨立測試。
class AmountCalculatorKeypad extends StatelessWidget {
  final ValueChanged<String> onDigit; // '0'-'9' / '.' / '00'
  final ValueChanged<String> onOp; // '+' / '-' / '×' / '÷'
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onEquals;
  final VoidCallback onSave;
  final bool isInCalcMode;
  final bool canSubmit;
  final bool isSubmitting;

  const AmountCalculatorKeypad({
    super.key,
    required this.onDigit,
    required this.onOp,
    required this.onBackspace,
    required this.onClear,
    required this.onEquals,
    required this.onSave,
    this.isInCalcMode = false,
    this.canSubmit = false,
    this.isSubmitting = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final primary = Theme.of(context).colorScheme.primary;

    Widget cell(Widget child, {Color? bg, VoidCallback? onTap}) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: bg ?? BeeTokens.surfaceKey(context),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(
              height: 46,
              child: Center(child: child),
            ),
          ),
        ),
      );
    }

    Widget digitKey(String label) => cell(
          Text(
            label,
            style: text.titleMedium?.copyWith(
              color: BeeTokens.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          onTap: () {
            SystemSound.play(SystemSoundType.click);
            onDigit(label);
          },
        );

    Widget opKey(String op) => cell(
          Text(
            op,
            style: text.titleMedium?.copyWith(
              color: BeeTokens.textPrimary(context),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          bg: BeeTokens.surfaceKeySecondary(context),
          onTap: () {
            HapticFeedback.selectionClick();
            SystemSound.play(SystemSoundType.click);
            onOp(op);
          },
        );

    Widget backspaceKey() => cell(
          Icon(Icons.backspace_outlined,
              color: BeeTokens.textPrimary(context), size: 20),
          onTap: () {
            SystemSound.play(SystemSoundType.click);
            onBackspace();
          },
        );

    Widget clearKey() => cell(
          Text(
            'C',
            style: text.titleMedium?.copyWith(
              color: BeeTokens.textSecondary(context),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          bg: BeeTokens.surfaceKeySecondary(context),
          onTap: () {
            SystemSound.play(SystemSoundType.click);
            onClear();
          },
        );

    Widget equalsKey() => cell(
          Icon(Icons.keyboard_return_rounded,
              color: BeeTokens.textPrimary(context), size: 20),
          bg: BeeTokens.surfaceKeySecondary(context),
          onTap: () {
            HapticFeedback.selectionClick();
            SystemSound.play(SystemSoundType.click);
            onEquals();
          },
        );

    Widget saveKey() {
      final enabled = canSubmit && !isSubmitting;
      return cell(
        isSubmitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Icon(
                Icons.check,
                color: enabled ? Colors.white : BeeTokens.textTertiary(context),
                size: 20,
              ),
        bg: enabled ? primary : BeeTokens.surfaceDisabled(context),
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                SystemSound.play(SystemSoundType.click);
                if (isInCalcMode) {
                  onEquals();
                } else {
                  onSave();
                }
              }
            : null,
      );
    }

    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth / 4;
      Widget row(List<Widget> children) => Row(
            children: [
              for (final child in children) SizedBox(width: w, child: child),
            ],
          );

      return Column(
        children: [
          row([opKey('÷'), opKey('×'), opKey('-'), opKey('+')]),
          row([digitKey('7'), digitKey('8'), digitKey('9'), backspaceKey()]),
          row([digitKey('4'), digitKey('5'), digitKey('6'), clearKey()]),
          row([digitKey('1'), digitKey('2'), digitKey('3'), equalsKey()]),
          row([digitKey('.'), digitKey('0'), digitKey('00'), saveKey()]),
        ],
      );
    });
  }
}
