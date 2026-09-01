import 'package:shared_preferences/shared_preferences.dart';

/// 「雲端同步未登入」提醒是否已被使用者永久關閉的持久化存取。
///
/// 僅本機設定：不入庫、不參與雲同步。一旦使用者勾選「不再提示」即永久生效,
/// 之後即使重新登出也不會恢復提醒。
class CloudLoginReminderStore {
  CloudLoginReminderStore._();

  static const String _prefsKey = 'cloud_login_reminder_dismissed';

  static Future<bool> isDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  static Future<void> setDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }
}
