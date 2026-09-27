# AI 助手:支援依帳戶名稱查詢消費,並修正錯誤訊息用語

## 背景

使用者用 AI 助手問「這個月用星展英雄聯盟卡花了多少」,得到「沒有找到消費紀錄」。
追查後發現 `query_transactions` 這個唯讀查詢工具(`lib/services/ai/free_chat_tools.dart`)
根本沒有「依帳戶查詢」的能力:它只比對交易的備註/商家/分類名稱
(`_matchesKeyword`),完全不看 `accountId`。routing 階段給模型的帳本上下文
(`lib/services/ai/free_chat_context.dart`)也只列出分類,不列帳戶,模型因此
沒辦法分辨「星展英雄聯盟卡」是帳戶名還是隨口的關鍵字,只能塞進 `keyword` 去
搜備註/商家文字 —— 除非交易備註剛好打了「星展」兩個字,否則必然 0 筆命中。

這**不是**兩次回答矛盾的問題:使用者截圖裡第一次「AI服务暂时不可用」是呼叫
底層 AI 服務時的暫時性錯誤(`ai_chat_service.dart` 的 `AIException` 兜底分支,
無自動重試,純粹是手動重送第二次),跟第二次「查無紀錄」是完全獨立的兩條路徑;
第二次是模型正常執行了查詢工具,只是工具本身缺了帳戶過濾這個能力。

## 改了什麼

- **`lib/services/ai/free_chat_tools.dart`**:`query_transactions` 新增
  `accountName` 參數,解析邏輯與既有 `categoryName` 一致(完全相同優先,
  沒有完全相同時退化為包含比對,`foldZh` 简繁摺疊);新增 `_resolveAccounts`。
  刻意排除 `type == 'account_group'` 的帳戶 —— 那只是合併帳單用的管理容器,
  從來不會是任何交易真正的 `accountId`,納入比對池只會產生「解析到帳戶名、
  但 matchedCount 永遠 0」的假陽性,做法與 `ai_extraction_context.dart`
  挑記帳候選帳戶、`bill_creation_service.dart` 用名稱回填帳戶 id 時的過濾
  一致。回傳結果的 `filters` 區塊新增 `accountName`/`resolvedAccounts`,讓
  模型(與除錯時的人)看得到「查詢詞被解析成了哪個實際帳戶」。
  帳戶清單原本只在有 sample 時延遲載入,現在跟分類表一樣一律預先載入
  (帳戶表通常只有幾十列,過濾用得到)。
- **`lib/services/ai/free_chat_context.dart`**:`FreeChatContext` 新增
  `accountNames` 欄位,`forLedger` 一併載入帳戶清單(同樣排除
  `account_group`),`toPromptSection` 多印一行「帳戶:...」。
- **`lib/services/ai/free_chat_router.dart`**:routing systemPrompt 的判斷
  規則從「分類 → categoryName,否則 keyword」擴充為「分類 → categoryName;
  帳戶 → accountName;都不是 → keyword」,並新增一則帳戶查詢的 few-shot 範例。
- **`lib/services/ai/ai_chat_service.dart`**:把通用錯誤兜底文案
  「AI服务暂时不可用,请稍后重试」(簡體)改成「AI 服務暫時無法使用，請稍後再試」
  (繁體台灣用語)。這條訊息涵蓋所有 `AIException`(逾時/限流/4xx-5xx/供應商
  回應格式異常等),本次只調整用語,沒有改錯誤分類或加重試邏輯 —— 那是另一個
  可能值得做但範圍更大的題目(目前完全沒有針對暫時性錯誤的自動重試)。
- **測試**:`test/services/ai/free_chat_tools_test.dart` 新增
  「query_transactions 帳戶解析」群組,涵蓋完全相等比對、退化包含比對、
  `account_group` 不會被命中、查無帳戶時 `resolvedAccounts` 為空四種情境。

## 刻意排除的範圍

- 沒有處理「帳戶群組(合併帳單)底下的子帳戶」自動展開 —— `categoryName` 有
  父分類自動含子分類的邏輯,但帳戶群組的 `parentAccountId` 存的是**syncId
  字串**而非本地 int id,要跟子帳戶關聯需要額外一次解析,而目前先解決的是
  「查真實帳戶名稱查不到」這個更常見的案例。如果之後有人想查「這個合併帳單
  群組底下所有卡加起來花多少」,需要另外處理。
- 沒有加自動重試或把 `AIException` 拆成更細的錯誤分類(逾時 vs 限流 vs
  伺服器錯誤)給使用者看不同文案 —— 這次只按需求把文案改成繁體台灣用語。

## 入口

沒有新增入口,沿用既有的「AI助手」對話頁(`lib/pages/ai/ai_chat_page.dart`)。
