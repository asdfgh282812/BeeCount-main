import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart' hide SyncStatus;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/license/license_cache.dart';
import '../services/system/logger_service.dart';
import 'sync_providers.dart';

// =============================================================================
// 授權金鑰 + 最低可同步版本 —— App 端的兩道門
// (docs/changes/2026-09-25-license-key-and-min-sync-version.md)
//
// `MainApp._getHomePage`(main.dart)依這兩個 provider 決定要顯示強制更新頁 /
// 授權頁,還是放行進 App。server 端每個請求都會再檢查一次(402/426),這裡
// 是 UX 層 + 離線期間的本地判斷。
// =============================================================================

enum LicenseGateStatus {
  /// 啟動時沒有有效的本地快取,正在跟 server 確認。
  checking,

  /// 可以使用。
  valid,

  /// 沒有設定 BeeCount Cloud 或沒有登入。
  needsLogin,

  /// 已登入但帳號沒有有效金鑰(從未啟用、已過期、被撤銷)。
  needsKey,

  /// 本地授權已過期(超過 7 天沒連網確認),且目前連不上 server。
  needsNetwork,
}

class LicenseGateState {
  const LicenseGateState({
    required this.status,
    this.expiresAt,
    this.verifiedUntil,
    this.exempt = false,
    this.busy = false,
  });

  final LicenseGateStatus status;

  /// 金鑰到期日(可能已過期,用來顯示「已於 X 到期」)。
  final DateTime? expiresAt;

  /// 本地離線可用期限。
  final DateTime? verifiedUntil;

  /// 管理員免金鑰。
  final bool exempt;

  /// 正在跟 server 通訊(授權頁按鈕顯示 loading 用)。
  final bool busy;

  bool get isValid => status == LicenseGateStatus.valid;

  LicenseGateState copyWith({bool? busy}) => LicenseGateState(
        status: status,
        expiresAt: expiresAt,
        verifiedUntil: verifiedUntil,
        exempt: exempt,
        busy: busy ?? this.busy,
      );
}

