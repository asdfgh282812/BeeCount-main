import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// 亮色/暗色主题共用的页面转场对照表。
///
/// iOS 刻意不用 [BeePageTransitionsBuilder]:Flutter 的「从左缘右滑返回」手势
/// (`_CupertinoBackGestureDetector`,框架私有类别)只有经由
/// `CupertinoRouteTransitionMixin.buildPageTransitions` 才会挂上去,自订的
/// PageTransitionsBuilder 无从复用,iOS 上若套用自订转场,整个 App 就失去
/// 右滑返回。代价:iOS 上「减少动画」不再退化成淡入淡出,跟系统原生页面在
/// 「减少动态效果」下仍保留 push/pop 滑动的行为一致。
const kBeePageTransitionsTheme = PageTransitionsTheme(builders: {
  TargetPlatform.android: BeePageTransitionsBuilder(),
  TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
  TargetPlatform.macOS: BeePageTransitionsBuilder(),
  TargetPlatform.windows: BeePageTransitionsBuilder(),
  TargetPlatform.linux: BeePageTransitionsBuilder(),
});

/// 非 iOS 平台的页面转场(iOS 为何不用见 [kBeePageTransitionsTheme]):新页
/// 从右侧滑入 + 轻微淡入,旧页轻微视差位移(往左偏移一小段距离)+ 轻微变暗,
/// 仿 iOS push/pop 观感。用 [BeeMotion.standard]——导航转场
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
