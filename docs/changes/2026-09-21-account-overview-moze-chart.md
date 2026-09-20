# 資產管理頁 Moze 風格互動走勢圖

日期:2026-09-21
背景:設計文件 `docs/superpowers/specs/2026-09-21-account-overview-moze-chart-design.md`
(使用者提供 3 張 Moze app「帳戶總覽」截圖作參考)。把「資產管理」頁
(`accountsTitle`)淨資產卡片的「走勢」內容,從純折線月圖改成「長條(收入/
支出)+ 折線(淨資產)」互動組合圖,可切換 日/週/月/年,可拖曳看某個時間點
的數字。

**功能入口**:資產管理 → 淨資產卡片「走勢」,可直接在卡片上點/拖曳看某一天
的數字;要看放大版,點頁首展開圖示 → 進入全螢幕圖表頁(橫向)。

**2026-09-21 二次修正**(使用者實測回饋後調整):
1. 內嵌卡片點擊/拖曳不再導航離開——原本「點圖表進全螢幕頁」與「拖曳選點」
   兩個需求字面互斥,拿掉前者,兩處都改成直接選點,只有頁首「展開」圖示能
   進全螢幕頁(細節見第 3、5 節)。
2. 全螢幕頁進頁鎖定橫向、離開恢復自由旋轉(見第 4 節)。

## 1. 純聚合邏輯:`lib/utils/overview_chart_utils.dart`(新檔)

新增 `OverviewGranularity`(day/week/month/year)、`OverviewChartPoint`
typedef,以及四個 `build*OverviewPoints` 純函式,把「逐日/逐月/逐年原始資料
→ 統一的 `OverviewChartPoint` 序列」的分桶規則從 provider(I/O)與 widget
(畫圖)中抽出來,不依賴 Drift/Riverpod,可直接單元測試
(`test/utils/overview_chart_utils_test.dart`)。

淨資產(折線)側四種粒度共用同一個技巧:把 `netWorthTrendSeriesProvider`
查詢範圍的終點固定收斂在「今天」,再依粒度的分桶 key(日/週起始日/月/年)
做「同桶後到值覆蓋前者」聚合(沿用 `net_worth_trend_utils.dart` 既有
`downsampleMonthly` 的做法並泛化)。這樣「當前未結束的週期」(本週/本月/
今年)不需要額外特判 if/else——桶內天生只有到今天為止的資料,同桶覆蓋規則
自然得到「今天」的值,而不是等週期結束才有數字。

收入/支出(長條)側則刻意分兩種做法(取捨,見下):
- **日/週粒度**:呼叫 `StatisticsRepository.totalsByDay` 撈一段連續範圍再由
  前端分桶(週粒度依 `weekStartsOnMondayProvider` 決定週一/週日起算)。
- **月/年粒度**:改用 `totalsByMonth`/`totalsByYearSeries`(各自查詢效率
  較好),不用 `totalsByDay` 前端分桶,避免跨年查詢時撈取大量逐日資料造成
  效能浪費。近 12 個月若跨年,需要额外拼今年+去年兩次 `totalsByMonth` 查詢
  結果並濾掉今年裡「今天之後」的月份(`totalsByMonth` 對整年 1~12 月都會
  補一筆,含未來月份);近 5 年若歷史不足 5 年,`totalsByYearSeries` 只回傳
  有資料的年份範圍,由 `buildYearlyOverviewPoints` 補 0 補齊到完整 5 年。

## 2. 資料源:`accountOverviewChartSeriesProvider`(`lib/providers/statistics_providers.dart`)

`FutureProvider.family.autoDispose<List<OverviewChartPoint>,
OverviewGranularity>`,依粒度算查詢視窗、分別呼叫 repo,再交給
overview_chart_utils.dart 的純函式組裝。

