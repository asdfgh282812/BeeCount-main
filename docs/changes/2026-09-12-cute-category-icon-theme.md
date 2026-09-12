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
若為 `cute`,就用 `CuteCategoryIcon.maybeBuild` 嘗試取對應 SVG(拿不到就退回
原本的 `Icon(iconData, ...)`),圖示下面疊一條 `CategoryColorUnderline`(顏色
預設來自 `CategoryUtils.parseColor(category?.color)`,解析失敗就退回
`iconColor`;呼叫端如果自己已經解析過顏色,可以用新增的
`underlineColorOverride` 參數直接覆蓋,見第 6 節)。

**(2026-09-12 追加)原本只動 `showBackground == false`,現在 cute 模式下
`showBackground` 完全不影響輸出**:第一版刻意只改「無背景色圓底」這條路徑,
`showBackground == true`(類別卡片用的圓形色底徽章)維持原樣不動——但使用者
實機看過後反饋圓形色底跟 cute 手繪圖示放在一起「很難看」,要求 cute 模式下
一律拿掉圓底、顏色統一用底線呈現。所以現在的判斷式只看
`iconStyle == CategoryIconStyle.cute`,不再檢查 `showBackground`;Material
模式下 `showBackground == true` 的圓底徽章行為完全沒變。

## 5. 外觀設定切換開關

**改了什麼**:`lib/pages/settings/appearance_settings_page.dart` 在「減少
動畫」開關跟「顯示縮放」之間插入一個新的 `AppListTile` + `Switch.adaptive`,
接 `categoryIconStyleProvider`。四份語系檔裡實際維護的兩份
(`app_en.arb`/`app_zh_TW.arb` ——本 repo 目前的 l10n 政策只維護這兩份,見
`app_zh.arb`/`app_ko.arb` 已停止手動維護的既有決議)新增
`appearanceCuteIcons`/`appearanceCuteIconsDesc` 兩個 key,跑過
`flutter gen-l10n` 重新產生 `app_localizations*.dart`。

## 6. (追加)另外兩處圓形色底徽章畫面——建議分類格、圖示選取格

**背景**:使用者實機看過第一版後,除了第 4 節那個全域行為調整,還額外指出
兩個具體畫面也要跟著改:「建議」分類分頁(`SuggestedCategoryGrid`)跟分類
編輯頁的「系統圖示」選取格(`GroupedIconGrid`)。這兩處各自有自己的一份
Container 渲染邏輯,**不是**透過 `CategoryIconWidget` 的 `showBackground`
路徑畫出來的,所以光改第 4 節那段還不夠,要分開處理。

**`lib/widgets/biz/suggested_category_grid.dart`**:改成 `ConsumerWidget`,
`ref.watch(categoryIconStyleProvider)`。cute 模式下,原本包一層
`resolvedColor` 當底色的圓形 `Container` 拿掉,直接放
`CategoryIconWidget(category: category, size: 26, underlineColorOverride:
resolvedColor)`——這裡要傳 `underlineColorOverride` 而不是讓
`CategoryIconWidget` 自己重新讀 `category.color`,因為這個畫面對二級分類有
自己的「反查父分類顏色」規則(`colorByCategoryId`),`CategoryIconWidget`
本身不知道這個規則。Material 模式的圓形色底徽章完全不動。「新增」那格(固定
`+` 圖示)兩種模式下都不變——它本來就不是類別色,跟這次的問題無關。

**`lib/widgets/biz/grouped_icon_grid.dart`**:改成 `ConsumerWidget`。cute
模式下,對每一格 icon key 呼叫 `CuteCategoryIcon.maybeBuild`,能拿到 SVG
就用它換掉原本的 `Icon(iconData.iconData, ...)`;拿不到(不在 18 個白名單
裡)就照舊顯示 Material 圖示。選中/未選中的邊框跟底色樣式完全不變——這裡
本來就沒有類別顏色可顯示(顏色是編輯頁另外一塊「分類顏色」色板選的,跟
圖示選取格是分開的 UI),使用者要的只是「選圖示的時候看到的畫風,要跟切完
之後實際顯示的畫風一致」,不牽涉底線。

