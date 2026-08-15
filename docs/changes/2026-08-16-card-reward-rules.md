# 信用卡紅利回饋(card_reward_rule)

日期:2026-08-16
背景:App 端新增信用卡「紅利回饋」設定功能 —— 帳戶資訊頁入口、回饋列表頁、
新增/編輯頁,以及記帳表單裡選擇回饋方案並顯示預估回饋金。這是
`docs/CLOUD_SYNC_INTEGRATION.md` §1 列出的「Cloud 有、App 完全沒有」6 種
entity 之一(`card_reward_rule`),屬於該文件 §5「從零生出一個全新 sync
entity」等級的工程。App 端原則:只負責設定資料的讀取/回填/UI 呈現/欄位
連動,真正的回饋金計算與排程入帳一律在 BeeCount Cloud 端跑。

實作前已在 `../BeeCount-Cloud`(同機、獨立 git repo)核對過實際 schema——
`frontend/packages/api-client/src/types.ts:949-1029`、
`src/sync_applier.py:192-216`、`src/schemas.py:1908-1968`、
`src/routers/write/card_reward_rules.py`、`src/services/card_rewards.py`,
不是憑空猜的。

## 已與使用者確認的兩個決策

1. **寫入路徑**:走跟 account/category/tag 一樣的通用 sync engine
   (`ChangeTracker` → push/pull),不另外接 web 用的專屬 REST endpoint。
   代價(已知落差,留給 Cloud 團隊後續評估是否要補):generic `/sync/push`
   最終會走到 `projection.upsert_card_reward_rule`,這個函式**不做**
   `_CARD_REWARD_LOCKED_FIELDS` 檢查(那個檢查只在 web 專用 REST write
   endpoint 上),且 `locked` 欄位本身也只有 web 專屬 GET endpoint
   (`routers/read/ledgers.py:830` 的 `card_rewards.rule_has_history(...)`)
   會回傳,不在 generic pull payload 裡。App 端因此用**本地代理值**判斷是否
   鎖欄位:本地任何交易的 `rewardRuleIds` 命中這條規則 → 視為 locked(見
   `card_reward_rule_editor_page.dart::_checkLocked`)。這是不完整的近似,
   看不到 server 端的自動入帳紀錄(`CardRewardPayout` 表)。
2. **圖示**:規則列表/編輯頁一律顯示固定的靜態圖示,編輯頁不提供圖示選擇
   器 —— 核對過 server schema 完全沒有 icon 欄位,不新造一個不會同步的本地
   欄位。同理拿掉了 mockup 裡出現、但 schema 沒有對應欄位的「單筆上限」跟
   「是否為基本回饋」兩個輸入項(mockup 疑似參考自另一個 app,不是這次
   confirmed schema 的一部分)。

## 資料層

- `lib/data/db.dart`:新增 `CardRewardRules` 表(schemaVersion 34→35),
  `Transactions` 新增 `rewardRuleIdsJson` 欄位(JSON list of syncId 字串,
  同 v34 `refundOfSyncId` 的做法——存 syncId 而非本地 int id,因為本地 id
  跨設備不穩定)。新增 `TransactionRewardRuleIds`/`CardRewardRuleCategoryIds`
  兩個 extension 做 JSON 解碼。

## Repository 層

- 新增 `lib/data/repositories/card_reward_rule_repository.dart`(介面)+
  `local/local_card_reward_rule_repository.dart`(實作),組進
  `BaseRepository`/`LocalRepository`,寫入路徑走
  `changeTracker.recordUserGlobalChange`(user-global,ledgerId 恆 0)。
- `TransactionRepository.addTransaction`/`updateTransaction` 新增
  `rewardRuleIds` 參數(語意同 `merchant`——無條件寫入,調用方需自行傳當前值
  以保留)。

## Sync 層(`lib/cloud/sync/`)

- `change_tracker.dart`:`_userGlobalEntityTypes` 加入 `card_reward_rule`。
- `entity_serializer.dart`:新增 `serializeCardRewardRule`——**跟其它
  entity 不同**,這裡不做任何 `if (x != null)` 省略,每個欄位每次都無條件
  帶出本地當前真值(包含 null),因為 server 端 `upsert_card_reward_rule` 是
  全量 UPSERT(`_upsert()` docstring:「主鍵撞了就 UPDATE 其他所有列」),不
  是 `_merge_from_spec` 的 partial merge。`serializeTransaction` 加
  `rewardRuleIds`(list,恆發,同 attachments 的「即使 `[]` 也要送」規則)。
