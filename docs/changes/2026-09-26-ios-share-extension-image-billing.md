# iOS 分享選單「蜜蜂記帳」:截圖分享給 App 直接跑圖片記帳

截圖後在系統分享選單點「蜜蜂記帳」,App 會切到前景,用跟「相簿記帳」一樣的流程辨識並建帳。

## 入口

任何能分享圖片的地方,例如截圖後點左下角縮圖 → 分享、「照片」App → 分享,在分享選單的 App 列點「蜜蜂記帳」(BeeCount)。第一次使用時,它可能藏在分享列最右邊的「更多」裡,要自己打開。一次只接受 1 張圖片。

## 改了什麼

- **`ios/BeeCountShare/`(新 target `BeeCountShare`,share extension)**
  - `ShareViewController.swift`:取出第一張圖片附件,附件可能是 URL、UIImage 或 Data,三種都接。長邊縮到 1920,壓成 JPEG,品質從 0.85 開始試,跟相簿記帳的 `ImagePicker` 參數一樣。編完太大時逐級降低品質。接著用 base64url 編進 `beecount://share-image#<data>`,沿 responder chain 找到 `UIApplication` 喚起主 App。喚起失敗或沒拿到圖片時,顯示 2 秒提示後關閉。
  - `Info.plist`:`NSExtensionActivationSupportsImageWithMaxCount = 1`,不用 storyboard,由 `NSExtensionPrincipalClass` 指定 view controller。
  - `*.lproj/InfoPlist.strings`:分享選單上顯示的名稱,en / 簡中 / 繁中各一份,跟主 App 的 `CFBundleDisplayName` 在地化一致。
  - 文案只有 3 句,直接寫在 Swift 裡,不走 Flutter arb。
- **`ios/Runner.xcodeproj/project.pbxproj`**:新增 target。寫法比照 `BeeCountWidgetExtension`,用 file-system synchronized 資料夾,`Info.plist` 設成 membership exception,並嵌進 Runner 的「Embed Foundation Extensions」。bundle id 是 `com.andy.beecount.dev.BeeCountShare`,沒有 entitlements。
- **`ios/Runner/SceneDelegate.swift`**:`interceptSharedImageURL` 在 URL 交給 app_links 之前,先把 fragment 裡的圖片取下來,交給 `AppDelegate.storeSharedImage` 寫成暫存檔,Flutter 只會收到不帶資料的 `beecount://share-image`。這樣做是為了不讓一兩 MB 的網址被 AppLink 日誌整串印出,或存進 `pending_deeplink_action`。冷啟動和熱啟動都經過 `handleOpenURL`,兩條路徑都有攔截到。
- **`ios/Runner/AppDelegate.swift`**
  - 新增 `com.beecount.app/share_image` channel。`takeSharedImage` 回傳暫存檔路徑,取完即清空,避免重複記帳。
  - **順手修了既有 bug**:`setupControllerDependentFeaturesIfNeeded()` 原本只在 `applicationDidBecomeActive` 呼叫,但 UIScene 生命週期下這個回呼不會觸發。模擬器上實測,`com.beecount.app/badge` 一直是 `MissingPluginException`。所以那段裡註冊的東西全都沒生效,包含 `AppIntentsBridge`(快捷指令截圖記帳)、logger channel 和 badge channel。改成在 `registerPlugins()`(SceneDelegate 建好 FlutterViewController 之後)也呼叫一次,原本的旗標確保只執行一次。
- **`lib/services/platform/app_link_service.dart`**:新增 `AppLinkAction.shareImage`,對應 host `share-image`。
- **`lib/app.dart`**:`_openDeepLink` 派發 `shareImage` 到 `ImageBillingHelper.billSharedImage`。走的是既有「持久化 → ready + resumed 後 drain」的深鏈路徑。
- **`lib/utils/image_billing_helper.dart`**:`billSharedImage` 透過 channel 取圖,取到後直接進 `_processImageBilling`,跟相簿記帳同一段,billingType 也一樣標成 image。沒取到就顯示 `imageBillingSharedImageMissing` 提示。
- **l10n**:`imageBillingSharedImageMissing`,加在 `app_en.arb` 和 `app_zh_TW.arb`。

## 為什麼用網址傳圖,不用 App Group / 剪貼簿

- **App Group**:標準做法,但本專案用免費個人開發者帳號簽署,免費帳號不支援 App Group。Runner 和 Widget 的 entitlements 目前都是空的,Widget 程式裡的 `group.com.tntlikely.beecount` 其實沒有作用。
- **具名剪貼簿 `UIPasteboard(name:create:)`**:文件說同 Team ID 的程式之間共用,原本是採用這個。實測在 iOS 26.5 模擬器上,擴充功能寫入成功(1 個 `public.jpeg` 項目),主 App 讀取時 `UIPasteboard(name:create:false)` 回傳 nil。改用開發憑證重簽,讓兩邊都帶 Team ID `D87CYP5V3A` 後,結果仍然一樣,所以放棄。
- **一般剪貼簿**:會蓋掉使用者原本的剪貼簿內容,主 App 讀取時還會跳「允許貼上」提示。
- **網址**:不需要任何 entitlement 或帳號功能。實測 1.56 MB 的高雜訊 JPEG(約 2.1M 字元的網址)仍能正常喚起。一般 App 截圖編完只有 100–200 KB。`maxEncodedLength = 2_000_000` 取在驗證過的範圍內。

## 喚起主 App 的做法

share extension 沒有官方 API 可以打開 containing app。這裡用的是業界常見做法:沿 responder chain 找到 `UIApplication`,再呼叫 `openURL:options:completionHandler:`。這個方法在 extension 內被標成 unavailable,所以透過 Objective-C runtime 取 IMP 呼叫。舊的單參數 `openURL:` 從 iOS 18 起已經沒有作用。已在 iOS 26.5 模擬器驗證可行。風險是未來 iOS 可能封鎖這個做法,屆時擴充功能會顯示「無法自動打開蜜蜂記帳」。

## 刻意不做

- **背景辨識、不切換 App**:extension 內沒有 Flutter,AI 設定、帳本和分類都在 Dart 端。要做就得把 AI 呼叫重寫成原生 Swift,工程量太大。背景辨識目前走既有的快捷指令 `AutoBillingAppIntent`。
- **一次分享多張**:`_processImageBilling` 一次處理一張,暫不支援多張。
- **授權閘門**:沒有有效授權時,整個 App 被 `LicenseGatePage` 擋住,深鏈不會被消化,20 秒後過期。這是所有深鏈共同的既有行為,這裡沒有另外處理。

## 驗證

iOS 26.5 模擬器(iPhone 17 Pro)。驗證時暫時略過授權閘門,已還原。

- 照片 → 分享 → 蜜蜂記帳:切到 App,URL 進 Flutter 時已經去掉資料,暫存檔大小跟擴充功能送出的一致,流程走到 `_processImageBilling`(模擬器沒設 AI,停在「未配置 AI 服務」提示)。
- 高雜訊大圖(1.56 MB JPEG):正常送達。
- 冷啟動(先 terminate App 再分享):URL 先暫存,App 就緒後派發,圖片正常取到。
- **尚未在實機驗證**:免費帳號簽署的實機上,分享選單出現、喚起 App 這兩步都需要實測。
