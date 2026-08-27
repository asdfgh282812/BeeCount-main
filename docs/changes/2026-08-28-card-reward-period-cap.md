# 紅利回饋:週期上限改為累計扣減 + 明細頁交易可點開詳情卡

## 問題

帳戶頁「紅利回饋」分組卡片與明細頁(`CardRewardDetailPage`)顯示的週期總回饋
金,會超過規則自己設定的 `capAmount`,且跟 BeeCount Cloud 網頁後台算出的金額
對不上。

根因:`estimateCardRewardForRule`([lib/utils/card_reward_calc.dart](../../lib/utils/card_reward_calc.dart))
只對**單筆交易**的估算金額套用 `capAmount`,而 `_summarizeRulePeriod`
([lib/providers/card_reward_rule_providers.dart](../../lib/providers/card_reward_rule_providers.dart))
把週期內每筆交易各自試算的結果直接加總,完全沒有讓上限在整個週期內被交易
共同吃掉。只要週期內沒有任何一筆交易「單筆」就超過上限,per-tx 的 cap 檢查
永遠不會觸發,週期加總自然可以無限超過設定的上限——這正是 server 端排程的
行為(cap 是整個週期共用一份額度,不是每筆各自一份)。

## 修正

- [lib/utils/card_reward_calc.dart](../../lib/utils/card_reward_calc.dart):
  新增 `estimateCardRewardCumulative(rule, transactionsAscending)`,依交易發生
  時間由舊到新依序累加,額度隨著交易被扣減,回傳 `{tx.id: 該筆分到的回饋金}`
  的 map,加總保證不超過 `capAmount`。`estimateCardRewardForRule` 本身不動
  (記帳表單/交易詳情卡等「compose 時」的單筆估算沒有完整週期資料,維持原本
  的單筆試算行為,這不在本次修正範圍)。
- [lib/models/card_reward_summary.dart](../../lib/models/card_reward_summary.dart):
  `CardRewardRuleSummary` 新增 `rewardByTransactionId` 欄位,存每筆交易分到的
  估算回饋金,供明細頁逐筆列表跟彙總卡片共用同一份數字。
- [lib/providers/card_reward_rule_providers.dart](../../lib/providers/card_reward_rule_providers.dart):
  `_summarizeRulePeriod` 改用 `estimateCardRewardCumulative` 算
  `totalReward`;`_summarizeRuleWindow` 的自然月拆分(`monthlyBreakdown`)分支
  把各自然月的 `rewardByTransactionId` 合併回外層——自然月拆分後每個子週期
  各自呼叫 `_summarizeRulePeriod`,上限本來就會隨自然月各自重置,行為不變。
- [lib/pages/account/card_reward_detail_page.dart](../../lib/pages/account/card_reward_detail_page.dart):
  逐筆列表改讀 `summary.rewardByTransactionId[tx.id]`,不再各自呼叫
  `estimateCardRewardForRule(rule, tx.amount)`(否則逐筆列表跟上方彙總卡片的
  總額還是會對不上)。

帳戶頁的紅利回饋分組卡片(`account_detail_page.dart`)跟 `cardRewardAccountSummaryProvider`
共用同一份 `_summarizeRuleWindow`,不用另外改就自動吃到修正。

前端這份估算依然是「純前端估算」(見檔案頂端註解),跟 server 端排程比對可能
還是會有邊界差異(例如週期起訖邊界上的交易、`capSharedKey` 跨規則共用上限
群組——這些都需要 server 端才看得到完整資料),但至少單一規則自己設定的
`capAmount` 現在保證不會被前端估算顯示超過。

## 附帶修正:明細頁交易可點開詳情卡

`CardRewardDetailPage` 的逐筆交易列表原本沒有接任何 `onTap`,跟 App 裡其它
交易列表頁(`project_detail_page.dart`、`tag_detail_page.dart`、
`calendar_body.dart`、`search_page.dart`、`category_detail_page.dart`、
`account_reconciliation_page.dart`、`transaction_list.dart`)點擊交易都會彈出
`showTransactionDetailCard` 的慣例不一致。補上 `InkWell` + `onTap`,點擊後彈
出跟其它頁面一樣的唯讀交易詳情卡。
