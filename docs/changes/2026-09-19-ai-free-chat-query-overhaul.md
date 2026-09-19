# AI 自由對話:查詢能力全套改善 + 訊息 Markdown 渲染

使用者回報:3.5 上線查詢工具後「能問的問題變多了」,但實測「我復健科至今為止花了
多少錢」仍然答不出來;另外 AI 回覆的 Markdown 符號會原樣顯示。

追查後確認前者**不是模型能力問題**,是三個工程缺陷疊加。以下記錄的是**從 diff 看
不出來的理由**,程式碼本身已有註解的不重複。

---

## 1. 根因:意圖路由把查詢句誤判成記帳句

`ai_chat_service.dart` 舊版:

```dart
final hasAmount = RegExp(r'\d+(?:\.\d+)?').hasMatch(input);
const keywords = ['买','花','消费','支付','记账','付','收入','赚','工资'];
return hasAmount || hasKeyword;
```

「我復健科至今為止**花**了多少錢」命中「花」→ 走 `_handleTransaction` → 提取不到
金額 → 回固定文案「抱歉,未識別到完整的記帳信息」。**整條查詢路徑從來沒被執行過。**
同理「上個月**付**了多少保費」「這個月**收入**多少」。而且關鍵字表是簡體,繁中的
「買/記帳/賺/工資」根本不匹配 —— 真正在觸發的只有「花/付/收入」這幾個簡繁同形的字,
而那三個恰好是查詢動詞。

### 為什麼改成「Layer 0 查詢否決 + Layer 1 AND」而不是只把 OR 改成 AND

**誤判的代價是不對稱的**,這是整個設計的核心理由:

- 誤判成記帳 → 使用者收到一段記帳教學,**完全碰不到查詢工具**,且沒有任何補救機會
- 誤判成查詢 → router 還有 `record_transaction` 決策可以救回來

所以閘門必須偏向放行查詢,光改 AND 不夠 —— 「2026 年總共花多少」同時有數字和「花」,
AND 一樣會誤判。必須有一層**無條件否決**。

新的三層在 `lib/services/ai/ai_chat_intent.dart`(抽成純函式,無 I/O,可單測):

| | 條件 | 去向 |
|---|---|---|
| Layer 0 | 命中查詢標記 | 自由對話(不管有沒有金額) |
| Layer 1 | `hasAmount && hasVerb` | 記帳快路徑,**LLM 往返次數不變** |
| Layer 2 | 其餘 | 交給 router 判斷 |

### 為什麼否決表刻意不收單字「查」「幾」「哪」

它們會出現在正常的記帳句裡:「健康檢**查**花了2000」「花了**幾**百塊」。誤攔記帳的
代價比漏攔查詢高(記帳是主要動作,而且使用者常在收銀台前面用)。需要這些語意時一律
用更長的片語(查詢 / 查一下 / 哪些)。測試裡有對應的回歸案例。

---

## 2. 沒有任何工具能算「關鍵字 X 的總花費」

`query_transactions` 只回明細不回總和,limit 上限 50、截斷只設 `truncated: true`,
模型自行加總樣本會**默默算錯**;`get_spending_summary` 能算總和卻沒有 keyword。
兩者的交集正好是使用者問的那種問題。

### 為什麼不新增一個 `summarize_transactions` 工具

它跟 `query_transactions` 會有大半參數重疊,對一個靠 prompt-JSON 選工具的模型來說,
**兩個高度相似的工具是主要的選錯來源**。更關鍵的是:只要「只回列表的那個工具」還
存在,模型就還是有機會挑到它、拿到截斷的 20 筆、自己加總、算錯 —— 我們正要修的 bug
會從「必然發生」退化成「偶爾發生」,而偶爾發生的數字錯誤比必然發生的更難被發現。

所以改成**一個工具、總額永遠正確、明細只是可選樣本**:

