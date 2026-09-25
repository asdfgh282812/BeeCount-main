# 新安裝預設幣種改為 TWD

## 背景

使用者反映：全新安裝 app、尚未同步過任何資料時，看到的預設幣種是人民幣 (CNY)，希望改成新台幣 (TWD)。

Onboarding 主線流程（`lib/pages/auth/welcome_page.dart`）其實早就把預設選中值改成了 `'TWD'`，但專案裡還散落一批「還沒走過 onboarding / 資料還沒建立完成」時會被打到的兜底值，這些都還是寫死 `'CNY'`：
- Drift schema 的 column default（全新資料庫建表時的 SQL DEFAULT）
- Riverpod provider 的初始 state 與 fallback 鏈最終值
- 「新增帳本」「新增帳戶」彈窗開啟瞬間的預選幣別
- Repository 方法簽章裡 `currency` 參數的預設值

這些兜底值平常大多不會被觸發（因為呼叫端幾乎都會顯式帶入 currency），但仍是「app 端預設值」的一部分，只要有任何路徑漏帶參數，使用者看到的就是 CNY 而非 TWD。這次把它們統一改成 TWD，讓「app 自己給的預設」和「onboarding 選幣頁的預設」一致。

## 改了什麼

- **`lib/data/db.dart`**：`Ledgers.currency`、`Accounts.currency`、`SharedLedgerAccounts.currency` 三個欄位的 `withDefault(const Constant('CNY'))` 改成 `'TWD'`；`ensureSeed()` 的 `currency` 參數預設值同步改。改完執行 `dart run build_runner build` 重新產生 `db.g.dart`。
- **`lib/services/data/seed_service.dart`**：`seedDatabase()` 的 `currency` 參數預設值改為 `'TWD'`。
- **`lib/providers/currency_providers.dart`**：`baseCurrencyProvider` 初始 state、`baseCurrencyInitProvider` 三層 fallback 鏈（① Welcome 選幣 → ② 當前帳本幣種 → ③ 最終兜底）的第③層、`currentLedgerCurrencyProvider` 的空值 fallback，三處都從 `'CNY'` 改為 `'TWD'`。
- **`lib/pages/main/ledgers_page_new.dart`**：「新增帳本」彈窗（`_showLedgerEditorDialog`）在沒有傳 `initialCurrency` 時的預選幣別改為 TWD。
- **`lib/pages/account/account_edit_page.dart`**：「新增帳戶」時（`widget.account == null`）的預選幣別改為 TWD。
- Repository 層方法簽章預設值一併改：`ledger_repository.dart`、`local_ledger_repository.dart`、`account_repository.dart`、`local_account_repository.dart`、`local_repository.dart`（含 `createLedger`/`createAccount` 等方法的 `currency = 'CNY'` 參數，以及 `local_repository.dart` 裡幾處 `ledger?.currency ?? 'CNY'` 的防禦性 fallback）。
- 對應調整了兩個受影響的既有測試（`test/providers/ledger_currency_providers_test.dart`、`test/data/repositories/net_worth_trend_test.dart`）裡原本斷言「兜底值是 CNY」的部分，改為斷言 TWD。

## 刻意沒動的部分

- **舊資料 migration**（`lib/data/db.dart` 裡的 `ALTER TABLE ... DEFAULT 'CNY'`、`COALESCE(..., 'CNY')`，以及 `lib/services/data/migration_service.dart` 的對應邏輯）：這些是「舊帳本/舊帳戶當初就是用 CNY 記的，搬遷時沒有更好資訊來源就補 CNY」的歷史資料相容邏輯，跟「新安裝預設值」無關，不應該因為這次改動牽動，否則會讓舊資料的補值語意失真。
- **散佈在 UI 頁面/widget/同步匯入匯出程式碼裡約 40 處的 `?? 'CNY'` 防禦性 fallback**（例如各交易/預算/專案頁面讀 `currentLedgerProvider...currency ?? 'CNY'`、home screen widget 預設參數、AI 記帳/匯入匯出 payload 缺欄位時的 fallback）：這些是「帳本/帳戶已經存在，但 currency 欄位理論上不該讀不到值卻讀不到」時的保護性程式碼，實務上幾乎不會被觸發（因為 schema 已保證有預設值），且分佈範圍很廣、改動風險/效益比不划算，這次沒有一併處理。如果之後想徹底掃乾淨，可以再拉個獨立任務處理。
- **已經同步下來的真實資料**：這次只改「app 自己給的預設值」，不影響已經存在、真的是從 server/其他裝置同步過來的 CNY 資料——那些是使用者自己或伺服器端的實際設定值，不是「預設值」，不應該被這次改動覆蓋。

## 影響範圍

只影響「全新安裝、尚未建立任何帳本/帳戶、也還沒同步過資料」時看到的預設幣種。已安裝、已有資料的使用者不受影響（既有資料庫不會重跑 `CREATE TABLE`，既有 SharedPreferences 裡已存的 `baseCurrency` 值也不會被這次改動覆寫）。
