# 退款應一併取消對應的信用卡紅利回饋

## 問題

App 的「退款」功能（`transaction_edit_utils.dart` 的 `refundTransaction()`）
是建立一筆獨立的反向交易（type 對調、`refundOfSyncId` 指回原交易），原交易
本身的金額、`rewardRuleIdsJson` 都不會被修改。

信用卡紅利回饋彙總（「紅利回饋明細」頁 / 帳戶頁彙總卡片）的計算邏輯
（`lib/providers/card_reward_rule_providers.dart` 的 `_summarizeRulePeriod`）
只依「這筆交易是否勾選了這條回饋規則」去撈交易加總，完全不管交易是否已經被
退款——導致使用者退款後，帳面消費雖然被抵銷了，但對應的回饋金額還是持續被
算進 `totalReward`/`totalSpend`，沒有一起被取消。

## 修正

`_summarizeRulePeriod` 在算出 `matched`（本期套用該規則的交易）之後，額外對
每筆有 `syncId` 的交易查一次 `getRefundsOf(syncId)`（既有的、查「誰的
`refundOfSyncId` 指向我」的方法），把該筆交易已退款的金額加總起來。

計算回饋金 / 消費統計時，用「原始金額 − 已退款金額」的**淨額**取代原始金額：
- 全額退款 → 淨額歸零 → 回饋金歸零。
- 部分退款（`refundTransaction()` 本來就支援改金額做部分退款）→ 回饋金按淨額
  等比例重算，不是整筆清零。

原交易物件本身（`transactions` 欄位,用於明細頁列表顯示）仍然是原始金額,只有
拿去餵 `estimateCardRewardCumulative` 累計扣減額度、以及 `totalSpend` 加總時
才用淨額——所以列表上還是看得到這筆交易原本花了多少錢,只是回饋金額會反映
退款後的實際狀況。

`cardRewardForTransactionProvider`（交易詳情卡的「紅利回饋」估算）、
`cardRewardForDraftProvider`（記帳表單草稿的即時估算）都是透過
`_summarizeRuleWindow` → `_summarizeRulePeriod` 間接吃到這次的淨額計算,不需要
另外改。

## 刻意不做的事

- 沒有在 `Transactions` 表加「已退款」欄位——用既有的 `getRefundsOf` 反查就
  夠了,退款關聯本來就是靠 `refundOfSyncId` 這個方向性欄位表達,加一個冗餘的
  正向 flag 只會多一個要保持同步的地方。
- 沒有處理「退款單自己被使用者手動勾選了回饋規則」這種邊界情況——
  `refundTransaction()` 建立退款單時本來就不帶 `rewardRuleIds`,這屬於使用者
  主動誤操作,不在這次修正範圍。
- 這是前端純估算（同檔案其他函式的既有限制，見 `card_reward_calc.dart` 開頭
  注釋）：真正入帳金額仍由 BeeCount Cloud 排程計算，本次修正沒有同步調整
  Cloud 端的排程邏輯是否也有同樣的退款漏算問題（需要另外在
  `BeeCount-Cloud` репо確認）。

## 測試

`test/providers/card_reward_refund_test.dart`：
- 全額退款後 `totalReward`/`totalSpend` 歸零。
- 部分退款後回饋金按淨額等比例重算。

兩個測試在修正前都會失敗（先驗證過 revert 修正後測試確實會 fail），確認有
覆蓋到這個 bug。
