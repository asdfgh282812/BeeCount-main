# 新功能公告(What's New Dialog)

設計文件:`docs/superpowers/specs/2026-09-11-whats-new-dialog-design.md`(實作完全依照該文件的架構,以下記錄實際落地時的檔案異動與取捨)。

## 背景

見設計文件「背景」章節:這是獨立於 `lib/models/feature_highlight.dart` 紅點系統之外的、版本觸發式的彈窗公告——更新後第一次開啟彈一次,之後可從「我的」→「新功能！」重看目前版本內容。兩套機制刻意並存。

## 新增檔案

- **`lib/whats_new/whats_new_content.dart`**:`WhatsNewItem`(title/description 皆為 `String Function(AppLocalizations)`)+ `kWhatsNewContent`(版本字串 → 條目清單)。**用 `final` 而非設計文件範例裡的 `const`**——`WhatsNewItem` 的兩個欄位是函式字面量(closure),Dart 的 const 表達式不允許閉包,套 `const Map`/`const` 建構會直接編譯錯誤(`flutter analyze` 已驗證);`final` 頂層變數語意上等價(App 生命週期內不會被重新賦值),只是不是編譯期常數。
- **`lib/whats_new/whats_new_store.dart`**:`WhatsNewStore`(`SharedPreferences` 讀寫已讀版本,`whatsnew.lastSeenVersion`)+ `decideWhatsNewAction`/`WhatsNewAction`。把觸發判斷抽成一個不依賴 `BuildContext` 的純函式(`decideWhatsNewAction`),對應設計文件要求的「分支可用 `SharedPreferences.setMockInitialValues` 直接測」——拆成三個分支(`alreadySeen`/`show`/`markOnlyNoContent`),`markOnlyNoContent` 需要呼叫端補寫入已讀版本但不彈窗。

  **2026-09-11 修改**:原本設計文件與初版實作對 `lastSeenVersion == null`(全新安裝)特化出第四個分支 `silentFirstRun`——靜默寫入已讀版本、不彈窗,理由是「新用戶沒有舊版本可比較」。使用者要求改成全新安裝也要跳出彈窗,讓新用戶第一次開啟就看到目前版本帶了哪些功能。做法:拿掉 `lastSeenVersion == null` 的特判,讓它自然落入「版本不同」分支(`null` 本來就不等於任何實際版本字串),`decideWhatsNewAction` 因此從四分支簡化成三分支,`WhatsNewAction.silentFirstRun` 一併刪除(改成只有 `alreadySeen`/`show`/`markOnlyNoContent`)。
- **`lib/widgets/ui/whats_new_dialog.dart`**:`WhatsNewDialog`(`StatelessWidget`,`BeeTokens` 配色)+ `maybeShowWhatsNewOnStartup`/`showWhatsNewForCurrentVersion`。額外加了 `currentAppVersionProvider`(`FutureProvider<String>`,包一層 `PackageInfo.fromPlatform()`)——專案沒有既有的共用版本 provider,直接讓「我的」頁面每次 rebuild 都呼叫 `PackageInfo.fromPlatform()` 會重複打 platform channel,用 Riverpod 的 `FutureProvider` 快取結果,寫法對齊既有的 `beecountCloudServerVersionProvider` 那套模式。
- **`test/whats_new/whats_new_store_test.dart`**:涵蓋 `WhatsNewStore` get/set + `decideWhatsNewAction` 三個分支(全新安裝的 `show`/`markOnlyNoContent` 各測一次),不建 Widget tree。

## 觸發點串接

- **`lib/app.dart`**:`_checkStartupReminders()` 既有的「登入提醒 → App 更新提醒」鏈之後接上第三步 `maybeShowWhatsNewOnStartup`,共用同一個 `_startupReminderCheckInProgress` 旗標。第三步不額外用回傳值互相 gate——跟既有第二步(`maybeShowAppUpdateReminder`,回傳 `void`)一樣,靠 `showDialog` 本身的 `await` 就能保證彈窗依序、不疊加,不需要每一步都回傳「有沒有顯示」。
- **`lib/pages/main/mine_page.dart`**:「說明/資訊」`SectionCard`(關於/使用說明所在的卡片)裡,`AppListTile(關於)` 前面插入一個 `Consumer` 包起來的條件式入口——`ref.watch(currentAppVersionProvider)` 拿版本號,`kWhatsNewContent[版本]` 為空就回傳 `SizedBox.shrink()`(整列不佔位),非空才渲染 `AppListTile` + 分隔線,`onTap` 呼叫 `showWhatsNewForCurrentVersion`。

## l10n

新增 5 個共用 key(`whatsNewDialogTitle`/`whatsNewDialogGotIt`/`whatsNewMenuTitle`)+ 3.3.0 版目前 3 則條目對應的 6 個 key(`whatsNew330{Gemini,AiProject,FirstDayOfWeek}{Title,Desc}`),只加進 `app_en.arb`/`app_zh_TW.arb`(依專案慣例不再維護 `app_zh.arb`/`app_ko.arb`)。

## 3.3.0 版內容取捨

`kWhatsNewContent['3.3.0']` 目前收錄 3 則,對應這幾個 commit 裡對使用者可見、值得公告的功能:Gemini 原生模型支援(`8ba4ccc`)、AI 記帳可指定專案(`feccd03`)、每週起始日可自訂(`fc19b3f`)。**刻意沒收錄**:`d72e020`(SwipeSmart 排除項提示)與 `b259866` 的民國年提示詞部分——這兩個偏向既有功能的細部調整,不是「新功能」等級的公告,放進去會稀釋公告本身的重要性。

## 範疇之外

同設計文件「範疇之外」章節:不做歷史版本 changelog 列表、不做遠端開關、不處理版本降級防呆、不改動 `feature_highlight.dart`。
