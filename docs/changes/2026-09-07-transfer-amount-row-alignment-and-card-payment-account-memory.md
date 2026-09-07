# 轉帳金額列對齊收支表單 + 信用卡繳費帳戶記憶改依卡片區分

## 背景

使用者回報三個問題:

1. 轉帳表單的金額欄位跟打勾確認的版面,跟收支(支出/收入)表單長得不一樣、沒有對齊。
2. 信用卡繳費時(用轉帳介面),App 應該記住「上次繳這張卡用的帳戶」;但實際上卻是记住「上次做的那一筆轉帳」用的帳戶,導致繳完 A 卡再繳 B 卡時,會被 A 卡繳費用過的帳戶污染。
3. 主頁的「新增轉帳」是通用功能,不該被信用卡繳費紀錄污染——除非使用者上次真的是在主頁用轉帳的方式轉給信用卡。

## 根因

- 版面:[transfer_form.dart](../../lib/widgets/transaction/transfer_form.dart) 的金額列用 `Spacer()` + 純文字 `Text`,沒有邊框、也沒有常駐的打勾送出鍵;收支表單([transaction_entry_form.dart](../../lib/widgets/biz/transaction_entry_form.dart))用的是 `Expanded` 包一個 44px 高、有邊框的 `Container`,右側再接一顆常駐的 `_buildInlineSubmitButton`(僅在點開底部小算盤時才會出現另一顆確認鍵,但常駐鍵一直都在)。轉帳表單當初沒有比照這個寫法。
- 帳戶記憶:[LocalTransactionRepository.getLastTransferAccounts](../../lib/data/repositories/local/local_transaction_repository.dart) 原本單純查「整本帳最近一筆轉帳」,完全不管轉入的是哪個帳戶,也不排除信用卡繳款。信用卡繳費的兩個入口(`account_detail_page.dart` 的 `_quickTransfer`/`_onAddPaymentRecord`)都只帶 `initialToAccountId`(這張卡),不帶 `initialFromAccountId`,所以每次繳費「來源帳戶」都是空的,使用者若曾經開過一次完全空白的轉帳(例如主頁「新增轉帳」),那次的 `_loadLastUsedTransferAccounts()` 會把「最近一筆轉帳的兩個帳戶」都預帶進來(含信用卡);之後不管是主頁新增轉帳、或是繳另一張卡,都可能撈到這筆汙染資料。

## 改動

### 1. 轉帳金額列版面對齊收支表單

[transfer_form.dart](../../lib/widgets/transaction/transfer_form.dart) 的金額列(原本用 `Spacer()`)改成跟收支表單一致的結構:貨幣徽章 + 手續費切換鈕 + `Expanded(Container(border, minHeight: 44))` 包住金額文字(靠右對齊、超長省略號)+ 常駐打勾送出鍵(新增 `_buildInlineSubmitButton`,邏輯照抄 `transaction_entry_form.dart` 同名方法,共用既有的 `_submit`/`_isSubmitting`)。連續運算(`_op`)的中間過程數字/運算符號一併搬進邊框內,跟收支表單相同。

### 2. 信用卡繳費:依「這張卡」而非「全帳本最近一筆轉帳」預帶來源帳戶

- 新增 repository 方法 `getLastFromAccountForToAccount(ledgerId, toAccountId)`([transaction_repository.dart](../../lib/data/repositories/transaction_repository.dart) 介面 + [local_transaction_repository.dart](../../lib/data/repositories/local/local_transaction_repository.dart) 實作 + [local_repository.dart](../../lib/data/repositories/local/local_repository.dart) 轉發):查「最近一筆轉入到這個帳戶的轉帳」用的來源帳戶,不論是不是信用卡繳款(這正是要找的對象)。
- [transfer_form.dart](../../lib/widgets/transaction/transfer_form.dart) 的 `initState`:當 `toAccountId` 已知(信用卡繳費入口的典型情境)但 `fromAccountId` 還是空的,改呼叫這個新方法依「這張卡」預帶,不再維持空白。
- `_pickAccount(isFrom: false)`:使用者手動在轉帳表單裡選「轉入帳戶」、且當下「轉出帳戶」還沒選過時,選完後一樣依新方法預帶對應的來源帳戶(涵蓋「先開空白轉帳、再手動挑一張信用卡當轉入」的情境)。

### 3. 主頁「新增轉帳」排除信用卡繳款紀錄

`getLastTransferAccounts`(通用「兩側都沒指定」時的預帶邏輯)的 SQL 加上 `AND (note IS NULL OR note NOT LIKE '信用卡繳款(帳單 %')`,排除備註帶 [cardPaymentNotePrefix](../../lib/utils/credit_card_payment.dart) 前綴的信用卡繳款轉帳,改抓「更早一筆的一般轉帳」。這樣主頁新增轉帳只會被「使用者自己真的用轉帳方式轉給信用卡」的一般轉帳污染(因為那種轉帳沒有這個備註前綴),不會被繳費頁面產生的繳款轉帳污染。

## 取捨 / 刻意不做的事

- 沒有另外區分「主頁新增轉帳」跟「帳戶詳情頁快速轉帳」這兩種入口的狀態——兩者共用同一張 `transactions` 表當作「記憶」來源,靠 SQL 條件(是否為信用卡繳款備註、是否指定了 `toAccountId`)區分行為,沒有引入新的 provider 或快取狀態,維持原本「查詢即狀態」的簡單設計。
- `getLastFromAccountForToAccount` 不排除信用卡繳款備註,因為「上次繳這張卡用的帳戶」本來就該從繳款紀錄本身去找。

## 測試

[test/repositories/category_suggestion_queries_test.dart](../../test/repositories/category_suggestion_queries_test.dart) 新增:
- `getLastTransferAccounts` 排除信用卡繳款轉帳,回傳更早一筆一般轉帳的案例。
- `getLastFromAccountForToAccount` 依轉入帳戶查詢、不同轉入帳戶互不干擾,以及查無紀錄回傳 `null` 的案例。

既有的 `test/widgets/transfer_form_*.dart` 系列測試(手續費/折扣、跨幣別、週期轉帳編輯)全數維持通過,確認版面改動沒有破壞既有互動流程。