class LicenseGateNotifier extends StateNotifier<LicenseGateState>
    with WidgetsBindingObserver {
  LicenseGateNotifier(this._ref, {LicenseCacheStore? store})
      : _store = store ?? LicenseCacheStore(),
        super(const LicenseGateState(status: LicenseGateStatus.checking)) {
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
  }

  final Ref _ref;
  final LicenseCacheStore _store;
  Timer? _expiryTimer;
  Future<bool>? _inflight;
  DateTime? _lastRefreshAt;

  static const Duration _requestTimeout = Duration(seconds: 15);
  static const Duration _resumeThrottle = Duration(seconds: 60);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle != AppLifecycleState.resumed) return;
    final last = _lastRefreshAt;
    if (last != null && DateTime.now().difference(last) < _resumeThrottle) {
      return;
    }
    unawaited(refresh());
  }

  /// server 回 402(任何 API)時由 `BeeCountCloudClientGate.onLicenseRequired`
  /// 觸發 —— 重新向 server 確認,確認後切到授權頁。
  void onServerLicenseRequired() {
    unawaited(refresh());
  }

  /// 跟 server 確認授權狀態並更新本地快取。回傳目前是否可用。
  /// 同時間只會有一個請求在跑,重複呼叫共用同一個結果。
  Future<bool> refresh() {
    return _inflight ??= _refresh().whenComplete(() => _inflight = null);
  }

  Future<bool> _refresh() async {
    _lastRefreshAt = DateTime.now();
    if (mounted) state = state.copyWith(busy: true);
    try {
      final next = await _computeState();
      _apply(next);
      return next.isValid;
    } catch (e, st) {
      logger.warning('License', '授權狀態檢查失敗: $e', st);
      if (mounted) state = state.copyWith(busy: false);
      return state.isValid;
    }
  }

  /// 先等設定檔載入完,再取 provider —— 冷啟動時 `activeCloudConfigProvider`
  /// 還沒有值,`beecountCloudProviderInstance` 第一輪會先回 null,直接讀會
  /// 誤判成「沒設定 BeeCount Cloud」。
  Future<BeeCountCloudProvider?> _cloud() async {
    await _ref.read(activeCloudConfigProvider.future);
    return _ref.read(beecountCloudProviderInstance.future);
  }

  Future<LicenseGateState> _computeState() async {
    final cloud = await _cloud();
    if (cloud == null) {
      return const LicenseGateState(status: LicenseGateStatus.needsLogin);
    }
    final serverKey = '${cloud.baseUrl ?? ''}${cloud.apiPrefix ?? ''}';

    CloudUser? user;
    try {
      user = await cloud.auth.currentUser;
    } catch (e) {
      logger.warning('License', '取得目前登入使用者失敗: $e');
    }
    if (user == null) {
      return const LicenseGateState(status: LicenseGateStatus.needsLogin);
    }

    final now = DateTime.now().toUtc();
    var cache = await _store.load();
    final localValid =
        cache?.isValidAt(now, serverKey: serverKey, userId: user.id) ?? false;
    if (cache != null && localValid) {
      cache = cache.copyWithSeen(now);
      await _store.save(cache);
      // 有效快取先放行,不讓使用者等網路 —— 下面照樣連線確認。
      if (mounted && !state.isValid) _apply(_stateFromCache(cache));
    }

    try {
      final status = await cloud.fetchLicenseStatus().timeout(_requestTimeout);
      if (status.licensed) {
        final fresh = LicenseCache.fromVerification(
          serverKey: serverKey,
          userId: user.id,
          now: now,
          serverTime: status.serverTime,
          offlineGraceDays: status.offlineGraceDays,
          exempt: status.exempt,
          licenseExpiresAt: status.expiresAt,
          previousMaxSeenAt: cache?.maxSeenAt,
        );
        await _store.save(fresh);
        return _stateFromCache(fresh);
      }
      await _store.clear();
      return LicenseGateState(
        status: LicenseGateStatus.needsKey,
        expiresAt: status.expiresAt,
      );
    } on CloudNotAuthenticatedException {
      return const LicenseGateState(status: LicenseGateStatus.needsLogin);
    } catch (e) {
      // 網路錯誤 / timeout / 426(版本門檻另外處理)—— 看本地快取。
      logger.info('License', '無法連線確認授權,改用本地快取: $e');
      if (cache != null && localValid) return _stateFromCache(cache);
      return LicenseGateState(
        status: LicenseGateStatus.needsNetwork,
        expiresAt: cache?.licenseExpiresAt,
      );
    }
  }

  LicenseGateState _stateFromCache(LicenseCache cache) => LicenseGateState(
        status: LicenseGateStatus.valid,
        expiresAt: cache.licenseExpiresAt,
        verifiedUntil: cache.verifiedUntil,
        exempt: cache.exempt,
      );

  void _apply(LicenseGateState next) {
    if (!mounted) return;
    state = next;
    _expiryTimer?.cancel();
    final until = next.verifiedUntil;
    if (next.isValid && until != null) {
      // App 一直開著沒切到背景時,到期那一刻也要重新確認(連不上就擋)。
      // 最長 6 小時檢查一次,順便讓 server 端撤銷的金鑰在前景也能生效。
      var wait = until.difference(DateTime.now().toUtc());
      const maxWait = Duration(hours: 6);
      if (wait > maxWait) wait = maxWait;
      if (wait.isNegative) wait = Duration.zero;
      _expiryTimer = Timer(wait + const Duration(seconds: 1), () {
        unawaited(refresh());
      });
    }
  }

  /// 輸入金鑰啟用。失敗抛 [BeeCountCloudLicenseException](或網路錯誤),
  /// 由 UI 轉成對應訊息。
  Future<void> activate(String key) async {
    final cloud = await _cloud();
    if (cloud == null) {
      throw CloudNotAuthenticatedException('BeeCount Cloud not configured');
    }
    final user = await cloud.auth.currentUser;
    if (user == null) {
      throw CloudNotAuthenticatedException('Not logged in');
    }
    final status = await cloud.activateLicense(key).timeout(_requestTimeout);
    final serverKey = '${cloud.baseUrl ?? ''}${cloud.apiPrefix ?? ''}';
    final now = DateTime.now().toUtc();
    if (!status.licensed) {
      _apply(LicenseGateState(
        status: LicenseGateStatus.needsKey,
        expiresAt: status.expiresAt,
      ));
      return;
    }
    final cache = LicenseCache.fromVerification(
      serverKey: serverKey,
      userId: user.id,
      now: now,
      serverTime: status.serverTime,
      offlineGraceDays: status.offlineGraceDays,
      exempt: status.exempt,
      licenseExpiresAt: status.expiresAt,
    );
    await _store.save(cache);
    _apply(_stateFromCache(cache));
  }

  /// 登出 / 切換帳號時清掉本地授權。
  Future<void> clearLocal() async {
    await _store.clear();
  }
}

