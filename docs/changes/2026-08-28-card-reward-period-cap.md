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
  (記帳表單「compose 時」還沒有交易 id、無法套用週期上限,維持原本的單筆
  試算行為當保守估算;交易詳情卡有真正的交易 id 跟所屬帳期,見下面的附帶
  修正)。
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

## 追加修正(同日):交易詳情卡的回饋金額也要吃週期累計上限

補上 tap-to-detail 之後發現交易詳情卡(`TransactionDetailCard`)「紅利回饋」
區塊顯示的金額,跟明細頁逐筆列表對同一筆交易算出來的金額不一樣——詳情卡
([lib/widgets/biz/transaction_detail_card.dart](../../lib/widgets/biz/transaction_detail_card.dart))
的 `_buildRewardSection` 直接呼叫 `estimateCardRewardForRule(rule, tx.amount)`,
是純單筆估算,沒有套用上面提到的週期累計上限,跟明細頁/彙總卡片是兩套不同
的數字。

- [lib/utils/card_reward_period.dart](../../lib/utils/card_reward_period.dart):
  新增 `billingCycleOffsetForDate(billingDay, date)`——由任意日期回推它落在
  `billingCyclePeriod` 的第幾期(offset),線性搜尋,靠相鄰週期首尾銜接的
  性質保證收斂。交易詳情卡只知道這筆交易的 `happenedAt`,不像明細頁那樣直接
  拿著使用者正在翻頁的 offset,需要這個反查。
- [lib/providers/card_reward_rule_providers.dart](../../lib/providers/card_reward_rule_providers.dart):
  新增 `cardRewardForTransactionProvider((rule, transaction))`——用
  `billingCycleOffsetForDate` 找出這筆交易所屬帳期,再呼叫既有的
  `_summarizeRuleWindow` 算出那個帳期的 `rewardByTransactionId`,取這筆交易
  自己的份。額外處理了合併帳單分組(`account_group`)的情境:交易若掛在分組
  子帳戶底下,要用「父帳戶 id + 全部子帳戶 id」去查,額度才會跟分組共用對
  齊(`_resolveRewardAccountContext`,邏輯對齊
  `account_detail_page.dart` 的 `_children()`)。這個 provider 是
  `autoDispose` 的即時查詢,不是快取值——如果同一帳期內有更早的交易被刪除
  /新增/改期,下次重新開啟交易詳情卡(重新 build 出新的 provider 呼叫)就會
  拿到重算後的金額。
- [lib/widgets/biz/transaction_detail_card.dart](../../lib/widgets/biz/transaction_detail_card.dart):
  「紅利回饋」區塊每一列拆成獨立的 `_RewardRuleRow`(`ConsumerWidget`),
  `watch` 上面這個新 provider;金額比單筆估算(`estimateCardRewardForRule`)
  低时,代表額度被同帳期其他交易吃掉一部分,加上「已達上限」(`txDetailRewardCapped`,
  新增 l10n key,只加在 `app_en.arb`/`app_zh_TW.arb`,見
  [[feedback-l10n-policy-change]])的小標籤,不然使用者會覺得金額對不上
  記帳表單當初顯示的預估值、看不出原因。
