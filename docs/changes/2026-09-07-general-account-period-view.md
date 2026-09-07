# 一般帳戶明細頁:日期區間 + moze 風格改版

## 為什麼

信用卡(含 `account_group` 合併帳單主帳戶)帳戶詳情頁的「交易明細」tab 已經有帳單週期選擇器(`< 2026/09/05 – 2026/10/04 >`,可翻頁/挑歷史帳期),但其它帳戶類型(現金/銀行卡/房產/車輛/投資/保險/公積金/貸款)完全沒有日期區間概念,統計是全生命週期,清單也沒有分頁以外的篩選。使用者希望這些帳戶也有一樣的區間選擇器,但**不要**套用信用卡的帳單日邏輯——而是綁定帳本既有的 `Ledgers.monthStartDay`(跟「專案」功能同一套週期算法),並把版面改成類似 moze app 的風格(摘要橫條 + 趨勢折線圖 + 支出/收入/轉出/轉入四分頁)。

## 改了什麼

### 日期區間(比照專案,不是信用卡帳單日)

- 新增 `lib/providers/account_period_providers.dart`:
  - `accountPeriodOffsetProvider`(`Map<accountId, offset>`)+ `accountPeriodRange(offset, monthStartDay)`,邏輯完全比照 `project_providers.dart` 的 `_projectPeriodAnchor`(monthly 分支)——用「月份標籤位移」而非直接對日期做月份加減,避免月底邊界問題。
  - `inclusiveEnd(range)`:`month_range.dart` 回傳的是半開區間 `[start, end)`,既有 repository 方法(`getAccountTransactions`/`getAccountDailyBalances`/新的 `getAccountPeriodSummary`)的 `endDate` 語意都是「含端點整個自然日」,兩者不能直接混用,呼叫前要換算。
  - `accountPeriodSummaryProvider`/`accountBalanceTrendProvider`:`FutureProvider.family.autoDispose`,同時 watch `syncGenerationProvider`(遠端 pull 後重算)跟 `statsRefreshProvider`(`TransactionEditorPage`/快速操作等存檔後會 bump 這顆 tick,兩個 provider 因此不用每個呼叫端各自手動 invalidate)。
- UI 直接複用既有的 `PeriodRangeSelector` + `showPeriodRangeListPicker(periodType: 'monthly', ...)`(`period_range_selector.dart`),這兩個元件本來就是給專案頁的 monthly 週期用,一般帳戶頁不用改它們一行程式碼。
- **沒有新增資料庫欄位**——`Ledgers.monthStartDay` 早就存在(專案/預算/統計都在用),這裡只是多一個消費端。

### 支出/收入語意變更(重要):四分頁互斥,不再疊加轉帳

舊版 `AccountRepository.getAccountTransactions` 的 `flow` 只有兩個值,且各自疊加轉帳:`'expense'` = 支出+轉出、`'income'` = 收入+轉入。現在改成四值互斥:`'expense'`(純支出)/`'income'`(純收入)/`'transfer_out'`(這個帳戶轉出)/`'transfer_in'`(這個帳戶轉入),同一筆轉帳只會出現在轉出或轉入分頁,不會同時出現在支出/收入分頁。

- `lib/data/repositories/account_repository.dart`:`getAccountTransactions` 新增 `ascending` 參數(排序方向,給清單「排序」圖示用);新增 `getAccountPeriodSummary(accountId, {startDate, endDate})` 回傳 `AccountPeriodSummary`(純支出/純收入/轉出/轉入各自的加總金額+筆數),口徑跟既有 `getAccountExpense`/`getAccountIncome` 一致(排除 `excludeFromStats`、排除共享帳本)。
- `lib/data/repositories/local/local_account_repository.dart`:`getAccountTransactions` 的 SQL `flow` switch 改成上述四值;新增 `getAccountPeriodSummary` 實作。
- `lib/data/repositories/local/local_repository.dart`:同步更新 facade 委派方法(這個類別是手動逐一委派給 `_accountRepo`,不是靠 `implements` 自動繼承,加新介面方法一定要記得在這裡也補一份)。
- **這個語意變更只影響一般帳戶明細頁**(唯一呼叫端)——信用卡分支的「交易明細」清單用的是另一個方法 `getAccountStatementTransactions`,完全不受影響。