**空狀態的取捨**:`build*OverviewPoints` 系列函式為了讓 X 軸桶数固定
(7/8/12/5),永遠會補 0 值把桶填滿——這對「帳本存在但這段時間沒交易」是
正確行為(桶內金額本來就是 0),但对「帳本裡根本沒有任何帳戶」這種情形
(`getNetWorthTrendSeries` 在 `accounts.isEmpty` 時回傳空列表)會被误画成一
条乎 0 橫線,而不是設計文件要求的「資料點不足時顯示空狀態」。因此 provider
在拿到 `netWorthDaily` 之後,若它是空列表就直接短路回傳 `[]`,交給 widget
層既有的 `points.length < 2` 判斷顯示 `commonEmpty` 文案(跟舊版
`_buildNetWorthChartInline` 對 `netWorthTrendSeriesProvider` 空列表的處理
一致)。

## 3. 圖表元件:`lib/widgets/charts/overview_combo_chart.dart`(新檔)

`OverviewComboChart`:手寫 `CustomPainter`(跟 `line_chart.dart` 風格一致,
不引入新圖表函式庫),左軸長條(收入/支出,0 起算)+ 右軸折線(淨資產,
min/max 自動抓格線),選中點顯示竖直參考線 + 圓點 + 數值泡泡(邊界自動
內縮),下方「日期 + 圓點 + 淨收支數字」列同步更新。右上角統計區間按鈕
(`showModalBottomSheet` 四選一)切換粒度後重設選中點為最新時間點。

**互動模式(2026-09-21 二次修正後)**:內嵌卡片版與全螢幕版都是「自己直接
處理 tap/拖曳選點」,沒有外層 `InkWell` 攔截點擊——一開始曾用
`line_chart.dart` 既有的 `LineChart.interactive` 開關做「內嵌版不吞手勢、
外層 InkWell 負責點擊進全螢幕頁」,但使用者實測後回饋:點卡片應該直接選
點看數字,不要被導去別的頁面。因此拿掉 `interactive` 參數,兩種用法都固定
可互動;進全螢幕頁改成只能靠頁首「展開」圖示(見第 5 節)。

內嵌版與全螢幕版各自是獨立的 widget 實例,`OverviewGranularity` 狀態各自
獨立持有(不跨實例同步),兩者都各自呼叫同一個
`accountOverviewChartSeriesProvider`——同一份資料來源/區間切換/拖曳邏輯,
沒有重複開發。

## 4. 全螢幕頁:`lib/pages/account/account_overview_chart_page.dart`(新檔)

`AccountOverviewChartPage`:標準 `PrimaryHeader`(含返回鍵)+ 佔滿頁面高度
的 `OverviewComboChart`。字級/長條寬度不需要額外的「全螢幕模式」參數——
`CustomPaint` 本就依實際 `Size` 自動縮放。

**強制橫向**:長條+折線組合圖需要較寬畫布才看得清楚,`initState` 呼叫
`SystemChrome.setPreferredOrientations([landscapeLeft, landscapeRight])`
鎖橫向,`dispose` 還原成 `DeviceOrientation.values`(自由旋轉,App 其它頁面
本來就沒鎖過方向,等同還原到進頁前的預設狀態)。這是頁面等級的暫時鎖定,
不影響其它頁面。

已確認 `android/app/src/main/AndroidManifest.xml` 的 `MainActivity` 本身
沒有設定 `android:screenOrientation`(先前排查時看到的 `screenOrientation
="portrait"` 是圖片裁切用的 `UCropActivity`,跟主 Flutter 頁面無關),不會
擋掉 `setPreferredOrientations` 的效果。iOS 這邊 `Info.plist` 的
`UISupportedInterfaceOrientations~ipad` 只列了 Portrait/PortraitUpsideDown、
沒有橫向,所以這個鎖定在 iPad 上不會真的轉成橫向(iOS 原生限制優先於
Flutter 的請求)——這是既有的 iPad 方向設定限制,修正它需要改
`Info.plist` 影響整個 App 在 iPad 上的旋轉行為,不在本次範圍內。

## 5. 頁首圓形圖示:`lib/pages/account/accounts_page.dart`

