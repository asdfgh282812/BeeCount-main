import 'package:shared_preferences/shared_preferences.dart';

/// 「有新版本可用」提醒的逐版本「不再提示」持久化存取。
///
/// 跟 [CloudLoginReminderStore]（`services/cloud_login_reminder_store.dart`）
/// 存的是永久 bool 不同——這裡存的是「使用者按過不再提示的那個版本號」,
/// 靠字串比對天然達成「逐版本失效」:server 端 `latest_version` 之後又更新
/// 成更新的版本,這裡存的舊版本號跟新讀到的版本號不相等,提醒就會重新生效,
/// 不需要額外的「清除」邏輯。僅本機設定,不入庫、不參與雲同步。
class AppUpdateReminderStore {
  AppUpdateReminderStore._();

  static const String _prefsKey = 'dismissed_app_update_version';

  static Future<String?> getDismissedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey);
  }

  static Future<void> setDismissedVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, version);
  }
}