### moze 風格版面(僅一般帳戶,信用卡/`account_group` 不變)

- 新增 `lib/pages/account/general_account_period_view.dart`(`GeneralAccountPeriodView`):日期區間列 → 摘要橫條(只列該區間有資料的類別:支出/收入/轉出/轉入,金額用色條長度做比例視覺化,一定會顯示「總計」淨額列,重用 `projectDetailNetTotalLabel` 這個既有 l10n key)→ 餘額趨勢折線圖(**發現並重新啟用了一個先前已經寫好但從沒被用過的 `BalanceTrendChart` widget**,直接接上既有的 `AccountRepository.getAccountDailyBalances`,兩邊都不用改)→ 支出/收入/轉出/轉入四分頁 → 依日期排列的交易清單(標題 + 排序圖示 + 新增圖示,比照信用卡帳單彙總卡片既有的「一般記錄」區塊樣式)。
- 刻意**不做**獨立的篩選圖示——四分頁本身已經是類型篩選,再加一個篩選圖示會功能重複(YAGNI)。
- 刻意**不做**類別圓餅圖——moze 參考畫面沒有這塊,拿掉後 `accountCategoryStatsProvider`/`AccountCategoryPieChart` 整個沒有其它呼叫端,一併刪除(`account_category_pie_chart.dart` 整個檔案刪掉)。
- `account_detail_page.dart` 原本的一般帳戶分支(`_buildStatsCard`/`_buildOverviewCard` 的統計卡+`_buildDetailChartSection`+`_buildTransactionList`/`_buildTransactionListBody`)已無其它呼叫端,一併刪除,改成直接 `return GeneralAccountPeriodView(...)`。`_TransactionTile` 改名成公開的 `TransactionTile`(兩個檔案共用同一份交易列項渲染邏輯,不重寫第二份)。
- `accountTransactionsPaginatedProvider`(既有的分頁交易 provider,原本只給一般帳戶清單用)家族 key 新增 `startDate`/`endDate`/`ascending` 三個欄位,繼續給新版一般帳戶頁用;信用卡分支本來就不用這個 provider,不受影響。

## 刻意排出範圍外

- 適用範圍只有「非信用卡」帳戶類型;信用卡/`account_group` 維持原本的帳單週期版面(使用者需求本來就是「跟信用卡一樣的區間選擇器」,不是「跟信用卡一樣的版面」)。
- 清單「排序」圖示只有新→舊/舊→新兩個選項(對齐既有 `reconciliationMenuSortNewest`/`reconciliationMenuSortOldest` 文案),沒有依金額排序。
- 沒有處理跨帳本/多幣別加總——一般帳戶頁本來就是單一帳戶自己幣別的視角,跟既有頁面行為一致。

## 測試

新增 `test/repositories/account_period_summary_test.dart`:純支出/純收入/轉出/轉入互斥不疊加、`excludeFromStats` 排除、`flow` 四值篩選、`ascending` 排序方向。既有 `account_transactions_aggregate_test.dart`/`account_statement_transactions_test.dart` 全數通過(語意變更沒有破壞既有測試,因為那兩份測試涵蓋的情境剛好在新舊語意下結果一致)。

`flutter analyze`(全專案)無新增 error;`flutter test`(全專案)僅有一個跟本次改動完全無關、在乾淨 checkout 上一樣會失敗的既有 `calendar_month_jump_test.dart` 失敗案例。

視覺驗證受限於本機環境:iOS Simulator 工具回報 `Xcode is installed but not selected`,需要使用者自行執行 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`(需要密碼,無法代為執行);Flutter Web 目標本身就編譯不過(`dart:ffi`/`record_web` 套件與 web 平台不相容,是既有、與本次改動無關的專案限制)。因此這次沒有實機截圖驗證,僅有 repository 層單元測試 + `flutter analyze` 把關。
