# 全站流暢動畫系統

日期:2026-09-05
背景:App 之前沒有統一的動畫語言,約 20 個檔案各自寫死
`Curves.easeOut`/`easeInOut`/`easeOutBack` 與各自的時長常數,頁面轉場也完全是
Flutter 預設轉場,沒有任何客製。依已核准的設計文件
[docs/superpowers/specs/2026-09-05-smooth-animations-design.md](../superpowers/specs/2026-09-05-smooth-animations-design.md)
與實作計畫 [docs/superpowers/plans/2026-09-05-smooth-animations.md](../superpowers/plans/2026-09-05-smooth-animations.md)
逐 Task 實作(19 個 Task,每個 Task 都有失敗測試 → 實作 → 測試通過的 TDD 循環)。

## 1. `BeeMotion` 動畫 Token

**改了什麼**:[lib/styles/tokens.dart](../../lib/styles/tokens.dart) 新增
`BeeMotion` class——`fast`(150ms)/`medium`(280ms)/`slow`(380ms) 三檔時長、
`standard`(`Curves.easeOutCubic`,無回彈)/`spring`(`Curves.easeOutBack`,帶
回彈感)兩個曲線,以及 `durationOf(context, normal)` 工具方法(減少動畫開關
或系統無障礙設定打開時把時長歸零)。

**為什麼**:全站動畫散落在各檔案各自寫常數,新增這套 token 後全部統一改用
`BeeMotion.xxx`,曲線只保留兩種語意(標準減速 / 帶觸感回彈),不引入自訂
`SpringSimulation`——直接沿用專案裡已驗證過、視覺上帶回彈感的
`Curves.easeOutBack`,成本效益比更合理。

## 2. 全域「減少動畫」開關

**改了什麼**:[lib/providers/theme_providers.dart](../../lib/providers/theme_providers.dart)
新增 `reduceMotionProvider`(`StateProvider<bool>`,預設 `false`)+
`reduceMotionInitProvider`(從 SharedPreferences key `reduceMotion` 讀回、
變更時寫回並推送雲端),架構完全比照既有 `skinAnimationEnabledProvider`。
[lib/providers/ui_state_providers.dart](../../lib/providers/ui_state_providers.dart)
把 `reduceMotionInitProvider.future` 加入啟動初始化清單。
[lib/pages/settings/appearance_settings_page.dart](../../lib/pages/settings/appearance_settings_page.dart)
在「皮肤动效」之後、「显示缩放」之前新增同款開關列(`appearanceReduceMotion`/
`appearanceReduceMotionDesc` 兩個新 l10n key,只加在 `app_en.arb`/
`app_zh_TW.arb`,依專案既有政策)。

**為什麼**:讓使用者可以自行選擇是否精簡動畫(省電、降低動態敏感度)。命名
方向刻意跟 `skinAnimationEnabledProvider` 相反(那個 `true`=啟用動效,這個
`true`=減少動畫),因為設定頁文案就是「減少動畫」,provider 語意跟 UI 一致
可以省掉一層反相判斷。

## 3. 雲端同步

**改了什麼**:`theme_providers.dart` 的 `_pushAppearanceToCloud` 在
`appearance` 字典新增 `'reduce_motion'` key;
[lib/providers/sync_providers.dart](../../lib/providers/sync_providers.dart)
的 `_applyAppearanceFields` 新增對應下行讀取,寫法逐行比照既有
`skin_animation` 那一段。

**為什麼**:`appearance` 是彈性 JSON 字典,無 server 端 schema 驗證,新增
key 不需要改 BeeCount Cloud 那邊的程式碼。

## 4. 開關的傳遞機制:復用既有 `MediaQuery.disableAnimations`

**改了什麼**:[lib/main.dart](../../lib/main.dart) `MainApp.build` 裡,根層級
`MediaQuery`(原本只用來套用字體縮放)新增
`disableAnimations: media.disableAnimations || ref.watch(reduceMotionProvider)`。

**為什麼**:不新增額外的 Scope 元件。系統的「減弱動態效果」無障礙設定維持
最高優先權(`||` 關係,系統開啟時不管 App 內開關是什麼都會停),下游所有
新寫的轉場/元件一律只讀 `MediaQuery.disableAnimationsOf(context)` 這一個
標準旗標。既有 `SkinAnimationScope` 不需要修改——它讀到的父層旗標現在已經
是「系統值 OR 全域開關」的合併結果,皮肤動效在全域開關關閉時也會一併停止,
這是預期行為。

## 5. 全站頁面轉場 `BeePageTransitionsBuilder`

