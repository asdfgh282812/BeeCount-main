import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../styles/tokens.dart';

/// 底部导航列的滑动胶囊 + 「按住左右拖曳选分页」手势(仿 iOS 26 分页列,
/// 不含玻璃材质)。
///
/// - 点按切页:胶囊以 [BeeMotion.softSpring] 滑到新分页(300ms)。
/// - 拖曳:水平拖曳一开始胶囊放大「浮起」(1.0→1.12,easeOutBack),随后跟着
///   手指走;手指下的分页即时亮起(activeIndex),每跨一格给一次轻触觉回馈。
///   放开时吸附到手指所在分页、胶囊缩回,并通知 [onSelected] 切页。
/// - 跟随用「短时长隐式动画反复重定目标」:每次 drag update 都让
///   AnimatedPositioned 从目前位置补间到新手指位置(90ms easeOutCubic),
///   等于一阶平滑——手指从别的分页起拖时胶囊会快速滑过去而不是瞬移,
///   正常拖曳时几乎贴手。
///
/// 手势竞技场:外层是 HorizontalDrag,分页本身是 Tap(中间按钮另有 LongPress)。
/// 手指移动超过 slop 才判给拖曳,所以一般点按不受影响;在「記帳」态的中间
/// 按钮上按住不动 500ms 仍是既有的快速记帐扇形选单(LongPress 先胜出)。
class BeeTabDragScope extends StatefulWidget {
  const BeeTabDragScope({
    super.key,
    required this.currentIndex,
    required this.tabCount,
    required this.primaryColor,
    required this.onSelected,
    required this.builder,
  });

  final int currentIndex;
  final int tabCount;
  final Color primaryColor;
  final ValueChanged<int> onSelected;

  /// [activeIndex] 是此刻该亮起的分页;[indicator] 是已定位好的胶囊层,
  /// 由呼叫端决定摆在 Stack 的哪一层。
  final Widget Function(BuildContext context, int activeIndex, Widget indicator)
      builder;

  @override
  State<BeeTabDragScope> createState() => _BeeTabDragScopeState();
}

class _BeeTabDragScopeState extends State<BeeTabDragScope> {
  /// 点按/放开后吸附:微阻尼弹簧,约 52% 时首次抵达、~1.5% 回弹后收敛。
  static const Duration _snapDuration = Duration(milliseconds: 300);

  /// 拖曳中跟手的平滑时长(见 class 说明)。
  static const Duration _followDuration = Duration(milliseconds: 90);

  static const Duration _liftDuration = Duration(milliseconds: 220);

  /// 拖曳中胶囊放大比例:高 46×1.12≈51.5,仍在 56 高的导航列内。
  static const double _liftScale = 1.12;

  /// 胶囊尺寸:高沿用改版前 AnimatedContainer 的视觉量(6+图标 22+1+文字
  /// ~12+6 ≈ 46);宽固定(原本随 label 长度伸缩),滑动时才不会忽宽忽窄。
  static const double _indicatorHeight = 46;
  static const double _indicatorMaxWidth = 64;

  /// 拖曳中手指的 x(相对导航列);null = 没在拖。
  double? _dragX;

  /// 拖曳中手指所在分页。
  int? _hoverIndex;

  /// 放开后、父层 currentIndex 还没更新到这一格之前的过渡目标——避免中间
  /// 那一帧胶囊先往旧分页弹再折返。
  int? _settlingIndex;

  double _width = 0;

  bool get _isDragging => _dragX != null;

  int get _targetIndex => _hoverIndex ?? _settlingIndex ?? widget.currentIndex;

  @override
  void didUpdateWidget(covariant BeeTabDragScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex) _settlingIndex = null;
  }

  int _indexAt(double x) {
    final slot = _width / widget.tabCount;
    if (slot <= 0) return widget.currentIndex;
    return (x / slot).floor().clamp(0, widget.tabCount - 1);
  }

  void _updateDrag(double x) {
    final index = _indexAt(x);
    if (index != _hoverIndex) HapticFeedback.selectionClick();
    setState(() {
      _dragX = x;
      _hoverIndex = index;
    });
  }

  void _onDragStart(DragStartDetails d) {
    _settlingIndex = null;
    _hoverIndex = _indexAt(d.localPosition.dx); // 起点不给触觉回馈
    setState(() => _dragX = d.localPosition.dx);
  }

  void _onDragUpdate(DragUpdateDetails d) => _updateDrag(d.localPosition.dx);

  void _onDragEnd([DragEndDetails? _]) {
    final selected = _hoverIndex;
    setState(() {
      _dragX = null;
      _hoverIndex = null;
      if (selected != null && selected != widget.currentIndex) {
        _settlingIndex = selected;
      }
    });
    if (selected != null && selected != widget.currentIndex) {
      widget.onSelected(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _width = constraints.maxWidth;
      final slotWidth = _width / widget.tabCount;
      final capsuleWidth = (slotWidth - 8).clamp(0.0, _indicatorMaxWidth);
      final minLeft = (slotWidth - capsuleWidth) / 2;
      final maxLeft = _width - slotWidth + minLeft;

      final left = _isDragging
          // 胶囊中心跟手指,限制在第一格与最后一格的置中位置之间
          ? (_dragX! - capsuleWidth / 2).clamp(minLeft, maxLeft)
          : slotWidth * _targetIndex + minLeft;

      final indicator = Stack(
        children: [
          AnimatedPositioned(
            duration: BeeMotion.durationOf(
                context, _isDragging ? _followDuration : _snapDuration),
            // 非线性:拖曳中减速跟随;吸附时微阻尼弹簧
            curve: _isDragging ? BeeMotion.standard : BeeMotion.softSpring,
            left: left,
            top: (constraints.maxHeight - _indicatorHeight) / 2,
            width: capsuleWidth,
            height: _indicatorHeight,
            child: AnimatedScale(
              scale: _isDragging ? _liftScale : 1.0,
              duration: BeeMotion.durationOf(context, _liftDuration),
              // 浮起带一点回弹;落下不回弹,免得缩过头
              curve: _isDragging ? BeeMotion.spring : BeeMotion.standard,
              child: AnimatedContainer(
                duration: BeeMotion.durationOf(context, _liftDuration),
                curve: BeeMotion.standard,
                decoration: BoxDecoration(
                  // 拖曳中底色加深一点,强调「被拿起来」
                  color: widget.primaryColor
                      .withValues(alpha: _isDragging ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(_indicatorHeight / 2),
                ),
              ),
            ),
          ),
        ],
      );

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: _onDragEnd,
        child: widget.builder(context, _targetIndex, indicator),
      );
    });
  }
}
