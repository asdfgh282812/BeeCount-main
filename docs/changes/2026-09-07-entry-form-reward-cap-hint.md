# 記帳表單顯示紅利回饋已達上限提示

## 背景

交易詳情卡(`transaction_detail_card.dart`)在存檔後,已經會用 `cardRewardForTransactionProvider`
即時查該筆交易所屬帳單週期內、扣掉同週期其他交易額度後的估算回饋金,若比單筆估算低就顯示
「已達上限」badge(`_RewardRuleRow`)。但記帳表單(新增/編輯交易時)的「預計可獲得回饋」文字
一直只用 `estimateCardRewardForRule`/`estimateCardRewardTotal` 做單筆估算,完全不知道同一帳單
週期已經有其他交易用掉多少額度——使用者在新增交易當下看到的預估金額,存檔後可能因為已達上限
而縮水,兩邊數字對不上,也沒有任何提示告訴使用者「哪一條規則已經到頂、這筆只能拿到多少」。

## 變更內容

- [lib/providers/card_reward_rule_providers.dart](../../lib/providers/card_reward_rule_providers.dart):
  新增 `cardRewardForDraftProvider`,是 `cardRewardForTransactionProvider` 的草稿版——輸入從
  「已存檔的 `Transaction` 物件」改成表單當下就有的 `accountId`/`happenedAt`/`amount`,
  底層一樣用 `_resolveRewardAccountContext` + `_summarizeRuleWindow` 查出該帳單週期已用掉多少
  額度,再拿 `rule.capAmount` 扣掉算出這筆草稿還能拿多少。編輯既有交易時傳
  `excludeTransactionId`(該交易的本機 id),把它自己在週期彙總裡的舊金額扣掉,避免自己算兩次。
- [lib/widgets/biz/transaction_entry_form.dart](../../lib/widgets/biz/transaction_entry_form.dart):
  `_buildEstimatedRewardRow` 原本只顯示一行總額,現在在下面逐條規則顯示「{規則名} 已達上限,
  本筆僅能獲得 {金額}」的警示文字(僅在該規則被同週期其他交易吃掉額度、實際估算低於單筆估算時
  才顯示),透過新增的 `_buildCappedRewardHints` 對每條已選規則呼叫 `cardRewardForDraftProvider`。
  拆出 `_draftRewardAmount()` 共用「目前輸入金額(含加減運算)」的計算,移除原本重複的
  `_estimatedReward()`(已無其他呼叫點)。
- [lib/l10n/app_en.arb](../../lib/l10n/app_en.arb) / [lib/l10n/app_zh_TW.arb](../../lib/l10n/app_zh_TW.arb):
  新增 `cardRewardRuleCappedHint` 字串(`{ruleLabel} has reached its cap — this transaction can
  only earn {amount}` / `{ruleLabel} 已達上限,本筆僅能獲得 {amount}`),`flutter gen-l10n` 重新產生。
  依照既有的 [L10n 政策](../../CLAUDE.md) 只維護 `app_en.arb`+`app_zh_TW.arb`,沒有動
  `app_zh.arb`/`app_ko.arb`,其餘語系會退回英文字串(跟其他既有未翻譯字串行為一致)。

## 取捨

- 跟 `_RewardRuleRow` 一樣,這仍然是純前端估算,不 call server;真正入帳金額由 BeeCount Cloud
  排程計算(見兩處程式碼註解)。`capSharedKey`(跨規則共用額度群組)目前 client 端完全沒有實作
  ——這個限制原本就存在(`cardRewardForTransactionProvider` 也沒處理),這次沒有一併補上。
- 沒有新增 provider 層級的測試,因為 `cardRewardForTransactionProvider` 本身也沒有對應測試,
  維持跟既有覆蓋範圍一致;純函式部分的回歸由既有的 `test/utils/card_reward_calc_test.dart` 覆蓋。
