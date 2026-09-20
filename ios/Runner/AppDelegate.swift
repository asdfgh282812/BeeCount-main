import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var didSetupControllerDependentFeatures = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 注意：不能在这里调用 GeneratedPluginRegistrant.register(with: self)。
    // 在 UIScene 生命週期下，這個方法比 Scene 連線（SceneDelegate 建立真正的
    // FlutterViewController/engine）還早執行，此時還沒有可用的 engine，插件會被
    // 注册到一个空壳上，导致所有 platform channel 全部连不上（见 registerPlugins()，
    // 由 SceneDelegate 在 FlutterViewController 建立後立刻呼叫）。

    // 设置通知中心代理
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    // 测试日志
    LoggerPlugin.info(tag: "AppDelegate", message: "日志系统已初始化")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // 由 SceneDelegate 在 FlutterViewController（及其 engine）建立完成後立即呼叫。
  private var didRegisterPlugins = false
  func registerPlugins() {
    guard !didRegisterPlugins else { return }
    didRegisterPlugins = true
    GeneratedPluginRegistrant.register(with: self)
  }

  // 採用 UIScene 生命週期後，window/rootViewController 要等 Scene 連線完成才就緒，
  // 不再像舊版 storyboard-only 模式那樣在 didFinishLaunchingWithOptions 當下就已存在，
  // 所以需要 controller 的初始化都挪到這裡（app 變成 active 前 Scene 必已連線），並用旗標只執行一次。
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    setupControllerDependentFeaturesIfNeeded()
  }

  private func setupControllerDependentFeaturesIfNeeded() {
    guard !didSetupControllerDependentFeatures else { return }
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    didSetupControllerDependentFeatures = true

    // 注册AppIntents桥接插件
    if #available(iOS 13.0, *) {
      let registrar = self.registrar(forPlugin: "AppIntentsBridge")
      if let registrar = registrar {
        AppIntentsBridge.register(with: registrar)
      }
    }

    // 设置日志插件
    let loggerChannel = FlutterMethodChannel(
      name: "com.beecount.logger",
      binaryMessenger: controller.binaryMessenger
    )
    LoggerPlugin.setup(channel: loggerChannel)

    // 清除 App 图标右上角通知徽章的 method channel——flutter_local_notifications
    // 在本项目的用法里没有暴露「无通知情况下把徽章清零」的 Dart API(只能在排程
    // 通知时设置 badgeNumber),徽章数字本身完全靠系统累加各个已触发通知的
    // badgeNumber,从不会自动清零,只能原生这一侧直接归零。
    let badgeChannel = FlutterMethodChannel(
      name: "com.beecount.app/badge",
      binaryMessenger: controller.binaryMessenger
    )
    badgeChannel.setMethodCallHandler { call, result in
      if call.method == "clearBadge" {
        UIApplication.shared.applicationIconBadgeNumber = 0
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // 监听 iCloud 日志（从插件模块发送）
    NotificationCenter.default.addObserver(
      forName: NSNotification.Name("ICloudLog"),
      object: nil,
      queue: .main
    ) { notification in
      if let message = notification.userInfo?["message"] as? String {
        LoggerPlugin.info(tag: "iCloud", message: message)
      }
    }
  }

  // 前台显示通知
  @available(iOS 10.0, *)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // 在前台也显示通知
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  // 处理通知点击
  @available(iOS 10.0, *)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    completionHandler()
  }
}
