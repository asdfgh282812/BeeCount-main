# 跨幣別轉帳(子專案 C)

設計文件:[docs/superpowers/specs/2026-08-29-cross-currency-transfers-design.md](../superpowers/specs/2026-08-29-cross-currency-transfers-design.md)。
延續子專案 A([2026-08-28-cross-currency-account-picker.md](./2026-08-28-cross-currency-account-picker.md))。

## 背景

App 端追平 BeeCount Cloud 已上線的 `to_amount` 協議(`0044_tx_transfer_to_amount.py`),
讓轉帳表單支援轉出/轉入帳戶幣別不同的組合,不再是「只能同幣別」的死限制。

## 改了什麼

### 1. Schema — `Transactions.toAmount`([lib/data/db.dart](../../lib/data/db.dart)）

- 新增 `toAmount REAL NULL`,語意對齊 Cloud 的 `to_amount`:只有
  `type == 'transfer'` 且轉出/轉入帳戶幣別不同才非 null;同幣別轉帳一律維持
  null,讓 `toAmount ?? amount` 這個 COALESCE 慣例同時是「轉入金額」跟「是否
  跨幣別」的單一事實來源。
- `schemaVersion` 44 → 45,`_addColumnIfMissing` 純加欄位遷移,無需回填
  (跟 Cloud 遷移的決定一致)。

### 2. Repository 層 — `toAmount` 參數貫穿三層

- `lib/data/repositories/transaction_repository.dart`(介面)、
  `lib/data/repositories/local/local_transaction_repository.dart`(子倉實作)、
  `lib/data/repositories/local/local_repository.dart`(聚合層 wrapper)。
- `addTransaction` 用普通 `double? toAmount`(insert 沒有「既有值」需要保留)。
- `updateTransaction` / `RecurringRuleRepository.updateRuleAndFuture` 用
  `dynamic toAmount`,比照既有 `accountId` 參數的寫法:不傳(`null`)= 不動
  既有值;顯式傳 `d.Value<double?>(null)` = 清空;傳 `d.Value(x)` 或裸
  `double` = 寫入新值。這個區分是必要的——同幣別轉帳送出時要能把「使用者
  曾經選過跨幣別帳戶又改回同幣別」殘留的舊 `toAmount` 顯式清空,而不只是
  「不覆蓋」。
- `updateRuleAndFuture` 批次更新「這筆與未來」時,同一個 `toAmount` 套用到
  每一列(不做比例換算,跟其餘欄位的批次套用方式一致)。

### 3. 轉帳表單 UI — [lib/widgets/transaction/transfer_form.dart](../../lib/widgets/transaction/transfer_form.dart)

- `_pickAccount()` 加 `allowAllCurrencies: true`(沿用子專案 A 的
  `AccountCardPicker` 參數),帳戶選擇器不再依幣別過濾候選清單。
- 移除舊的「跨幣種轉賬守衛」(擋掉跨幣別 + 編輯模式存量放行的特例邏輯),
  改成金額驗證:`fromCurrency != toCurrency` 時必須有一個 > 0 的轉入金額,
  否則跳 `transferToAmountRequiredError` 提示。
- 新增內嵌區塊(`_buildCrossCurrencySection`,只在跨幣別時顯示):
  - 轉入金額輸入框(`Key('transferToAmountField')`,方便 widget test 定位)。
  - 唯讀匯率展示列 `1 {from} = {rate} {to}`,隨轉入金額變動即時重算(不是
    子專案 A 那種可反向編輯匯率的對話框——這裡的交換圖示是「互換轉出/轉入
    帳戶」用途,維持跟參考畫面一致的簡化互動)。
  - 「採用線上匯率」開關(沿用 `txUseOnlineRateLabel`):開啟時欄位唯讀,
    跟 `effectiveRatesForLedgerProvider` + `computeNativeAmount` 走(精簡版,
    沒有複製 `transaction_entry_form.dart` 那套 `_currentRate`/
    `_maybeAutoFetchRate`,直接用 provider + 純函式重新組);關閉後可手動
    編輯,值即為最終 `toAmount`。
  - 已知簡化:`effectiveRatesForLedgerProvider` 的 base 固定是「目前這本帳的
    本位幣」,不是轉入帳戶的幣別——多數情境下兩者相同(轉帳常見場景是換回
    本位幣帳戶),但轉出/轉入都不是本位幣的組合,線上匯率預覽可能不準,使用
    者可以關閉開關手動修正。設計文件已明確接受這個 MVP 範圍。
