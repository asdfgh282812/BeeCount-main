import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../styles/tokens.dart';

/// 由螢幕底部往上滑入的全螢幕頁面路由(新增記帳等「建立型」視窗用),
/// 支援「從哪來就從哪回」的下滑關閉手勢。
///
/// 動畫組成:
/// - 頁面:translateY 100% → 0%,[BeeMotion.standard](easeOutCubic)減速進場;
///   關閉時同一條曲線反向播放 = 先慢後快的加速離場,手感像把卡片「推回」底部。
///   進出場同為 [_duration],符合「以相同速度收回」。
/// - 遮罩:[barrierColor] 由 ModalRoute 內建的 barrier 自動隨 route 動畫
///   淡入/淡出,曲線由 [barrierCurve] 指定(同樣非線性)。下滑拖曳時遮罩也
///   跟著手指即時變淡。
///
/// 下滑關閉(見 [_SheetDismissGesture]):
/// - 不會捲動的區域(標題列、空白處、小算盤):直接往下拖。
/// - 會捲動的區域:內容已經在頂端時再往下拉,才改成拖整個頁面(同 iOS 原生
///   sheet);內容沒捲到頂時照常捲動內容。
/// - 放開時:往下甩(速度 > [_flingVelocity])或拖過 [_dismissFraction] 高度 →
///   關閉;否則彈回原位。兩者都用 easeOutCubic 並依剩餘距離縮短時長。
/// - 跟 iOS 返回手勢同一套判斷(見 [_canStartDismissGesture]):頁面裡有
///   PopScope(canPop: false) 之類擋關閉的邏輯時,手勢自動停用。
///
/// 設計取捨:
/// - `fullscreenDialog: true`:讓底下的 MaterialPageRoute/Cupertino 路由的
///   `canTransitionTo` 回傳 false,底層頁面不會跟著做左移視差,只被遮罩壓暗。
/// - `opaque: true`:TransitionRoute 在動畫進行中本來就會把 overlay entry 暫時
///   設為非不透明(看得到底下頁面與遮罩),動畫結束才轉為不透明,讓底層頁面
///   被 offstage、Ticker 被停掉——避免首頁動態皮肤在背後持續重繪發燙
///   (見 app.dart IndexedStack 那段 TickerMode 說明)。拖曳期間 route 動畫
///   離開 completed,底層頁面會自動重新顯示在遮罩後面。
/// - 自訂路由拿不到 iOS 左緣右滑返回手勢(框架私有),以下滑關閉取代。
/// - 減少動畫開啟時,進出場退化為單純淡入淡出。
class SlideUpPageRoute<T> extends PageRoute<T> {
  SlideUpPageRoute({
    required this.builder,
    super.settings,
  }) : super(fullscreenDialog: true);

  final WidgetBuilder builder;

  static const _duration = Duration(milliseconds: 300);

  /// 放開時往下甩的速度門檻(logical px/s),超過就直接關閉。
  static const double _flingVelocity = 700;

  /// 沒有甩動時,拖超過頁面高度的這個比例才關閉,否則彈回。
  static const double _dismissFraction = 0.35;

  @override
  Duration get transitionDuration => _duration;

  @override
  Duration get reverseTransitionDuration => _duration;

  @override
  bool get opaque => true;

  @override
  bool get maintainState => true;

  /// 半透明黑色遮罩(Scrim)。
  @override
  Color? get barrierColor => Colors.black54;

  /// 遮罩淡入淡出曲線:與頁面位移同一條減速曲線,兩者視覺上同步。
  @override
  Curve get barrierCurve => BeeMotion.standard;

  /// 頁面露出遮罩的時候(進出場動畫期間)點擊遮罩可關閉。
  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  // ---------------------------------------------------------------------------
  // 下滑關閉手勢:由 [_SheetDismissGesture] 回報拖曳量,這裡直接操作 route 的
  // AnimationController(value 1 = 完全展開、0 = 完全收到底部外)。
  // 流程比照 Flutter Cupertino 返回手勢(_CupertinoBackGestureController)。
  // ---------------------------------------------------------------------------

