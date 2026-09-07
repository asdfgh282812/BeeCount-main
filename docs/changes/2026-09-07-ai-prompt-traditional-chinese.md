# AI 記帳提示詞改為繁體中文（台灣用語）

## 為什麼

`lib/ai/core/prompt_builder.dart` 的 `defaultTemplate` 等提示詞內容原本是簡體中文，且**不隨 App 語系切換**——不管使用者介面選哪個語言，送給 AI 的記帳抽取提示詞永遠是同一份簡體模板。專案的 l10n 政策已改為只維護 `app_en.arb` + `app_zh_TW.arb`（見 `docs/changes/` 內既有記錄），不再對外提供簡體介面，所以這份寫死的簡體提示詞已經和產品定位不一致，直接影響台灣使用者體驗（例如提示詞裡的例子用「建行」「零錢包」「朋友圈」等中國大陸特有名詞/App，對台灣使用者沒有意義）。

## 改了什麼

只動「真正會送進 AI 提示詞裡的文字」，不動程式內部註解（那些維持原本簡體，屬於另一件事）：

- [`lib/ai/core/prompt_builder.dart`](../../lib/ai/core/prompt_builder.dart)：`defaultTemplate`、`_currencyFieldSpec`、`billGuardForImage`、`_hardcodedCategoryHint`，以及 `_buildCategoryHint`/`_buildAccountHint`/`_buildCurrencyHint` 動態組出的標籤文字（分類清單、帳戶清單、帳本主要幣別、幣別對照）全部改成繁體中文。順帶把幾個中國大陸特有情境詞換成台灣對照：「建行/零錢包」→「台新/街口」、「拼單」→「合購」、「地鐵」→「捷運」、「朋友圈、微博」→「社群動態、社群網站」，範例本位幣的示範金額符號從 `￥` 改成 `NT$`。
  - Hardcoded fallback 分類清單改用 app 實際的繁體預設分類名稱（對照 `lib/services/data/seed_service.dart` 的 key 順序 + `app_zh_TW.arb` 的 `categoryExpenseList`/`categoryIncomeList`），「工資」「收紅包」等用詞與 app 既有分類保持一致，不是另外自創譯名。
- [`lib/ai/core/ai_extraction_engine.dart`](../../lib/ai/core/ai_extraction_engine.dart)：文字/圖片兩個管道傳給 `PromptBuilder.build` 的 `inputSource` 描述改繁體（僅改這兩個字串，其餘 log 訊息不動——log 不是送給 AI 的內容，也不是使用者可見文字）。
- [`lib/services/ai/ai_chat_service.dart`](../../lib/services/ai/ai_chat_service.dart)：`_handleFreeChat` 送給 AI 的中文 `systemPrompt` 改繁體（英文分支不動；同檔案裡其他面向使用者的錯誤訊息字串——如「抱歉,處理失敗」——維持原狀，屬於一般 UI 文案而非 AI 提示詞，超出本次範圍）。
- [`lib/services/ai/ai_quick_command_service.dart`](../../lib/services/ai/ai_quick_command_service.dart)：`_getMonthlyStatsText`/`_getCategoryStatsText`/`_getRecentTransactionsText`/`_getRecentTrendsText` 組出、會被塞進快捷指令 prompt（`[monthlyStats]` 等佔位符）的統計摘要文字改繁體。快捷指令本身的模板文字走 `AppLocalizations`（`aiQuickCommandXxxPrompt` key），不在本次改動範圍內，本來就已經是 arb 資源。
- [`lib/utils/currency_aliases.dart`](../../lib/utils/currency_aliases.dart)：`_zhAliases` 對照表本身**沒有刪除任何既有別名**（避免使用者打簡體幣別詞時解析失效），只調整同一幣別底下多個別名的登記順序，讓繁體/台灣慣用說法排在最前面——這決定了 `zhAliasesForCode(code, limit: 1)` 回傳的「規範名」，也就是 `PromptBuilder._buildCurrencyHint` 塞進提示詞「幣別對照」那一行實際顯示給 AI 的中文名稱（例如 JPY 從顯示「日元」改成「日圓」、HKD 從「港币」改成「港幣」）。另外新增「新台幣」「台幣」「泰銖」「沙特里亞爾」等原本完全沒有繁體寫法登記的別名。

## 刻意不動的部分

- 程式內部的開發者註解（doc comment）維持簡體，不在「提示詞」範圍內，牽動面太廣，另案處理。
- `ai_chat_service.dart`、`image_billing_helper.dart`、`voice_billing_helper.dart` 等檔案裡面向使用者的一般 UI 提示字串（toast、錯誤訊息）目前多半是寫死的簡體中文、未走 `AppLocalizations`，這是既有的技術債，和「AI 提示詞」是兩件事，本次不處理。
- `ai_quick_command_service.dart` 的快捷指令模板本體已經是走 `app_zh_TW.arb`，沒有需要改的簡體字串。

## 測試

- [`test/ai/core/prompt_builder_test.dart`](../../test/ai/core/prompt_builder_test.dart) 原本的斷言是寫死的簡體字串（含一條明確鎖住「繁體變體只用於解析、不該出現在 prompt 裡」的迴歸測試），跟著改成繁體對應字串，並把那條迴歸測試的方向反過來鎖「簡體變體不該出現在 prompt 裡」。
- `test/utils/currency_aliases_test.dart` 全部針對 `currencyCodeFromAlias`（文字→代碼的解析方向）斷言，別名表重新排序不影響解析結果，不需要改動，已重跑確認全過。
- `flutter test test/ai/ test/services/ai/`、`flutter test test/ai/core/prompt_builder_test.dart test/utils/currency_aliases_test.dart`、`flutter analyze` 均已跑過，全數通過。
