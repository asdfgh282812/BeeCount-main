import 'package:flutter/material.dart';

import '../../styles/tokens.dart';

/// 通用按压回馈:按下时轻微缩小,放开时用回弹曲线弹回原尺寸。取代各处手刻的
/// GestureDetector + AnimatedScale 写法(例如 product_promo_card.dart 原本
/// 两处几乎一样的实现)。
class BeePressable extends StatefulWidget {
  const BeePressable({
    super.key,
    required this.child,
    required this.onTap,
    this.pressedScale = 0.96,
  });

  final Widget child;
  final VoidCallback onTap;
  final double pressedScale;

  @override
  State<BeePressable> createState() => _BeePressableState();
}

class _BeePressableState extends State<BeePressable> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? widget.pressedScale : 1.0,
        duration: BeeMotion.durationOf(context, BeeMotion.fast),
        curve: BeeMotion.spring,
        child: widget.child,
      ),
    );
  }
}
