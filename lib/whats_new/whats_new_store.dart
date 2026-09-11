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

/// [decideWhatsNewAction] 的三種結果,對應觸發邏輯設計文件的三個分支。
enum WhatsNewAction {
  /// 已讀版本就是目前版本:不彈窗。
  alreadySeen,

  /// 已讀版本不是目前版本(含全新安裝、從未記錄過的情況),且目前版本有
  /// 公告內容:應該彈窗。全新安裝也會跳出,讓新用戶知道目前版本帶了哪些
  /// 功能,不特別區分「升級後第一次開」跟「全新安裝第一次開」。
  show,

  /// 已讀版本不是目前版本,但目前版本沒有公告內容:仍要把目前版本寫入已讀
  /// (避免下次比對又觸發到這個空版本),但不彈窗。
  markOnlyNoContent,
}

/// 純函式版的觸發判斷,不依賴 BuildContext/Widget tree,方便單元測試直接
/// 灌 (lastSeenVersion, currentVersion, hasContent) 三個值驗證三種分支。
///
/// 版本比對只用字串是否相等,不做數值大小比較——`kWhatsNewContent` 的 key
/// 本來就是精確版本字串,需求是「更新後(或全新安裝)第一次開啟」,相等/
/// 不相等已足夠表達,不處理版本降級(那是開發測試場景,交給 debug 手動清
/// SharedPreferences)。`lastSeenVersion == null` 沒有特殊處理:null 本來
/// 就不等於任何實際版本字串,自然落入下面的「版本不同」分支。
WhatsNewAction decideWhatsNewAction({
  required String? lastSeenVersion,
  required String currentVersion,
  required bool hasContent,
}) {
  if (lastSeenVersion == currentVersion) return WhatsNewAction.alreadySeen;
  return hasContent ? WhatsNewAction.show : WhatsNewAction.markOnlyNoContent;
}
