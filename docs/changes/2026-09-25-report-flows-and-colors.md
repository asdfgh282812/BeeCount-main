# 統計報表:支出/收入/轉帳/回饋金切換、下鑽只列同類、收支金額照設定上色

## 入口

- 底部第 4 個分頁「報表」→ 任一報表。
- 帳戶、專案、帳戶分組、名稱、商家、標籤和對象、排行這幾個分頁的上方切換,從「支出/收入」改成「支出/收入/轉帳/回饋金」四選一。
- 點任一列會開下鑽列表,標題下方會標出目前是哪一類(例:「2026-09 · 支出」)。
- 收支顏色設定在「我的 → 外觀設定 → 收支顏色」(`incomeExpenseColorSchemeProvider`,預設收入紅、支出綠)。

## 1. 四種切換

聚合邏輯在 `lib/services/report/report_aggregator.dart`,切換項目定義在 `ReportFlow`。

- **支出 / 收入**:跟之前一樣,包含退款沖銷(見 [2026-09-25-refund-netting.md](2026-09-25-refund-netting.md))。
- **轉帳**:只算 `type == 'transfer'`,不含餘額調整。
  - 帳戶和帳戶分組的轉帳金額 = 轉入 + 轉出,同一筆轉帳會同時出現在兩個帳戶。所以這兩個維度的佔比分母用各列合計,不用轉帳總額,頁面下方有註腳說明。
  - 其他維度(專案、名稱、商家…)按轉帳交易自己的欄位歸屬。
- **回饋金**:信用卡回饋規則的**估算值**,跟交易詳情卡、回饋明細頁同一份算法。
  - 會按帳單週期累積扣減 `capAmount`,已退款的部分不算。
  - 實作:`lib/providers/card_reward_rule_providers.dart::estimateCardRewardsForTransactions`,同一條規則、同一期帳單只查一次。報表端透過 `reportRewardsProvider` 使用,只有切到回饋金才會計算。
  - 一筆交易的回饋金按 leg 金額比例分到各維度(`ReportAggregator.rewardShare`)。拆帳交易被篩選時,只算命中的明細那一部分。
  - 沒有用 Cloud 實際入帳的回饋收入交易來算,原因有兩個:App 本地沒有 `rewardSourceTxId`,對不回原消費;而且手動結算的規則根本沒有入帳交易。

## 2. 下鑽只列同一類

- **舊行為**:`dimensionPredicate` 只看維度值,不看收支類型。在「支出」點專案,列表會混進該專案的收入和轉帳。
- **新行為**:`dimensionPredicate(d, key, flow:)` 同時比對 flow。`ReportTransactionsPage` 新增 `flow` 參數,表頭只顯示該類的筆數和合計。
- 類別分頁有篩選時的下鑽(`openReportCategoryDrilldown`)本來就有比對類型,這次只補傳 `flow`,讓表頭正確。
- 支出下鑽會列出扣在該支出上的退款單。退款單在清單裡仍顯示為收入,但金額已從合計扣掉,表頭合計跟列上的金額一致。

## 3. 收支金額上色

新增 `lib/widgets/statistics/report_colors.dart`:
- `reportFlowColor`:收入和回饋金用收入色,支出用支出色,轉帳用 `BeeTokens.chartTransfer`。
- `reportBalanceColor`:結餘 ≥ 0 用收入色,< 0 用支出色。
- 底層都是 `BeeTokens.incomeColor/expenseColor`。

套用範圍:

- **統計報表**
  - 清單卡片的收/支/結餘。
  - 總覽:摘要卡、前 5 類別、TOP 3、商家。
  - 類別分頁:排行列、圓餅中間總額、趨勢摘要。
  - 排行、各維度分頁的總額和每列金額、下鑽表頭。
  - 為此 `ShareBarRow`、`ReportTxRow`、`CategoryRankRow` 新增 `amountColor` 參數,`CategoryPieChart` 新增 `centerColor` 參數。