  /// 拖曳中(含放開後的收尾動畫)為 true。這段期間 [buildTransitions] 改用
  /// 線性映射,頁面才會 1:1 跟手——若沿用 easeOutCubic,在 value≈1 附近曲線
  /// 幾乎是平的,手指往下拉頁面卻幾乎不動。
  bool _dismissGestureActive = false;
  NavigatorState? _gestureNavigator;

  /// 目前展開程度(1 = 完全展開)。controller 是 protected,給手勢 State 讀用。
  double get _sheetValue => controller!.value;

  /// 同 [ModalRoute.popGestureEnabled] 的判斷(頂層路由、有 PopScope 擋、
  /// 動畫未結束都不行),但不能直接呼叫它:[PageRoute] 覆寫成
  /// 「fullscreenDialog 一律 false」,而這裡為了不讓底層頁面做視差刻意設了
  /// fullscreenDialog。也不覆寫 popGestureEnabled 本身——Android 預測式返回
  /// 也讀它,改了會連帶改變那條路徑的行為。
  bool get _canStartDismissGesture =>
      !_dismissGestureActive &&
      isCurrent &&
      !isFirst &&
      !willHandlePopInternally &&
      popDisposition != RoutePopDisposition.doNotPop &&
      animation!.isCompleted;

  void _handleDismissStart() {
    _dismissGestureActive = true;
    _gestureNavigator = navigator!..didStartUserGesture();
  }

  /// [dy] 往下為正;[height] 為頁面高度,用來把像素換算成 0~1 進度。
  void _handleDismissUpdate(double dy, double height) {
    if (height <= 0) return;
    controller!.value -= dy / height; // AnimationController 自動 clamp 在 0~1
  }

  void _handleDismissEnd(double velocityY) {
    final ctrl = controller!;
    final nav = _gestureNavigator!;
    final bool dismiss;
    if (velocityY > _flingVelocity) {
      dismiss = true;
    } else if (velocityY < -_flingVelocity) {
      dismiss = false;
    } else {
      dismiss = ctrl.value < 1 - _dismissFraction;
    }

    // 表單可能在拖曳中途自己關掉了頁面(例如送出成功),這時不能再 pop 一次,
    // 否則會把底下的頁面也關掉。
    if (dismiss && isCurrent) {
      // pop 觸發 didPop → controller.reverse();隨即以自訂曲線覆蓋,讓收尾
      // 與進場同一條 easeOutCubic,時長依剩餘距離等比縮短。
      nav.pop();
      if (ctrl.isAnimating) {
        ctrl.animateBack(0,
            duration: _duration * ctrl.value, curve: BeeMotion.standard);
      }
    } else if (!dismiss && ctrl.value < 1) {
      ctrl.animateTo(1,
          duration: _duration * (1 - ctrl.value), curve: BeeMotion.standard);
    }

    void finish() {
      _dismissGestureActive = false;
      _gestureNavigator = null;
      nav.didStopUserGesture();
    }

    if (ctrl.isAnimating) {
      late final AnimationStatusListener listener;
      listener = (status) {
        if (status.isAnimating) return;
        ctrl.removeStatusListener(listener);
        finish();
      };
      ctrl.addStatusListener(listener);
    } else {
      finish();
    }
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      _SheetDismissGesture(route: this, child: builder(context));

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context) && !_dismissGestureActive) {
      return FadeTransition(opacity: animation, child: child);
    }
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1), // translateY: 100%(螢幕底部外)
        end: Offset.zero, // translateY: 0%
      ).animate(_dismissGestureActive
          // 拖曳中線性 1:1 跟手;收尾曲線由 animateTo/animateBack 自己帶
          ? animation
          : CurvedAnimation(
              parent: animation,
              // 進場減速;reverseCurve 留空 = 反向時沿用同一條曲線,
              // 效果為先慢後快的加速離場(Material 的 exit 慣例)。
              curve: BeeMotion.standard,
            )),
      child: child,
    );
  }
}

