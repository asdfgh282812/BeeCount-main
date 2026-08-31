# 「建議」分頁 + 智慧預設(帳戶/備註/轉帳/回饋)+ 拉到底送出

日期:2026-09-01
背景:使用者提供的截圖是理想化的 UI 概念(多一個「建議」分頁、應收/應付拆成
獨立分頁),但那不是目前實際畫面——確認過後,這次只新增「建議」分頁,不拆
分既有的「欠款」分頁。核心訴求:新增記錄時系統依歷史訊號自動猜測最可能的
類別/帳戶/回饋,減少手動選擇;另外加一個「從下往上拉到底送出」的手勢。

## 1. DB migration v48:回饋學習快取表 + 交易排序索引

**改了什麼**:`lib/data/db.dart` `schemaVersion` 47→48。新增 `RewardChoiceCaches`
表(`ledgerId, categoryId, accountId, rewardRuleIdsJson, updatedAt`),唯一
索引 `idx_reward_choice_caches_key(ledger_id, category_id, account_id)`;
新增索引 `idx_transactions_ledger_type_happened(ledger_id, type, happened_at)`。
兩者都同時加進 `onUpgrade` 的 `if (from < 48)` 區塊「和」`onCreate` 區塊。

**為什麼**:過程中發現一個既有的架構缺口——`transactions`/`accounts` 等表
歷史上所有靠 raw SQL `customStatement` 加的索引(`idx_transactions_sync_id`
等)都只在 `onUpgrade` 建,`onCreate`(全新安裝直接建表,不會跑 onUpgrade)
完全沒有補建。用 `BeeDatabase.forTesting(NativeDatabase.memory())` 驗證後
確認:全新安裝的資料庫上,這些索引全部不存在。這是舊有技術債,超出本次範圍
不去動它,但新加的這兩個索引(尤其唯一索引本身是資料正確性約束,不只是效能)
沒有理由重蹈覆轍,所以同時補進 `onCreate`。

`transactions` 原本只有 `idx_transactions_sync_id` 一個索引,`getNoteHistory`/
`getRecentDistinctAmounts`/新的建議分頁查詢全部是 `WHERE ledger_id=?`
全表掃描,一併補上複合索引。

**連帶修正**:`test/data/migration_v46_test.dart`/`migration_v47_test.dart`/
`sync_pull_errors_schema_test.dart` 原本斷言 `schemaVersion` 等於一個寫死的
數字,每次版本推進都要手動改——改成 `greaterThanOrEqualTo`,這樣以後新增
migration 不會再讓一堆歷史測試跟著失敗。新增 `test/data/migration_v48_test.dart`
驗證新表/新索引存在 + 唯一約束生效。

## 2. 拉到底送出手勢

**改了什麼**:新檔 `lib/widgets/biz/pull_to_submit_scroll_view.dart`
(`PullToSubmitScrollView`)。包住表單既有的 `SingleChildScrollView`,用
`NotificationListener<ScrollNotification>` 偵測 `OverscrollNotification`
(限定 `dragDetails != null`,排除放開後的回彈動畫)累積拉動距離,超過閾值
(72px)標記 `_armed` 並觸發 `HapticFeedback.mediumImpact()`;`ScrollEndNotification`
時若已 armed 才呼叫 `onSubmit`——直接是表單原本的 `_submit` 函式本身,天然
繼承所有既有驗證/錯誤 toast,這個 widget 不需要知道「為什麼不能存」。強制
`BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())`,讓 Android
也能可靠產生 overscroll(代價是這幾個表單頁在 Android 上滑動手感變成 iOS
式彈性回彈,跟其他頁面不一致——這是跟使用者確認過、刻意接受的取捨)。

套用到 `lib/widgets/biz/transaction_entry_form.dart`(支出/收入共用)、
`lib/widgets/transaction/transfer_form.dart`、`lib/widgets/transaction/debt_entry_form.dart`
——三個檔案都只是把原本的 `SingleChildScrollView` 換成 `PullToSubmitScrollView`,
`child` 內容不變。

新增 l10n key `pullToSubmitHint`(「上拉送出」)/`pullToSubmitRelease`
(「放開送出」)。

## 3. 轉帳分頁自動代入最近兩個帳戶

**改了什麼**:`TransactionRepository`/`LocalTransactionRepository`/
`LocalRepository` 新增 `getLastTransferAccounts({ledgerId})`——查該帳本最近
一筆 `type='transfer'` 交易的 `account_id`/`to_account_id`。
`lib/widgets/transaction/transfer_form.dart` `initState`:全新轉帳(沒有
`initialFromAccountId`/`initialToAccountId`、不是編輯模式)時呼叫新方法
`_loadLastUsedTransferAccounts()`,驗證兩個帳戶都存在且未隱藏後靜默代入。