final licenseGateProvider =
    StateNotifierProvider<LicenseGateNotifier, LicenseGateState>((ref) {
  final notifier = LicenseGateNotifier(ref);
  // 切换伺服器 / 登入 / 登出都会让 BeeCount Cloud provider 重建 —— 跟着重新
  // 确认授权(refresh 内部有去重,同时间只会发一个请求)。
  ref.listen(beecountCloudProviderInstance, (_, next) {
    if (next.hasValue) unawaited(notifier.refresh());
  });
  ref.listen(authServiceProvider, (_, next) {
    if (next.hasValue) unawaited(notifier.refresh());
  });
  return notifier;
});

// -----------------------------------------------------------------------------
// 最低可同步版本
// -----------------------------------------------------------------------------

/// `3.6.0` / `3.6.0+2` 都取 `3.6.0`;不合格式回 null(跟 server
/// `services/license.py::parse_version` 同規則)。
List<int>? parseAppVersion(String? raw) {
  if (raw == null) return null;
  final head = raw.trim().split(RegExp(r'[+\s-]')).first;
  if (!RegExp(r'^\d+(\.\d+){0,3}$').hasMatch(head)) return null;
  return head.split('.').map(int.parse).toList();
}

/// [current] 是否低於 [minimum];任一方無法解析時視為「不低於」(不擋)。
bool isAppVersionBelow(String current, String minimum) {
  final c = parseAppVersion(current);
  final m = parseAppVersion(minimum);
  if (c == null || m == null) return false;
  final length = c.length > m.length ? c.length : m.length;
  for (var i = 0; i < length; i++) {
    final a = i < c.length ? c[i] : 0;
    final b = i < m.length ? m[i] : 0;
    if (a != b) return a < b;
  }
  return false;
}

class AppVersionGateState {
  const AppVersionGateState({
    required this.currentVersion,
    this.minSyncVersion,
    this.busy = false,
  });

  final String currentVersion;
  final String? minSyncVersion;
  final bool busy;

  bool get blocked =>
      minSyncVersion != null &&
      currentVersion.isNotEmpty &&
      isAppVersionBelow(currentVersion, minSyncVersion!);
}

class AppVersionGateNotifier extends StateNotifier<AppVersionGateState>
    with WidgetsBindingObserver {
  AppVersionGateNotifier(this._ref)
      : super(AppVersionGateState(
          currentVersion: BeeCountCloudClientGate.appVersion ?? '',
        )) {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadCachedThenRefresh());
  }

  final Ref _ref;
  static const String _cacheKey = 'beecount_min_sync_version_cache';
  DateTime? _lastRefreshAt;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle != AppLifecycleState.resumed) return;
    final last = _lastRefreshAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 60)) {
      return;
    }
    unawaited(refresh());
  }

  Future<void> _loadCachedThenRefresh() async {
    // 上次從 server 拿到的門檻先套用 —— 離線時舊版 App 一樣要擋。
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (mounted && cached != null && cached.isNotEmpty) {
      state = AppVersionGateState(
        currentVersion: state.currentVersion,
        minSyncVersion: cached,
      );
    }
    await refresh();
  }

  /// 重新向 server 拿最低可同步版本(`GET /app-version/latest`,公開端點)。
  /// server 回 426 時由 `BeeCountCloudClientGate.onAppVersionTooOld` 觸發。
  Future<void> refresh() async {
    _lastRefreshAt = DateTime.now();
    if (mounted) {
      state = AppVersionGateState(
        currentVersion: state.currentVersion,
        minSyncVersion: state.minSyncVersion,
        busy: true,
      );
    }
    String? minVersion = state.minSyncVersion;
    try {
      await _ref.read(activeCloudConfigProvider.future);
      final cloud = await _ref.read(beecountCloudProviderInstance.future);
      if (cloud != null) {
        final latest = await cloud
            .fetchLatestAppVersion()
            .timeout(const Duration(seconds: 15));
        minVersion = latest.minSyncVersion;
        final prefs = await SharedPreferences.getInstance();
        if (minVersion == null) {
          await prefs.remove(_cacheKey);
        } else {
          await prefs.setString(_cacheKey, minVersion);
        }
      }
    } catch (e) {
      logger.info('AppVersionGate', '取得最低可同步版本失敗,沿用快取: $e');
    }
    if (mounted) {
      state = AppVersionGateState(
        currentVersion: state.currentVersion,
        minSyncVersion: minVersion,
      );
    }
  }
}

final appVersionGateProvider =
    StateNotifierProvider<AppVersionGateNotifier, AppVersionGateState>(
  (ref) => AppVersionGateNotifier(ref),
);