/// 偵測下滑關閉手勢,把拖曳量回報給 [SlideUpPageRoute]。兩種來源:
///
/// 1. **不會捲動的區域**:外層 [GestureDetector] 的垂直拖曳。會捲動的區域
///    其 Scrollable 的拖曳辨識器在手勢競技場裡比較深、會先勝出,所以這裡
///    自然只接到「沒人要」的垂直拖曳。只在第一段位移「往下」時才啟動——
///    往上拉是表單「拉到底送出」的手勢(PullToSubmitScrollView,走原始指標
///    事件),不能被這裡吃掉或誤觸關閉。
/// 2. **會捲動的區域且內容已在頂端**:[_SheetScrollPhysics] 讓頂端不回彈、
///    改發 [OverscrollNotification];收到「往下拉過頂端」就接手,之後由外層
///    [Listener] 讀原始指標位移驅動頁面,同時凍結內容捲動(避免內容和頁面
///    一起動)。拖回原位後若手指繼續往上,就把手勢還給內容照常捲動。
class _SheetDismissGesture extends StatefulWidget {
  const _SheetDismissGesture({required this.route, required this.child});

  final SlideUpPageRoute<dynamic> route;
  final Widget child;

  @override
  State<_SheetDismissGesture> createState() => _SheetDismissGestureState();
}

enum _DragSource { none, recognizer, scroll }

class _SheetDismissGestureState extends State<_SheetDismissGesture> {
  _DragSource _source = _DragSource.none;
  double _height = 0;

  /// 來源 1:已通過競技場、等待第一段位移判斷方向。
  bool _recognizerPending = false;

  /// 來源 2:最近一根按下的手指與其速度追蹤。
  int? _lastPointer;
  VelocityTracker? _velocityTracker;

  /// 來源 2 期間凍結內容捲動(見 [_SheetScrollPhysics.isFrozen])。
  /// 跟 [_source] 分開,因為放開時要晚一拍才解凍,見 [_endScrollDrag]。
  bool _frozen = false;

  SlideUpPageRoute<dynamic> get _route => widget.route;

  // ---- 來源 1:不會捲動的區域 ----------------------------------------------

  void _onVerticalDragStart(DragStartDetails details) {
    _recognizerPending =
        _source == _DragSource.none && _route._canStartDismissGesture;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_recognizerPending) {
      // 辨識器勝出後第一個 update 常是 0 位移(slop 已在 start 前吃掉),
      // 要等到真正有方向的那一步才判斷。
      if (details.delta.dy == 0) return;
      _recognizerPending = false;
      if (details.delta.dy < 0) return; // 先往上 = 拉到底送出,不處理
      _source = _DragSource.recognizer;
      _route._handleDismissStart();
    }
    if (_source == _DragSource.recognizer) {
      _route._handleDismissUpdate(details.delta.dy, _height);
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _recognizerPending = false;
    if (_source != _DragSource.recognizer) return;
    _source = _DragSource.none;
    _route._handleDismissEnd(details.velocity.pixelsPerSecond.dy);
  }

  void _onVerticalDragCancel() {
    _recognizerPending = false;
    if (_source != _DragSource.recognizer) return;
    _source = _DragSource.none;
    _route._handleDismissEnd(0);
  }

  // ---- 來源 2:會捲動的區域 ------------------------------------------------

  bool _onScrollNotification(ScrollNotification n) {
    if (n is OverscrollNotification &&
        n.metrics.axis == Axis.vertical &&
        n.dragDetails != null && // 只接手指拖曳,不接慣性滑動撞到頂端
        n.overscroll < 0 && // 往下拉過頂端
        _source == _DragSource.none &&
        _lastPointer != null &&
        _route._canStartDismissGesture) {
      // 指標事件的派送順序:hit-test 路徑上的 RenderObject(含外層 Listener)
      // 先收到,最後才由 GestureBinding 轉給手勢辨識器——所以觸發這則通知的
      // 那一步,外層 Listener 已經處理過(當時還沒接手),越界量要在這裡補上;
      // 之後的位移都由 Listener 先套用,辨識器那邊內容已凍結、不會重複移動。
      _source = _DragSource.scroll;
      _frozen = true;
      _velocityTracker = VelocityTracker.withKind(PointerDeviceKind.touch);
      _route._handleDismissStart();
      _route._handleDismissUpdate(-n.overscroll, _height);
    }
    return false;
  }

