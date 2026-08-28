# 跨幣別帳戶選擇 + 雙向換算(子專案 A:一般記帳表單)

設計文件:[docs/superpowers/specs/2026-08-28-cross-currency-account-picker-design.md](../superpowers/specs/2026-08-28-cross-currency-account-picker-design.md)。

範圍只涵蓋一般收支記帳表單(`TransactionEntryForm`),對齊 BeeCount Cloud 網頁版
「帳戶下拉不依幣別過濾」的行為。定期記帳規則(子專案 B)、跨幣別轉帳(子專案 C)
不在本次範圍。

## `lib/widgets/biz/account_card_picker.dart`

- `AccountCardPicker.show()` / `_AccountCardPickerSheet` 新增 `allowAllCurrencies`
  參數,預設 `false`——所有既有呼叫端(`transfer_form.dart`、`debt_entry_form.dart`、
  `credit_card_group_payment_page.dart`、`recurring_rule_editor_page.dart`、
  `voice_billing_helper.dart`、`image_billing_helper.dart`、`ai_chat_page.dart`、
  `pending_account_transactions_page.dart`、`card_reward_rule_editor_page.dart`、
  `debt_repayment_page.dart`)完全不用改,行為不變。
- `_load()` 的過濾條件:`allowAllCurrencies == true` 時略過幣別比對,只保留
  `isTradableType` + 排除 `account_group` 容器 + 排除 `excludeAccountId`。
- `_AccountRow` 副標題新增幣別標籤:帳戶幣別跟「想要的幣別」(`filterCurrency ??
  ledger.currency`,現在只拿來決定要不要顯示標籤,不再拿來過濾)不同時,副標題附加
  幣別代碼(例如「銀行帳戶 · JPY」),方便混合幣別清單裡分辨。這個值透過新的
  `_wantedCurrency` state 從 sheet 一路傳到 `_AccountTypeSection` 再到 `_AccountRow`。

## `lib/widgets/biz/transaction_entry_form.dart`

- `_openAccountPicker()` 呼叫 `AccountCardPicker.show()` 時帶
  `allowAllCurrencies: true`——帳戶選擇器列出帳本下所有幣別的帳戶。
- `_loadDefaultAccount()` 移除 `if (account.currency != ledger.currency) return;`
  這個限制:新增交易時若使用者設定的預設帳戶是外幣帳戶,現在會照常自動選取並觸發
  換算流程,跟手動選外幣帳戶完全一致。
- `_buildCurrencySection` 的換算預覽列:`onTap` 從「只在匯率缺失時可點
  (`rateMissing ? _editRate : null`)」改成「只要是外幣交易就永遠可點
  (`_editRate`)」。
- `_editRate()` 整個重寫:原本是單一「匯率」輸入框的 `AlertDialog`,改成
  `StatefulBuilder` 包的對話框,兩個欄位(換算金額、匯率)+ 一個「採用線上匯率」
  開關:
  - 開關對應 `!_rateManuallySet`,開啟時兩欄位唯讀並顯示線上匯率(獨立於
    `_currentRate()` 現算,因為 `_currentRate()` 在 `_rateManuallySet==true` 時
    回傳的是舊的手動匯率,不能拿來當「切回線上」的來源,所以另外寫了
    `onlineRate()` 直接讀 `effectiveRatesForLedgerProvider`)。
  - 關閉開關後兩欄位可編輯,`onChanged` 互相即時反推(純本地乘除,沒有
    debounce/非同步)。
  - 確認送出:開關開著就清空 `_rateStr`/`_rateManuallySet=false`(讓
    `_currentRate()` 走回自動抓取路徑);關著就以當下「匯率」欄位顯示的數值寫回
    `_rateStr`/`_rateManuallySet=true`。
  - 兩個 `TextEditingController` 刻意不在對話框關閉後立刻 `dispose()`——
    `AlertDialog` 走退場動畫,`Navigator.pop` 之後 `TextField` 還會在動畫期間
    再 build 幾幀,提早 dispose 會炸 `TextEditingController used after being
    disposed`。沒有其他持有者,交給 GC 回收,不是長期洩漏。
- 新增 l10n key(只加到 `app_en.arb` + `app_zh_TW.arb`,依 memory 的既定政策):
  `txConvertDialogTitle`、`txConvertedAmountLabel`、`txUseOnlineRateLabel`。

## 測試

- `test/widgets/account_card_picker_test.dart`:新增
  `allowAllCurrencies:true` 時跨幣別帳戶也列入候選清單並標示幣別代碼的案例;
  既有「依幣種過濾」案例(`allowAllCurrencies` 預設 `false`)維持不動,驗證回歸。
- `test/widgets/transaction_entry_form_test.dart`:新增兩個案例——
  (1) 選外幣帳戶後換算預覽隨時可點,關閉「採用線上匯率」開關、編輯換算金額欄位、
  確認後,提交交易的 `nativeAmount` 反映新換算結果;
  (2) 對話框內編輯「匯率」欄位即時更新「換算金額」欄位,反之亦然。
  這兩個案例額外在 `setUp()` 加了每個 test 重置 `SharedPreferences` mock 值
  ——沒重置的話,前一個 test 寫入的 `default_expense_account_id` 之類的 key
  會跟這個 test 全新建的帳戶 id 撞上,汙染 `_loadDefaultAccount()` 的自動選取
  結果(這個問題在改動前不會浮現,因為改動前外幣帳戶會被 `_loadDefaultAccount`
  的幣別檢查擋掉;拿掉限制後才第一次露出來)。
