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

## 8. (再追加)全表覆蓋 288 個 key + 修正強調色偏暗 + 圖示放大

**背景**:使用者實機再看一輪,回報三件事:(a)還有很多實際分類(尤其
「交通」大類底下,一次就有 5 個子分類)顯示 `_fallback.svg`;(b)不少
新畫的圖示強調色太暗(特指深藍色系),擔心深色模式下看不清楚;(c)圖示整體
偏小,希望放大。

**(a) 全表覆蓋**:核對 `lib/services/data/category_service.dart` 的
`CategoryService.getCategoryIcon` switch,總共 257 個不重複 key(比第 7 節
用的 `SeedService` 127 個预设分类 key 的集合大得多——後者只是「新建分類时
的默认值」,前者才是「实际渲染任何分类图示时真正会查的完整表」,使用者自己
新建/编辑分类时透过 `grouped_icon_grid.dart` 的图示选取格能选到的 268 个
key 绝大多数也在这个范围内)。跟已覆蓋的 129 個比對後缺口是 159 個,這次
全部畫完,`kCuteCategoryIconKeys` 從 129 擴充到 **288**(= 257 + 之前就有、
但不在 `category_service.dart` switch 里的 31 个原始/预设专属 key,比如
`account_balance_wallet`/`card_travel` 等,詳見檔案內的分段注解)。至此
`CuteCategoryIcon.maybeBuild` 對 `CategoryService.getCategoryIcon` 涵蓋的
每一個 key 都有專屬手繪圖示,`_fallback.svg` 只會在使用者輸入了一個連
`category_service.dart` 都不認得的 icon 字串時才出現(理論上不應該發生,
是防禦性的兜底,不是這次的「正常路徑」)。

**(b) 強調色偏暗的修正**:寫了一個腳本核對全部 130 張既有 SVG 的強調色
(fill hex,不含 `currentColor`)感知亮度(`0.299R+0.587G+0.114B`),發現
最暗的 `#6B8CAE`(用在 29 個檔案裡,包含原始 18 個裡的 `laptop.svg`)
亮度只有 134,`#4FAE8B`(9 個檔案)134→141.6,`#4DA8B0`(`directions_bus.svg`
原始 18 個之一)141.7——這三個偏暗色是使用者說「太多暗色系統顏色了(深藍)」
的來源:强调色是写死的 hex,不像线稿那样透过 `currentColor` 跟着主题换色,
深色模式背景本身也很暗,一个本来就偏暗的强调色块会跟暗色背景糊在一起、
辨識度變差。全域 `sed` 替換成更亮的同色系版本(`#6B8CAE→#9AC0E6`、
`#4FAE8B→#74CBA3`、`#4DA8B0→#6FC4CC`,亮度分別提升到 185/172/172),
包含原始 18 個檔案(這裡刻意不迴避改到「已核准」的舊圖示,因為使用者的
反饋是針對整體觀感,不是針對特定某一批)。第二輪 159 個新圖示的畫圖指令
裡也加了明確的「強調色亮度下限 150」規則,避免重蹈覆轍。

**(c) 圖示放大**:`lib/widgets/category_icon.dart` 的 cute 分支新增
`glyphSize = size * 1.25`,取代原本直接用呼叫端傳入的 `size`——手繪圖示
旁邊沒有 Material 版原本圓底徽章的視覺襯托,同樣的 `size` 看起來比較小。
1.25 倍還在舊版圓底徽章 `size * 1.5` 預留的版面空間內,不會撐爆既有版面。
這是唯一一個修改點,`suggested_category_grid.dart`/`category_selector.dart`
都是透過 `CategoryIconWidget` 走這條路徑,自動一起放大;只有
`grouped_icon_grid.dart` 的圖示選取格(直接呼叫
`CuteCategoryIcon.maybeBuild`,不經過 `CategoryIconWidget`)沒有放大,因為
那裡是刻意緊湊的選取網格,使用者沒有反饋那裡太小。

