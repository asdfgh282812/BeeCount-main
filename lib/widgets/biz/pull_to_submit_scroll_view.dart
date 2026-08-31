import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

/// 記帳表單「從下往上拉到底送出」手勢。包住既有的 [SingleChildScrollView],
/// 偵測使用者把內容拉過底部邊界(overscroll)並放開,呼叫 [onSubmit]——
/// 即表單原本點存檔鍵的同一個函式,天然繼承它原有的所有驗證/錯誤提示邏輯,
/// 這個 widget 完全不需要知道「為什麼不能存」。
///
/// 強制使用 [BouncingScrollPhysics] 而非依賴平台預設(Android 的
/// [ClampingScrollPhysics] 不會真的產生 overscroll,[OverscrollNotification]
/// 永遠不會觸發),代價是這幾個表單頁在 Android 上的滑動手感會跟其他頁面不同
/// (變成 iOS 式彈性回彈)——這是刻意的取捨,換取兩平台手勢偵測一致可靠。
class PullToSubmitScrollView extends StatefulWidget {
  const PullToSubmitScrollView({
    super.key,
    required this.child,
    required this.canSubmit,
    required this.isSubmitting,
    required this.onSubmit,
    this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool canSubmit;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  @override
  State<PullToSubmitScrollView> createState() =>
      _PullToSubmitScrollViewState();
}

class _PullToSubmitScrollViewState extends State<PullToSubmitScrollView> {
  static const double _threshold = 72;

  double _dragExtent = 0;
  bool _armed = false;

  void _reset() {
    if (_dragExtent != 0 || _armed) {
      setState(() {
        _dragExtent = 0;
        _armed = false;
      });
    }
  }

  bool _onNotification(ScrollNotification notification) {
    if (notification is OverscrollNotification) {
      // dragDetails == null 代表是回彈動畫自己產生的 overscroll(手指已放開),
      // 不是使用者正在拉——只有真手指拖曳才累積距離。
      if (notification.overscroll > 0 && notification.dragDetails != null) {
        setState(() {
          _dragExtent += notification.overscroll;
          if (!_armed && _dragExtent >= _threshold) {
            _armed = true;
            HapticFeedback.mediumImpact();
          }
        });
      }
    } else if (notification is ScrollUpdateNotification) {
      // 使用者把內容拉過底部邊界後、放開前又滑回正常範圍內——視為取消手勢。
      if (notification.dragDetails != null &&
          _dragExtent > 0 &&
          notification.metrics.pixels < notification.metrics.maxScrollExtent) {
        _reset();
      }
    } else if (notification is ScrollEndNotification) {
      final shouldSubmit = _armed;
      _reset();
      if (shouldSubmit && widget.canSubmit && !widget.isSubmitting) {
        widget.onSubmit();
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragExtent / _threshold).clamp(0.0, 1.0);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onNotification,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: widget.padding,
            child: widget.child,
          ),
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
    );
  }
}