**為什麼**:轉帳的來源/目的帳戶組合通常高度重複(例如「錢包→零錢包」),
每次都要手動選兩次是多餘的摩擦。

## 4. 依類別自動代入常用帳戶

**改了什麼**:新增 `getMostUsedAccountForCategory({ledgerId, categoryId})`
(依筆數、同筆數再依最近使用時間排序)。`lib/widgets/biz/transaction_entry_form.dart`
新增 `_accountManuallySet` 旗標(在 `_openAccountPicker`、`_onRecommendationTapped`
內設為 true,代表使用者這次已經主動選過帳戶,之後不再被自動覆蓋),新增
`_maybeApplyPerCategoryAccountDefault()`,在 `_onCategoryChanged` 觸發時呼叫
(一般類別格 + 「建議」分頁點選都會觸發)——非編輯模式、非已指定初始帳戶、
非已手動選過帳戶時才靜默代入,語意上比照既有 `_loadDefaultAccount`(靜默
代入,不是先高亮再等確認)。

## 5. 「建議」分頁 + 排序演算法 + 備註範圍隨類別收斂

**改了什麼**:
- 新檔 `lib/widgets/biz/suggested_entry_tab.dart`(`SuggestedEntryTab`)+
  `lib/widgets/biz/suggested_category_grid.dart`——只渲染一個依分數排序的
  扁平類別格(重用 `CategoryIconWidget`,視覺沿用既有 `BeeTokens.surfaceCategoryIcon`
  配色,沒有另外發明一套顏色系統)。點類別後透過既有的跨分頁 GlobalKey
  呼叫模式(比照 `applySharedFields`)呼叫支出表單新增的公開方法
  `TransactionEntryFormState.selectCategoryFromSuggestion(c)`,再
  `_tab.animateTo(1)` 切過去——「建議」分頁完全不複製一份金額/帳戶邏輯。
- `lib/pages/transaction/transaction_editor_page.dart`:`TabController`
  4→5,分頁順序 建議(0)/支出(1)/收入(2)/轉帳(3)/欠款(4),所有原本以
  index 判斷分頁的地方(落地分頁、`_exportSharedFields`/`_applySharedFields`
  的 `case`)全部 +1。新增落地規則:非編輯模式、無指定分類、`initialKind
  == 'expense'`(即首頁「記一筆」入口)時直接落地建議分頁——這是跟使用者
  確認過的預期行為,會改變目前最常用入口的預設畫面。新增 l10n key
  `suggestedTabLabel`(「建議」)/`suggestedTabEmpty`。
- 新檔 `lib/models/category_suggestion.dart`(`CategoryUsageSignal`/
  `CategorySuggestionScore`)、`lib/services/data/category_suggestion_service.dart`
  (`CategorySuggestionService`,比照 `NoteHistoryService` 的靜態方法結構)、
  `lib/providers/suggestion_providers.dart`(`categorySuggestionsProvider`,
  `FutureProvider.autoDispose`)。`TransactionRepository` 新增
  `getCategoryUsageSignals({ledgerId, kind, since, limit})`,查最近 90 天
  (或 500 筆,取先達到者)的 `(category_id, happened_at, account_id, note)`。

  **評分公式**(每個訊號正規化到 0~1,`budgetPenalty` 是乘法懲罰非加項):
  ```
  score = budgetPenalty × (0.40·recencyFreq + 0.25·timeOfDay
                          + 0.10·dayOfWeek + 0.15·accountContext
                          + 0.10·noteText)
  ```
  - `recencyFreq`:每筆歷史紀錄依 14 天半衰期指數衰減後加總,除以最大值正規化。
  - `timeOfDay`/`dayOfWeek`:條件機率(此分類落在當前時段/星期的比例,而非
    原始次數)——避免「整體最常用」的分類永遠贏過「只在特定時段用、但那個
    時段命中率很高」的分類。
  - `accountContext`:此分類歷史紀錄中使用目前情境帳戶的比例。
  - `noteText`:進行中備註/商家文字跟歷史備註的字詞重疊比例(冷啟動通常
    為 0,權重最低,屬次要訊號)。
  - `budgetPenalty`:預算使用率 ≥1.0 懲罰 0.3、≥0.9 懲罰 0.6(沿用
    `budget_repository.dart` 既有的 danger/exceeded 門檻),抑制「這個分類
    這期已經超支了,先別再建議」。

  沒有任何歷史紀錄(冷啟動)時退回 `getUsableCategories('expense')`(全部
  可記帳分類,不排序)。

