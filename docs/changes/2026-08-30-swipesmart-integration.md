# SwipeSmart 信用卡推薦整合

日期:2026-08-30
背景:SwipeSmart 信用卡推薦整合已在 BeeCount-Cloud 端完整實作(API key 管理、
卡片目錄、自動比對、刷卡建議);本次把對應的 App 端串接進來。完整設計理由見
`docs/superpowers/specs/2026-08-30-swipesmart-integration-design.md`,執行計畫見
`docs/superpowers/plans/2026-08-30-swipesmart-integration.md`。本文只記錄「改了
什麼檔案、為什麼這樣改」,不重複設計文件已有的推理過程。

## 1. Schema v47:`accounts.swipesmart_card_id`

**改了什麼**:`lib/data/db.dart` 新增 `Accounts.swipesmartCardId`(可空
`TextColumn`),`schemaVersion` 46→47,`MigrationStrategy.onUpgrade` 加一段
`if (from < 47)` 用 `_addColumnIfMissing` 補欄位。`lib/data/db.g.dart` 由
`build_runner` 重新產生。測試見 `test/data/migration_v47_test.dart`。

**為什麼沒有資料回填**:這個欄位是「本地信用卡帳戶 ↔ SwipeSmart 卡片目錄」
的對照關係,舊資料本來就不存在這個對照(語意上等同「尚未對照」),不需要
也無法回填——跟 `parentAccountId`(v32)引入時的處理方式一致。

## 2. Repository 層:`updateAccount` 新增 `swipesmartCardId`/`clearSwipesmartCardId`

**改了什麼**:`lib/data/repositories/account_repository.dart`(介面)、
`lib/data/repositories/local/local_account_repository.dart`(Drift 寫入)、
`lib/data/repositories/local/local_repository.dart`(sync-tracking facade)
三層都加上這兩個參數,寫法完全比照既有的 `parentAccountId`/
`clearParentAccount`(non-null 寫入 / true 清空 / 都不傳則不動)。
`createAccount` **沒有**加這個參數——建立帳戶當下通常還沒有對照,YAGNI。

**為什麼不用新的 ChangeTracker 呼叫**:`account` 本來就在
`_userGlobalEntityTypes` 裡,`LocalRepository.updateAccount` 呼叫
`recordUserGlobalChange` 是無條件觸發(只要該帳戶有 `syncId`),所以只要把
新欄位塞進既有的 `updateAccount` 呼叫鏈,就自動會被追蹤、push——不需要碰
`ChangeTracker` 本身。

## 3. 同步 push/pull:`entity_serializer.dart` + `sync_engine_apply.dart`

**改了什麼**:`serializeAccount` 無條件送出
`'swipesmartCardId': account.swipesmartCardId ?? ''`(跟 `parentAccountId`
同款「無條件送 + 空字串清空」約定)。`_applyAccountChange` 用跟
`parentAccountId` 一樣的 `containsKey` 保護讀取:缺鍵 → `d.Value.absent()`
(update 分支不動本地值);顯式空字串 → 清空;非空 → 寫入。insert 分支同樣
帶入這個欄位。

**為什麼要 containsKey 保護**:舊版 App / 早於這次改動的歷史 sync_change
payload 沒有這個鍵,如果無條件把缺鍵當 `null` 寫回去,會靜默清掉其他裝置
剛做好的對照(不管是使用者手動選的,還是 server 端自動比對寫回的)。測試
覆蓋三種情境:缺鍵保留、空字串清空、insert 分支帶入,見
`test/cloud/sync/entity_serializer_swipesmart_test.dart`(push)與
`test/sync/account_swipesmart_apply_test.dart`(pull)。

## 4. `flutter_cloud_sync` 套件:3 個 REST 回應 model + 5 個 client 方法

**改了什麼**:`packages/flutter_cloud_sync/lib/src/providers/beecount_cloud_provider.dart`
新增 `SwipeSmartKeyStatus`/`SwipeSmartCard`/`SwipeSmartCardRecommendation` 三個
純資料 model(`fromJson` 對齊 Cloud 的 snake_case 回應),以及
`getSwipeSmartKeyStatus`/`setSwipeSmartKey`/`deleteSwipeSmartKey`/
`getSwipeSmartCards`/`getCardRecommendation` 五個方法,`BeeCountCloudStorageService`
跟 `BeeCountCloudProvider` 各一份(後者是薄 passthrough,`_storage == null` 時
丟 `CloudConfigurationException`,跟其他既有方法一致)。順手加了
`_decodeJsonList` 輔助函式(鏡射既有的 `_decodeJsonObject`)——這個套件之前
所有回應都是單一 JSON object,SwipeSmart 的卡片目錄/推薦結果是第一批回傳
JSON array 的端點。