- **`AnalyticsSummary`**:原本預設寫死 `Colors.green/red`(收入綠),改成跟隨設定。
- **交易清單每日小計**(`DaySectionHeader`):原本整行灰色,改成標籤灰、金額上色。
- **年度報告頁、年度報告海報、月/年/帳本分享海報**:原本寫死「收入綠、支出紅」,跟預設的「收入紅」相反。
  - 改成依設定對調。海報是 StatelessWidget,由呼叫端傳 `incomeIsRed`。
  - 保留原本較飽和的紅綠色值,因為它們畫在主題色或白色背景上。
  - 「最高/最低支出月份」兩個都是支出金額,都用支出色,最低月份的長條用淡一點的支出色區分。
  - 「比上月支出增加/減少」這種好壞指標沒有改。
- **專案詳情頁的收支統計條**:原本用固定的 `chartIncome/chartExpense`,改成跟隨設定。

## 4. 維度列的圖標

- **帳戶、帳戶分組**:改用資產頁的帳戶頭像(自訂 logo,沒有就顯示類型圖標)。帳戶分組的 key 就是主帳戶的 syncId,所以顯示主帳戶自己的頭像。「未分組」和已刪除的帳戶用中性的資料夾或錢包圖標。
- **專案**:改用專案自己的圖標(`ThemedIconGlyph`,emoji 或圖示),跟專案頁一致。「(無)」用旗子圖標。
- **名稱、商家、標籤、對象**:本來就只是文字,不加圖標。`ShareBarRow.leading` 改成可為 null。
- 資產頁 `accounts_page.dart` 與帳戶選擇器 `account_card_picker.dart` 原本各有一份相同的私有頭像元件,抽成共用的 `lib/widgets/biz/account_avatar.dart`(`AccountAvatarImage` + `AccountAvatar`),三處共用。

## 5. 明細分頁的列表跟著上方切換

- **舊行為**:「明細」分頁的「支出/收入/結餘」只切換上方趨勢圖,下方列表永遠列出期間內全部記錄。
- **新行為**(`lib/pages/statistics/tabs/details_tab.dart`):
  - 支出、收入:只列該類的 leg,用 `ReportAggregator.transactions((e) => e.type == _type)` 篩選。扣在支出上的退款單也會列出,跟每日小計、下鑽的沖銷口徑一致。
  - 結餘:列出全部記錄,包含轉帳。這是轉帳在明細分頁唯一出現的地方。

## 6. 期間選單只列到第一筆交易

- **舊行為**:點報表頁首的期間標籤,選單固定往前列 36 期。沒記帳的年份(例如 2023)也列出來,點進去全是空的。「上一期」箭頭也能一直往前翻。
- **新行為**(`lib/pages/statistics/statistics_report_page.dart`):
  - 選單從當期往前列到**目前帳本第一筆交易**所在的那一期。沒有任何交易就只列當期。
  - 「上一期」箭頭和類別趨勢圖的左右滑,到第一筆交易那一期就停住。
  - 第一筆交易由新的 `reportFirstTxDateProvider(ledgerId)` 查詢(`lib/providers/report_providers.dart`,沿用 `getFirstTransactionByLedger`)。它不看報表篩選,也不看 `excludeFromStats`,只看帳本本身什麼時候開始有資料。
  - 目前停在更早的期間時(例如第一筆交易後來被刪了),選單仍會列到那一期,打勾才對得上。
  - 選單最多 520 期,防止第一筆交易很早又是週報表時列出上千項。

## 範圍外

- 類別分頁維持「支出/收入/結餘」,沒有加轉帳和回饋金:轉帳通常沒有分類,依分類看回饋金的需求也還沒提出。
- 總覽分頁沒有加轉帳和回饋金的摘要。
- 報表篩選仍然沒有「回饋」條件(MOZE 有),見 [2026-09-25-statistics-report.md](2026-09-25-statistics-report.md)。

## 測試

- `test/providers/report_flows_test.dart`:下鑽依 flow 過濾、帳戶轉帳 = 轉入 + 轉出、回饋金套用上限並分到各維度與排行。
- `test/widgets/statistics_report_page_test.dart`:四種切換都能渲染;支出下鑽的表頭不含收入;明細分頁切換支出/收入/結餘時,傳給 `TransactionList` 的交易跟著變;期間選單只列到第一筆交易那一期,到了那一期「上一期」會停用。