- `lib/widgets/biz/transaction_entry_form.dart` `_onCategoryChanged` 新增
  `bool viaSuggestion` 參數,`_loadRecentNotes` 新增 `scopeOverride`——從
  「建議」分頁點類別過來時,強制這一次用 `NoteHistoryScope.currentCategory`
  (不管使用者的全域備註範圍設定),讓備註歷史只顯示這個類別過去的紀錄。
  **一次性**:同一次記帳中若之後手動改選別的類別,備註範圍還原回全域設定
  (跟使用者確認過的行為)。

**為什麼算法只做這 5 個訊號**:跟使用者討論過延伸方向(地理位置、預算超支
提示),決定聚焦時間/帳戶/金額脈絡/備註 + 星期幾 + 預算超支提示,暫不做
地理位置(需要額外定位權限,牽涉隱私授權流程,超出這次範圍)。

## 6. 回饋規則學習快取(SwipeSmart 整合的延伸)

**改了什麼**:新增 `RewardChoiceCacheRepository` 接口 + `LocalRewardChoiceCacheRepository`
實作(掛進 `BaseRepository`/`LocalRepository`,比照 `CardRewardRuleRepository`
的既有分工)。`lib/widgets/biz/transaction_entry_form.dart`:
- `_openRewardRuleSelector`(既有的手動選回饋規則選單)選完後呼叫新增的
  `_rememberRewardChoice`——非空清單 `upsertRewardChoice`,空清單
  `clearRewardChoice`(直接刪列,語意上等同「從未設定過」,呼叫端本來就把
  null 跟空清單一視同仁,見 `_maybeAutoApplyRewardCache` 的判斷)。
- 新增 `_maybeAutoApplyRewardCache()`:類別+帳戶皆已知、這次還沒選過回饋
  規則時,查快取並用 `cardRewardRulesForAccountProvider` 過濾掉已失效的
  規則 id 後代入。呼叫點:依類別代入帳戶之後、手動開帳戶選單之後、點
  SwipeSmart 推薦卡片之後、切分頁同步共用欄位之後。

**範圍刻意收窄(跟使用者確認過)**:SwipeSmart 雲端卡片推薦點選
(`_onRecommendationTapped`)**只代入帳戶,不寫入快取**——它是即時查詢
雲端 API 的結果,沒有對應到本機 `CardRewardRules.syncId`,無從得知「使用者
選了哪條回饋規則」。只有「手動選回饋規則」那個選單能寫入學習快取。

## 測試

新增:`test/data/migration_v48_test.dart`、
`test/repositories/category_suggestion_queries_test.dart`(3 個新
repository 查詢)、`test/repositories/reward_choice_cache_repository_test.dart`、
`test/services/data/category_suggestion_service_test.dart`(`computeScores`
純函式的時間衰減/時段/星期/帳戶情境/預算懲罰各項訊號 + `getSuggestedCategories`
的冷啟動 fallback)。修正 `test/widgets/transaction_editor_page_tab_sync_test.dart`
——「建議」分頁上線後,全新支出預設落地在建議分頁而非支出分頁,兩個既有測試
案例補上「先切到支出分頁」的步驟。

全專案 `flutter test`(954 個測試)、`flutter analyze` 均通過。UI 互動驗證
(建議分頁點選、拉到底送出手勢)受限於本機 iOS 模擬器工具鏈問題(Xcode
未經 `xcode-select` 選定,修復需要使用者密碼,無法由 agent 自行執行)未能
完成點擊互動驗證,僅確認 App 能在模擬器上正常建置/啟動;使用者確認目前的
自動化測試覆蓋已足夠。

## 未做的事 / 待辦

- l10n:本次新增的 key 只寫進 `app_en.arb`/`app_zh_TW.arb`(依專案目前政策,
  不再維護 `app_zh.arb`/`app_ko.arb`)。
- Phase 5(建議分頁)是本次改動中風險最集中的一塊,建議獨立 PR/QA 重點
  真機測試「建議分頁 → 點類別 → 跳轉支出分頁 → 備註範圍收斂」這條路徑,
  以及拉到底送出手勢在 iOS/Android 真機上的手感。

## 後續修正(2026-09-01,真機試用回報 3 個問題)

使用者在 iOS 真機上實際試用「建議」分頁後回報三個問題,以下逐一記錄根因
與修法:

**1. 建議清單應該只顯示前 10 個,不用全部塞出來。**
[lib/services/data/category_suggestion_service.dart](lib/services/data/category_suggestion_service.dart)
新增 `maxSuggestions = 10`,`getSuggestedCategories` 冷啟動 fallback
(`usable.take(10)`)跟排序後的正常路徑(`ranked.take(10)`)都套用,行為
一致。

