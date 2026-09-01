import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

/// 記帳表單「從下往上拉到底送出」手勢。包住既有的 [SingleChildScrollView],
/// 偵測使用者把內容拉過底部邊界並放開,呼叫 [onSubmit]——即表單原本點存檔鍵
/// 的同一個函式,天然繼承它原有的所有驗證/錯誤提示邏輯,這個 widget 完全
/// 不需要知道「為什麼不能存」。
///
/// v2(2026-09-01,真機回報手勢「沒有反應」修正):原本靠
/// [OverscrollNotification] 偵測,只能在使用者手指壓在 [SingleChildScrollView]
/// 本體範圍內才有效——但表單下方常常還疊著固定不滾動的
/// [AmountCalculatorKeypad]/[KeyboardSuggestionBar](見 [bottomBar]),手指從
/// 那塊區域開始拉,ScrollView 完全收不到任何事件,使用者會覺得「整個手勢沒用」。
/// 改用 [Listener] 直接監聽原始指標事件,涵蓋整個 widget(包含 [bottomBar]);
/// 判斷條件從「實際 overscroll 像素」改成「[_scrollController] 已到底 + 手指
/// 持續往上移動的原始距離」,不再依賴 [BouncingScrollPhysics] 的摩擦阻尼(那個
/// 阻尼會讓同樣的手指移動距離换算出遠小於 72px 的 overscroll,變相拉高實際
/// 需要的滑動距離)。副作用是不用再強制 Android 使用 iOS 式回彈手感——
/// [SingleChildScrollView] 現在用回平台預設 physics。
class PullToSubmitScrollView extends StatefulWidget {
  const PullToSubmitScrollView({
    super.key,
    required this.child,
    required this.canSubmit,
    required this.isSubmitting,
    required this.onSubmit,
    this.padding,
    this.bottomBar,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool canSubmit;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  /// 疊在滾動內容下方、固定不隨滾動的區塊(如金額小算盤、備註歷史建議列)。
  /// 手指壓在這塊區域拖曳一樣算數,見上方 class 說明。
  final Widget? bottomBar;

  @override
  State<PullToSubmitScrollView> createState() => _PullToSubmitScrollViewState();
}

class _PullToSubmitScrollViewState extends State<PullToSubmitScrollView> {
  static const double _threshold = 72;

  final ScrollController _scrollController = ScrollController();

  int? _activePointer;
  double? _lastPointerY;
  double _dragExtent = 0;
  bool _armed = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _reset() {
    if (_dragExtent != 0 || _armed) {
      setState(() {
        _dragExtent = 0;
        _armed = false;
      });
    }
  }

  bool get _scrolledToBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.pixels >= position.maxScrollExtent - 0.5;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _lastPointerY = event.position.dy;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    final lastY = _lastPointerY;
    _lastPointerY = event.position.dy;
    if (lastY == null) return;
    final dy = event.position.dy - lastY; // 負值代表手指往上移動

    if (dy < 0 && _scrolledToBottom) {
      setState(() {
        _dragExtent += -dy;
        if (!_armed && _dragExtent >= _threshold) {
          _armed = true;
          HapticFeedback.mediumImpact();
        }
      });
    } else if (dy > 0 && _dragExtent > 0) {
      // 手指往回移動(不論是否已武裝)一律視為取消這次手勢。
      _reset();
    }
  }

  void _onPointerEnd(int pointer) {
    if (pointer != _activePointer) return;
    _activePointer = null;
    _lastPointerY = null;
    final shouldSubmit = _armed;
    _reset();
    if (shouldSubmit && widget.canSubmit && !widget.isSubmitting) {
      widget.onSubmit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragExtent / _threshold).clamp(0.0, 1.0);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: (e) => _onPointerEnd(e.pointer),
      onPointerCancel: (e) => _onPointerEnd(e.pointer),
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: widget.padding,
                  child: widget.child,
                ),
              ),
              if (widget.bottomBar != null) widget.bottomBar!,
            ],
          ),
          if (progress > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: IgnorePointer(
                child: Center(
                  child: Opacity(
                    opacity: progress,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary
                            .withValues(alpha: _armed ? 0.95 : 0.75),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.keyboard_double_arrow_up_rounded,
                            size: 16,
                            color: theme.colorScheme.onPrimary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _armed
                                ? l10n.pullToSubmitRelease
                                : l10n.pullToSubmitHint,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