**測試**:`test/widgets/cute_category_icon_keys_test.dart` 的數量斷言改成
288,新增對第二輪 key(`train`/`boat`/`category`/`bookmark`/`wifi`)的
覆蓋檢查;`test/widgets/grouped_icon_grid_test.dart` 原本「未覆蓋 key 顯示
fallback」的測試改寫成「cute 模式下整個網格(expense/income 兩份)找不到
任何 `Icon` 元件,全部都是 `CuteCategoryIcon`」——因為選取格自己的 259 條
key 现在全部覆盖,原本拿來測試 fallback 行為的 `'label'` key 也被這輪畫進去
了,舊測試的前提不再成立。

## 9. (再追加)暗色模式線稿加淡白底 + 明細列表圖示格 0.4px overflow

**背景**:使用者實機在暗色主題下看,回報兩件事:(a)手繪線稿在深色背景下
線條偏細、看不清楚;(b)「明細」列表(`transaction_list_item.dart`)的分類
圖示格出現紅黑條紋的 `RenderFlex overflowed by 0.4 pixels` 警告,底線效果
沒有正常顯示。

**(a) 暗色模式線稿加淡白底**:`CuteCategoryIcon.build`
(`lib/widgets/cute_icons/cute_category_icon_keys.dart`)在
`BeeTokens.isDark(context)` 為真時,用 `DecoratedBox` 在 SVG 外面加一層
`Colors.white.withValues(alpha: 0.08)` 的圓形底,提升線條與深色背景的對比。
故意把透明度壓得很低(8%),不會變回第 6 節才剛拿掉的那種醒目色底徽章——
這一層只是提升可讀性的中性襯托,不帶分類色彩。改在 `CuteCategoryIcon`
這個最底層畫,所有呼叫路徑(`CategoryIconWidget`、`SuggestedCategoryGrid`、
`GroupedIconGrid`)都會自動套用,不用逐一改。

**(b) 明細列表 0.4px overflow**:`transaction_list_item.dart` 原本用一個
寫死 `width: 32, height: 32` 的圓形色底 `Container` 包着分類圖示(呼叫
`CategoryIconWidget(size: 18)`)。Cute 模式下 `CategoryIconWidget` 回傳的是
「圖示 + 底線」上下排列的 `Column`,實際高度是
`size*1.25`(圖示)+ 間距 + 底線,`size=18` 時算出來 ≈32.4——比固定的
32 高出 0.4px,`Column` 在緊約束(tight constraint)下放不下,觸發
`RenderFlex overflow`。

第一輪修正只是把外層 `Container` 換成同樣寫死 `height: 32` 的 `SizedBox`,
拿掉了色底、但兩者都是緊約束,並沒有解決真正的溢出——使用者截圖顯示警告
依舊在。真正的修正:cute 模式下只固定寬度(`SizedBox(width: 32)`,維持跟
右側文字的水平間距對齊),不設高度上限,讓 `Column` 依內容自然撐開;`Row`
本身 `crossAxisAlignment` 預設 `center`,整列高度會自動撐到跟圖示一樣高,
不影響其他欄位。同時比照第 6 節其他畫面,把這裡也一併改成 cute 模式拿掉
圓形色底、改用 `underlineColorOverride` 顯示分類色底線,補上這裡先前沒
處理到的第三個「明細列表」場景(第 5 部分「待處理」清單里提過的
`transaction_list_item.dart` 就是這裡)。

**測試**:新增 `test/widgets/transaction_list_item_cute_icon_test.dart`,
斷言 cute 模式下 `tester.takeException()` 為 `null`(這個回歸測試在改回
`height: 32` 的版本上會失敗,驗證過真的能抓到這個 bug)、顯示
`CategoryColorUnderline`、不再有圓形色底 `Container`;另一個案例驗證
Material 模式維持原樣(圓形色底、無底線)。`flutter test` 全套 1281 案例
只有同一個既有、跟本次改動無關的失敗
(`test/widgets/calendar_month_jump_test.dart`)。

