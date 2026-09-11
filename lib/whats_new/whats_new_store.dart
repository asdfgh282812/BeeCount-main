import 'package:shared_preferences/shared_preferences.dart';

/// 「新功能公告」已讀版本的持久化存取。沿用
/// `AppUpdateReminderStore`(`lib/services/update/app_update_reminder_store.dart`)
/// 的既有模式:純 SharedPreferences 靜態包裝類別,不入庫、不參與雲同步——
/// 這是「這台裝置上的人看過哪個版本的公告」,跟帳本資料無關。
class WhatsNewStore {
  WhatsNewStore._();

  static const String _prefsKey = 'whatsnew.lastSeenVersion';

  static Future<String?> getLastSeenVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey);
  }

  static Future<void> setLastSeenVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, version);
  }
}

/// [decideWhatsNewAction] 的四種結果,對應觸發邏輯設計文件的四個分支。
enum WhatsNewAction {
  /// 從未記錄過已讀版本(全新安裝,或舊版升級但這功能剛上線):靜默寫入目前
  /// 版本為已讀,不彈窗。
  silentFirstRun,

  /// 已讀版本就是目前版本:不彈窗。
  alreadySeen,

  /// 已讀版本不是目前版本,且目前版本有公告內容:應該彈窗。
  show,

  /// 已讀版本不是目前版本,但目前版本沒有公告內容:仍要把目前版本寫入已讀
  /// (避免下次比對又觸發到這個空版本),但不彈窗。
  markOnlyNoContent,
}

/// 純函式版的觸發判斷,不依賴 BuildContext/Widget tree,方便單元測試直接
/// 灌 (lastSeenVersion, currentVersion, hasContent) 三個值驗證四種分支。
///
/// 版本比對只用字串是否相等,不做數值大小比較——`kWhatsNewContent` 的 key
/// 本來就是精確版本字串,需求是「更新後第一次開啟」,相等/不相等已足夠表達,
/// 不處理版本降級(那是開發測試場景,交給 debug 手動清 SharedPreferences)。
WhatsNewAction decideWhatsNewAction({
  required String? lastSeenVersion,
  required String currentVersion,
  required bool hasContent,
}) {
  if (lastSeenVersion == null) return WhatsNewAction.silentFirstRun;
  if (lastSeenVersion == currentVersion) return WhatsNewAction.alreadySeen;
  return hasContent ? WhatsNewAction.show : WhatsNewAction.markOnlyNoContent;
}