  void _onPointerDown(PointerDownEvent e) => _lastPointer = e.pointer;

  void _onPointerMove(PointerMoveEvent e) {
    if (_source != _DragSource.scroll || e.pointer != _lastPointer) return;
    _velocityTracker!.addPosition(e.timeStamp, e.position);
    final dy = e.delta.dy;
    if (dy < 0 && _route._sheetValue >= 1) {
      // 已拖回原位還繼續往上 → 把手勢還給內容捲動(立即解凍,同一個事件
      // 接著送到辨識器,內容就從這一步開始捲)
      _endScrollDrag(0);
      _frozen = false;
      return;
    }
    _route._handleDismissUpdate(dy, _height);
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_source != _DragSource.scroll || e.pointer != _lastPointer) return;
    _endScrollDrag(_velocityTracker!.getVelocity().pixelsPerSecond.dy);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (_source != _DragSource.scroll || e.pointer != _lastPointer) return;
    _endScrollDrag(0);
  }

  void _endScrollDrag(double velocityY) {
    _source = _DragSource.none;
    _velocityTracker = null;
    _route._handleDismissEnd(velocityY);
    // 放開時 Listener 比辨識器先收到 up 事件;晚一拍(整個事件派送完)才解凍,
    // 辨識器那邊的 drag end 才不會拿這次甩動的速度讓內容慣性滑動。
    Future.microtask(() {
      if (_source != _DragSource.scroll) _frozen = false;
    });
  }

  bool _isScrollFrozen() => _frozen;

  @override
  Widget build(BuildContext context) {
    final baseBehavior = ScrollConfiguration.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      _height = constraints.maxHeight;
      return Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: GestureDetector(
          onVerticalDragStart: _onVerticalDragStart,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          onVerticalDragCancel: _onVerticalDragCancel,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: ScrollConfiguration(
              behavior: baseBehavior.copyWith(
                physics: _SheetScrollPhysics(
                  isFrozen: _isScrollFrozen,
                  parent: baseBehavior.getScrollPhysics(context),
                ),
              ),
              child: widget.child,
            ),
          ),
        ),
      );
    });
  }
}

/// 頁面內所有未自訂 physics 的 Scrollable 共用的捲動物理(自訂 physics 的
/// 也會以此為 parent,邊界判斷一樣生效),只影響垂直方向:
/// - 頂端不回彈(同 iOS 原生 sheet):往下拉過頂端改發 [OverscrollNotification],
///   交給 [_SheetDismissGesture] 接手拖整個頁面。底端照舊(平台預設回彈),
///   「拉到底送出」不受影響。
/// - [isFrozen] 為 true(頁面正被拖著走)時,內容不跟著捲、也不做慣性滑動。
class _SheetScrollPhysics extends ScrollPhysics {
  const _SheetScrollPhysics({required this.isFrozen, super.parent});

  final ValueGetter<bool> isFrozen;

  @override
  _SheetScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _SheetScrollPhysics(isFrozen: isFrozen, parent: buildParent(ancestor));

  bool _isVertical(ScrollMetrics m) => m.axis == Axis.vertical;

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (_isVertical(position) && isFrozen()) return 0;
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (_isVertical(position)) {
      final min = position.minScrollExtent;
      // 已在頂端(或更上面)還要往上越界
      if (value < position.pixels && position.pixels <= min) {
        return value - position.pixels;
      }
      // 這一步會從內容區跨過頂端
      if (value < min && min < position.pixels) return value - min;
    }
    return super.applyBoundaryConditions(position, value);
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    if (_isVertical(position) && isFrozen()) return null;
    return super.createBallisticSimulation(position, velocity);
  }
}