新增私有 widget `_CircleHeaderIcon`(32×32 圓形,背景用
`BeeTokens.surfaceCapsule` 中性 token、圖示色用 `BeeTokens.iconPrimary`,
深色模式自動跟隨),取代原本兩個裸 `IconButton`,並在最左新增第三個
「展開」圖示(`Icons.open_in_full`,點擊進 `AccountOverviewChartPage`,
是目前唯一能進全螢幕頁的入口)。三者一起靠右對齊,順序:展開 / 新增帳戶 /
設定。`_editingOrder`(帳戶清單拖曳排序)模式下仍換成單一「完成」按鈕退
出,邏輯不變。

`_buildNetWorthChartInline` 改成直接回傳 `SizedBox(height:
220, child: OverviewComboChart())`,不再包一層「點擊進全螢幕頁」的
`InkWell`(原本的 `_inlineChartBox` loading/error/empty 處理已內收進
`OverviewComboChart` 自身,一併刪除)。

## 6. 明確的範圍外決定:`NetWorthTrendPage` 變成沒有入口的死代碼

`lib/pages/account/net_worth_trend_page.dart`(舊版純折線淨值趨勢全螢幕頁)
在這次改動前只有一個呼叫點,就是本次替換掉的 `_buildNetWorthChartInline`。
設計文件的範圍只涵蓋「新增 `AccountOverviewChartPage`」,沒有要求刪除舊頁
面,因此這個檔案**刻意保留、不刪除、不修改**,但目前確實沒有任何頁面會
導航過去。是否刪除留給之後單獨評估,不在本次變更範圍內。

## 7. 本地化

新增 key(僅 `app_en.arb` + `app_zh_TW.arb`,依既有政策不再維護
`app_zh.arb`/`app_ko.arb`):`accountOverviewChartExpandTooltip`、
`accountOverviewChartPageTitle`、`accountOverviewChartGranularityTitle`、
`accountOverviewChartByDay`/`ByWeek`/`ByMonth`/`ByYear`。

## 測試

- `test/utils/overview_chart_utils_test.dart`:`overviewWindowStart` 四種
  粒度視窗起點、四個 `build*OverviewPoints` 的分桶/合併正確性,含「當前未
  結束週期只加總到今天」「週起始日切換影響分桶」「跨年邊界不串桶」「歷史
  不足時補 0」等邊界情況。
- `test/widgets/charts/account_overview_chart_page_test.dart`:全螢幕頁
  smoke test——空帳本顯示 `commonEmpty`、有資料時能開啟統計區間選單。
- **未新增** `AccountsPage`(資產管理頁本體)的 widget smoke test:實測
  `pumpWidget(AccountsPage())` 會觸發 `initState` 裡既有的
  `refreshExchangeRatesFromUi(ref)` 背景刷新(`accounts_page.dart:311-313`,
  跟本次改動無關的既有邏輯),在沒有網路的 widget test 沙盒環境裡卡在真實
  網路逾時(實測 5 分半才失敗),最終還在 `flutter_test` 的
  `!timersPending` 收尾檢查上斷言失敗(「A Timer is still pending even
  after the widget tree was disposed」)。這代表 `AccountsPage` 本體目前
  不適合用一般 widget test 直接 `pumpWidget`,不是本次新增程式碼的問題;
  頁首三個圓形圖示(展開／新增／設定)改為只靠程式碼審閱確認順序與
  `onPressed` 接線正確,未來若要幫 `AccountsPage` 補 widget test,需要先
  單獨處理這個既有的初始化副作用(例如抽出可覆寫/可停用的 hook)。
- 未另外針對 `OverviewComboChart` 內部拖曳選點寫 widget test(`CustomPaint`
  手勢座標計算已跟純函式資料分桶邏輯解耦,選點對應數字是否正確已經由
  `overview_chart_utils_test.dart` 間接保證;手勢座標本身的正確性建議之後
  用 preview 手動驗證 日/週/月/年 切換 + 拖曳互動)。