**`lib/widgets/category_icon.dart` 新增的 `underlineColorOverride` 參數**:
給上面 `SuggestedCategoryGrid` 這種「呼叫端已經自己解析好顏色」的場景用,
預設 `null`,行為等同沒加這個參數之前(繼續讀 `category?.color`)。

## 7. (追加)擴充到 129 個圖示 + 通用 fallback,完全不再顯示 Material 圖示

**背景**:使用者看過第 6 節的修改後,又回報「支出/收入」單獨進入的分類選擇格
(`lib/widgets/category/category_selector.dart` 的 `_CategoryItem`——第三處
自己包一層色底 `Container` 的畫面,前面漏掉沒改到)還是有色底,並且提出更大
的需求:把原本只覆蓋 18 個 key 的畫風,擴充到覆蓋**所有預設分類**,而且
「只要開啟可愛圖示,就只會顯示手繪圖示,不會再看到 Material 圖示」。

**規模確認**:核對 `SeedService.getDefaultIcon()`(一級 46 個 flat key + 二級
分類 map 展開)用到的 icon value,總共 127 個不重複,其中 16 個跟原本 18 個
裡的重疊,缺口是 111 個。跟使用者確認範圍後(見對話紀錄),決定:111 個一次
全部畫完,並且另外設計 1 個通用「其他」手繪圖示(`_fallback.svg`)當所有
「沒有專屬素材的 key」的顯示內容——不管是自訂分類、還是還沒特別設計過的
生僻 key,cute 模式下都顯示這個通用圖示,徹底不再出現 Material 圖示。

**`assets/icons/categories_cute/`**:新增 111 個新 icon key 的 SVG + 1 個
`_fallback.svg`,畫風延續第 3 節的規則(`stroke="currentColor"` 線稿 +
1-2 個寫死 hex 的裝飾色塊,`viewBox="0 0 48 48"`)。這批是分 4 批平行讓
subagent 各畫 ~28 個、最後逐一核對檔名/viewBox/currentColor 出爐的,不是
使用者逐張看過 Artifact 預覽確認的(跟原本 18 個的流程不同,使用者這次直接
要求「一次全部畫完」,略過分批預覽這一步)。

**`lib/widgets/cute_icons/cute_category_icon_keys.dart`**:
`kCuteCategoryIconKeys` 從 18 個擴充到 129 個(18 + 111,無重複)。
`CuteCategoryIcon.maybeBuild` 的行為改變(這是這次改動裡唯一動到既有邏輯的
地方)——**以前**:key 不在白名單(或為 `null`)回傳 `null`,呼叫端 `??` 接
Material `Icon` 顯示;**現在**:一律回傳非 null 的 `CuteCategoryIcon`,key
不在白名單就用 `_fallback` 這個 assetKey 頂上。回傳型別也從 `Widget?` 改成
`Widget`(non-nullable)——因為現在真的不可能回傳 null 了,順手把型別收緊,
兩個呼叫端(`category_icon.dart`、`grouped_icon_grid.dart`)原本的
`cuteIcon ?? Icon(...)` 死代碼也一併清掉(`grouped_icon_grid.dart` 那邊的
`??` 是靠外層 `isCute ? ... : null` 三元判斷式維持型別可為 null,不用改)。

**`lib/widgets/category/category_selector.dart`**:`_CategoryItem` 改成
`ConsumerWidget`,cute 模式下拿掉圓形色底 `Container`,直接用
`CategoryIconWidget(..., underlineColorOverride: resolvedColor)`——跟第 6
節 `SuggestedCategoryGrid` 同樣的處理方式(這裡的 `resolvedColor` 也有二級
分類繼承父分類顏色的邏輯,所以一樣要用 `underlineColorOverride` 而不是讓
`CategoryIconWidget` 自己重新解析)。「有子分類」的右下角三點徽章
(`Positioned` 疊加)不受影響,兩種模式下都還在。

**分類編輯頁的圖示選取格(`grouped_icon_grid.dart`)跟這次擴充的關聯**:
不用再改——第 6 節已經把邏輯寫成「cute 模式下呼叫 `maybeBuild`,回傳什麼就
顯示什麼」,`maybeBuild` 這次擴大覆蓋範圍後,選取格自動跟著多出 111 個能顯示
手繪版的 key,不用碰這個檔案。

