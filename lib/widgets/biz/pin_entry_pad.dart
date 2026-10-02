import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../providers/theme_providers.dart';
import '../ui/bee_pressable.dart';

/// PIN 码圆点指示器
class PinDotIndicator extends ConsumerWidget {
  final int length;
  final int filledCount;
  final bool isError;

  const PinDotIndicator({
    super.key,
    this.length = 4,
    required this.filledCount,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primaryColor = ref.watch(primaryColorProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (index) {
        final filled = index < filledCount;
        final dotSize = 14.0.scaled(context, ref);
        final color = isError
            ? BeeTokens.error(context)
            : (filled ? primaryColor : BeeTokens.border(context));

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: EdgeInsets.symmetric(horizontal: 10.0.scaled(context, ref)),
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : Colors.transparent,
            border: Border.all(color: color, width: 2),
          ),
        );
      }),
    );
  }
}

/// 数字键盘
class NumberPad extends ConsumerWidget {
  final ValueChanged<String> onNumberTap;
  final VoidCallback onDelete;
  final VoidCallback? onBiometric;
  final bool showBiometric;

  const NumberPad({
    super.key,
    required this.onNumberTap,
    required this.onDelete,
    this.onBiometric,
    this.showBiometric = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['bio', '0', 'del'],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: keys.map((row) {
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6.0.scaled(context, ref)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((key) {
              if (key == 'bio') {
                return _buildKeyButton(
                  context,
                  ref,
                  child: showBiometric
                      ? Icon(Icons.fingerprint,
                          size: 28.0.scaled(context, ref),
                          color: BeeTokens.textPrimary(context))
                      : const SizedBox.shrink(),
                  onTap: showBiometric ? onBiometric : null,
                );
              }
              if (key == 'del') {
                return _buildKeyButton(
                  context,
                  ref,
                  child: Icon(Icons.backspace_outlined,
                      size: 24.0.scaled(context, ref),
                      color: BeeTokens.textPrimary(context)),
                  onTap: onDelete,
                );
              }
              return _buildKeyButton(
                context,
                ref,
                child: Text(
                  key,
                  style: TextStyle(
                    fontSize: 28.0.scaled(context, ref),
                    fontWeight: FontWeight.w400,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
                onTap: () => onNumberTap(key),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKeyButton(
    BuildContext context,
    WidgetRef ref, {
    required Widget child,
    VoidCallback? onTap,
  }) {
    final size = 72.0.scaled(context, ref);
    // 佔位键(onTap == null)不可点,不做按压回馈
    if (onTap == null) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        child: child,
      );
    }
    return _PinKey(size: size, onTap: onTap, child: child);
  }
}

/// PIN 圆形按键:按下时缩放 0.92 + 底色加深一阶,触觉回馈仍在放开(onTap)时触发。
class _PinKey extends StatefulWidget {
  const _PinKey({
    required this.size,
    required this.onTap,
    required this.child,
  });

  final double size;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PinKey> createState() => _PinKeyState();
}

class _PinKeyState extends State<_PinKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final base = BeeTokens.surfaceSecondary(context);
    final pressedColor = Color.alphaBlend(
        BeeTokens.textPrimary(context).withValues(alpha: 0.08), base);
    return BeePressable(
      pressedScale: 0.92,
      onPressedChanged: (v) => setState(() => _pressed = v),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration:
            BeeMotion.durationOf(context, const Duration(milliseconds: 100)),
        width: widget.size,
        height: widget.size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _pressed ? pressedColor : base,
        ),
        child: widget.child,
      ),
    );
  }
}