- `sync_engine_serialization.dart`/`sync_engine_apply.dart`:push/pull 各加
  一個 `card_reward_rule` case,pull 端 accountId 解析不到時直接跳過(帳戶
  尚未同步到本地),不建孤兒行;`_applyTransactionChange` 的 rewardRuleIds
  用 `containsKey` 缺鍵保護(同 excludeFromStats/refundOfId 的套路)。
- 已知限制:全新裝置的「首次同步」如果走的是 JSON 快照下載
  (`runFullPull`/`_exportLedgerJson`,主要給 WebDAV/S3/iCloud 等非 BeeCount
  Cloud provider 用)而不是 `replayAllChanges()`(從 change_id=0 重放
  BeeCount Cloud 的 sync_changes log),card_reward_rule 不會出現在那份 JSON
  快照裡。因為這個 entity 目前只有 BeeCount Cloud provider 支援(卡片回饋是
  Cloud 端功能),日常使用走的都是 replay 路徑,這個落差影響面很小,先不處理。

## UI

- `lib/pages/account/account_detail_page.dart`:信用卡帳戶資訊 tab 新增
  「紅利回饋」可點列,顯示啟用中規則數量,進
  `card_reward_rule_list_page.dart`。
- `lib/pages/account/card_reward_rule_list_page.dart`(新):進行中/已結束
  分組,支援拖曳排序(`ReorderableListView.builder`),右上角 `+` 新增。
- `lib/pages/account/card_reward_rule_editor_page.dart`(新):完整表單,
  locked 規則(本地代理判斷)disable 全部計算類欄位並顯示提示。
- `lib/widgets/biz/card_reward_rule_selector.dart`(新):記帳表單裡的回饋
  規則多選 bottom sheet,只列該信用卡「啟用中 + 在有效期間內」的規則。
- `lib/widgets/biz/transaction_entry_form.dart`:選了 `credit_card` 帳戶時,
  標籤/附件列多一個回饋圖示按鈕開回饋選單;選取結果以 chip 形式跟標籤並排
  顯示(可點 x 移除);底部新增「預計可獲得回饋」文字,純前端估算(不 call
  server)——`amount * rateValue / 100` 依規則 `rounding` 取整,`capAmount`
  存在時 clamp,多規則加總。這只是輸入當下的提示,真正入帳金額仍由 server
  排程計算。

## Localization / Tests

- 四個 `.arb` 都補了對應 key,`flutter gen-l10n` 重新產生。
- `test/sync/card_reward_rule_apply_test.dart`:新增/full-replace 更新
  (驗證缺鍵視為清空,不是缺鍵保留)/刪除/帳戶未就緒時跳過。
- `test/sync/transaction_reward_rule_ids_apply_test.dart`:新增帶值/缺鍵
  保留/顯式空 list 清空。
- `test/repositories/card_reward_rule_repository_test.dart`:CRUD + 排序 +
  user-global change 記錄。

## 追加(同日):舊規則不同步的 bug 修復 + 複製/刪除功能

初版上線後回報:server 端(web 建立)先前就存在的舊紅利規則,在已經用過一段
時間的裝置上打開信用卡帳戶看不到;但新建規則能正常雙向同步。另外,原計劃
的「複製」「刪除」互動一直沒有 UI 入口(repository 早就有 `deleteCardRewardRule`
但沒人呼叫)。

### Bug 根因與修復

`SyncEngine.applyRemoteChange`(`sync_engine_apply.dart`)對辨認不出的
`entityType` 只是打一行 warning log 就 `return false`,**但呼叫方
`_runPullLoop` 不管單條 apply 有沒有成功都照樣把整頁 `appCursor.commit(result.
serverCursor)` 推進**——這在設計上是對的(否則一條髒 change 會卡死整條
pull),但代表:任何裝置只要在「這個 app 版本認得 card_reward_rule 之前」
就已經拉過一輪 pull,它的 app cursor 早就越過了 server 上那些舊規則對應的
change_id。之後再怎麼增量 pull 也拉不回——`SyncEngine.replayAllChanges()`
(`sinceOverride=0` 從頭重放)本來就是為這類情境準備的,只是沒人在「新支援
一個 entity type」這個時間點觸發過它。

修復(`lib/cloud/sync/sync_engine_pull.dart` + `sync_engine.dart`):
- `AppCursorStore` 新增 `hasBackfilled(tag)`/`markBackfilled(tag)`,key 派生
  方式跟既有 cursor key 一樣(`baseUrl|userId|deviceId` 的 sha1),同一組
  帳號+裝置只會真的補一次。