**這次沒有再地毯式搜過全專案是否還有第 4 種色底 Container**:目前確認過的
是第 4/6/7 節這 4 個地方(`CategoryIconWidget` 自己的 `showBackground`、
`SuggestedCategoryGrid`、`CategorySelector._CategoryItem`)。
`grep -rln "BoxShape.circle" lib | xargs grep -l "CategoryIconWidget"` 顯示
還有 `category_manage_page.dart`(3 處類似寫法)、`account_detail_page.dart`、
`transaction_list_item.dart`、`analytics/category_rank_row.dart` 沒有處理——
這些使用者還沒实际看到/反馈过,先不动,等使用者之後在这些画面看到色底再处理,
避免在没验证过实际视觉效果前就大范围改动。

## 範圍外(刻意不做)

- **切換偏好跨裝置同步**:見上面第 1 節。
- **(2026-09-12 更新)第 7 節之後,不再有「其餘 key fallback 回 Material」
  這件事**:129 個預設分類 key 各自有專屬手繪圖示,其餘任何 key(自訂分類、
  更生僻的 key)都顯示 `_fallback.svg` 通用手繪圖示,cute 模式下不會再出現
  Material 圖示。`category_service.dart` 259 條 switch 裡,還有 129 之外
  沒被 129 涵蓋、但被使用者自訂分類實際用到的 key,一样會落到
  `_fallback.svg`,這是刻意的(見第 7 節)。
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
  進外觀設定切換「可愛類別圖示」開關,確認可以正常開關、App 沒有崩潰。

**(2026-09-12 追加,第 6 節改動)**:這一輪(拿掉 `showBackground` 圓底、
`SuggestedCategoryGrid`/`GroupedIconGrid` 兩處個別畫面)是根據使用者實際
操作 App 後回報的畫面反饋才動的手,不是原計畫內容。新增/更新了 3 份測試檔
(`test/widgets/category_icon_widget_test.dart` 補一個 `showBackground: true`
案例、新增 `test/widgets/suggested_category_grid_test.dart`、新增
`test/widgets/grouped_icon_grid_test.dart`),全部綠燈;`flutter test` 全套
1276 案例(新增 6 個測試後)只有前述同一個既有無關失敗。`flutter analyze`
乾淨。**這一輪改完後,尚未讓使用者在模擬器上重新肉眼確認實際畫面**——下次
如果使用者或未來的 session 要繼續這個功能,這是還沒收尾的驗證步驟。

**(2026-09-12 再追加,第 7 節改動——129 個圖示 + 通用 fallback)**:
- 129 個 asset key(18 舊 + 111 新)跟 1 個 `_fallback.svg` 全部核對過:
  `kCuteCategoryIconKeys ∪ {_fallback}` 跟 `assets/icons/categories_cute/`
  實際檔名做過集合差集比對,雙向都是空集合(無缺檔、無多餘檔),另外用
  Python 的 `xml.etree.ElementTree` 逐一 parse 過全部 130 個 SVG 檔,確認
  都是合法 XML、都有 `viewBox="0 0 48 48"`、都含 `currentColor`。
- 新增 `test/widgets/category_selector_cute_icon_test.dart`(補上
  `CategorySelector._CategoryItem` 這第三處色底 Container 的覆蓋),更新
  `test/widgets/cute_category_icon_keys_test.dart`(129 個 key 的數量斷言、
  `maybeBuild` 不再回傳 null 的新行為)、`category_icon_widget_test.dart`、
  `grouped_icon_grid_test.dart` 裡「fallback 回 Material」的舊斷言,改成
  斷言「顯示 `_fallback` 手繪圖示」。`flutter test` 全套 1279 案例,只有
  前述同一個既有無關失敗;`flutter analyze` 對這次觸碰到的檔案乾淨無新增
  issue。
- **這批 111 個新圖示沒有走使用者逐張預覽確認的流程**(使用者明確要求
  「一次全部畫完再看」,略過了原本 18 個那種分批 Artifact 預覽再定稿的
  步驟)——所以實際手繪畫風是否讓使用者滿意、有沒有哪幾張需要重畫,**還沒
  经过使用者本人肉眼確認**,只驗證了「檔案存在、格式合法、程式碼接線正確」
  這個技術層面。這是這次改動最大的未知風險,下次使用者反饋在這批新圖示上,
  預期會需要針對個別圖示重畫調整。