**2. 點第一次的建議類別,不會自動代入分類,反而跳到支出分頁「展開全部
分類」的狀態(看起來像完全沒反應)。**

根因:`TabBarView` 底層是 `PageView`,分頁只有捲到 cache 範圍內才會真的
build 出來——`SuggestedEntryTab`(index 0)點類別的當下,支出分頁
(index 1)的 `GlobalKey<TransactionEntryFormState>.currentState` 通常還是
`null`。原本的呼叫順序是「先呼叫 `selectCategoryFromSuggestion`(整個
no-op,因為 state 是 null)→ 再 `_tab.animateTo(1)`」,所以使用者看到的
永遠是支出分頁全新 build 出來的預設空白狀態(= 未選類別時的「展開全部
分類」),完全沒吃到剛剛點的建議類別。

這其實跟 `_applySharedFieldsWhenReady`(切分頁時同步共用欄位)是同一個
時序問題,專案裡已經有解法可以照搬:[lib/pages/transaction/transaction_editor_page.dart](lib/pages/transaction/transaction_editor_page.dart)
新增 `_selectSuggestedCategoryWhenReady(Category c, {attemptsLeft = 30})`,
改成「先 `_tab.animateTo(1)` 觸發切頁 → 每一幀用 `addPostFrameCallback`
檢查 `_expenseFormKey.currentState` 是否已經 mount,mount 好才呼叫
`selectCategoryFromSuggestion`,還沒好就排下一幀繼續等,最多等 30 幀
(~500ms,遠超過切頁動畫時長 300ms)」。

**3. 選了類別後,名稱(備註)欄位左邊的歷史圖示、商家欄位都沒有「常用」
清單可以選,只有金額有跳出常用金額 chips。**

- 名稱欄位那部分其實是問題 2 的連帶症狀:因為類別根本沒選到,
  `_onCategoryChanged` 沒被真的觸發,`_loadRecentNotes` 自然拿不到任何
  分類範圍內的備註歷史。問題 2 修好後這裡會自動一併恢復——但要注意這是
  「歷史圖示出現、點開彈窗選」,不是文字直接自動填入(跟 UI 既有設計
  一致,不是本次改動範圍)。
- 商家欄位則是原本就完全沒有「常用商家」這個功能(v33 加欄位以來一直是
  純自由輸入框)。跟使用者確認後,比照名稱欄位補上同款「依分類記住常用
  商家」機制:
  - [lib/models/merchant_history.dart](lib/models/merchant_history.dart)新增
    `MerchantHistoryEntry`(跟 `NoteHistoryEntry` 同形狀,但不需要
    `NoteHistoryScope`/`NoteHistorySort` 那組使用者可調設定——商家歷史恆
    依分類過濾、恆按使用次數排序,沒有全域偏好設定的必要)。
  - `TransactionRepository.getMerchantHistory` 介面 +
    `LocalTransactionRepository` 實作(SQL 寫法照抄 `getNoteHistory`,
    改成聚合 `merchant` 欄位)+ `LocalRepository` 轉發。
  - [lib/services/data/merchant_history_service.dart](lib/services/data/merchant_history_service.dart)
    (`MerchantHistoryService.getHistoryMerchants`)+
    [lib/widgets/biz/merchant_picker_dialog.dart](lib/widgets/biz/merchant_picker_dialog.dart)
    (`MerchantPickerDialog`,UI 版面照抄 `NotePickerDialog`)。
  - `transaction_entry_form.dart`:新增 `_frequentMerchants` +
    `_loadRecentMerchants()`,掛進 `_onCategoryChanged`(跟 `_loadRecentNotes`
    同一個觸發點,所以建議分頁選類別、一般類別格選類別、編輯模式回顯都會
    自動套用);商家欄位的 `prefixIcon` 比照名稱欄位,有歷史紀錄時顯示
    歷史圖示點開 `MerchantPickerDialog`,沒有歷史紀錄時維持原本的商店
    icon。
  - l10n 新增 `appearanceMerchantHistory`(商家歷史彈窗標題),同樣只寫
    `app_en.arb`/`app_zh_TW.arb`。

### 測試

新增 `test/repositories/merchant_history_test.dart`(`getMerchantHistory`
依分類過濾/排序/空白商家不納入統計、`MerchantHistoryService` 無分類時
退回全帳本),`test/services/data/category_suggestion_service_test.dart`
補一個「可用分類超過 10 個時只回傳前 10 個」的案例(冷啟動 + 有歷史紀錄
兩條路徑都驗)。全專案 `flutter test`(959 個測試)、`flutter analyze`
均通過。第 2 點的時序修正無法用 widget test 直接重現 `PageView` 的
lazy-build 行為,依賴使用者真機回報驗證。