**為什麼沒有寫這 5 個方法的單元測試**:純 HTTP 呼叫轉發,沒有分支邏輯;
真正的邏輯(JSON 解析)已經在 model 的 `fromJson` 測試裡覆蓋
(`packages/flutter_cloud_sync/test/swipesmart_models_test.dart`),端到端行為
交給 Task 7/8 的手動驗證——跟 `readLedgerStats`/`updateMyProfileAiConfig` 這
兩個既有方法沒有專屬單元測試是同一套判斷。

## 5. 為什麼沒有把 SwipeSmart 的模糊比對演算法搬進 Dart

App 端要用到的兩個場景——「連 Key 時順便自動比對」「打開卡片對照頁時順便
重跑自動比對」——都是呼叫既有的兩支 REST 端點(`POST /profile/swipesmart`、
`GET /profile/swipesmart/cards`)時,Cloud server 端**當作呼叫的副作用**執行
的,結果直接以 `SyncChange` 的形式出現在下一次 pull 裡。App 端只需要「呼叫
端點 → 觸發一次 pull」,不需要重新實作一份比對邏輯——這也是為什麼
`swipesmart_card_mapping_page.dart` 在拿到卡片目錄後,一定會接著呼叫
`engine.pull(...)` 才去讀本地帳戶資料。

## 6. 三個新 UI 介面

**改了什麼**:
- `lib/pages/cloud/swipesmart_settings_page.dart`(新增):API Key
  連接/中斷,顯示自動比對到的帳戶數。從 `beecount_cloud_sync_page.dart`
  新增的一列導覽進入(僅登入時顯示)。
- `lib/pages/cloud/swipesmart_card_mapping_page.dart`(新增):列出本地
  `credit_card` 帳戶,每個帳戶一個下拉選單可選/清空對照的 SwipeSmart 卡片。
- `lib/widgets/biz/transaction_entry_form.dart`(修改):商家欄位下方新增
  一個水平捲動的建議卡片列。只在「支出交易 + 已連 SwipeSmart Key + 金額>0
  + 商家非空」時,商家/名稱欄位失焦 500ms 後打一次
  `getCardRecommendation`;同一組(金額,商家)不重打。點擊已對照的建議卡片
  → 直接代入該帳戶;點擊未對照的 → 帳戶不動,備註附加「銀行名 卡名」並
  toast 提示去完成對照。任何一步失敗(沒連 Key、逾時、網路錯誤)都靜默
  降級成「沒有建議」,不影響記帳表單本身可用性。

**刻意排除(範圍決策)**:設計文件 §5(Phase D「一鍵記帳」原生 quick-add)
評估後決定不在這次做——不新增 `beecount://swipesmart-quickadd` action,也
沒有動 `AppLinkService`/`AppLinkBuilder`。理由與取捨細節見設計文件 §5/§7,
這裡不重複。

## 7. 上線後修正:卡片對照頁排版 + 歷史對照資料撈不回來

初版上線後實測發現兩個問題:

**改了什麼(排版)**:`swipesmart_card_mapping_page.dart` 原本用
`ListTile(title:, trailing: DropdownButton(...))`——Flutter 的
`DropdownButton` 收起狀態的寬度是取**所有** menu item 裡最寬的那個(內部用
`IndexedStack` 量測全部 item,不只是目前選中項),卡片對照的候選項標籤
(例如「永豐銀行 現金回饋Green卡」)一長,`trailing` 就把整列橫向空間吃光,
`title` 帳戶名被擠成幾乎零寬度,逐字換行。改成 `Row` 手動排版:帳戶名/備註
用 `Expanded` 吃剩餘寬度,下拉選單包一個固定 `SizedBox(width: 140)` +
`isExpanded: true`,兩邊都帶 `overflow: ellipsis`。

**改了什麼(歷史資料)**:`sync_engine.dart` 的 `_entityTypeBackfillTags`
新增一條 `account_swipesmart_card_id_v47`。