- 彙總(`matchedCount` / `totalExpense` / `totalIncome` / `byCategory`)在
  `take(limit)` **之前**算完。舊版其實握著完整的過濾結果,只是沒拿去加總就丟掉了。
- 樣本包進 `sample: { count, isPartial, transactions }`。舊版 `count` 平鋪在頂層,
  語意在「總筆數」與「回傳筆數」之間含糊。
- 結果 payload 裡帶一行 `note` 明講「總額已涵蓋全部 N 筆,請勿自行加總樣本」。
  **放在 payload 而不是 systemPrompt**,是因為它跟資料在同一個位置,比較擋得住
  「看到陣列就想加總」的反射。
- `byCategory` 順手回傳:同一次迴圈就有,但它讓「復健科跟牙科比呢」這種複合問題
  在單次工具呼叫內就能回答。這是最划算的一個欄位。

`get_spending_summary` 保留(純 SQL 聚合的快路徑,不必扛 keyword),所以仍是 4 個工具。

---

## 3. 沒有「至今為止 / 全部期間」語意

舊版 `startDate`/`endDate` 必填,模型只能亂編一個開始日期。

### 為什麼選「省略日期」而不是哨兵值或 allTime bool

- **哨兵值**(`"all"` / `"1970-01-01"`)最差:模型會發明 `"ALL"` `"*"` `"all_time"`
  `"9999-12-31"` 等變體。沒被認出的要嘛拋例外讓使用者看到「暫時處理不了」,要嘛剛好
  parse 成一個**合法但錯誤**的日期而靜默給錯答案。
- **獨立的 allTime bool** 會出現矛盾狀態 `{"allTime":true,"startDate":"2026-01-01"}`
  —— 而模型確實會這樣寫(它傾向把 schema 裡所有欄位都填滿)。
- **省略欄位**是所有 JSON 行為裡最穩的一個,而且可組合。

實作上**仍然容忍** `allTime: true` 並定義優先序為覆蓋日期:一旦 prompt 裡提到全期間
這個概念,模型就有機率主動發明這個欄位,認得它比讓它落到未知參數被靜默忽略好。

### 真正的安全網是回傳實際區間,不是參數驗證

日期變選填後,模型「忘了填」會靜默給出全期間答案(「這個月花多少」被回答成「過去三年
總共 47 萬」)。防線有兩道,但只有第二道是可靠的:

1. prompt 明確化(與參數改動**同一個 commit**,否則等於只留下風險)
2. 結果帶回 `range.allTime` + `actualFirstDate` / `actualLastDate`。模型看到就會寫成
   「從 2024 年 3 月到現在…」,**使用者自己看得出範圍不對**。零成本,比任何參數驗證有效。

---

## 4. 關鍵字與分類比對

### 簡繁:為什麼靠模型給變體,而不是自維護對照表

完整 OpenCC 表約 3000 字,為了一個查詢功能拉進來成本效益不成立;小型手工表更糟 ——
漏掉的字就是靜默零結果,而且永遠追不完。

改成 `keyword` 接受 `string | array`,prompt 寫明可同時給簡繁變體與同義詞
(`["復健","复健","物理治療"]`)。模型本來就完美知道簡繁對映,而且它**本來就要輸出
這個 JSON**,給陣列不多花任何往返。更關鍵的是它順手解決了對照表永遠做不到的**同義詞**
問題:使用者問「復健科」但備註寫「物理治療」時,只有這條路救得回來。

### 為什麼「分類名摺疊、note/merchant 不摺疊」

這個不對稱是刻意的:摺疊必須對被比對的兩邊同時套用,而 SQL `LIKE` 做不到字元摺疊 ——
要對 note/merchant 摺疊就得把所有列撈回 Dart 比對,等於放棄索引(會擋住未來換成 SQL
搜尋的路)。而 `Categories` 表只有幾十列、本來就整批載入,摺疊它是零邊際成本。
使用者舉的例子「復健科」正是分類名稱。

