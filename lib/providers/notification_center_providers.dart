import 'dart:async';

import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/notification_factory.dart';
import 'sync_providers.dart';

/// 通知中心状态 —— App 只展示 server(BeeCount Cloud)已生成的通知,不做任何
/// 本地通知规则计算。[error] 非空时代表最近一次 refresh 失败,items/unreadCount
/// 保留上一次成功拉取的结果,由页面决定要不要展示重试态。
class NotificationCenterState {
  const NotificationCenterState({
    this.items = const [],
    this.unreadCount = 0,
    this.loading = false,
    this.error,
  });

  final List<BeeCountCloudNotificationItem> items;
  final int unreadCount;
  final bool loading;
  final Object? error;

  NotificationCenterState copyWith({
    List<BeeCountCloudNotificationItem>? items,
    int? unreadCount,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) {
    return NotificationCenterState(
      items: items ?? this.items,
      unreadCount: unreadCount ?? this.unreadCount,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

const _pollInterval = Duration(seconds: 60);

/// 通知中心 Notifier —— 只在 BeeCount Cloud 后端激活时轮询
/// `GET /notifications`。[notificationCenterProvider] 的 builder 里
/// watch 了 [beecountCloudProviderInstance],切换/退出 Cloud 后端会让
/// provider 重建(旧实例连同其 Timer 一起 dispose),无需额外的状态机。
class NotificationCenterNotifier
    extends StateNotifier<NotificationCenterState> {
  NotificationCenterNotifier(this._cloudProvider)
      : super(const NotificationCenterState()) {
    if (_cloudProvider != null) {
      state = state.copyWith(loading: true);
      unawaited(refresh());
      _pollTimer = Timer.periodic(_pollInterval, (_) => refresh());
    }
  }

  final BeeCountCloudProvider? _cloudProvider;
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    final provider = _cloudProvider;
    if (provider == null || !mounted) return;
    state = state.copyWith(loading: true);
    try {
      final page = await provider.fetchNotifications();
      if (!mounted) return;
      state = NotificationCenterState(
        items: page.items,
        unreadCount: page.unreadCount,
      );
      unawaited(_notifyNewUnread(page.items));
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: e);
    }
  }

  static const _lastNotifiedIdKey = 'notification_center_last_notified_id';

  /// 把輪詢新拉到的未讀通知順便跳一則本機系統通知,讓 App 開著/剛回前景時
  /// 使用者不用主動點開通知中心才看得到(見
  /// docs/changes/2026-09-13-notification-center-local-push.md)。只在 App
  /// 有在跑輪詢時生效,不是真正的遠端推播,App 完全關閉時不會補跳。
  ///
  /// 用 SharedPreferences 存一個「看過的最大 id」watermark 去重,避免同一則
  /// 每次輪詢都重跳一次。第一次執行(本機還沒有 watermark,例如剛升級這個
  /// 版本或剛登入)只記錄當下最大 id 當基準線、不倒著把既有未讀通通跳出來。
  Future<void> _notifyNewUnread(List<BeeCountCloudNotificationItem> items) async {
    if (items.isEmpty) return;
    final maxId = items.map((item) => item.id).reduce((a, b) => a > b ? a : b);
    final prefs = await SharedPreferences.getInstance();
    final lastNotifiedId = prefs.getInt(_lastNotifiedIdKey);

    if (lastNotifiedId == null) {
      await prefs.setInt(_lastNotifiedIdKey, maxId);
      return;
    }

    final newUnread =
        items.where((item) => item.id > lastNotifiedId && !item.isRead);
    for (final item in newUnread) {
      try {
        await NotificationFactory.getInstance().showNotification(
          id: item.id,
          title: item.title,
          body: item.body ?? '',
        );
      } catch (_) {
        // 通知子系統失敗(未授權/不支援的平台等)不應影響輪詢本身。
      }
    }

    if (maxId > lastNotifiedId) {
      await prefs.setInt(_lastNotifiedIdKey, maxId);
    }
  }

  Future<void> markRead(int id) async {
    final provider = _cloudProvider;
    if (provider == null) return;
    final target = state.items.where((item) => item.id == id);
    if (target.isEmpty || target.first.isRead) return;

    final now = DateTime.now();
    state = state.copyWith(
      items: [
        for (final item in state.items)
          if (item.id == id) _withReadAt(item, now) else item,
      ],
      unreadCount: state.unreadCount > 0 ? state.unreadCount - 1 : 0,
    );
    try {
      await provider.markNotificationRead(id: id);
    } catch (_) {
      await refresh();
    }
  }

  Future<void> markAllRead() async {
    final provider = _cloudProvider;
    if (provider == null || state.unreadCount == 0) return;

    final now = DateTime.now();
    state = state.copyWith(
      items: [
        for (final item in state.items)
          if (item.readAt == null) _withReadAt(item, now) else item,
      ],
      unreadCount: 0,
    );
    try {
      await provider.markAllNotificationsRead();
    } catch (_) {
      await refresh();
    }
  }

  static BeeCountCloudNotificationItem _withReadAt(
    BeeCountCloudNotificationItem item,
    DateTime readAt,
  ) {
    return BeeCountCloudNotificationItem(
      id: item.id,
      category: item.category,
      title: item.title,
      body: item.body,
      payload: item.payload,
      readAt: readAt,
      createdAt: item.createdAt,
    );
  }
}

final notificationCenterProvider =
    StateNotifierProvider<NotificationCenterNotifier, NotificationCenterState>(
        (ref) {
  final cloudProvider = ref.watch(beecountCloudProviderInstance).valueOrNull;
  return NotificationCenterNotifier(cloudProvider);
});
