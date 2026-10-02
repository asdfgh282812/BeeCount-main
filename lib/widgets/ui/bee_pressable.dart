import 'package:flutter/material.dart';

import '../../styles/tokens.dart';

/// 通用按压回馈:按下时轻微缩小,放开时用回弹曲线弹回原尺寸。取代各处手刻的
/// GestureDetector + AnimatedScale 写法(例如 product_promo_card.dart 原本
/// 两处几乎一样的实现)。
///
/// - 按下:[_pressDuration](100ms)+ [BeeMotion.standard](ease-out,无回弹)。
/// - 放开:[BeeMotion.fast](150ms)+ [BeeMotion.spring](带回弹)。
///
/// 按下态用 [Listener.onPointerDown] 立即触发,而不是 `onTapDown`:后者要等
/// 手指按住超过 ~100ms(kPressTimeout)才会回呼,快速点击时 down/up 同一帧
/// 到达,缩放会被瞬间取消而完全看不到。还原则交给 `onTapUp` / `onTapCancel`
/// ——手指开始捲动、外层水平拖曳(底部导航列)或长按赢得手势时,tap 会被取消,
/// 缩放自动复原。
///
/// 长按回呼原样透传给 [GestureDetector],中间记帐键的扇形选单依赖
/// start / moveUpdate / end 三个回呼(见 app.dart)。
class BeePressable extends StatefulWidget {
  const BeePressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.onPressedChanged,
    this.pressedScale = 0.96,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;

  /// 按下态变化回呼(true=按下,false=还原),供外层同步做底色等额外回馈。
  final ValueChanged<bool>? onPressedChanged;

  /// 按下时的缩放比例:小元件(chip、按钮)0.96,大区块 0.98,
  /// 小图示的导航 tab 0.92。
  final double pressedScale;
  final HitTestBehavior behavior;

  @override
  State<BeePressable> createState() => _BeePressableState();
}

class _BeePressableState extends State<BeePressable> {
  static const _pressDuration = Duration(milliseconds: 100);

  bool _isPressed = false;

  void _setPressed(bool value) {
    if (_isPressed == value) return;
    setState(() => _isPressed = value);
    widget.onPressedChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: widget.behavior,
      onPointerDown: (_) => _setPressed(true),
      child: GestureDetector(
        behavior: widget.behavior,
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onLongPressStart: widget.onLongPressStart,
        onLongPressMoveUpdate: widget.onLongPressMoveUpdate,
        onLongPressEnd: widget.onLongPressEnd,
        child: AnimatedScale(
          scale: _isPressed ? widget.pressedScale : 1.0,
          duration: BeeMotion.durationOf(
              context, _isPressed ? _pressDuration : BeeMotion.fast),
          curve: _isPressed ? BeeMotion.standard : BeeMotion.spring,
          child: widget.child,
        ),
      ),
    );
  }
}
