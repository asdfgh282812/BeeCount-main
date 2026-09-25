import 'package:shared_preferences/shared_preferences.dart';

/// Android 啟動時自動檢查到新版 APK、使用者按「稍後」後的暫緩紀錄。
///
/// 存「按稍後的那個版本號 + 時間」:同一版本在 [snoozeDuration] 內不再自動跳出,
/// 避免每次冷啟動 / 回到前景都跳一次;雲端出了更新的版本號就不相等,立即恢復提示。
/// 只影響啟動時的自動檢查,「關於 → 檢查更新」手動檢查永遠會顯示。僅本機設定。
class ApkUpdateSnoozeStore {
  ApkUpdateSnoozeStore._();

  static const Duration snoozeDuration = Duration(hours: 24);

  static const String _versionKey = 'apk_update_snoozed_version';
  static const String _atKey = 'apk_update_snoozed_at_ms';

  static Future<bool> isSnoozed(String version) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_versionKey) != version) return false;
    final at = prefs.getInt(_atKey);
    if (at == null) return false;
    final elapsed =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at));
    return elapsed < snoozeDuration;
  }

  static Future<void> snooze(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_versionKey, version);
    await prefs.setInt(_atKey, DateTime.now().millisecondsSinceEpoch);
  }
}