**為什麼**:這條 tag 復用的是 v35 `card_reward_rule` 上線時就踩過的同一個
根因(見該常量上方註解)——`account` entity type 本身老設備早就認得,但
`swipesmartCardId` 是這次才新增的欄位。BeeCount-Cloud 端的 SwipeSmart 比對
/手動對照上線時間**早於**這次 App 整合,代表大量帳戶在 App 裝上這個欄位
之前,server 端就已經有 SyncChange 把 `swipesmartCardId` 寫進去了——那些
歷史 change 的 change_id 早被舊版 App 的 pull cursor 越過(舊版 code 讀到
不認識的 JSON key 就是單純忽略,其餘欄位照常 apply,cursor 照常前進,不會
報錯也不會停下),之後永遠拉不回來。且 server 端的自動比對
(`swipesmart_matching.py`)只處理**目前未對照**(`swipesmart_card_id IS
NULL`)的帳戶,重新呼叫一次 `GET /profile/swipesmart/cards`
(`swipesmart_card_mapping_page.dart` 開頁本來就會呼叫)也不會替已經對照好
的帳戶重發一次 change——單靠「開頁時 pull 一次」這個手段,不管是舊帳戶的
歷史對照,還是使用者稍早在 web 上手動 / 自動配好的對照,都補不回來。加上
這個 tag 後,任何一台裝置在升級到這版 App 後第一次 `sync()`,都會偵測到
待補齐標記,自動觸發一次 `replayAllChanges()`(從 change_id=0 全量重放,
apply 幂等,不會產生重複資料),補齊後永久標記完成,不再重放第二次。

測試見 `test/cloud/sync/sync_engine_e2e_test.dart`
「entity-type 一次性 backfill(v47 account.swipesmartCardId)」——模擬「舊
設備已經把 cursor 推過這條歷史 change 但完全沒 apply 到欄位」,驗證升級後
第一次 `sync()` 會自動 replay 補齊。

## 8. 上線後修正:記帳表單商家欄位打字完全不觸發刷卡建議

實測回報:在記帳表單商家欄位輸入「蝦皮」,金額已填好、SwipeSmart Key 也已連
接,但完全沒有出現建議卡片;以 server 端 log 確認,`GET
/profile/recommend-card`(`getCardRecommendation`)這支 API 從頭到尾沒被
打過——不是回應為空,是請求根本沒發出去。

**根因**:`transaction_entry_form.dart` 原本用 `_nameFocus`/`_merchantFocus`
兩個 `FocusNode` 的 `addListener` 來偵測「失焦」,判斷式是
`_textFieldFocused = _nameFocus.hasFocus || _merchantFocus.hasFocus`,兩個
欄位都失焦才觸發查詢。但「商家 → 名稱」是最自然的連續輸入流程(先填商家,
再點到名稱欄補備註)——這種情況下,商家欄位失去焦點跟名稱欄位拿到焦點是
同一個 focus transaction,Flutter 在通知兩邊的 listener 之前就已經把兩個
`FocusNode` 的 `hasFocus` 都更新完了,所以無論哪一邊的 listener 先被呼叫,
讀到的都是「商家失焦、名稱已聚焦」的最終狀態,`_textFieldFocused` 恆為
`true`,判斷式永遠不會通過。使用者這次回報的畫面(商家欄已經是「蝦皮」,
游標卻停在名稱欄)正是這個 transition 的典型畫面。

**改了什麼**:把觸發來源從「`_nameFocus`/`_merchantFocus` 失焦事件」改成
直接監聽 `_merchantCtrl`(商家欄 `TextEditingController`)的文字變動,用
既有的 500ms `Timer` debounce 取代「失焦」語意——使用者停止輸入 500ms 後
就查,不再依賴任何欄位是否/何時失焦,自然不受欄位切換順序影響。連帶把
「金額>0、支出交易、有 Key、同組合不重打」四個判斷條件抽成純函式
`shouldQueueSwipesmartRecommendation`(仿 §6 `swipesmartUnmappedNoteAppend`
的抽法),方便不用建 widget tree/mock 網路就能單元測試——刻意不讓這個純
函式接收任何 focus 相關參數,避免以後又不小心把「失焦」語意加回來。

測試見 `test/widgets/transaction_entry_form_swipesmart_test.dart`
`shouldQueueSwipesmartRecommendation` group,覆蓋:條件皆滿足時觸發、缺
Key/收入交易/金額為 0/商家為空時不觸發、同組合不重打、任一值變動要重打。

## 9. 上線後修正:REST 路徑漏掉 `/read` 前綴,建議永遠是空的

實測回報:§8 的 debounce 修正上線後,商家欄輸入仍然看不到建議卡片。查
BeeCount-Cloud 端 log 確認 `GET /read/ledgers/{id}/card-recommendation`
完全沒被打到。