摺疊表在 `lib/utils/zh_variants.dart`,102 組記帳語境常用字,定位是變體清單的**補網**
而非主要手段。

### 分類名稱:為什麼是分級解析而不是單純換成 contains

舊版 `catName != categoryName` 完全相等,模型得一字不差;直接換成 contains 又會過度
匹配(`"餐"` 同時命中餐飲/餐廳/早餐)。分級解析的關鍵是「**完全相等優先,有就不往下**」:
`categoryName: "餐飲"` 只回餐飲;`"餐"` 沒有完全相等才退化成雙向包含。

三個配套:
- `resolvedCategories` 回進 JSON,讓回覆能說「我把復健科、復健治療都算進去了」。
  **這是模糊比對唯一可以接受的前提** —— 使用者能立刻看出算錯並修正。
- **父分類自動含子分類**(`Categories.parentId`)。這不是優化是正確性:否則
  「醫療總共花多少」會漏掉所有二級分類,嚴重低估。
- `type` 參數消歧同名分類(「獎金」在收支兩側都可能存在)。

### N+1

舊版在迴圈裡逐筆 `getCategoryById` / `getAccount`,而且 `getCategoryById` 跑在
`categoryName` 過濾**之前** —— 指定分類查詢時絕大多數列會在下一行被 `continue` 丟掉,
那次查詢是純浪費(三年帳本查一個分類可能是數千次無用查詢)。改成迴圈外建 Map。
帳戶 Map 只有樣本用得到,`limit: 0` 時完全不載入。
測試 `不再有 N+1` 直接斷言 `getCategoryById` 呼叫次數為 **0**。

---

## 5. 單輪多工具呼叫

改成支援 `{"type":"tool_call","tools":[...]}`(上限 3,舊的單一 `tool` 仍相容),
`Future.wait` 並行 —— 全部唯讀、彼此獨立、打的是行程內 SQLite。

**LLM 往返次數完全不變**(routing 1 次 + answer 1 次),所以複合問題「復健科跟牙科
比呢」是零延遲代價解決的。這是本次 CP 值最高的一項。

**刻意不做 observation loop**(answer 階段再回頭呼叫工具):每多一輪就多一次完整網路
往返(手機上 2-5 秒),而 3 輪以上的問題使用者自己分兩句問會更快也更容易看懂。加上
`byCategory` 免費回傳之後,需要鏈式查詢的情境已經很少。等實際 log 顯示有需要再說。

**部分失敗不再中止整輪**:舊版只要任一工具拋例外,整回合就死在「暫時處理不了」。
現在失敗的那格填 `error`,其他照常,answer 階段仍跑 —— 模型可以說「預算我查不到,
但支出的部分是…」。只有**全部**失敗才回固定文案。這對體感的改善不輸主功能。

---

## 6. `record_transaction`:為什麼它不是 executor 的工具

`FreeChatToolExecutor` 是 `const`、只吃 `(repo, ledgerId)`,且整批工具刻意設計成唯讀
(原始碼註解明講「沒有授權彈窗的必要」)。把寫入塞進去會破壞這個不變量,而且它拿不到
`l10n`、也拿不到 `resolveMissingAccount` / `resolveMissingProject` —— 那兩個是綁
`BuildContext`、會彈 `AccountCardPicker` / `ProjectPicker` 的 closure。

改成 **router 回決策、service 執行**:`route()` 回傳型別從 `Future<String>` 改成
`Future<FreeChatOutcome>`(sealed:`FreeChatAnswer` / `FreeChatBookkeepingRequest`),
`AIChatService._handleFreeChat` 加分支轉呼叫 `_handleTransaction`。那兩個 callback
本來就是 `processMessage` 的參數,service 一直握著,**完全不需要傳進 router**。
分層也乾淨:router 只做決策,service 做編排。`ai_chat_page.dart` 一行都沒改。

