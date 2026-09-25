import Flutter
import UIKit

// 部分新版 Xcode/iOS SDK 不接受「只在 Info.plist 指定 UISceneStoryboardFile、不寫
// SceneDelegate class」的免程式碼搬遷寫法——系統找不到指定的 delegate class 時會直接
// 放棄自動建立 window（"There is no scene delegate set" 警告），導致
// FlutterViewController 被重複初始化、畫面卡黑屏。這裡手動實作，等同於 UIKit 原本
// 該自動做的事：用 Main storyboard 建立 window 並接上 AppDelegate 既有的 window 屬性，
// 讓依賴 window.rootViewController 的既有程式碼（見 AppDelegate.swift）維持正常運作。
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }

    let storyboard = UIStoryboard(name: "Main", bundle: nil)
    let newWindow = UIWindow(windowScene: windowScene)
    newWindow.rootViewController = storyboard.instantiateInitialViewController()
    self.window = newWindow

    if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
      appDelegate.window = newWindow
      // 此时 FlutterViewController（与其 engine）已经建立，才能正确注册插件，
      // 否则插件会注册到还不存在的 engine 上，导致所有 platform channel 连不上。
      appDelegate.registerPlugins()
    }

    newWindow.makeKeyAndVisible()

    // 冷啟動就帶著 URL / Universal Link 進來的情況（例如 SSO 登入回跳時 App 剛好
    // 被系统終止），此時不會再觸發下面的 openURLContexts / continue，要在這裡補處理。
    if let urlContext = connectionOptions.urlContexts.first {
      handleOpenURL(urlContext.url)
    }
    if let userActivity = connectionOptions.userActivities.first {
      handleUserActivity(userActivity)
    }
    if let shortcutItem = connectionOptions.shortcutItem {
      handleShortcutItem(shortcutItem)
    }
  }

  // 長按 App 圖示叫出的「快速操作」（QuickActionsPlugin）同樣是靠 AppDelegate 的舊式
  // application(_:performActionFor:completionHandler:) 接收事件，Scene 架構下改由
  // windowScene(_:performActionFor:completionHandler:) 接收，一併轉發過去。
  func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    handleShortcutItem(shortcutItem, completionHandler: completionHandler)
  }

  private func handleShortcutItem(
    _ shortcutItem: UIApplicationShortcutItem,
    completionHandler: ((Bool) -> Void)? = nil
  ) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      completionHandler?(false)
      return
    }
    appDelegate.application(
      UIApplication.shared, performActionFor: shortcutItem,
      completionHandler: completionHandler ?? { _ in })
  }

  // app_links 等插件是透过 AppDelegate 的舊式 application(_:open:options:) /
  // application(_:continue:restorationHandler:) 接收 URL 回跳（例如 SSO 登入完成後
  // 从 Safari 跳回 App）。採用 UIScene 生命週期後，系統改成呼叫 SceneDelegate 這兩個
  // 方法，不再呼叫 AppDelegate 的舊方法，所以要手動轉發，否則回跳永遠沒人處理，
  // 表现为登入頁一直轉圈圈、App 端收不到登入完成的訊號。
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    URLContexts.forEach { handleOpenURL($0.url) }
  }

  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    handleUserActivity(userActivity)
  }

  private func handleOpenURL(_ url: URL) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
    _ = appDelegate.application(
      UIApplication.shared, open: interceptSharedImageURL(url), options: [:])
  }

  /// 系統分享選單「蜜蜂記帳」擴充功能（ios/BeeCountShare）把圖片以 base64url
  /// 編在 `beecount://share-image#...` 的 fragment 裡。這裡先把圖片取下來交給
  /// AppDelegate 暫存，再只把不帶資料的 `beecount://share-image` 轉給 app_links，
  /// 避免好幾百 KB 的網址進到 Flutter 被 AppLink 日誌整串印出、存進待處理深鏈。
  private func interceptSharedImageURL(_ url: URL) -> URL {
    guard url.scheme == "beecount", url.host == "share-image",
      let payload = url.fragment, !payload.isEmpty
    else { return url }
    AppDelegate.storeSharedImage(base64URL: payload)
    return URL(string: "beecount://share-image")!
  }

  private func handleUserActivity(_ userActivity: NSUserActivity) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
    _ = appDelegate.application(
      UIApplication.shared, continue: userActivity, restorationHandler: { _ in })
  }
}
