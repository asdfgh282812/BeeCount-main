# 「報表」分頁改為 MOZE 風格統計報表

參考:https://doc.moze.app/analysis/statistics-report

## 入口

- 底部導覽第 4 個分頁「報表」(`lib/app.dart` 的 `_pages[3]`),進去是報表清單。
- 點卡片開報表。右上 `+` 新增報表,右上「恢復」圖示把刪掉的內建報表加回來。卡片右側 `⋯` 可編輯、複製、刪除;長按拖曳可排序。
- 報表頁右上:篩選(有條件時顯示數字徽章)、編輯(名稱/期間/篩選)、分享海報(只在「每 1 月 / 每 1 年」且沒有篩選時出現)。
- 原本洞察頁的內容(圓餅、分類排行、趨勢)在報表頁的「類別」分頁。
- What's New:`lib/whats_new/whats_new_content.dart` 的 `'3.5.8'`。**pubspec 目前還是 3.5.7**,要等版本號升到 3.5.8 才會彈出。3.5.7 已經發布過,放那裡已更新的使用者看不到。

## 架構:一次載入、在記憶體聚合

期間內交易用一次 SELECT 撈出來,分類、帳戶、標籤、專案、欠款也一次批次預載。接著把交易展開成 `ReportEntry` legs:一般交易一條,拆帳交易每筆明細一條。篩選套用在 leg 上,10 個分頁都從同一份 legs 算出來。

為什麼不為每個分頁各寫 SQL:
- 拆帳、共享帳本 synthetic 分類/帳戶/標籤、標籤覆寫這些解析本來就在 Dart 裡做。10 個維度 × 包含/排除改寫成 SQL,等於把同一套解析抄 10 遍。
- 分類篩選要作用在拆帳明細:一筆拆成餐飲 70、娛樂 30 的交易,篩「餐飲」只能算 70。SQL 做不到這件事。
- 個人帳本每年大約幾千到一萬多筆,O(n) 聚合只要幾毫秒,切分頁也不用重查。

檔案:

- **期間**
  - 定義:`lib/models/report/report_period.dart`,三種類型(重複循環 / 截至今天 / 單一區間),可存成 JSON。
  - 解析:`lib/services/report/report_period_resolver.dart`,純函式。
    - 重複循環的月和年按帳本 monthStartDay 切;每 N 月會對齊,例如季從 1/4/7/10 月開始。
    - 當期只算到明天 0 點(不含未來交易),跟舊洞察頁一樣。
    - 日期一律用日曆運算,不用 `Duration`,避開 DST 問題。
- **篩選**
  - 定義:`lib/models/report/report_filter.dart`。
  - 所有實體都用 **syncId** 當 key,沒有 syncId 的舊資料用 `id:<本地 id>`(`reportEntityKey`)。
  - 不存本地 int id,是為了以後要跨裝置同步報表時不必轉換。
- **載入**:`lib/data/repositories/local/local_report_loader.dart`(`StatisticsRepository.loadReportDataset` / `loadReportFilterOptions`)。
  - `isIn` 每 500 個分段查,避開 SQLite 變數上限。
  - 口徑刻意跟 `totalsByCategoryWithHierarchy` 一模一樣(見下方「統計口徑」)。
- **聚合**:`lib/services/report/report_aggregator.dart`,純函式、不依賴 Riverpod 或 Drift。
- **Providers**:`lib/providers/report_providers.dart`。
  - `reportDatasetProvider`:family,key 是帳本 + 區間 + 篩選,watch `statsRefreshProvider`。
  - `reportStoreProvider`:已儲存的報表清單。
  - `reportOffsetProvider`:各報表目前切到第幾期。
- **UI**:`lib/pages/statistics/`(`lib/pages/report/` 已經給年度報告用了)。
  - `statistics_report_list_page.dart`:清單
  - `statistics_report_page.dart`:報表頁
  - `report_edit_page.dart`:新增/編輯
  - `report_filter_page.dart`:篩選總覽與勾選頁
  - `report_transactions_page.dart`:下鑽列表
  - `tabs/`:各分頁

## 統計口徑(跟舊洞察頁、首頁一致)