## 10. (再追加)底線顏色誤用 primaryColor + 帳戶明細/專案/分類管理仍未套用 cute

**背景**:使用者實機再看一輪,回報三件事:(a)分類編輯的圖示選取格裡,底線
顏色沒有跟著分類跑,「明明圖示是綠色的,底線卻是黃色的」;(b)「專案」
(`project_detail_page.dart`)裡的分類圖示還是舊版方形色底,沒有跟著切到
cute;(c)每個帳戶詳情頁(`account_detail_page.dart`)的交易列表底線一樣有
問題(第 9 節修的是首頁/明細共用的 `TransactionListItem`,帳戶詳情頁是自己
另一份 `TransactionTile` 實作,没有共用那份代码,漏改了)。

**(a) 底線顏色錯誤的根因**:`SeedService` 幫預設分類建檔時本來就不寫入
`color` 欄位(只有使用者自己在顏色選擇器挑過才會有值),所以絕大多數預設
分類(門診/醫療用品/藥品…)的 `category.color` 其實是 `null`。
`category_icon.dart` 原本的底線顏色 fallback 邏輯是
`underlineColorOverride ?? CategoryUtils.parseColor(category?.color) ?? iconColor`,
`iconColor` 沒有另外傳 `color` 參數時就是 `primaryColor`——這個值會跟著
App 當下的主題色跑,使用者截圖當時 App 剛好套用「一週年」節日限定金色
主題,没配色的分類底線因此显示成刺眼的金色,跟图示本身的绿色强调色对不
起来,看起来像「底线没有跟着分类颜色跑」。**修正**:把 fallback 換成中性
的 `BeeTokens.iconCategory(context)`(跟線稿本身同色系的墨色 token),
没配色时不再套用会随主题变动的 primaryColor。新增回歸測試
`test/widgets/category_icon_widget_test.dart`(用一個刻意跟預設值不同的
`primaryColorProvider` override 驗證底線顏色不等於它,而是等於
`BeeTokens.iconCategory`)。

**(b) 專案裡的圖標**:`project_detail_page.dart` 的 `_CategoryBudgetTile`
(分類預算列)跟 `_UnsetCategorySectionState._buildRow`(未設定分類清單)
各自寫死一個方形(`BorderRadius.circular(8)`)色底 `Container` +
純 Material `Icon`,完全没有 cute 分支。抽出共用的 `_ProjectCategoryIcon`
(`ConsumerWidget`),cute 模式下拿掉方形色底、改用
`CategoryIconWidget(underlineColorOverride: resolvedColor)`,兩個呼叫點都
改用它。

**(c) 帳戶詳情頁**:`account_detail_page.dart` 的 `TransactionTile` 是獨立
於 `TransactionListItem` 的另一份交易列渲染邏輯,同樣的圓形色底
`Container` + `CategoryIconWidget(size: 18)` 組合、同樣的 32 高度緊約束,
跟第 9 節分析的 `TransactionListItem` 是一模一樣的成因(cute 模式「圖示+
底線」直向排版 ≈32.4 高,擠進寫死 32 高的容器裡溢出 0.4px)。套用同一個
修法:cute 模式下只固定寬度、不設高度上限,並拿掉色底改用底線。

**順手一併檢查/修正的其餘同類位置**(都是同一批「圓形/方形色底 Container
+ CategoryIconWidget」模式,趁這次上下文還在,一次核對完,避免又要使用者
一個個畫面找出來回報):
- `category_manage_page.dart`「分類管理」主網格(`_CategoryCard`,28/32 高
  的圓形色底)——同樣的 32.4 vs 32 溢出成因,补上 cute 分支。
- `category_manage_page.dart` 子分類彈窗(`_SubcategoryDialog` 標題列的
  32 高圓形色底、`_DialogSubCategoryCard` 26 高圓形色底)——後者 26 高其實
  沒有實際溢出(14×1.25+間距+底線≈25.2<26),但為了畫面一致性一併改成底
  線呈現。