- 換帳戶(`_pickAccount`)或互換方向(`_swapAccounts`)都會重置轉入金額狀態
  (`_toAmountManuallySet` / `_toAmountCtrl` / 抓取狀態),避免帶著上一組帳戶
  對的匯率/金額殘留到新的帳戶對。
- `TransferForm` 新增 `initialToAmount` 參數,編輯既有跨幣別轉帳時回填(視為
  「手動」狀態,不會被線上匯率覆蓋,跟 `transaction_entry_form.dart` 的
  `initialNativeAmount` → `_rateManuallySet = true` 同款寫法)。串接路徑:
  `TransactionEditorPage.initialToAmount` →
  `TransactionEditUtils.editTransaction`/`copyTransaction` 傳
  `transaction.toAmount` → `ai_chat_page.dart` 的編輯入口比照補上。

### 4. 同步序列化/解析

- `lib/cloud/sync/entity_serializer.dart`:`serializeTransaction` 新增
  `if (tx.toAmount != null) 'toAmount': tx.toAmount,`(有值才發,跟
  `nativeAmount` 同款),wire key 對齊 Cloud `sync_applier.py` 的
  `("toAmount", "to_amount")` merge spec。
- `lib/cloud/sync/sync_engine_apply.dart`:`_applyTransactionChange` 鏡像
  `nativeAmount` 的「缺鍵不覆蓋」判斷,但 fallback 算法**不是**沿用
  `nativeAmount` 既有的「缺鍵時退化 1:1」邏輯,而是實作了真正的等比縮放
  (`_rescaleAmount`):payload 帶新 `amount` 但沒帶 `toAmount`、且本地既有列
  本身是 `type == 'transfer'` 且已有 `toAmount` 快照時,按
  `舊 toAmount / 舊 amount * 新 amount` 重算。這個公式必須跟 Cloud
  `snapshot_mutator.rescale_native_amount`(經 `sync_applier.py::
  _sync_to_amount_after_merge` 呼叫)完全一致,兩邊各自維護但不能各自發明
  算法,否則多端同步後金額會兜不起來——已用
  `test/sync/transaction_to_amount_apply_test.dart` 驗證公式對齊。
  為了避免 `nativeAmount`/`toAmount` 各自查一次舊行,把原本 `nativeValue`
  區塊裡的 `SELECT` 提出來共用一次。

### 5. 餘額計算 — [lib/data/repositories/local/local_account_repository.dart](../../lib/data/repositories/local/local_account_repository.dart)

6 個轉入腳(`toAccountId == accountId` 分支)一律從 `t.amount` 改成
`t.toAmount ?? t.amount`:`getAccountBalance`、`getAccountGlobalBalance`、
`getAccountBalanceInLedger`、`getAccountIncome`、`getAccountDailyBalances`
(range 前累加 + 逐日累加兩處)。轉出腳(`accountId == accountId` 分支)完全
不動——轉出永遠是自己帳戶幣別的 `amount`。

這是本次變更風險最高的部分(直接影響餘額正確性),驗證方式:
`test/repositories/cross_currency_transfer_balance_test.dart` 對 6 個方法
都各寫了一組「`toAmount` 非 null → 轉入按 `toAmount` 計」+「`toAmount` 為
null(同幣別/舊資料)→ 兩邊都按 `amount` 計,既有行為完全不變」的對照測試。

## 範圍外(明確不做,跟設計文件一致)

- 定期轉帳規則模板本身(`RecurringTransactions` 表)不支援存
  `toAmount`/`toCurrencyCode`——子專案 B 才處理。`transfer_form.dart` 的
  「這筆與未來」分支只更新已生成的 `Transactions` 列,不碰規則模板。
- 拆帳、債務/信用卡還款不受影響(沿用既有決策)。
- 交易列表/對帳單/CSV 匯出等顯示層:本次只保證資料正確寫入 + 餘額計算正確,
  顯示轉入金額的周邊畫面留待個別需要時再調整。

## 上線後修正(實機測試發現)

實機測試時發現兩個問題,一併修正:

- **轉入金額欄位完全無法輸入**:`_toAmountCtrl` 這個 `TextField` 原本沒有掛
  自己的 `FocusNode`,`_textFieldFocused`(控制底部小算盤要不要收起讓系統
  鍵盤出現)只認名稱/商家欄位。使用者點進轉入金額欄位後,底部小算盤沒有收
  起,數字鍵打的其實是「轉出金額」而不是這個欄位,等於完全打不進去。修正:
  新增 `_toAmountFocus`,比照名稱/商家欄位掛進 `_onTextFieldFocusChange`
  監聽 + `_textFieldFocused` 判斷。
- **幣別代碼只有點進欄位後才看得到**:原本用 `InputDecoration.suffixText`
  顯示轉入幣別,但欄位在「採用線上匯率」模式下是 `enabled: false`,disabled
  時 suffix 文字顏色被壓暗,在深色主題下幾乎融進底色,看起來像沒有幣別字
  樣。改成獨立於 `TextField` 之外、恆常顯示的幣別徽章(flag + code chip,
  跟頂部 `_buildCurrencyBadge`、參考畫面的視覺語言一致),不受欄位
  enabled/disabled 狀態影響。
- **全域計算機鍵盤(`AmountCalculatorKeypad`,收支/轉帳表單共用)按鍵稍微
  縮小**:每顆按鍵高度 56→46、外距 6→4、字級/圖示等比縮小,騰出畫面空間。

`test/widgets/transfer_form_cross_currency_test.dart` 補上「先關閉採用線上
匯率開關手動輸入 → 收起鍵盤 → 送出」的完整流程,直接覆蓋了上述輸入 bug
(若 `FocusNode` 沒接對,`enterText` 後底部小算盤的送出鍵會被誤判成消失,
測試本身就會炸掉)。

## 上線後修正 2 — 線上匯率換算方向錯誤(實機第二輪回報)

實機測試「轉出帳戶是帳本本位幣、轉入帳戶是外幣」這個方向(例如帳本本位幣是
TWD,轉出帳戶也是 TWD,轉入帳戶是 JPY——這其實是最常見的轉帳方向)時,不管
「採用線上匯率」開關開或關,都顯示查無匯率、無法自動換算。

根因:`effectiveRatesForLedgerProvider` 回傳的 `rates` 是「以帳本本位幣為
base」的一組匯率,key 是相對本位幣的**其他**幣別(例如本位幣 TWD 時,
`rates['JPY']` = 「1 JPY = ? TWD」),**不包含本位幣自己**。原本直接呼叫
`computeNativeAmount(accountCurrency: fromCurrency, ledgerBase: toCurrency,
rates)`,只有在 `toCurrency == 帳本本位幣` 時才查得到 `rates[fromCurrency]`;
一旦反過來、`fromCurrency` 才是本位幣,`rates[fromCurrency]` 永遠查不到,
於是這個(其實更常見的)方向永遠顯示「查無匯率」。

修正:新增 `_convertCrossCurrency`,先把 `fromCurrency` 換算到帳本本位幣
(這一段繼續複用 `computeNativeAmount` 既有邏輯),再從本位幣換到
`toCurrency`(兩者都不是本位幣時就是完整的三角換算,經過本位幣中轉)。
`_maybeAutoFetchToRate` 一併修正:改抓「轉出/轉入兩者裡不等於帳本本位幣的
那些」幣別的線上匯率,而不是固定只抓轉出幣別。

`test/widgets/transfer_form_cross_currency_test.dart` 新增一個用
`repo.upsertAutoRates` seed 匯率的回歸測試,驗證 TWD(本位幣)→JPY 這個方向
在預設「採用線上匯率」開啟時能自動算出正確金額並送出(修正前這個測試會直接
斷言失敗,欄位永遠是空字串)。

## 測試

- `test/repositories/cross_currency_transfer_balance_test.dart`(10 個):
  `addTransaction`/`updateTransaction` 的 `toAmount` 參數寫入/保留/清空語意
  + 6 處餘額計算方法的 `toAmount ?? amount` 回歸。
- `test/sync/transaction_to_amount_apply_test.dart`(4 個):insert/update 帶
  鍵直接寫入、缺鍵等比縮放、缺鍵且本地 `toAmount` 本來就是 null 時維持
  null。
- `test/widgets/transfer_form_cross_currency_test.dart`(2 個):跨幣別帳戶對
  → 轉入金額區塊出現 + 送出後 `toAmount` 非 null;同幣別送出 → `toAmount`
  為 null。
- `test/data/sync_pull_errors_schema_test.dart`:更新 schemaVersion 斷言
  44 → 45。
