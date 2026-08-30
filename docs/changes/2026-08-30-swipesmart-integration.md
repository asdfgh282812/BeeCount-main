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