`_handleTransaction` 新增 `fromRouter` / `fallbackText`:走這條路徑失敗時回模型自己寫
的自然語言,而不是那段記帳教學 —— 模型已經誤判過一次,再丟教學給正在問問題的人只會更糟。

---

## 7. routing prompt 補上帳本分類清單

修掉路由 bug 之後,這是**最大的剩餘失敗模式**:模型不知道「復健科」是分類名、商家名
還是隨手寫的備註,只能瞎猜要填 `categoryName` 還是 `keyword`。給了清單它就能選對參數
(走分類解析、含子分類、精準),不會發明不存在的分類名,甚至能在帳本根本沒有那個分類
時直接回答而**不呼叫工具** —— 反而省下一次往返。成本約 120-200 token。

新檔 `lib/services/ai/free_chat_context.dart`,放 L2 不是 `lib/ai/`(L1 不得有
Repository 依賴)。**刻意不重用 `AiExtractionContext.forLedger`**:那個是記帳側的,
順帶查帳戶+幣種、讀 SharedPreferences 自訂模板、讀專案指派模式 —— routing 一個都不
需要,而且會把 SharedPreferences 拉進每一則訊息的路徑。

**不做快取**:每則訊息多一次小查詢可以忽略;快取一份過期的分類清單(使用者剛新增分類
卻查不到)是比多一次查詢糟得多的 bug。載入失敗會降級成空上下文,不讓整則訊息失敗。

answer prompt 也補了反幻覺護欄,其中「`matchedCount` 為 0 就直接說找不到,不要編造
數字」最重要 —— 空結果時模型編一個數字出來,比任何其他失敗模式都危險,因為使用者
**沒有任何線索知道它是假的**。

---

## 8. 訊息 Markdown 渲染

**入口點:AI 記帳 → 對話視窗,AI 回覆的訊息氣泡。**

專案原本連傳遞依賴都沒有任何 markdown 套件,訊息最終走 `TypewriterText`,其 build 就是
一個純 `Text`,所以 `**粗體**` 的星號會原樣顯示。

### 為什麼自寫而不是引入套件

官方 `flutter_markdown` 已停止維護;社群 fork 與 `gpt_markdown` 都要評估與專案工具鏈
的相容性(pubspec 裡已有因為 SDK constraint 而被迫鎖版的前例)。而 LLM 實際會產出的
語法子集很窄,自寫約 400 行、零依賴,還能**完全接上 `BeeTokens` 與呼叫端傳入的
`.scaled()` 字級**,不破壞暗色模式與全域字級縮放。

拆成兩個檔:`markdown_parser.dart`(純 Dart,無 Flutter 依賴,可獨立單測)與
`markdown_text.dart`(widget)。所有樣式都從呼叫端傳入的 base `TextStyle` 衍生,
渲染器內不硬編碼任何顏色或字級。

**唯一的硬性要求:未知語法原樣輸出,絕不吞字。** 渲染器再不完整,也不能讓使用者看到
的字比原文少。測試裡有一整組「絕不吞字」的案例(未閉合的 `**`、孤兒反引號、
snake_case 不被當斜體、像表格但沒有分隔列…)。

### 打字機動畫怎麼共存

逐字動畫期間餵進去的常是半截語法(只打出 `**粗`),即時解析會閃爍。所以
**動畫播放中用純 `Text`,播完才切換成 Markdown**:動畫結束時 `onComplete` 本來就會
清掉 `_animatingMessageId`,重建後自然走到 `MarkdownText` 這一支 —— `TypewriterText`
一行都沒改。使用者自己打的字一律不做 Markdown 解析(輸入應照原樣呈現)。

長按複製仍然複製 `message.content` 原文,行為不變。

`_buildAnswerSystemPrompt` 同步告訴模型可以用簡單 Markdown(這句**必須在渲染器上線
之後才加**,否則符號只會更常出現)。

---

## 行為變更與刻意不修的部分

### ⚠️ 行為變更:`query_transactions` 現在排除 `excludeFromStats` 的交易