**改了什麼**:新增 [lib/styles/bee_page_transitions.dart](../../lib/styles/bee_page_transitions.dart),
套用到 `main.dart` 亮色/暗色兩份 `ThemeData` 的 `pageTransitionsTheme`(所有
`TargetPlatform` 統一用同一個 builder)。正常狀態:新頁從右側滑入 + 輕微
淡入,舊頁輕微視差位移(往左偏移一小段距離)+ 輕微變暗,曲線用
`BeeMotion.standard`。減少動畫狀態退化成單純 `FadeTransition`,不歸零
`PageRoute.transitionDuration`(那是路由層級固定值,`PageTransitionsBuilder`
拿不到控制權去改)。

**為什麼**:集中式改法——只改 `main.dart` 主題設定,全站所有既有
`MaterialPageRoute`/`Navigator.push` 呼叫點自動套用,不用逐一修改呼叫端。

## 6. 共用按壓回饋元件 `BeePressable`

**改了什麼**:新增 [lib/widgets/ui/bee_pressable.dart](../../lib/widgets/ui/bee_pressable.dart)——
包裝 child,按下時縮小(預設 scale 0.96)、放開時用 `BeeMotion.spring` 彈回。
取代 [lib/widgets/biz/product_promo_card.dart](../../lib/widgets/biz/product_promo_card.dart)
裡 `ProductPromoCard`/`ProductPromoCompact` 原本各自手刻的
「`GestureDetector` + `AnimatedScale` + `_isPressed` 狀態」寫法。

**實作時對計畫文件的一處修正**:`GestureDetector` 額外加了
`behavior: HitTestBehavior.opaque`。計畫文件裡的範例程式碼沒有這一行,實測
發現預設的 `HitTestBehavior.deferToChild` 會導致包住「本身不繪製任何內容」
的 child(例如空的 `SizedBox`)時完全收不到點擊——`RenderConstrainedBox`
沒有 child 時 `hitTestSelf`/`hitTestChildren` 都回傳 false,整個手勢偵測器
形同虛設。`test/widgets/ui/bee_pressable_test.dart` 第一個測試案例(空
`SizedBox` 當 child)因此一開始失敗,加上 `opaque` 後才通過,也更符合這個
元件「包住任意 child 都要能點」的設計初衷。

**為什麼**:單一共用元件取代重複程式碼,按壓手感統一、也自動吃到減少動畫
開關(內部用 `BeeMotion.durationOf`)。

## 7. 既有動畫程式碼 retrofit(9 個檔案)

以下檔案的既有 `AnimationController`/`TweenAnimationBuilder`/`animateTo` 呼叫,
曲線/時長全部改用 `BeeMotion.xxx`,原本沒有檢查減少動畫開關的補上
`BeeMotion.durationOf(context, ...)`:

- [lib/widgets/ui/message_popover_menu.dart](../../lib/widgets/ui/message_popover_menu.dart) —
  彈出選單開合動畫
- `product_promo_card.dart` — 進場動畫(`ProductPromoCard` 首次顯示的
  scale+fade)
- [lib/pages/main/mine_page.dart](../../lib/pages/main/mine_page.dart) /
  [lib/pages/settings/data_management_page.dart](../../lib/pages/settings/data_management_page.dart) —
  `_ImportSuccessTile` 導入完成進度條(時長維持原本的 900ms 語意時長,只加
  開關判斷,不套 fast/medium/slow 分級)
- [lib/pages/ai/ai_chat_page.dart](../../lib/pages/ai/ai_chat_page.dart) —
  對話捲動到底部(兩處 `animateTo`)
- [lib/services/export/share_poster_service.dart](../../lib/services/export/share_poster_service.dart) —
  分享海報輪播翻頁
- [lib/pages/auth/welcome_page.dart](../../lib/pages/auth/welcome_page.dart) —
  引導流程翻頁(5 處 `previousPage`/`nextPage`)
- [lib/pages/account/accounts_page.dart](../../lib/pages/account/accounts_page.dart) —
  帳戶滑動快捷操作 snap 動畫
- [lib/app.dart](../../lib/app.dart) — 記帳中心按鈕展開動畫

其中 `message_popover_menu.dart`/`product_promo_card.dart`(進場)/
`accounts_page.dart`/`app.dart` 這幾處的 `duration` 是在 `initState` 讀取
當下的 `MediaQuery`,之後不會隨開關即時變化——彈窗/按鈕控制器只在對應元件
首次建構時初始化一次。這是刻意接受的取捨(用戶切換開關後,下次重新開啟該
彈窗/重建該元件/重啟 App 才會套用新狀態),不影響最終一致性,詳見計畫文件
Task 10/11/17/18 的個別說明。

## 未做的事(刻意排除,依已核准的設計文件)

