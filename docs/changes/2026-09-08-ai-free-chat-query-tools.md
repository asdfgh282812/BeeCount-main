# AI 自由對話:唯讀查詢工具 + 多輪對話記憶

設計文件:`docs/superpowers/specs/2026-09-08-ai-free-chat-query-tools-design.md`(本地
scratch,未提交,見 [[project_docs_superpowers_gitignored]])。本檔記錄實際落地時
跟設計稿的差異與理由。

## 新增檔案

- `lib/services/ai/free_chat_tools.dart`:4 個唯讀查詢工具的 metadata(`freeChatTools`)
  + `FreeChatToolExecutor`。`FreeChatToolException` 供缺參數/未知工具名時降級用。
- `lib/services/ai/free_chat_router.dart`:`FreeChatRouter.route()`,兩階段
  prompt-JSON 路由,不改動 `AIProviderFactory` 介面(`ChatFn` 型別對齊
  `chat(prompt, {systemPrompt})` 的子集)。

## 修改既有檔案

- `lib/data/repositories/ai_repository.dart` + `local_ai_repository.dart`:新增
  `getRecentMessages(conversationId, {limit})`,依 `createdAt` 升冪回傳最近 N 則。
- `lib/data/repositories/local/local_repository.dart`:補上對應的委派方法 ——
  `LocalRepository` 對 `AIRepository` 的其它方法都是逐一手寫委派給
  `_aiRepo`,不是靠 mixin,所以光改介面 + `LocalAIRepository` 還不夠,漏了這步
  `flutter analyze`/`flutter test` 會直接編譯失敗(`missing implementations`)。
- `lib/services/ai/ai_chat_service.dart`:`processMessage` 新增 `conversationId`
  參數;`_handleFreeChat` 改為委派 `FreeChatRouter`(建構子可選注入,預設用
  `FreeChatRouter(repo: repo)`)。
- `lib/pages/ai/ai_chat_page.dart`:呼叫 `processMessage` 時多帶
  `conversationId: _conversationId`。

## 跟設計稿的差異

**歷史訊息去重**(設計稿沒明確處理):`ai_chat_page.dart` 在呼叫
`chatService.processMessage` **之前**就已經把當前這輪的使用者輸入存進
`Messages` 表(`_sendMessageText` 裡先 `createMessage` 再呼叫 `processMessage`)。
所以 `FreeChatRouter.route()` 呼叫 `getRecentMessages` 時,回傳的最近 N 則訊息
最後一筆通常就是「使用者這一句話」本身。設計稿第 77 行寫
`routingPrompt = 對話紀錄 + "\n使用者：$userInput"`,如果照字面直接接,會讓同一句
話在 prompt 裡出現兩次。實作在 `FreeChatRouter._loadHistoryExcludingCurrentTurn`
裡加了一層防禦:如果歷史紀錄的最後一則是 `role == 'user'` 且
`content == userInput`,就把它從歷史裡去掉,再組 `$歷史\n使用者：$userInput`。
測試:`free_chat_router_test.dart`「歷史紀錄會帶進 routing prompt,且不重複當前
這句輸入」。

**JSON 解析容錯**:沒有直接重用 `lib/ai/core/json_response_parser.dart` 的
`_extractBalancedBlock`/`_cleanupJson`(那兩個方法是 private,且該類是綁定
`BillInfo` 陣列解析語意的),在 `free_chat_router.dart` 裡照抄了同一套
balanced-block 提取 + trailing-comma 清理的手法,回傳型別換成
`Map<String, dynamic>?`。

**日期區間慣例**:專案既有的 `totalsInRange`/`getTransactionsByLedgerInRange` 都是
`[start, end)` 左閉右開(`happenedAt >= start && happenedAt < end`)。工具的
`startDate`/`endDate` 參數語意是「含當天」,所以 executor 內部把 `endDate` 轉成
「隔天 00:00」再傳給 repository,而不是直接把使用者給的 `endDate` 當 exclusive
上界(否則 `endDate` 當天的交易會被漏掉)。

## 沒動的部分(同設計稿)

`lib/ai/`(L1)、資料庫 schema、`AIProviderFactory` 介面全部沒有改動;`query_transactions`
限制 50 筆的邏輯、工具呼叫失敗降級成固定文案、單輪最多 1 次工具呼叫,都照設計稿實作。
