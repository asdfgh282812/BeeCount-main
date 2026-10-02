import 'package:flutter_cloud_sync/flutter_cloud_sync.dart'
    show BeeCountCloudProfile, BeeCountCloudProvider;
import 'package:shared_preferences/shared_preferences.dart';

import 'logger_service.dart';

/// 通知設定(記帳提醒 + 信用卡提醒)的帳號級同步。
///
/// 設定本體仍存在 SharedPreferences(排程邏輯、`main.dart` 啟動恢復都直接
/// 讀這些 key),這裡只負責「prefs ↔ `/profile/me` 的 `notification_settings`」
/// 的雙向搬運。wire key 刻意與 prefs key 同名,snapshot/apply 靠 [_schema]
/// 單一來源驅動,新增設定只需加一行。
///
/// 通知權限、排程 ID、`notification_center_last_notified_id` 屬於裝置狀態,
/// 不在同步範圍內。
class NotificationSettingsSync {
  NotificationSettingsSync._();

  /// key → 預設值(型別由預設值決定:bool 或 int)。預設值需與
  /// `reminder_providers.dart` / `credit_card_reminder_overview_page.dart` 一致。
  static const Map<String, Object> _schema = {
    'reminder_enabled': false,
    'reminder_hour': 21,
    'reminder_minute': 0,
    'cc_reminder_hour': 10,
    'cc_reminder_minute': 0,
    'cc_reminder_enabled': false,
    'cc_reminder_days': 3,
    'cc_billing_reminder_enabled': false,
    'cc_due_reminder_enabled': false,
    'cc_due_reminder_maxdays': 3,
  };

  /// 任一通知設定被使用者改動後呼叫;由 `sync_providers.dart` 在雲端同步
  /// 啟用時指派為「推送到 server」。未指派(本地模式)時為 no-op。
  static void Function()? onChanged;

  static void notifyChanged() => onChanged?.call();

  /// 讀目前本機值(未設定者用預設值)組成整包 payload。server 是整包替換語意。
  static Future<Map<String, dynamic>> snapshot() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final e in _schema.entries) e.key: _read(prefs, e.key, e.value),
    };
  }

  /// 把 server 的值寫回 prefs,只寫有差異且型別正確的 key。回傳是否有變動;
  /// 不經過 [notifyChanged],所以不會回推造成迴圈。
  static Future<bool> applyFromServer(Map<String, dynamic> remote) async {
    final prefs = await SharedPreferences.getInstance();
    var changed = false;
    for (final e in _schema.entries) {
      final v = remote[e.key];
      if (e.value is bool && v is bool) {
        if (_read(prefs, e.key, e.value) != v) {
          await prefs.setBool(e.key, v);
          changed = true;
        }
      } else if (e.value is int && v is num) {
        final n = v.toInt();
        if (_read(prefs, e.key, e.value) != n) {
          await prefs.setInt(e.key, n);
          changed = true;
        }
      }
    }
    return changed;
  }

  /// 首次綁定對帳:server 還沒有通知設定、而本機有使用者設過的值時補推上去
  /// (升級前就設好提醒的使用者)。雙方都有值則以 server 為準。
  static Future<void> reconcile(
    BeeCountCloudProvider cloud,
    BeeCountCloudProfile profile,
  ) async {
    final remote = profile.notificationSettings;
    if (remote != null && remote.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (!_schema.keys.any(prefs.containsKey)) return;
    try {
      await cloud.updateMyProfileNotificationSettings(
        notificationSettings: await snapshot(),
      );
      logger.info('CloudSync', 'reconcile: pushed notification_settings');
    } catch (e, st) {
      logger.warning('CloudSync', 'reconcile 通知設定推送失敗: $e', st);
    }
  }

  static Object _read(SharedPreferences prefs, String key, Object def) {
    if (def is bool) return prefs.getBool(key) ?? def;
    return prefs.getInt(key) ?? def;
  }
}
