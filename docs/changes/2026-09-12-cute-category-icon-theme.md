# 新增「可愛類別圖示」主題

日期:2026-09-12
背景:類別圖示目前只有 Material Icons 一種畫風。使用者想要一個更活潑、手繪
風的替代畫風，但不想失去用類別顏色快速辨識分類的能力。這次新增一個可在
外觀設定切換的第二套圖示主題，跟現行 Material 主題並存,不取代它。

**入口**:我的 → 外觀設定 → 可愛類別圖示(開關)。

## 1. `CategoryIconStyle` 偏好 provider

**改了什麼**:`lib/providers/theme_providers.dart` 新增 `CategoryIconStyle`
enum(`material` / `cute`)、`categoryIconStyleProvider`
(`StateNotifierProvider`)跟 `CategoryIconStyleNotifier`。寫法照抄同檔案裡
既有的 `AssetTrendViewNotifier`(本機 `SharedPreferences` 持久化,不推播雲端)。

**為什麼刻意不推雲端**:同一頁其他外觀開關
(`skinAnimationEnabledProvider`/`reduceMotionProvider`)在 `select()`/監聽時
會呼叫 `_pushAppearanceToCloud(ref)` 推上 server。這次先只驗證畫風本身能不能
被使用者接受,故意把爆炸半徑縮小到本機——之後如果要跨裝置同步,在
notifier 裡補一樣的推播呼叫、並擴充 server 端外觀 payload 即可,這次不提前做。

## 2. 色鉛筆質感底線(`CategoryColorUnderline`)

**改了什麼**:新增 `lib/widgets/cute_icons/pencil_underline_painter.dart`——
`PencilUnderlinePainter`(`CustomPainter`)+ 包一層方便呼叫的
`CategoryColorUnderline` widget。畫一條手繪波浪路徑,疊兩層不同寬度、半透明
的筆觸(粗的模擬鉛筆壓痕暈染、細的模擬筆芯核心線),再用固定種子
(`Random(7)`)沿路徑撒一批小圓點模擬「筆芯顆粒感」。

**為什麼用兩層筆觸+固定種子撒點,而不是濾鏡**:設計討論階段的 Artifact demo
用 SVG 的 `feTurbulence`/`feDisplacementMap` 濾鏡做出粗糙質感,但 Flutter
`Canvas` 沒有對應的位移濾鏡 API,`flutter_svg` 也不支援這兩個 SVG 濾鏡
primitive。改成原生手繪的近似效果是這次刻意的取捨——如果之後實機看起來
「手繪感」不夠,顆粒密度/透明度是可以再調的參數(都在這個檔案裡)。固定種子
是為了讓同一顆分類色每次重繪、每次截圖/測試看到的顆粒位置都一樣,不會每幀
亂跳。

## 3. 18 個原創 SVG 圖示 + key 對照表

**改了什麼**:`assets/icons/categories_cute/` 新增 18 個 `.svg`
檔(`restaurant`/`bakery_dining`/`directions_bus`/`shopping_bag`/
`shopping_cart`/`home`/`flash_on`/`sports_esports`/`local_hospital`/
`menu_book`/`smartphone`/`checkroom`/`card_travel`/`laptop`/`pets`/
`fitness_center`/`account_balance_wallet`/`trending_up`),`pubspec.yaml`
註冊這個 asset 資料夾。新增 `lib/widgets/cute_icons/cute_category_icon_keys.dart`:
`kCuteCategoryIconKeys`(這 18 個 key 的白名單)+ `CuteCategoryIcon` widget
(`SvgPicture.asset` 包 `SvgTheme(currentColor: ...)`)+ `maybeBuild()` 靜態
方法(key 不在白名單就回傳 `null`,呼叫端可以無痛 fallback 回 Material 圖示)。

**圖示畫法**:每個 SVG 的線稿一律用 `stroke="currentColor"`/
`fill="currentColor"`,讓 `flutter_svg` 的 `SvgTheme.currentColor` 能在
render 時跟著主題換色(深色模式自動變色,接的是 `BeeTokens.iconCategory`,
跟 App 其他地方的類別圖示用同一個 token)。每個圖示自己「品牌感」的內建色塊
(例如餐飲碗裡的芥末黃、房子的鼠尾草綠)是寫死的 hex,不隨主題、也不是
`category.color`——類別顏色只透過底線呈現,這是設計討論階段就定案、跟兩個
替代方案(圖示外圈染色 / 角落色點)比較後選出來的。

