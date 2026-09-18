# AI 記帳自動套用信用卡回饋規則

日期:2026-09-18
設計文件:`docs/superpowers/specs/2026-09-18-ai-bookkeeping-reward-autofill-design.md`(本地
scratch,未提交——BeeCount `docs/superpowers/` 是 gitignore 的規劃稿,不是正式文檔)

## 背景

AI 記帳(對話/拍照/語音/背景截圖/背景通知,共 5 條管道,全部經
`BillCreationService.createFromBill` 落庫)選好帳戶後,信用卡消費的回饋規則過去完全靠使
用者事後手動點開 `CardRewardRuleSelector` 勾選。本次讓 `BillCreationService` 在建交易當
下自動判斷該套用哪一條本地已設定的 `CardRewardRule`,一次寫入,不需要事後補選。

## 改動內容

### 1. `BillInfo` 新增商家欄位(`lib/ai/core/bill_info.dart`)

新增 `final String? merchant`,JSON key 是 `merchant_name`——刻意不沿用 `merchant`
這個舊 key,那是自訂 prompt 模板的相容欄位,語意等同塞進 `note`,跟這次的獨立商家欄位
是兩回事。`copyWith`/`toJson` 同步跟進。

### 2. Prompt 調整(僅預設模板,`lib/ai/core/prompt_builder.dart`)

- 新增 `merchant_name` 欄位說明,緊接在 `note` 之後。
- 調整 `note` 的擷取優先順序:商品名稱/使用者描述優先,商家退到最後一級 fallback(避免
  兩個欄位長期重複同一個值,也避免 `note` 常態留空)。
- 只改預設模板;使用者自訂過 prompt 的話 AI 不會吐 `merchant_name`,這條功能對他們自然
  不生效(不查 SwipeSmart、不自動套用回饋),不報錯、不用 `note` 內容硬猜。
- 跑過 `test/ai/`、`test/services/ai/` 既有測試案例確認無回歸。

### 3. 回饋規則模糊比對(`lib/services/billing/reward_rule_matcher.dart`,新檔)

`matchUniqueRewardRuleByLabel`:小寫+trim 正規化後互相 `contains` 比對 SwipeSmart 建議
的規則名稱字串到本地規則的 `label`,**剛好一筆命中才採用**,0 筆或多筆命中一律 `null`
(不猜、不取分數最高/回饋最多那條——跟 `2026-09-02-swipesmart-quickadd-deeplink-design.md`
當初刻意不做這個反向比對時定下的精確度基準一致)。`effectiveRewardRules` 抽出「目前生效
中」(`enabled` + `startsAt`/`endsAt` 窗口)的判定,跟 `card_reward_rule_selector.dart` 的
`_eligible` 共用同一套邏輯,避免兩處各自維護一份容易漂移。

### 4. `BillCreationService` 新增回饋自動比對(`lib/services/billing/bill_creation_service.dart`)

新增建構子參數 `RecommendRewardRuleName? recommendRewardRuleName`(比照既有 `EnsureRate`
的注入模式,service 層不依賴 `flutter_cloud_sync`)。`createFromBill` 新增 4.9 步驟,僅
`expense` 且帳戶為 `credit_card` 才進入 `_resolveRewardRuleIds`:

1. `categoryId` 非空時先查「同帳戶+同分類」學習快取(`RewardChoiceCacheRepository`,跟手
   動表單共用同一份資料,**只讀不寫**),過濾掉已被刪除的 syncId,非空就採用。
2. 快取沒有可用結果時,只在帳戶已對照 `swipesmartCardId`、AI 有辨識出商家、且注入了
   `recommendRewardRuleName` 時才查 SwipeSmart 推薦,丟給
   `matchUniqueRewardRuleByLabel` 模糊比對。
3. 結果直接放進本來就有的 `addTransaction(..., merchant:, rewardRuleIds:)` 一次寫入。

任何一步沒有結果都回傳 `null`,交易照常建立,不擋流程。**自動比對結果不寫回學習快
取**——維持「只有使用者手動選才寫入」的既有不變量,下次同帳戶+同分類若快取仍是空的,
會再查一次 SwipeSmart。

