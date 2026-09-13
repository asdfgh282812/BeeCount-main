# 交易幣別跟帳戶幣別脫鉤

## 問題

「建立交易」表單(`lib/widgets/biz/transaction_entry_form.dart`)裡,選定帳戶後就無法再手動改選別的幣別:例如選了台幣帳戶,點「幣別」欄位改選日圓,存檔或重新打開帳戶選單後幣別又跳回台幣。反過來選日圓帳戶也選不了台幣。這跟 BeeCount Cloud 網頁端的行為不一致——網頁端任何帳戶都能記一筆任意幣別的交易,由使用者輸入該幣別金額 + 匯率,自動折算回帳本本位幣。

## 根因

`_txCurrency()`(原本邏輯)只要 `_selectedAccountId != null`,就無條件優先回傳 `_selectedAccountCurrency`(帳戶自身幣種),使用者在「幣別」欄位手動選的 `_pickedCurrency` 只在帳戶沒有幣種時才會被採用。`_pickCurrency()` 為了繞開這個優先序,選完幣別後會把整個帳戶選擇清空(`_selectedAccountId = null` 等),讓 `_txCurrency()` 落回 `_pickedCurrency` 分支——但這只是把「幣別選不了」換成「選完幣別帳戶被清空」,使用者只要重新選(哪怕選回同一個)帳戶,`_loadSelectedAccount` 又會用該帳戶的幣種蓋掉剛選好的幣別,回到原本的 bug。

編輯既有交易時也有同樣的問題:`_pickedCurrency` 初始化自 `widget.initialCurrencyCode`(該筆交易實際存的 currencyCode),但沒有標記「這是使用者/資料明確指定的幣別」,一旦 `_loadSelectedAccount` 非同步載入完帳戶幣種,`_txCurrency()` 一樣會蓋掉它——編輯一筆「台幣帳戶記的日圓交易」會被悄悄改回台幣。

## 修正

`lib/widgets/biz/transaction_entry_form.dart`:

- 新增 `_currencyManuallySet` 旗標,語意比照既有的 `_accountManuallySet`:使用者透過「幣別」欄位主動選過幣別、或編輯模式下交易本身就帶著 `initialCurrencyCode`,都視為「明確指定」。
- `_txCurrency()` 優先序改為:`_currencyManuallySet` 為真時一律用 `_pickedCurrency`;否則才依序落回帳戶自身幣種 → 使用者曾選過的幣別 → 帳本本位幣。帳戶幣種不再無條件蓋過明確指定的幣別。
- `_pickCurrency()` 不再清空帳戶選擇(`_selectedAccountId`/`_selectedAccountCurrency`/`_selectedAccountName`/`_selectedAccountType`)——選幣別跟選帳戶是兩個獨立操作,互不影響。也不再把「選到等於帳本本位幣」特殊處理成 `null`(視為「未指定」),而是照樣存成明確值,避免「日圓帳戶手動改回本位幣」這個方向的同款 bug。
- 幣別選擇 sheet 的 `selected` 高亮改用 `_txCurrency()`(目前實際生效的幣別),而不是先前的 `_pickedCurrency ?? base`(帳戶帶起來的幣別不會反映在高亮上)。

## 沒有改變的行為

- 新增交易、尚未手動碰過「幣別」欄位時,選一個外幣帳戶(例如日圓帳戶),交易幣別依然自動跟著帳戶幣種走(既有測試:`選外幣帳戶後換算預覽隨時可點,編輯換算金額後 nativeAmount 反映新結果`)——這條路徑走的是 `_currencyManuallySet == false` 分支,行為不變。
- 匯率輸入/線上匯率折算 UI(`_buildCurrencySection`/`_editRate`)本來就只依賴 `_txCurrency()` vs 帳本本位幣,沒有额外改動。

## 測試

`test/widgets/transaction_entry_form_test.dart` 新增一個回歸測試:選一個本位幣帳戶(CNY)後,手動把幣別改成 JPY,驗證帳戶列仍顯示原帳戶名稱(沒被清空)、換算預覽正確出現、送出後 `currencyCode == 'JPY'` 且 `accountId` 還是原帳戶。同時給 `_buildCurrencyChip` 加上 `Key('currencyChip')` 供測試點擊。