- `SyncEngine._pullWithOneTimeBackfills`(新):`sync()` 原本直接呼叫
  `pull(ledgerId)` 的地方改呼叫這個方法。內部維護一份
  `_entityTypeBackfillTags` 常量列表(目前只有 `'card_reward_rule_v35'`),
  第一次執行時發現有 tag 沒打過標記,就觸發一次 `replayAllChanges()`(從
  change_id=0 全量重放,apply 是 syncId upsert 幂等,不會重複插入),成功後
  把待補的 tag 一次全部標記完成——因為一次 replay 本來就會覆蓋所有 entity
  type,不需要每個 tag 各跑一次。失敗時不標記,不阻塞本次 `sync()`(退化成
  普通增量 pull),下次 sync 自動重試。
- 之後新增別的 sync entity type、又需要對已同步裝置補歷史資料時,照這個
  模式在 `_entityTypeBackfillTags` 加一個新 tag 即可,不用重新設計機制。
- 測試:`test/cloud/sync/sync_engine_e2e_test.dart` 新增
  `entity-type 一次性 backfill(v35 card_reward_rule)` group,驗證「cursor
  已推進 + 標記未寫入 → 觸發 since=0 重放 → 標記寫入 → 第二次恢復增量」以及
  「replay 失敗不阻塞 sync()、不誤標記」兩個場景。

### 複製 / 刪除 UI

刪除語意刻意對齊 BeeCount Cloud web 專屬 REST endpoint 的行為
(`routers/write/card_reward_rules.py::delete_card_reward_rule_api`),而不是
generic sync 的行為——這兩者不一樣,是本次踩的另一個坑:web 端刪除規則前會
查 `card_rewards.rule_has_history`,有交易/入帳紀錄掛著就**軟刪**
(`enabled=false`),沒有才真刪,理由是硬刪會讓那些交易的 `rewardRuleIds`
斷鏈引用一個不存在的規則。但 App 這邊(決策 1)走的是 generic
`/sync/push` delete action,對應的 `projection.delete_card_reward_rule` 是
**無條件硬刪**,不會做這個歷史檢查。所以 App 端刪除前必須自己先做這個判斷,
不能直接呼叫 `repo.deleteCardRewardRule` 就完事。

新增 `lib/widgets/biz/card_reward_rule_actions.dart`,提供兩個共用函式給
列表頁 + 編輯頁一起用(避免兩處各寫一份):
- `duplicateCardRewardRule`:讀出來源規則所有欄位原樣建一條新規則,名稱加
  `(複製)` 後綴(不開編輯頁讓使用者先調整,直接建立+更新列表,對齐使用者
  原始需求描述的「自動帶入」選項),`sortOrder` 排在同帳戶現有規則之後。
- `confirmAndDeleteCardRewardRule`:先用跟編輯頁 `_checkLocked` 相同的本地
  代理判斷(本地是否有交易的 `rewardRuleIds` 命中這條規則的 syncId)決定要
  顯示「一般刪除」還是「已鎖定,將改為停用」的確認文案;確認後對應地走
  `deleteCardRewardRule`(硬刪)或 `updateCardRewardRule(enabled: false)`
  (軟刪)。回傳是否真的執行了動作,呼叫方據此決定要不要順手關掉當前頁面。

UI 掛載點:
- `card_reward_rule_list_page.dart`:每個 tile 尾端加 `BeePopupMenu`(既有
  元件,`lib/widgets/ui/bee_popup_menu.dart`,跟專案裡其它「更多」選單一致
  的視覺),兩個選項「複製」「刪除」。
- `card_reward_rule_editor_page.dart`:AppBar 在「儲存」左邊加同款
  `BeePopupMenu`,只在編輯既有規則時顯示(新增中的規則還沒有東西可複製/
  刪除)。選了複製或刪除成功後 `Navigator.pop()` 回列表頁。

新增 l10n key(四個 `.arb` 都補了):`cardRewardRuleCopy`/`cardRewardRuleDelete`
/`cardRewardRuleCopyLabel`/`cardRewardRuleCopied`/`cardRewardRuleDeleted`/
`cardRewardRuleDeleteLockedTitle`/`cardRewardRuleDeleteLockedBody`/
`cardRewardRuleDisabledInsteadOfDeleted`。`cardRewardRuleDeleteConfirmTitle`/
`cardRewardRuleDeleteConfirmBody` 是初版就加了但沒接 UI 的既有 key,這次補上
呼叫方,不重複新增。

測試:`test/widgets/card_reward_rule_actions_test.dart`,覆蓋複製欄位/名稱
後綴/獨立 syncId、無交易引用時硬刪、有交易引用時軟刪、取消對話框不變更。
