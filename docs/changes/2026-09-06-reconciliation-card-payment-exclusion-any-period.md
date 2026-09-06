# 對帳模式:信用卡繳款轉帳不分期別,一律排除

## 問題

使用者回報(截圖):對帳模式(`AccountReconciliationPage`)清單裡出現一筆
「轉帳」-7,477(2026/08/20),這其實是繳清「上一期」信用卡帳單的轉帳(note
是 `creditCardPaymentNote()` 產生的「信用卡繳款(帳單 ...)」格式),卻出現在
「這一期」(2026-08-05~2026-09-05)的對帳候選清單裡讓使用者勾選/延後——跟
BeeCount Cloud 的 `get_account_statement` 端點行為不一致(server 端不會把這
筆繳款算進清單)。

## 根因

[2026-09-05-credit-card-reconciliation-self-payment-exclusion.md](2026-09-05-credit-card-reconciliation-self-payment-exclusion.md)
只排除「繳的正是這一期自己」的繳款轉帳(note 尾端帳單結束日剛好等於本次
查詢的 `cycleEnd`),繳的是「別期」帳單、只是入帳歸屬日落在這期窗口內的繳款
轉帳仍然保留在清單裡——當時誤以為這是刻意設計,鎖在
`account_statement_transactions_test.dart` 的「期三」案例裡。

直接查證 BeeCount Cloud 的
`src/routers/read/ledgers.py::get_account_statement`
(`src/services/credit_card_billing.py::is_card_settlement_note`)才發現:
server 端排除的判斷**只看 note 前綴**(`信用卡繳款(帳單 ` /
`自動扣繳(帳單 `),完全不管繳的是哪一期帳單——因為
`compute_cycle_period_billing` 已經用不分時間窗口的 lifetime `paid_total`
FIFO watermark 把清償效果算進 `remaining_due`/`carryover_due`,清單裡不論
哪一期再收一次繳款轉帳,都會讓使用者看到一筆跟真實消費對不上的「多出來」項目。
上一版 doc 誤判「server 端也有一樣的問題」是錯的,實際上 App 端排除得比
server 更窄。

「期三」案例裡的兩筆轉帳(819/5744)本身沒有 note,是單純轉帳,不受這次
修正影響——這次修正只收窄「有信用卡繳款 note 前綴」的轉帳排除範圍,一般
轉帳(沒有這個前綴,包含使用者自訂 note 覆蓋掉前綴的情況)依舊照舊收進清單。

## 修正

- [lib/utils/credit_card_payment.dart](../../lib/utils/credit_card_payment.dart)——把
  「信用卡繳款(帳單 」前綴抽成共用常數 `cardPaymentNotePrefix`,`creditCardPaymentNote()`
  改用這個常數組字串,避免兩處各自硬編碼同一段中文字面量。
- [lib/data/repositories/local/local_account_repository.dart](../../lib/data/repositories/local/local_account_repository.dart)
  `getAccountStatementTransactions()`——排除條件從「note 尾端帳單結束日等於
  `cycleEnd`」改成「note 前綴等於 `cardPaymentNotePrefix`」(不分期別),鏡射
  BeeCount Cloud `is_card_settlement_note` 的前綴排除語意,同時拿掉不再需要的
  `cycleEndIso` 計算。
- [lib/data/repositories/account_repository.dart](../../lib/data/repositories/account_repository.dart)——更新
  `getAccountStatementTransactions()` 介面文件註解,說明新的不分期別排除語意。
- [test/repositories/account_statement_transactions_test.dart](../../test/repositories/account_statement_transactions_test.dart)——把原本鎖定「別期繳款仍要收」的案例改成鎖定「別期繳款也要排除」,並新增一個
  「一般轉帳(沒有繳款 note)依舊收進清單」的斷言,確保這次修正沒有誤傷一般轉帳。

## Out of scope

BeeCount Cloud 已經是「不分期別、只看前綴」的排除語意,不需要另外修改 server
端;`自動扣繳(帳單 ...)` 前綴目前只有 Cloud 端(`services/credit_card_autopay.py`)
會產生,App 端還沒有對應的自動扣繳交易生成邏輯,所以這次沒有在 App 端加這個
前綴的排除(等 App 真的有自動扣繳功能寫出這種 note 時再一併處理)。
