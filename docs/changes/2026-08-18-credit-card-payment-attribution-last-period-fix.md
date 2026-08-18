# 「繳款記錄」FIFO 歸屬:改成「最後沖到的那期」,不是「開始沖的那期」

> **⚠️ 一度被推翻,後來又恢復(範圍收窄)**:曾在
> [2026-08-18-credit-card-reconciliation-cloud-parity-fix.md](2026-08-18-credit-card-reconciliation-cloud-parity-fix.md)
> 被整個撤回(`attributePaymentsToPeriods` 一度刪除),但使用者隨後用
> 「星展信用卡」實測反饋推翻了那次撤回,最終在
> [2026-08-18-credit-card-payment-record-attribution-restore.md](2026-08-18-credit-card-payment-record-attribution-restore.md)
> 恢復——這份文件定案的「最後沖到的那一期」(`lastTarget`)規則本身是對的,
> 現狀程式碼就是照這份文件的規則實作,只是套用範圍收窄成只有「繳款記錄」
> 小節,不影響對帳模式/彙總數字。

日期:2026-08-18
背景:延續 [2026-08-18-credit-card-payment-period-attribution-fix.md](2026-08-18-credit-card-payment-period-attribution-fix.md)
新增的 `attributePaymentsToPeriods`。使用者拿「星展信用卡」實測資料(用
`postgresql://temp_user@10.0.4.20:5431/beecount` 這個 BeeCount Cloud 正式
資料庫核對過)重新回報同一個症狀還在:查看已經結清的 `2026/07/11–08/11`
帳期,摘要卡片顯示「剩餘帳款 已繳清 ✓」,但「繳款記錄」清單卻是
「(0) 無交易記錄」;08/12 21:07 那兩筆繳款(819 + 5744)反而都出現在再往前
一期的 `2026/06/11–07/11`。

## 用真實資料重建、確認根因在演算法設計,不是實作漏洞

直接查 Cloud 正式庫 `read_tx_projection` 撈出「星展信用卡」(account_group,
子卡「星展eco卡」+「星展英雄聯盟卡」)這張群組帳戶的全部交易,手算
`07/11–08/11` 期的入帳歸屬日(`COALESCE(deferred_posting_at, happened_at)`)
落在期間內的 expense/income:得出新增花費 = 4259,跟 Web 端顯示完全一致
(App 端 `getAccountTransactions(byEffectiveDate: true)` 的 SQL 走查也確認會
正確排除掉 4 筆 `deferred_posting_at` 落在下一期的延後入帳交易,總金額差
正好是使用者回報的 3112——**這部分〔問題 1:新增花費算錯〕在
`2026-08-18-credit-card-charged-deferred-posting-fix.md` 已經修好,程式碼
現狀正確,這次不用再改**)。

問題出在〔問題 2:繳款記錄期別掛載〕。用同一份真實資料手動模擬
`attributePaymentsToPeriods`:`06/11–07/11` 期欠 2304、`07/11–08/11` 期欠
4259,兩筆繳款 819(先處理)、5744(後處理)。旧版演算法:819 沒沖完
`06/11–07/11`(欠款剩 1485),`home[819] = 06/11–07/11`;5744 先沖掉
`06/11–07/11` 剩餘的 1485,又接著把 `07/11–08/11` 的 4259 全部沖完,但舊版
只認「這筆繳款**開始**沖銷的那一期」(`firstTarget ??= periodId`,第一次
賦值後就不再更新),所以 `home[5744]` 還是 `06/11–07/11`,不是它實際沖乾淨
的 `07/11–08/11`。這正是使用者看到「已繳清的帳期,繳款記錄卻是 0 筆」的
根因——不是查詢邊界或時區算錯,是「一筆繳款橫跨兩期時該算給哪一期」這個
歸屬規則本身選錯了方向。

## 改法:`firstTarget` 改成 `lastTarget`,回傳「最後沖到的那一期」

`lib/utils/credit_card_payment.dart::attributePaymentsToPeriods` 迴圈裡把
`firstTarget ??= periodId`(只在第一次賦值)改成 `lastTarget = periodId`
(每次沖銷到某一期都更新),回傳 `home[payment.paymentId] = lastTarget ?? periods.last.periodId`。

**為什麼選「最後」而不是「開始」**:一筆繳款如果把一個早就拖欠很久的舊
帳期沖乾淨、順便也沖掉當期的新帳款,使用者的直覺認知是「這筆錢是繳這期
的」,不是「繳那個已經結清很久的舊帳期的」。選「最後沖到的那期」有個
額外保證:這個目標一定**不會是「這筆繳款開始處理前就已經欠款歸零」的
歷史舊帳期**(因為指標只會往還有欠款的期別走),不管這筆繳款沖了幾期,
回傳的一定是它實際造成影響的最新那一期。

**維持原設計的取捨不變**:仍然不把同一筆交易拆成兩半分別顯示在兩個帳期
——[[2026-08-18-credit-card-payment-period-attribution-fix]] 文件裡「UI 不用
處理一筆交易金額被切開顯示的複雜度」這個理由沒有變,只是把「哪一期算是
它的家」的判斷方向反過來。

## 測試

- `test/utils/credit_card_payment_test.dart`:
  - 更新既有 2 個案例的預期值/敘述,反映新規則(`一筆繳款金額足夠沖掉舊
    帳期又有找零` 從「歸屬仍是最舊那期」改成「歸屬到找零流入的下一期」;
    `多筆繳款依序沖銷同一期` 的 payment2 從歸屬 `-2` 改成 `-1`)。
  - 新增 1 個案例直接鏡射「星展信用卡」真實金額(2304/4259 兩期,
    819/5744 兩筆繳款),斷言 5744 歸屬到新一期、819 留在舊一期。
- `test/providers/credit_card_payment_period_records_provider_test.dart`:
  新增端到端案例(`BeeDatabase.forTesting` + `LocalRepository` +
  `ProviderContainer`),同樣用 2304/4259/819/5744 這組真實金額,驗證
  `creditCardPaymentPeriodRecordsProvider` 對兩個帳期分別查詢時,819 出現在
  舊一期、5744 出現在新一期(而不是新一期查出來是空清單)。
- 全部 27 個信用卡繳款相關測試 + 全專案 766 個測試(含這次新增的 2 個)
  全數通過;`flutter analyze` 涉及的 3 個檔案 0 issue。

## Verification

- 用 Cloud 正式資料庫(唯讀查詢)實際核對「星展信用卡」帳戶的原始交易,
  手算跟修正後的程式邏輯比對一致,確認問題 1(新增花費)程式碼現狀已經
  正確、問題 2(繳款記錄歸屬)這次改動後手算結果也對得上。
- 手動驗證(模擬器/實機)待補:沒有實際點開 App 核對「07/11–08/11」期別
  的「繳款記錄」區塊現在會顯示 5744 那筆、「06/11–07/11」期別顯示 819
  那筆。