**根因**:`beecount_cloud_provider.dart` 的 `getCardRecommendation` 呼叫
`_authedRequest(path: '/ledgers/$ledgerId/card-recommendation')`,漏了
`/read` 前綴——伺服器端這支端點掛在 `read` router 下(`src/main.py` 把
`read.router` 掛在 `{api_prefix}/read`,實際路徑定義在
`src/routers/read/ledgers.py`),跟同檔案裡緊鄰的 `readLedgerStats`
(`path: '/read/ledgers/$ledgerId/stats'`)明顯不對稱。每次請求都是 404,
但 `_fetchRecommendation` 的 catch block 把任何失敗都當成「暫時沒有建議」
靜默吞掉(§4 的設計本意是不讓這個附加功能擋住記帳,副作用是連「呼叫的
URL 根本錯了」這種明顯 bug 也不會冒出任何錯誤訊息)。

**改了什麼**:補上 `/read` 前綴。這支方法本身沒有專屬單元測試(見 §4「為
什麼沒有寫這 5 個方法的單元測試」的既有判斷——純 HTTP 轉發),這次的錯誤
純粹是手動核對兩支相鄰方法的路徑字串才抓到的,之後如果要再幫這類「純轉發
但路徑容易打錯」的方法補測試,可以考慮對 `_authedRequest` 呼叫做一層路徑
斷言。

## 10. 建議卡片列:未對照的不顯示 + 點擊後移到最前面

實測使用回報兩個體驗問題:

1. 建議卡片列裡混著已對照、未對照的卡片,點未對照的卡片除了跳一個「去完成
   對照」的 toast、備註被自動加上「銀行名 卡名」之外沒有其他作用——使用者
   會誤以為點了會生效。既然點了也選不出帳戶,乾脆一開始就不要列出來。
2. 建議卡片列每次重新查詢後順序都是伺服器回傳的原始順序,使用者選了某張卡
   之後,下次瞄一眼卡片列還要重新找一次剛選的是哪張。

**改了什麼**:`_fetchRecommendation` 拿到 server 回應後,先過濾成只保留
`accountId != null`(已對照)的項目才存進 `_recommendations`——`
_onRecommendationTapped` 因此不再需要處理「未對照」分支,連帶把當初為了
測試這個分支而抽出的 `swipesmartUnmappedNoteAppend` 純函式跟它的測試一起
刪掉(YAGNI,分支已經打不到了),`swipesmartRecommendationUnmappedHint`
這個 l10n key 也從 `app_en.arb`/`app_zh_TW.arb` 移除。點擊已對照卡片時,
除了代入帳戶,也把該筆從 `_recommendations` 移除後重新 `insert(0, rec)`
插回最前面。橫向卡片列的邊框樣式(原本只有已對照的卡片才畫框)也跟著簡化
成一律畫框,因為現在列表裡只會有已對照的卡片。

**範圍決策**:「已對照卡片被選中後移到最前面」只影響同一次 debounce 查詢
結果內的顯示順序——下一次商家/金額變動觸發新的 `_fetchRecommendation` 時
會拿到全新的伺服器排序(server 端排序邏輯本來就是依推薦分數,不是本地
「使用頻率」),不會把「使用者偏好」持久化跨查詢記住,這次沒有做那件事。

## 11. 上線後修正:點建議卡片代入帳戶後,信用卡回饋選單消失不見

實測回報:透過建議卡片列點卡代入帳戶可以正常存交易,但畫面上不會出現
「選擇紅利回饋」的入口;同一張信用卡改用手動「選擇帳戶」代入,回饋選單就
正常出現。

**根因**:`_onRecommendationTapped` 只 `setState` 了 `_selectedAccountId`,
沒有像 `_openAccountPicker`/`_loadSelectedAccount` 那樣一併同步
`_selectedAccountName`/`_selectedAccountType`/`_selectedAccountCurrency`。
帳戶列文字用 `_selectedAccountName` 顯示(缺了就是空白),而回饋選單是否
出現靠 `_rewardRuleSelectionEnabled`(`_selectedAccountType == 'credit_card'`)
判斷——這個欄位一直是 `null`,選單自然永遠不出現,即使選中的确实是信用卡
帳戶。

**改了什麼**:`_onRecommendationTapped` 原本就已經為了拿 `account.id` 查過
一次帳戶列,直接把同一筆 `account` 的 `name`/`type`/`currency` 一併寫進對
應欄位,不用再多查一次;比照其他換帳戶路徑,帳戶真的變了才清空
`_selectedRewardRuleIds`(避免殘留上一張卡選的回饋規則 id)。
