# AI 對話介面改版 + 可選的「連續記憶」

## 入口
我的 → AI 助手(對話頁)→ 右上角 🧠 記憶圖示(開/關連續記憶)。What's New 3.7.0 也有一則說明。

## 為什麼
1. 對話頁只有最基本的氣泡,視覺陽春。
2. 原本 `FreeChatRouter` **一律**帶最近 8 則歷史進 prompt,沒有開關。Gemini 免費 API 額度小,長對話容易被限流/失敗,使用者無法關掉。改成「預設不帶歷史、使用者自己開」。

## 變更
- `lib/ai/providers/ai_constants.dart`:新增 `keyAiChatMemoryEnabled`。
- `lib/providers/ai_config_providers.dart`:`AIChatMemoryNotifier` / `aiChatMemoryProvider`(StateNotifier,SharedPreferences,預設 false)。**本機設定,不走 `onConfigChanged` 同步**——是否省 token 取決於各裝置用的服務商/額度。
- `lib/services/ai/free_chat_router.dart`:`route(useMemory)`;false 時歷史為空。router 預設 true 以保持既有測試/呼叫行為,真正的預設關閉由 `AIChatService.processMessage(useMemory: false)` 負責。
- `lib/services/ai/ai_chat_service.dart`:`useMemory` 一路傳到 router。**記帳意圖(`AiBookkeeper`)本來就不帶歷史,不受影響。**
- `lib/pages/ai/ai_chat_page.dart`:
  - 開啟記憶**每次**都跳警告對話框(token 增加、免費 API 易限流、對話內容會送到服務商),確認才開;關閉不需確認。開啟時輸入框上方有綠色提示列。
  - 視覺:頂部主題色柔光漸層背景、漸層發光頭像、使用者氣泡為主題色漸層、AI 氣泡為玻璃質感+主題色細邊框(不對稱圓角)、空狀態、三點脈動思考動畫、毛玻璃輸入區(聚焦時發光)、圓形漸層送出鈕。全部用 `BeeTokens` + 主題色,深色模式照常。
- `lib/widgets/ai/ai_typing_indicator.dart`:新增三點動畫元件。
- l10n:只補 `app_en.arb` / `app_zh_TW.arb`(依既有政策)。

## 取捨 / 刻意不做
- 記憶範圍沿用既有「最近 8 則」,未做可調數字,避免多一個設定。
- 開關放在對話頁而非 AI 設定頁,因為使用者在長對話出問題時就在那一頁。
- 銷毀歷史仍用既有「清除記錄」按鈕。
