import 'package:flutter/material.dart';

import 'tokens.dart';

/// 全站页面转场:新页从右侧滑入 + 轻微淡入,旧页轻微视差位移(往左偏移一小段
/// 距离)+ 轻微变暗,仿 iOS push/pop 观感。用 [BeeMotion.standard]——导航转场
/// 不该有回弹,回弹感留给 [BeeMotion.spring] 那类「有触感」的微互动
/// (见 bee_pressable.dart)。
///
/// 减少动画开关打开(或系统无障碍设定)时退化成单纯 FadeTransition,不做
/// 滑动/视差/缩放。刻意不去动 PageRoute.transitionDuration(那是路由层级的
/// 固定值,PageTransitionsBuilder 拿不到控制权改它)——退化成淡入淡出已经
/// 去除了绝大部分动态感,不需要为了追求瞬切去动更底层的 Navigator 架构。
class BeePageTransitionsBuilder extends PageTransitionsBuilder {
  const BeePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }

    final curved = CurvedAnimation(
      parent: animation,
      curve: BeeMotion.standard,
      reverseCurve: BeeMotion.standard.flipped,
    );
    final secondaryCurved = CurvedAnimation(
      parent: secondaryAnimation,
      curve: BeeMotion.standard,
      reverseCurve: BeeMotion.standard.flipped,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(curved),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.25, 0.0),
        ).animate(secondaryCurved),
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.85, end: 1.0).animate(curved),
          child: child,
        ),
      ),
    );
  }
}