**為什麼是原創圖案**:過程中試過兩個方向後放棄——(a) 全部手刻
`CustomPainter` Canvas 呼叫(18 個太耗費對話 token,報酬率不划算),(b) 找
Flaticon 真實素材(卡在瀏覽器沙箱環境無法真正觸發下載存檔,且風格最接近的
Magnific「Special Lineal Color」實際看到後比使用者想要的更花俏)。最後改成
由使用者透過 Artifact 即時預覽、逐輪調整確認的 18 個原創 SVG,沒有第三方
授權/歸屬問題,SVG 原始碼直接寫進 repo,不需要手動下載步驟。

**這 18 個 key 是怎麼選的**:用
`grep -c "case '<key>':" lib/services/data/category_service.dart` 逐一核對
`lib/services/data/category_service.dart` 的 259 條 case,確認每個 key 確實
真實存在且被處理(全部剛好回傳 1)。順帶發現一個既有 bug(跟這次無關,不
在這次範圍修):`lib/services/data/seed_service.dart` 的 `getDefaultIcon()`
把種子分類 `dining_breakfast` 對應到圖示 key `free_breakfast`,但
`category_service.dart` 沒有對應 case,導致這個子分類今天其實是走通用
fallback 圖示,沒人注意到。

## 4. `CategoryIconWidget` 接線

**改了什麼**:`lib/widgets/category_icon.dart` 的 `build()` 在自訂圖示分支
之後、Material 圖示分支之前,新增一段:`ref.watch(categoryIconStyleProvider)`
若為 `cute` 且 `showBackground == false`,就用 `CuteCategoryIcon.maybeBuild`
嘗試取對應 SVG(拿不到就退回原本的 `Icon(iconData, ...)`),圖示下面疊一條
`CategoryColorUnderline`(顏色來自 `CategoryUtils.parseColor(category?.color)`,
解析失敗就退回 `iconColor`)。

**為什麼只動 `showBackground == false` 這條路徑**:`showBackground == true`
是另一套既有的「圓形色底徽章」呈現類別色的方式(類別卡片在用),疊加底線會
互相打架、視覺上很亂,不是這次使用者驗收過的畫面。這個圓底徽章路徑完全
不動。

## 5. 外觀設定切換開關

**改了什麼**:`lib/pages/settings/appearance_settings_page.dart` 在「減少
動畫」開關跟「顯示縮放」之間插入一個新的 `AppListTile` + `Switch.adaptive`,
接 `categoryIconStyleProvider`。四份語系檔裡實際維護的兩份
(`app_en.arb`/`app_zh_TW.arb` ——本 repo 目前的 l10n 政策只維護這兩份,見
`app_zh.arb`/`app_ko.arb` 已停止手動維護的既有決議)新增
`appearanceCuteIcons`/`appearanceCuteIconsDesc` 兩個 key,跑過
`flutter gen-l10n` 重新產生 `app_localizations*.dart`。

## 範圍外(刻意不做)

- **切換偏好跨裝置同步**:見上面第 1 節。
- **另外 240+ 個類別圖示 key 的可愛畫風**:這次只覆蓋使用者逐一審過的 18
  個常用 key,其餘 key 在 cute 模式下會自動 fallback 回 Material 圖示(不會
  報錯、不會空白)。
- **整併三份重複的 key→圖示對照表**(`category_service.dart` 的 259 條
  switch、`grouped_icon_grid.dart` 的 268 條 picker、已死的
  `icon_picker_page.dart`):這是既有技術債
  (見 `docs/changes/2026-09-06-category-icon-color-picker-ux.md:41`),跟這次
  新增一個主題無關,沒有動這三個檔案。

## 驗證

- `flutter test`:新增 4 份測試檔全部綠燈
  (`test/providers/category_icon_style_provider_test.dart`、
  `test/widgets/pencil_underline_painter_test.dart`、
  `test/widgets/cute_category_icon_keys_test.dart`、
  `test/widgets/category_icon_widget_test.dart`),全套 1270 案例只有一個
  跟這次改動完全無關的既有失敗(`test/widgets/calendar_month_jump_test.dart`,
  在改動前的乾淨 `main` 上跑同一個測試也會失敗,已核對過不是這次引入的
  回歸)。
- `flutter analyze`:這次新增/修改的檔案本身乾淨無 issue;專案既有的其他
  lint 雜訊(`dangling_library_doc_comments` 等)跟這次改動無關,沒有新增。
- `flutter gen-l10n`:`en`/`zh_TW` 兩份新 key 生成無誤。
- 實機驗證:iOS Simulator(iPhone 17 Pro)上跑 `flutter run` 實際開啟 App,
  進外觀設定切換「可愛類別圖示」開關,確認 18 個已覆蓋的分類顯示新圖示、
  其餘分類 fallback 回 Material 圖示但疊加類別色底線,深色模式下線稿正確
  跟著換色,切回 Material 後畫面完全回復原狀無版面跳動。