### 5. Provider 裝配(`lib/providers/ai_chat_providers.dart`)

`aiBookkeeperProvider` 組裝 `BillCreationService` 時注入 `recommendRewardRuleName`:查該
帳本的 SwipeSmart 建議清單,挑出 `accountId`(server 端已對照好的本地帳戶 syncId)等於這
次本地帳戶 syncId 的那一筆,回傳其 `ruleName`。任何例外(沒連 Key、逾時、網路錯誤)一律
catch 後回傳 `null`,跟手動表單 `_fetchRecommendation` 的降級哲學一致。

### 6. UI 顯示(`lib/widgets/ai/bill_card_widget.dart`)

- 新增 `transactionByIdProvider`(`lib/providers/database_providers.dart`)和
  `cardRewardRuleBySyncIdProvider`(`lib/providers/card_reward_rule_providers.dart`)—— 
  `BillCardWidget` 只拿得到 `BillInfo`(AI 抽取結果,不含落庫後才決定的
  `merchant`/`rewardRuleIds`),要顯示「已套用的回饋」得另外查一次實際落庫的
  `Transaction`。
- 新增「商家」列(`billInfo.merchant` 非空時顯示)與「回饋」列(交易的 `rewardRuleIds`
  非空時逐一查規則名稱,格式比照 `transaction_entry_form.dart` 的 `_rewardChipLabel`:
  「規則名稱 (比例%)」)。兩列都只在 `!isUndone` 且有值時顯示。
- 新增 l10n key `billCardMerchant`/`billCardReward`(只加到 `app_en.arb` +
  `app_zh_TW.arb`,依現行 l10n 維護範圍)。

## 範圍排除(與使用者確認過的取捨)

- 不做「取分數最高/回饋最多那條」這種更寬鬆的比對。
- 自動比對結果不寫入學習快取。
- 不新增 SwipeSmart Key 連線狀態的獨立檢查呼叫,直接用「帳戶是否已對照
  `swipesmartCardId`」當閘門。
- 不修改週期性交易生成路徑,只涵蓋 AI 記帳的 5 條管道。
- 不動使用者自訂 prompt 模板。

## Schema/同步

無新增 schema。`Transaction.merchant`(v33)、`Transaction.rewardRuleIds`(v35)都是既有
欄位,這次只是 AI 記帳第一次把它們填上值,同步機制不需要改動。

## 測試

- `test/ai/core/bill_info_test.dart`:`merchant`/`merchant_name` 的
  `fromJson`/`toJson`/`copyWith` round-trip,含跟舊版 `merchant` 兼容欄位不混用的回歸鎖。
- `test/services/billing/reward_rule_matcher_test.dart`(新增):完全命中、模糊互相包含
  命中、零命中、多筆命中降級 `null`、大小寫/空白正規化、`effectiveRewardRules` 的
  enabled/時間窗口過濾。
- `test/services/billing/bill_creation_service_test.dart`:新增「信用卡回饋規則自動比
  對」group,覆蓋快取命中、SwipeSmart 唯一命中、零/多筆命中不套用、非信用卡帳戶跳過、
  商家為空跳過、`recommendRewardRuleName` 未注入時優雅跳過、`swipesmartCardId` 未對照
  時不查、自動比對結果不寫回快取。
- `test/widgets/bill_card_widget_test.dart`(新增,本來沒有 widget test 基礎設施,這次
  補上):商家列顯示、回饋列顯示格式、無回饋規則/已撤銷時不顯示。
- 全量跑過 `test/ai/`、`test/services/ai/`、`test/services/billing/` 確認無回歸
  (234 個測試全過)。

## 入口點

這是背景自動比對邏輯,沒有新的使用者可見入口——效果會直接反映在 AI 記帳(對話/拍照/語
音/背景截圖/背景通知)產生的交易紀錄卡片上:符合條件時「回饋」列會自動出現已套用的規
則,不需要使用者手動操作。