- 排除 `excludeFromStats`。金額用 `nativeAmount ?? amount`。
- 拆帳明細金額乘上 `nativeAmount / amount` 折算比例。`hasSplits=true` 但查不到明細的交易不貢獻金額,跟 `totalsByCategory` 相同。
- 轉帳和餘額調整不計入收支,只出現在「明細」列表和「帳戶/帳戶分組」的轉入/轉出。
- **退款沖銷**:退款單記成反方向的負值,扣回原交易的分類,跟 Cloud 同口徑。細節見 [2026-09-25-refund-netting.md](2026-09-25-refund-netting.md)。
- 統計時間用 `happenedAt`,不看 `deferredPostingAt`,跟既有統計一致。
- 測試 `test/repositories/report_data_loader_test.dart` 的「對帳」案例鎖定:新引擎的分類階層與收支總額必須等於舊的 `totalsByCategoryWithHierarchy` / `totalsInRange`。

## 各分頁的欄位對應

- 名稱:記帳表單的「名稱」欄,實際存在 `Transaction.note` 裡(`transaction_entry_form.dart`)。
- 商家:`merchant`。
- 專案:`projectSyncId`。
- 對象:欠款的 `counterpartyName`。
  - 交易透過 `debtSyncId` 或欠款的 `originTransactionSyncId` 對到欠款。
  - 同名的多筆欠款併成同一列。
- 帳戶分組:子卡的 `parentAccountId` 指向的 `account_group` 主帳戶。沒有掛在任何主帳戶下的帳戶歸「未分組」。
- 標籤是多值的:一筆交易有兩個標籤,兩列都會算到,所以各列加總可能大於總額,頁面上有註腳說明。

## 行為變化

- **報表翻期不再牽動首頁月份。** 舊洞察頁直接寫 `selectedMonthProvider`,那是首頁共用的狀態;報表改用自己的 `reportOffsetProvider`。
- **「類別」分頁**
  - 支出/收入/結餘改成分頁內的膠囊切換,拿掉舊的「選擇視角」對話框和左右滑切換類型。
  - 月/年/全部的切換由報表期間取代。
  - 趨勢圖左右滑仍然是上一期/下一期。
- **分頁切換:** 報表頁的 `TabBarView` 關掉左右滑,只能點上方 TabBar 換分頁(同 MOZE),讓趨勢圖的滑動手勢不會打架。
- **父分類查不到的二級分類:** 舊的 `_aggregateTopLevelCategories` 會把它們直接丟掉(總額少算),現在改成自己成為一列一級分類。
- **下鑽:** 報表有篩選時,點分類/圓餅改開 `ReportTransactionsPage`(會套用篩選);沒篩選時仍然開原本的 `CategoryDetailPage`。為此在 `CategoryPieChart` / `CategoryRankRow` 加了可選的 `periodLabel`、`onOpenDetail`。

## 其他改到的既有元件

- `LineChart`:加了可選的 `onPointTap(index)`,給「明細」分頁點圖捲動列表用。
- `TransactionList`:加了 `ascending`(日期由舊到新)和 `jumpToDate()`。
- 外幣補折算橫幅和折算腳注從舊頁面搬到 `lib/widgets/statistics/foreign_currency_stats_banner.dart`。
- 刪除 `lib/pages/main/analytics_page.dart`。`analyticsHeaderHintDismissedProvider` 等提示 provider 還留著,「類別」分頁的趨勢圖提示仍在使用 chart hint。

## 儲存

- 報表清單存在 SharedPreferences,key 是 `statistics_reports_v1`,格式 `{"version":1,"reports":[…]}`。
  - 首次載入時植入內建的每月/每週/每年三份。
  - 使用者全部刪光後不會再自動植入,要按「恢復預設報表」。
  - JSON 損毀時退回內建三份,但不覆寫原資料。
- **刻意不做雲端同步,也不開 Drift 表。** 這樣不需要 v63 migration,也不會多一個 Cloud 不認得的 ChangeTracker 實體。
  - 以後要同步的話,可以整包 JSON 塞進 profile 的 appearance/AI 設定 blob(Cloud 端不驗 schema)。篩選 key 已經是 syncId,不需要轉換。
- 報表一律跟隨「目前帳本」,沒有綁定特定帳本。帳戶/分類/標籤是 user-global,換帳本仍然有效;專案/欠款是 ledger-scoped,換帳本後對不到就自然不命中。

## 刻意不做(範圍外)

- MOZE 的回饋、事件類型、交易方式篩選。
- 報表 CSV 匯出。
- 自訂每份報表要顯示哪些分頁。
- iPad 並排版面。
- Web 端比較報表(MOZE comparison report)在 BeeCount-Cloud repo 做:入口是 Web 頂部導覽「比較報表」,設計與手動測試步驟見 `../BeeCount-Cloud/docs/COMPARISON_MATRIX_SD.md`。
