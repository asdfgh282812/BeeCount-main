import 'package:flutter/material.dart';

import '../../styles/tokens.dart';

/// 记账流程用的底部选单 / 对话框统一入口,集中控制进出场的时长与曲线。
///
/// Flutter 内建的 sheet(250/200ms,legacyDecelerate)与 dialog(150ms 纯淡入)
/// 不看「减少动画」,而且离场的 reverseCurve 是减速曲线,套在下降的控制值上
/// 起步偏慢。这里统一成:
/// - 进场用 [BeeMotion.standard](减速,无回弹);
/// - 离场用 `standard.flipped`,一按下就立刻起步(同 SlideUpPageRoute);
/// - 底部选单禁用带 overshoot 的 spring,否则贴底的 sheet 会露出接缝;
/// - 减少动画开启时时长归零。

/// sheet 进场 [BeeMotion.medium],离场略短:使用者已决定离开,不该让他等。
const _sheetExit = Duration(milliseconds: 210);

const _dialogEnter = Duration(milliseconds: 180);
const _dialogExit = Duration(milliseconds: 120);

/// 对话框起始缩放;只缩 4%,配合淡入有「浮现」感又不抢戏。
const _dialogStartScale = 0.96;

/// 底部选单。[animationStyle] 逐欄位覆写预设值。
Future<T?> showBeeBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? backgroundColor,
  ShapeBorder? shape,
  AnimationStyle? animationStyle,
}) {
  final base = AnimationStyle(
    duration: BeeMotion.durationOf(context, BeeMotion.medium),
    reverseDuration: BeeMotion.durationOf(context, _sheetExit),
    curve: BeeMotion.standard,
    reverseCurve: BeeMotion.standard.flipped,
  );
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: backgroundColor,
    shape: shape,
    sheetAnimationStyle: animationStyle == null
        ? base
        : base.copyWith(
            duration: animationStyle.duration,
            reverseDuration: animationStyle.reverseDuration,
            curve: animationStyle.curve,
            reverseCurve: animationStyle.reverseCurve,
          ),
  );
}

/// 对话框:淡入 + 0.96→1 缩放,进场 180ms / 离场 120ms。
///
/// 内建 `showDialog` 的 AnimationStyle 只有一个 duration(离场同长),无法分开
/// 设定离场时长,所以直接用 [DialogRoute] 子类;主题捕获与 SafeArea 等包装
/// 都由 [DialogRoute] 自己处理。
Future<T?> showBeeDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  bool useRootNavigator = true,
  AnimationStyle? animationStyle,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final enter =
      animationStyle?.duration ?? BeeMotion.durationOf(context, _dialogEnter);
  final exit = animationStyle?.reverseDuration ??
      BeeMotion.durationOf(context, _dialogExit);
  return navigator.push<T>(_BeeDialogRoute<T>(
    context: context,
    builder: builder,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    barrierColor: barrierColor ??
        Theme.of(context).dialogTheme.barrierColor ??
        Colors.black54,
    barrierDismissible: barrierDismissible,
    enter: enter,
    exit: exit,
    curve: animationStyle?.curve ?? BeeMotion.standard,
    reverseCurve: animationStyle?.reverseCurve ?? BeeMotion.standard.flipped,
  ));
}

class _BeeDialogRoute<T> extends DialogRoute<T> {
  _BeeDialogRoute({
    required super.context,
    required super.builder,
    required super.themes,
    required super.barrierColor,
    required super.barrierDismissible,
    required Duration enter,
    required Duration exit,
    required Curve curve,
    required Curve reverseCurve,
  })  : _exit = exit,
        _curve = curve,
        _reverseCurve = reverseCurve,
        super(
          animationStyle: AnimationStyle(
            duration: enter,
            curve: curve,
            reverseCurve: reverseCurve,
          ),
        );

  final Duration _exit;
  final Curve _curve;
  final Curve _reverseCurve;

  @override
  Duration get reverseTransitionDuration => _exit;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // super 负责淡入(用上面传入的 curve / reverseCurve)
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      _DialogScaleIn(
        animation: animation,
        curve: _curve,
        reverseCurve: _reverseCurve,
        child: child,
      ),
    );
  }
}

class _DialogScaleIn extends StatefulWidget {
  const _DialogScaleIn({
    required this.animation,
    required this.curve,
    required this.reverseCurve,
    required this.child,
  });

  final Animation<double> animation;
  final Curve curve;
  final Curve reverseCurve;
  final Widget child;

  @override
  State<_DialogScaleIn> createState() => _DialogScaleInState();
}

class _DialogScaleInState extends State<_DialogScaleIn> {
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: widget.animation,
    curve: widget.curve,
    reverseCurve: widget.reverseCurve,
  );

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: _dialogStartScale, end: 1).animate(_curved),
      child: widget.child,
    );
  }
}
