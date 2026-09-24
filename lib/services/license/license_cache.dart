import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// App 端本地授權快取(docs/changes/2026-09-25-license-key-and-min-sync-version.md)。
///
/// 每次成功跟 BeeCount Cloud 確認「這個帳號的金鑰有效」後,本地可用期限延長
/// 到「現在 + 離線寬限天數(7 天)」,但不超過金鑰本身的到期日。期限內離線
/// 也能用;超過期限就必須連網重新確認,否則整個 App 擋住。
///
/// 快取綁定 server + userId:換帳號/換 server 後舊快取一律失效,不能拿 A 帳號
/// 的授權開 B 帳號。
///
/// 防時鐘回撥:記錄曾經看過的最大「現在時間」(`maxSeenAt`),裝置時間比它
/// 早超過容忍值就視為被調過時鐘,快取失效(必須連網)。這只能擋「把時鐘往回
/// 調來延長離線期限」這種簡單手法;root/越獄後直接改 SharedPreferences 的人
/// 擋不住 —— 真正保護雲端資料的是 server 端每個請求都檢查授權。
class LicenseCache {
  const LicenseCache({
    required this.serverKey,
    required this.userId,
    required this.verifiedUntil,
    required this.lastVerifiedAt,
    required this.maxSeenAt,
    required this.exempt,
    this.licenseExpiresAt,
  });

  final String serverKey;
  final String userId;

  /// 本地可離線使用到這個時間(裝置時鐘,UTC)。
  final DateTime verifiedUntil;

  /// 上次成功跟 server 確認的時間(裝置時鐘,UTC)。
  final DateTime lastVerifiedAt;

  /// 曾經看過的最大裝置時間(UTC),用來偵測時鐘回撥。
  final DateTime maxSeenAt;

  /// 管理員免金鑰。
  final bool exempt;

  /// 金鑰到期日(server 時鐘,UTC),只用來顯示。
  final DateTime? licenseExpiresAt;

  /// 容忍的時鐘回撥幅度(NTP 校時、時區切換造成的小幅跳動)。
  static const Duration clockRollbackTolerance = Duration(minutes: 10);

  /// server 確認有效後建立新快取。
  ///
  /// 用「金鑰到期日 − server 當下時間」換算剩餘時間,再加到裝置時鐘上 ——
  /// 裝置時鐘跟 server 有誤差時也不會多給或少給天數。
  factory LicenseCache.fromVerification({
    required String serverKey,
    required String userId,
    required DateTime now,
    required DateTime serverTime,
    required int offlineGraceDays,
    required bool exempt,
    DateTime? licenseExpiresAt,
    DateTime? previousMaxSeenAt,
  }) {
    var remaining = Duration(days: offlineGraceDays);
    if (!exempt && licenseExpiresAt != null) {
      final keyRemaining = licenseExpiresAt.difference(serverTime);
      if (keyRemaining < remaining) remaining = keyRemaining;
    }
    if (remaining.isNegative) remaining = Duration.zero;
    final maxSeen = previousMaxSeenAt != null && previousMaxSeenAt.isAfter(now)
        ? previousMaxSeenAt
        : now;
    return LicenseCache(
      serverKey: serverKey,
      userId: userId,
      verifiedUntil: now.add(remaining),
      lastVerifiedAt: now,
      maxSeenAt: maxSeen,
      exempt: exempt,
      licenseExpiresAt: licenseExpiresAt,
    );
  }

  /// 本地快取在 `now` 這個時間點是否仍可用。
  bool isValidAt(DateTime now, {required String serverKey, required String userId}) {
    if (this.serverKey != serverKey || this.userId != userId) return false;
    if (now.isBefore(maxSeenAt.subtract(clockRollbackTolerance))) return false;
    return now.isBefore(verifiedUntil);
  }

  LicenseCache copyWithSeen(DateTime now) {
    if (!now.isAfter(maxSeenAt)) return this;
    return LicenseCache(
      serverKey: serverKey,
      userId: userId,
      verifiedUntil: verifiedUntil,
      lastVerifiedAt: lastVerifiedAt,
      maxSeenAt: now,
      exempt: exempt,
      licenseExpiresAt: licenseExpiresAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'serverKey': serverKey,
        'userId': userId,
        'verifiedUntil': verifiedUntil.millisecondsSinceEpoch,
        'lastVerifiedAt': lastVerifiedAt.millisecondsSinceEpoch,
        'maxSeenAt': maxSeenAt.millisecondsSinceEpoch,
        'exempt': exempt,
        if (licenseExpiresAt != null)
          'licenseExpiresAt': licenseExpiresAt!.millisecondsSinceEpoch,
      };

  static LicenseCache? fromJson(Map<String, dynamic> json) {
    DateTime? ts(String key) {
      final v = json[key];
      return v is int
          ? DateTime.fromMillisecondsSinceEpoch(v, isUtc: true)
          : null;
    }

    final serverKey = json['serverKey'];
    final userId = json['userId'];
    final verifiedUntil = ts('verifiedUntil');
    final lastVerifiedAt = ts('lastVerifiedAt');
    final maxSeenAt = ts('maxSeenAt');
    if (serverKey is! String ||
        userId is! String ||
        verifiedUntil == null ||
        lastVerifiedAt == null ||
        maxSeenAt == null) {
      return null;
    }
    return LicenseCache(
      serverKey: serverKey,
      userId: userId,
      verifiedUntil: verifiedUntil,
      lastVerifiedAt: lastVerifiedAt,
      maxSeenAt: maxSeenAt,
      exempt: json['exempt'] == true,
      licenseExpiresAt: ts('licenseExpiresAt'),
    );
  }
}

class LicenseCacheStore {
  static const String _key = 'beecount_license_cache_v1';

  Future<LicenseCache?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return LicenseCache.fromJson(decoded);
    } catch (_) {}
    return null;
  }

  Future<void> save(LicenseCache cache) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(cache.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
