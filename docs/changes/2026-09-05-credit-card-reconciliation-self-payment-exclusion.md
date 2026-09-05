# 對帳模式:排除「繳自己這期帳單」的轉帳

## 問題

使用者回報:對帳模式(`AccountReconciliationPage`)的候選清單裡,出現一筆
「信用卡繳款(帳單 2026-08-05~2026-09-05)」的轉帳項目,而這筆繳款正是繳清
**當前正在對帳的這一期**(2026-08-05~2026-09-05)帳單——它是繳款動作本身,
不是這期帳單裡的一筆新增消費,不該出現在清單裡讓使用者勾選。

「新增消費」金額(`newSpend`/`_buildBillingSummaryRows`)本來就已經排除所有
`type == 'transfer'` 交易,金額沒有算錯;問題只在於**清單筆數/清單裡的
那一行**——`帳單筆數`/`統計勾選進度`把這筆繳款也算成一筆待確認項目。

## 根因

`LocalAccountRepository.getAccountStatementTransactions()`
(`lib/data/repositories/local/local_account_repository.dart`)的候選集合口徑
是:

```
(type IN ('expense','income') AND account_id IN (...))
OR (type = 'transfer' AND to_account_id IN (...))
```

第二個分支「轉入這張卡的轉帳都算」是刻意設計(見
`docs/changes/2026-08-18-credit-card-reconciliation-cloud-parity-fix.md`):
使用者延後到下一期才繳清上一期欠款時,那筆繳款要依它自己的入帳歸屬日出現在
「繳款當下那一期」的對帳清單裡,讓使用者能看到這期帳單上出現了一筆「繳款
沖銷」的項目(`test/repositories/account_statement_transactions_test.dart`的
「期三」案例鎖定了這個行為,對齊 BeeCount Cloud 正式資料庫核對過的
`get_account_statement` 語意)。

但這個分支完全沒有排除「繳的正是這一期自己」的退化情況——`creditCardPaymentNote()`
(`lib/utils/credit_card_payment.dart`)過去在結帳日當天繳款時,會因為
`mostRecentlyClosedBillingOffset` 的 off-by-one(已於同日另一個修正處理,見
`lib/utils/card_reward_period.dart` 註解)把「當期」誤判成「已結清的上一期」,
寫出 note 尾端日期等於這期自己 `cycleEnd` 的繳款記錄;即使該 off-by-one 已修
正,只要繳款動作剛好落在該帳期的結帳日窗口內,COALESCE 入帳歸屬日一樣會落進
自己這期,舊資料/未來邊界情況都可能重現這個現象。

## 修正

在 transfer 分支加一個排除條件:note 尾端的帳單結束日等於本次查詢的
`cycleEnd` 時,視為「繳自己這期」而排除;note 是其他日期(繳的是別期帳單)
或沒有 note,行為完全不變。用字串比對(`LIKE '信用卡繳款(帳單 %~<cycleEnd>)%'`)
而不是解析成日期物件比較,因為判斷只需要「這期」跟「note 裡寫的那期」是否
為同一天,不需要真正的日期運算。

- [lib/data/repositories/local/local_account_repository.dart](../../lib/data/repositories/local/local_account_repository.dart) `getAccountStatementTransactions()`——加排除條件。
- [lib/data/repositories/account_repository.dart](../../lib/data/repositories/account_repository.dart)——更新介面文件註解說明新的排除語意。
- [test/repositories/account_statement_transactions_test.dart](../../test/repositories/account_statement_transactions_test.dart)——新增案例鎖定:①同期繳款被排除;②別期繳款(note 尾端日期不同)仍然要收,不能被這次修正誤傷既有的「期三」行為。

## Out of scope

使用者同時回報「server 端也有一樣的問題」——BeeCount Cloud
(`../BeeCount-Cloud`,獨立 git repo)的 `get_account_statement` 若有對等邏輯,
需要另外在該倉庫比照修正,不在本次改動範圍內。