- 未 retrofit 專案裡另外約 11 個只用「隱式動畫元件 + 預設曲線」的檔案(如
  `skeleton.dart`、`capsule_switcher.dart`、`pin_entry_pad.dart` 等),留給
  後續工作。
- 未替目前完全靜態、尚無動畫的互動點新增動畫(例如記帳成功回饋、彈窗開合的
  進一步打磨)——設計文件對這部分只給了示意例子,沒有具體清單。
- 未寫自訂 `SpringSimulation` 物理模擬 Curve,未新增「系統減少動態效果」的
  自動偵測邏輯(沿用 `MediaQuery.disableAnimations` 本來就有的系統值)。

## 測試

新增 4 個測試檔案(`test/styles/bee_motion_test.dart`、
`test/providers/reduce_motion_provider_test.dart`、
`test/styles/bee_page_transitions_test.dart`、
`test/widgets/ui/bee_pressable_test.dart`),全部通過。純機械式替換
`Curves.xxx` → `BeeMotion.xxx` 的檔案(第 7 節)沒有新增可觀察行為,只用
`flutter analyze` 確認無新增警告。`flutter analyze`/`flutter test` 全量跑過,
無新增問題(`dart format --set-exit-if-changed .` 在本機環境對約 340 個既有
檔案回報格式差異,經比對是這個環境既有的 SDK/formatter 版本差異,跟本次
改動無關,不在本次範圍內處理)。

**手动验证受限于本机环境**:iOS Simulator 因 Xcode 尚未 `xcode-select` 到
完整安装(需要使用者手动执行
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`,这一步
需要密码,当前会话无法代为执行)而无法启动;本机也没有 Android 模拟器镜像;
Flutter Web 因专案依赖 `sqlite3`(`dart:ffi`)而不支援。因此计划 Task 19
清单里「模拟器/实机肉眼确认转场、按压回馈手感」这一项**尚未由本次会话执行**,
需要使用者在自己的设备/模拟器上补做一次。

## 8. 事後修正:App 一啟動就崩潰(`initState` 呼叫 `MediaQuery`)

**問題**:第 7 節裡 `message_popover_menu.dart`(彈出選單)、
`product_promo_card.dart`(進場動畫)、`accounts_page.dart`(滑動 snap 動畫)、
`app.dart`(記帳中心按鈕展開動畫)這 4 個檔案的 `AnimationController`
初始化都在 `initState()` 裡直接呼叫 `BeeMotion.durationOf(context, ...)`。
`durationOf` 內部呼叫 `MediaQuery.disableAnimationsOf(context)`,即
`context.dependOnInheritedWidgetOfExactType<MediaQuery>()`——這個呼叫**不能**
在 `initState()` 裡同步進行(Flutter 框架斷言:
"`dependOnInheritedWidgetOfExactType<MediaQuery>()` ... was called before
`_BeeAppState.initState()` completed")。因為 `app.dart` 的 `_BeeAppState`
是整個 App 的根層 State,這個斷言在冷啟動時立刻觸發,導致 App 完全無法使用
(紅屏崩潰)。

計畫文件與 Task 10/11/17/18 對這個取捨的說明(「`duration` 是在 `initState`
讀取當下的 `MediaQuery`,之後不會隨開關即時變化」)本身沒錯,但沒注意到
`initState` 階段連讀一次都不被 Flutter 框架允許——這是純粹的實作疏漏,
`flutter analyze`(靜態分析)抓不到這類執行期生命週期斷言,而這 4 個檔案
依計畫本來就沒有寫對應的 widget test(見文件開頭「測試覆蓋的取捨」),所以
一路到使用者實際啟動 App 才發現。

**改了什麼**:4 個檔案的 `initState()` 裡,`AnimationController` 的
`duration` 先給 `BeeMotion.xxx` 常數當佔位值(不呼叫 `durationOf`);新增
`didChangeDependencies()` override,在裡面用
`_controller.duration = BeeMotion.durationOf(context, BeeMotion.xxx);`
校正——這正是 Flutter 錯誤訊息自己建議的位置("initialization based on
inherited widgets can be placed in the didChangeDependencies method")。
`message_popover_menu.dart` 原本在 `initState` 裡呼叫的
`_controller.forward()` 一併搬到 `didChangeDependencies`(加一個 `_started`
旗標避免重複觸發);`product_promo_card.dart` 的 `forward()` 本來就包在
`Future.delayed` 裡延遲到下一輪事件循環才觸發,`didChangeDependencies` 一定
會先跑完,不需要額外旗標。

**驗證**:`flutter analyze`/`flutter test`(全量 1135 個測試)重新跑過,
無新增問題。