這修掉一個**既有的口徑不一致**:`totalsInRange` 的 SQL 帶了
`AND exclude_from_stats = 0`,但 `getTransactionsByLedgerInRange` 完全沒有這個過濾。
所以在此之前,`get_spending_summary` 跟 `query_transactions` 對**同一個區間**的認知
就已經不同了。現在統一與統計頁一致(排除),同時也排除 `type == 'transfer'`。

### 刻意不修(但必須記錄 —— 這類錯是靜默的數字誤差,不會有人報 bug)

- **拆帳交易**:`totalsByCategory` 對 `hasSplits = true` 會改用 `transaction_splits`
  逐筆累加並按 `nativeAmount/amount` 比例縮放。本次的分類過濾是直接篩主表的
  `categoryId`,**會漏掉拆帳交易的子分類 → 有拆帳的帳本,分類彙總會低估**。
  要補的話是 `OR id IN (SELECT transaction_id FROM transaction_splits WHERE ...)`,
  但金額還要按比例縮放,複雜度不小,適合獨立一輪。
- **共享帳本的 `categorySyncIdOverride`**:Editor 記的交易 `categoryId` 是 null,
  分類資訊在 override 欄位。這種交易的分類過濾必定漏,樣本裡的 `category` 也會是 null。
- **效能**:目前仍是「撈區間 → Dart 過濾」,全期間查詢會把整個帳本載進記憶體
  (重度使用者三年可能上萬筆)。正確性問題已經關掉,效能留給後續改成 repository 層的
  SQL 搜尋方法(`searchTotals` / `searchTransactions`)。屆時的驗收條件是
  **本次寫的測試一行不改仍全過** —— 那是「換底層沒有偷偷改語意」的唯一可靠證明。
  注意:要記得在 `local_repository.dart` 補委派方法,`LocalRepository` 對這些介面是
  逐一手寫委派而非 mixin,漏掉會直接編譯失敗(見
  `2026-09-08-ai-free-chat-query-tools.md` 已經踩過的同一個坑)。

### 已知缺口(建議另案)

- `_buildRoutingSystemPrompt` / `_buildAnswerSystemPrompt` 都是
  `isEn = languageCode == 'en'` 二分,**韓文使用者會收到繁中 prompt**。
- `AIChatService._handleTransaction` 提取失敗的文案是硬編碼簡中,`l10n` 明明已經
  傳進來了。

---

## 測試

| 檔案 | 覆蓋 |
|---|---|
| `test/services/ai/ai_chat_intent_test.dart` | **新** 33 例:查詢否決、記帳快路徑不退化、AND 條件、不誤攔「檢查」 |
| `test/services/ai/ai_chat_query_e2e_test.dart` | **新** 端到端驗收:「我復健科至今為止花了多少錢」走到查詢工具、總額涵蓋全部 37 筆 18,400、記帳句仍走記帳 |
| `test/services/ai/free_chat_tools_test.dart` | 擴充:彙總不受 limit 截斷、全期間、關鍵字命中分類名、簡繁互通、分類分級解析、父含子、統計口徑、N+1 為 0 |
| `test/services/ai/free_chat_router_test.dart` | 擴充:工具陣列、上限、部分失敗、全失敗、`record_transaction`、prompt 內容 |
| `test/utils/zh_variants_test.dart` | **新** 摺疊對稱性、未收錄字原樣通過 |
| `test/widgets/ai/markdown_parser_test.dart` | **新** 行內/區塊語法、一整組「絕不吞字」 |
| `test/widgets/ai/markdown_text_widget_test.dart` | **新** 實際繪製、暗色模式、畸形表格不拋例外 |

`flutter analyze` 在本次改動的檔案上零問題(專案既有 884 項未動)。
`flutter test` 1439 通過;`test/widgets/calendar_month_jump_test.dart` 的 1 項失敗
在本次改動**之前就已存在**(已用 `git stash` 確認),與此無關。