- `lib/widgets/analytics/category_rank_row.dart`(分析頁的分類排行榜列)
  ——44/38 高的圓形色底本身沒有溢出風險(圖示更大、格子也更大),但同樣
  一直是舊版色底徽章,没跟着 cute 切換;這裡的顏色來源是排行榜自己算好的
  `widget.color`(圖表配色,不一定等於 `category.color`),所以
  `underlineColorOverride` 直接傳 `widget.color`,不是走 `category.color`
  解析,底線顏色才會跟畫面上其他排行榜元素(進度條、百分比)的配色對得上。
- `category_manage_page.dart` 頂部「轉帳圖示設定」卡片(`CategoryIconWidget(
  showBackground: true)` 那處)已經是走 `showBackground` 參數,第 6 節就把
  cute 分支改成「不管 showBackground 是不是 true 都忽略」,這裡不用額外
  改動就自動套用。

**測試**:除了 (a) 的回歸測試,其餘 (b)(c) 及順手修正的位置目前用
`flutter analyze` + `flutter test` 全套 1282 案例(同一個既有無關失敗)
驗證沒有引入新的編譯錯誤/回歸;沒有針對 `account_detail_page.dart`/
`project_detail_page.dart`/`category_manage_page.dart`/`category_rank_row.dart`
逐一新增 widget test(這幾個頁面本身的既有測試覆蓋率就不高,建立完整測試
夾具超出這次修 bug 的範圍),實機驗證仍待使用者確認。

## 範圍外(刻意不做)

- **切換偏好跨裝置同步**:見上面第 1 節。
- **(2026-09-12 更新,第 8 節後)cute 模式下實質上不再有 fallback 這件
  事**:288 個 key 涵蓋 `CategoryService.getCategoryIcon` 認得的每一個 key,
  `_fallback.svg` 只在遇到連 Material 對照表都不認得的字串時才會出現,是
  防禦性兜底,不是正常會走到的路徑。
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

**(2026-09-12 再再追加,第 8 節改動——288 個 key 全表覆蓋 + 亮度修正 +
放大)**:
- 289 個檔案(288 個 key + `_fallback.svg`)跟
  `assets/icons/categories_cute/` 實際檔名再次做過集合差集比對,雙向皆空;
  全部 289 個檔案重新跑過 XML 合法性 + `viewBox`/`currentColor` 檢查,全過。
- 亮度修正後,全部 289 個檔案裡的強調色 hex 只剩 28 個「邊緣值」落在
  146–149.7(都是原始 18 個既有色盤的重用,例如 `home.svg` 的 `#6FA97B`
  sage green),沒有任何一個接近使用者點名的深藍色系;真正的深藍
  `#6B8CAE`(29 檔)/`#4FAE8B`(9 檔)/`#4DA8B0`(1 檔)已全部替換。
- `test/widgets/cute_category_icon_keys_test.dart`(288 數量斷言 + 第二輪
  key 抽查)、`test/widgets/grouped_icon_grid_test.dart`(改寫成「整個網格
  找不到任何 Material `Icon`」)更新完成,`flutter test` 全套 1279 案例
  只有前述同一個既有無關失敗,`flutter analyze` 乾淨。
- **這 159 張圖一樣沒有經過使用者逐張確認**——已更新
  [Cute Icon Review Board](https://claude.ai/code/artifact/e024d9b9-6655-49c8-a1b7-5e6cff6b48f2)
  這個複審看板加入全部 289 個圖示,方便使用者事後檢視、挑出需要重畫的。
- 圖示放大(`glyphSize = size * 1.25`)跟亮度修正都只驗證了程式碼邏輯跟
  數值,實機視覺效果(是否「剛好大小」、深色模式下是否真的清楚)同樣還沒
  经过使用者在模擬器/實機上肉眼確認。
