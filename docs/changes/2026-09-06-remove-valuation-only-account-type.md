# 移除「估值型帳戶」概念,對齊 BeeCount Cloud 的餘額計算公式

## 背景

延續 [2026-09-05-account-balance-reconciliation.md](2026-09-05-account-balance-reconciliation.md) 的追查:使用者發現在 BeeCount Cloud 網頁端對投資帳戶「調整餘額」,交易本身有正常同步到 App,但 App 的帳戶餘額顯示完全沒反應。

追到底發現這不是同步 bug,是 **App 跟 Cloud 對「這 6 種帳戶類型的餘額該怎麼算」根本是兩套公式**:

- **BeeCount Cloud**(`src/services/recurring_materializer.py::compute_account_balance`):對所有帳戶類型一視同仁,公式恆為 `initial_balance + 收入 - 支出 - 轉出 + 轉入 + adjustment`,會加總所有交易。
- **App(修正前)**:`lib/utils/account_type_utils.dart` 定義了 `valuationOnlyTypes = ['real_estate', 'vehicle', 'investment', 'insurance', 'social_fund', 'loan']`,這 6 種類型的 `getAccountBalance()` 直接 early-return `Accounts.initialBalance`,完全忽略交易紀錄。

這個落差不是一次性小 bug,而是持續性架構分裂:只要這 6 種類型的帳戶上記了任何交易(調整餘額、一般收支、轉帳),Cloud 網頁會正確反映,App 永遠不會,而且差距會隨交易累積越差越多。

使用者決定:**App 改成完全比照 Cloud**,這 6 種類型的餘額計算方式跟 cash/bank_card 等一般帳戶完全一樣(initialBalance + 交易加總),範圍是全部 6 種類型(不是只改 investment)。

## 改動範圍

### 核心邏輯(餘額計算)

- `lib/data/repositories/local/local_account_repository.dart`:`getAccountBalance()`、`getAccountGlobalBalance()`、`getAccountDailyBalances()` 三處的「估值型帳戶 early-return `initialBalance`」分支全部刪除,自然落入既有的「加總交易」邏輯——這段邏輯本身對 `account.type` 沒有任何依賴,不需要額外改動。`getAssetCompositionByType`/`getNetWorthBreakdown`/`getNetWorthTrendSeries` 等統計函式都只是迴圈呼叫這幾個底層函式,拿掉 early-return 後全部自動對齊 Cloud 口徑,不需要另外改。

### 帳戶選擇器(記帳/轉帳)

- `lib/widgets/biz/account_picker.dart`、`lib/widgets/biz/account_card_picker.dart`:移除 `isTradableType` 過濾——這是關鍵改動,否則就算餘額改成加總交易,這 6 種類型也永遠沒有交易可加總,等於換湯不換藥。`account_group`(合併帳單主帳戶)仍然排除,理由不變(它是純管理容器,不是真實可入帳的帳戶)。

### 帳戶詳情頁 / 編輯頁 UI

- `lib/pages/account/account_detail_page.dart`:
  - `canAdjustBalance` 簡化成 `account.type != 'account_group'`(不再排除估值型)。
  - 刪除整個「估值卡片」分支(`_buildValuationCard`/`_showUpdateValuationDialog`,共約 190 行),這 6 種類型現在跟一般帳戶一樣走「餘額/收支卡 + 概覽卡 + 圖表 + 分頁交易列表」。
  - 移除不再使用的 `currencies.dart` import。
- `lib/pages/account/account_edit_page.dart`:
  - 「日常/估值」雙 Tab UI **保留**(純粹作為建立帳戶時的分組 UI,不再有功能性差異)——`tradableAccountTypes`/`valuationAccountTypes` 是這個檔案自己獨立維護的清單,跟 `account_type_utils.dart` 被刪除的全域概念脫鉤。
  - 編輯模式「禁止跨大類切換」的限制拿掉(語意不再不同,可以自由切換)。
  - 期初餘額欄位的 label/hint 統一顯示「期初餘額」,不再對這 6 種類型顯示「目前價值/目前欠款」這種暗示「這格就是全部餘額」的文案。

### 帳戶總覽頁

- `lib/pages/account/accounts_page.dart`:滑動快捷操作的「調整餘額」分支,拿掉對估值型的排除,只保留 `account_group` 排除。

### 移除死代碼

- `updateAccountValuation`(`AccountRepository` 介面 + `LocalRepository`/`LocalAccountRepository` 兩層實作)整條方法鏈已刪除——它唯一的呼叫端(帳戶詳情頁的「更新估值」按鈕)已經隨估值卡片一起刪掉,沒有其他呼叫者。`test/repositories/account_valuation_sync_test.dart`(這是同一天稍早為了修 `updateAccountValuation` 漏同步的 bug 而新增的回歸測試)一併刪除。
- l10n:移除 8 個孤兒 key(`valuationCurrentValue`/`valuationCurrentDebt`/`valuationUpdateValue`/`valuationUpdateDebt`/`valuationLastUpdated`/`valuationAccountHint`/`valuationDebtHint`/`balanceAdjustmentNotSupportedForType`),只改 `app_en.arb`/`app_zh_TW.arb`(專案慣例不再維護 `app_zh.arb`/`app_ko.arb`)。

## 沒有改動的地方

- `isLiabilityType`(`credit_card`/`loan` → 負債分類)是完全獨立的概念,跟這次刪除的估值型無關,維持不變。
- `account_group` 的特殊處理(沒有自己的餘額、不能直接入帳)全部保留,這是另一個不相關的原因(合併帳單容器,不是估值語意)。
- Web/Cloud 端沒有任何改動——Cloud 本來就是這次要對齊的目標,不需要動。

## 驗證

- `flutter analyze lib/` 無新增錯誤(既有的 info/warning 均為改動前就存在的無關項目)。
- `flutter test` 全數 1139 個測試通過,沒有因為餘額計算公式改變而破壞既有的淨資產/資產構成/信用卡帳單等測試(這些類型此前很少被拿來實際記帳測試,恰好沒有既有測試斷言依賴「估值型帳戶餘額只等於 initialBalance」這個舊行為)。

## 使用者需要注意的事

這 6 種類型的帳戶如果**過去曾經**在上面記過交易(在舊行為下這些交易對餘額顯示沒有作用,但確實存在於資料庫),升級後這些交易會**第一次**被計入餘額——如果帳戶的 `initialBalance` 是照著「當時的真實總值」設定的,疊加這些舊交易可能會讓餘額看起來對不上,需要使用者自行核對、必要時用「調整餘額」抹平差額。這是這次架構對齊必然的一次性代價,無法在程式邏輯層面避免(因為兩套口徑本來就不是同一件事的兩種算法,而是「該不該計入交易」這個是非題)。
