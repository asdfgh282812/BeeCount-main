# 週期性收支(recurring_rule)對齐 BeeCount Cloud + MOZE 風格 UI

日期:2026-08-17
背景:App 原本有一個**純本地**的「周期記帳」功能(`RecurringTransactions` 表
+ `RecurringTransactionRepository` + 兩個獨立頁面)——本地生成、不接
`ChangeTracker`、Web/其它裝置完全看不到,用「開檔時掃描、一筆一筆生成」的
lazy 模型。BeeCount Cloud(`../BeeCount-Cloud`)已經有功能豐富得多、且已上線
的 `recurring_rule` sync entity + Web「週期交易」頁,用「視窗批次預生成」
模型,支援單筆覆寫(occurrence override)、「修改/刪除此記錄 vs 連同未來
週期」等 MOZE 對標的細緻操作。這次把 App 端整段替換成跟 Cloud 對齐、雙向
同步一致的實作,UI 依照使用者提供的 MOZE 截圖規格。

**已與使用者確認鎖定的範圍**(2026-08-17):
- 欄位範圍:實作 Cloud `recurring_rule` **除了** `project` 關聯和手續費/
  折扣(`feeAmount`/`feeLabel`/`discountAmount`/`discountLabel`/
  `baseAmount`)**以外**的全部欄位與行為——含 `merchant`、`tagIds`、
  `rewardRuleIds`(信用卡紅利回饋連動)、transfer 類型「到期才生成 + 餘額
  不足跳過並通知」的特殊行為。「分期」tab 只做 UI 佔位,不實作邏輯。
- 遷移策略:**取代**現有本地周期記帳(不並存),redesign
  `RecurringTransactions` 表對齐 Cloud 欄位,舊本地資料在 schema migration
  搬進新結構,舊頁面/repository 整段刪除,不留相容殼子。
- 在地化政策(覆蓋 CLAUDE.md 既有慣例,使用者本次明確下達、適用於此後所有
  改動):只維護 `app_en.arb`(範本)+ `app_zh_TW.arb`(繁中);
  `app_zh.arb`/`app_ko.arb` 不再新增/更新 key,含這個功能新增的所有字串。

## Phase 1:Schema + Migration

- `lib/data/db.dart`:`Transactions` 移除本地 `recurringId`(int,指向舊表),
  新增 `recurringRuleId`(`TextColumn`,存**規則的 syncId** 而非本地 int
  id——同 `refundOfSyncId` 模式,本地 id 跨裝置不穩定)、
  `recurringOccurrenceOverridden`(`BoolColumn`,預設 false,標記這期是否被
  「修改此記錄」單獨編輯過)。
- `RecurringTransactions` 整表 redesign 對齐 Cloud `recurring_rule`:新增
  `syncId`、`fromAccountId`(轉帳來源,獨立欄位)、`merchant`、
  `tagSyncIdsJson`、`rewardRuleIdsJson`、`advancedRuleJson`(JSON,只支援
  `weekly_days`/`monthly_day` 兩種,見下)、`nextRunAt`、`generatedUntilAt`。
  拿掉 `dayOfMonth`/`dayOfWeek`/`monthOfYear`(改用 `advancedRuleJson` 統一
  表達)、`lastGeneratedDate`(改用 `generatedUntilAt`,語意從「上次生成
  日」變成「已生成到哪」)。
- `schemaVersion` 35→36,`onUpgrade` 新分支:舊 `RecurringTransactions` 列
  的 `dayOfMonth` 轉成 `advancedRuleJson.monthly_day`,`lastGeneratedDate`
  當 `generatedUntilAt` 起點,`syncId` 全部設 null(視同新建規則,下次啟動
  補推一次 `local_changes`);舊 `Transactions.recurringId`(int)join 舊
  `RecurringTransactions.id` 反查出新 `syncId`,回填新的
  `recurringRuleId` 文字欄位,再丟棄 `recurringId` 整欄。

## Phase 2:生成引擎 + Repository 編排

- `lib/services/data/recurring_rule_schedule.dart`(新增,純 Dart、無 DB
  依賴、獨立可測):原樣移植 Cloud `services/recurring_schedule.py` 的
  `enumerate_occurrences`/`plan_initial_generation` 演算法,常數
  (`DEFAULT_WINDOW_MONTHS=12`、`DEFAULT_WINDOW_MAX_OCCURRENCES=200`、
  `MAX_OCCURRENCES_PER_GENERATION=2000`、`REFILL_THRESHOLD_DAYS=30`、
  `REFILL_WINDOW_MONTHS=12`)照抄 Cloud 端數值,避免兩端漂移。`advanced_rule`
  的 `weekly_days.days` 用 **Monday=0..Sunday=6**(對齐 Python
  `datetime.weekday()`),**不是** Dart 原生 `DateTime.weekday`
  (Monday=1..Sunday=7)——`weekdayZeroBased()` 統一做轉換,呼叫端不要直接
  塞 `DateTime.weekday`。`test/services/data/recurring_rule_schedule_test.dart`
  17 個測試對照 Cloud Python 測試案例移植(含跨月/UTC 邊界)。
- `lib/data/repositories/recurring_rule_repository.dart` +
  `lib/data/repositories/local/local_recurring_rule_repository.dart`:單表
  CRUD。跨表編排(建規則當場批次生成 occurrence、「此記錄 vs 連同未來週期」
  、視窗續產生、transfer 自動扣繳)直接寫在 `LocalRepository`,同
  budget/account 既有慣例(見 `docs/CLOUD_SYNC_INTEGRATION.md` §2)。
- **App 自己在本地算生成日期**,不等 server 算完再 pull——App 必須支援完全
  離線的使用者。`syncId` 建規則當下就地產生(`Uuid().v4()`),不會有「兩端
  各自生成出不同 syncId 的重複交易」問題。
- **修改/刪除語意**(對齐 Cloud web-only REST endpoint
  `routers/write/recurring_rules.py` 的行為,但 mobile 不呼叫那些
  endpoint,全部在本地用 Drift 查詢重新實作一遍):
  - 修改此記錄:只改這一筆 `Transactions` 列,標記
    `recurringOccurrenceOverridden=true`。
  - 修改連同未來週期:更新規則列本身 + 批次更新同規則、
    `happenedAt >= anchor.happenedAt`、`recurringOccurrenceOverridden==false`
    的既有 occurrence(不動 `happenedAt`,只改內容)。
  - 刪除此記錄:直接刪這一筆。
  - 刪除連同未來週期:刪除同規則、`happenedAt > now` 的所有 occurrence(不
    論是否 overridden),規則標記 `enabled=false`。
- transfer 類型(自動扣繳)不吃批次視窗生成,到期當下才逐筆生成、生成前查
  帳戶當下記帳餘額,不夠就跳過(不推進 `generatedUntilAt`)並發本地通知。
  Repository 回傳 `RecurringRuleTransferSkip` 結構化資料,通知的實際呼叫在
  `lib/providers/ui_state_providers.dart`(repository 層刻意不依賴
  `flutter_local_notifications`,維持 Pages → Providers → Repositories →
  Drift DB 分層)。
- `test/repositories/recurring_rule_repository_test.dart`:8 個整合測試
  覆蓋 createRule(有/無 endAt)、updateOccurrence、updateRuleAndFuture、
  terminateFuture、deleteRule、materializeDueTransferRules(餘額不足/充足
  兩支路徑)。
- 舊實作整段刪除:`recurring_transaction_repository.dart`、
  `local_recurring_transaction_repository.dart`、
  `recurring_transaction_service.dart`、兩個舊頁面、對應舊測試,無相容殼子。

## Phase 3:Sync 接線

- `lib/cloud/sync/entity_serializer.dart`:新增 `serializeRecurringRule`
  (跟 `serializeBudget` 同款「全量 UPSERT」語意——BeeCount Cloud
  `sync_applier.py::_LEDGER_MERGE_SPECS["recurring_rule"]` 走
  `projection.upsert_recurring_rule`,缺鍵/null 由 server 端從既有列補齐,
  所以這裡把規則當下完整值都帶上)。**注意 wire 字段是 `txType`,不是
  `type`**(核對 Cloud merge spec 逐字確認,跟 Transaction 的
  `serializeTransaction` 不同)。`advancedRuleJson` 在 wire 上傳解碼後的
  `Map`(對齐 Cloud `snapshot_builder.py` 的形狀),不是雙重編碼的字串。
  刻意不帶 `projectId`/`baseAmount`/`feeAmount`/`feeLabel`/
  `discountAmount`/`discountLabel`(範圍決策,本地表也没有對應欄位)。
  `serializeTransaction` 新增 `recurringRuleId`(有值才發,同 `refundOfId`)
  + `recurringOccurrenceOverridden`(恆發,同 `excludeFromStats`)。
- `lib/cloud/sync/sync_engine_serialization.dart`:`_serializeEntityForPush`
  新增 `case 'recurring_rule':`(查規則列 + 解析 category/account/
  fromAccount/toAccount 的 syncId);`_pushAllEntities`(fullPush 路徑)新增
  對應迴圈,同 budget 那段模式。
- `lib/cloud/sync/sync_engine_apply.dart`:新增 `case 'recurring_rule':` →
  `_applyRecurringRuleChange`(full-replace upsert,不做 containsKey 保護,
  同 `_applyBudgetChange`;`ledgerId` 解析不到就跳過,不建孤兒規則)。
  `_applyTransactionChange` 新增 `recurringRuleId`(缺鍵不覆蓋)/
  `recurringOccurrenceOverridden`(缺鍵不覆蓋,防旧客戶端冲掉本地已標記的
  true)兩個欄位的 containsKey 解析——**這步容易漏**:serializer 加欄位不等
  於 apply 端會認得,一開始只加了 push 端,被
  `test/sync/recurring_rule_apply_test.dart` 的 occurrence 落地測試抓到。
- **`/sync/full` 涵蓋確認**:讀了 Cloud `snapshot_builder.py` 確認
  `recurringRules` 已經在 `/sync/full` 回應裡。但 App 端 `download()`
  (`packages/flutter_cloud_sync/.../beecount_cloud_provider.dart`)只從
  `/sync/full` 回應裡取 `snapshot.payload.content`(fullPush 上傳時附帶的
  legacy JSON 字串),不會解析 `recurringRules` 欄位——這條路徑本來就不含
  `budgets`(同款先例),新設備真正靠的是 `pull()` 從 `cursor=0` 開始的
  **增量重放**(`replayAllChanges`/`_pullWithOneTimeBackfills`),把
  `recurring_rule` 接進 `applyRemoteChange` 分派就夠,不需要再碰
  `_exportLedgerJson`/`importTransactionsJson`/`runFullPull` 那條 legacy
  快照路徑。
- `test/sync/recurring_rule_apply_test.dart`:5 個測試(insert 欄位齊全、
  full-replace 缺鍵清空、delete、ledger 未就緒跳過、transaction payload 的
  recurringRuleId/recurringOccurrenceOverridden 正確落地)。

## Phase 4:MOZE 風格 UI

- `lib/widgets/biz/recurring_rule_advanced_sheet.dart`(新增):「進階設定」
  彈窗——單次/週期/分期(disabled)tab、區間 picker(每 N 日/週/月/年)、
  週選星期 chip 多選、月選日期 chip 單選、次數(無限期/指定次數)、入帳方式
  (v1 只有「立即入帳」一種,純展示,不接邏輯)。「指定次數」在 UI 層用
  `enumerateOccurrences(maxCount: N)` 換算成具體 `endAt` 日期——底層資料模型
  沒有「次數」欄位,只有 `endAt`,這是刻意的簡化,使用者體感仍是「輸入次
  數」。`RecurringRuleDraft.summary()` 產生列表/表單共用的摘要文字。
  **範圍簡化**(算法限制,非疏漏):選「週」時完全用 `weekly_days` 進階規則
  表達,隱藏區間 stepper(移植的 `enumerateOccurrences` 對 `weekly_days` 本來
  就不吃 `interval`,見 `recurring_rule_schedule.dart` 的 `_enumerateWeeklyDays`
  簽名)。
- `lib/widgets/biz/recurring_occurrence_dialogs.dart`(新增):
  `showRecurringEditChoiceSheet`/`showRecurringDeleteChoiceSheet`,MOZE 截圖
  的「此記錄 / 連同未來週期」二選一 bottom sheet(未新增 `AppDialog` 的多選
  項變體,避免動到共用元件的既有呼叫方)。
- `lib/widgets/biz/transaction_entry_form.dart`:新增「週期」欄位入口(比照
  日期列樣式),**只在新增模式顯示**(`editingTransactionId == null`)——
  v1 範圍決策:不支援把既有一次性交易回填成週期規則。`AmountEditorResult`
  新增 `recurringDraft` 欄位。`onSubmit` 型別從 `void Function(...)` 改成
  `TransactionSubmitCallback`(`Future<void> Function(...)`)——編輯週期
  occurrence 時上層要先跳選擇彈窗,使用者取消時整個存檔動作會中止且不 pop
  頁面,表單靠 `onSubmit` 回傳的 Future 完成後解除 `_isSubmitting`,否則存
  檔鍵會卡在禁用狀態。
- `lib/pages/transaction/transaction_editor_page.dart`
  (`_handleSubmit`):
  - 新增模式 + `res.recurringDraft != null`:改呼叫 `repo.createRule(...)`
    (內部批次生成第一個視窗的 occurrence,含當下這筆)而不是
    `addTransaction`,之後查規則 syncId 底下最早的 occurrence 取得
    `transactionId` 接上原本的附件/標籤/作者回填流程。**已知落差**(範圍
    決策,未擴充 `createRule`/`_createOccurrenceTransaction` 的欄位集合):
    透過「週期」入口建立的交易不支援
    `excludeFromStats`/`excludeFromBudget`/多幣種/共享帳本 override/
    退款關聯——這些欄位只有一般單次交易的 `addTransaction` 路徑支援。
  - 編輯既有交易前先查 `recurringRuleId`,非 null 時跳
    `showRecurringEditChoiceSheet`;取消則整個存檔中止。「此記錄」:走原本
    完整欄位的 `updateTransaction`(不變)+ 直接 Drift 更新
    `recurringOccurrenceOverridden=true`(不額外補 change,push 時序列化器
    統一讀 DB 最新狀態,同檔案既有的 tag override 注釋邏輯)。「連同未來週
    期」:原本完整欄位的 `updateTransaction` 之後,再呼叫
    `repo.updateRuleAndFuture(...)` 轉發「規則模板」窄欄位集合
    (type/amount/category/account/note/merchant,不含 tags/回饋規則——v1
    範圍決策,未串接本地 tag id → syncId 轉換)。`updateRuleAndFuture` 內部
    批次迴圈本來就會連帶重寫 anchor 的同一批欄位,跟前面的
    `updateTransaction` 冗余但等冪,不影響正確性。
- `lib/pages/transaction/recurring_rule_list_page.dart`(新增,取代舊版
  `recurring_transaction_page.dart`):依 `enabled` 分「進行中/已結束」兩組
  (同 `card_reward_rule_list_page.dart` 分組慣例)。**v1 範圍**:只有檢視
  + 整條規則刪除(`deleteRule(deleteFutureOccurrences: true)`),不支援就地
  編輯規則設定——規則欄位/排程只能在新增交易時的「週期」入口一次性建立。
- `lib/widgets/biz/transaction_detail_card.dart`(`_handleDelete`):
  `recurringRuleId != null` 時跳 `showRecurringDeleteChoiceSheet` 取代原本
  的單一確認彈窗;「連同未來週期」= `deleteOccurrence`(刪這一筆)+
  `terminateFuture(ruleId)`(刪其餘未來 occurrence + 規則標記
  `enabled=false`)。
- `lib/pages/settings/automation_page.dart`:恢復「週期記帳」入口(Phase 2
  結束時暫時下線的那個),連到 `RecurringRuleListPage`。
- `lib/l10n/app_en.arb` + `lib/l10n/app_zh_TW.arb`:新增約 45 個 key(進階
  設定彈窗、規則列表頁、編輯/刪除選擇彈窗、自動化頁入口),依鎖定的 l10n
  政策**只加這兩個檔案**,`app_zh.arb`/`app_ko.arb` 不動(`flutter gen-l10n`
  對這兩個檔案回報的 untranslated 計數是預期中的,不是回歸)。

### UI 測試與模擬器限制

這台機器的 Xcode 沒有 `xcode-select` 指向正確路徑(需要使用者手動跑
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`,這個命令
需要密碼,agent 無法代跑),也没有安裝 Android SDK——**這次改動沒有辦法在
iOS 模擬器或 Android 裝置上實機跑一遍**,只能靠自動化測試把關:
- `test/widgets/recurring_rule_advanced_sheet_test.dart`(新增,4 個):
  用 `tester.pumpWidget` + `tester.tap` 真的驅動彈窗互動(切 tab、點星期
  chip、確定/取消),不只測純函式。過程中抓到一個真的 bug——
  `RecurringRuleDraft.summary()` 對 `advancedRule['days']` 用
  `.cast<int>()..sort()` 原地排序,如果來源是不可變 list(例如呼叫端傳
  `const` list)會拋 `Unsupported operation`,已修成
  `List<int>.of(...)..sort()`。
- `test/widgets/recurring_occurrence_dialogs_test.dart`(新增,4 個):同款
  互動式測試覆蓋編輯/刪除選擇彈窗兩個入口 × 選項/取消。
- `test/widgets/recurring_rule_draft_summary_test.dart`(新增,4 個):純函式
  單元測試,`summary()` 的簡單頻率/weekly_days/monthly_day 三種分支。
- `test/widgets/transaction_entry_form_test.dart` /
  `test/widgets/amount_editor_currency_test.dart`:既有測試因為
  `onSubmit` 型別改動需要同步改成 `async`,已修正,兩個檔案的既有案例照舊
  全過,間接確認 `TransactionEntryForm` 的結構改動(新增週期列、型別改動)
  沒有破壞既有 widget tree。
- `_handleSubmit`/`_handleDelete` 裡的 glue 邏輯(把 UI 選擇接到對應
  repository 呼叫)本身沒有專門的 widget test——`TransactionEditorPage`
  在這之前也从来没有被 widget test 覆蓋過(依賴太多 provider/導航,
  同 codebase 既有的「重頁面不 widget test,測子元件跟 repository 層」慣
  例),這次沒有新開先例。真正的把關落在 repository 層的 8 個整合測試
  (Phase 2)+ sync 層的 5 個測試(Phase 3)+ 這裡的 UI 決策層測試,合起來
  覆蓋了資料流的每一段,但沒有端到端 widget 級別的驗證。

## 已知範圍限制(留給後續 phase)

- 透過「週期」入口建立的交易不支援 excludeFromStats/excludeFromBudget/
  多幣種/共享帳本 override/退款關聯。
- 「連同未來週期」編輯不轉發標籤/信用卡回饋規則變更(只轉發
  type/amount/category/account/note/merchant)。
- 規則列表頁不支援就地編輯規則設定(頻率/區間/星期/日期/結束條件),只能
  檢視 + 整條刪除。
- 週期入口只在「新增交易」模式顯示,不支援把既有一次性交易回填成週期規則。
- 不支援 project 關聯與手續費/折扣欄位(使用者本次明確要求跳過)。

## 驗證

- `dart run build_runner build --delete-conflicting-outputs` 後
  `flutter analyze` 乾淨(0 error,既有 warning/info 數量不變)。
- `flutter test`:689 個測試全過(含這次新增的 17+8+5+4+4=38 個測試:算法
  17 + repository 整合 8 + sync apply 5 + advanced sheet 互動 4 +
  occurrence 選擇彈窗互動 4 + summary 純函式 4,原文如此加總可能因既有測試
  基準變動略有出入,以 `flutter test` 實際輸出為準)。
- `flutter gen-l10n` 成功(只更新 `app_en.arb`/`app_zh_TW.arb` 的
  untranslated 統計,`app_zh.arb`/`app_ko.arb` 的 untranslated 計數增加是
  預期中的政策結果)。
- 手動 App↔Web 雙向同步、離線建規則重新連線後補推等場景**未在此環境驗證**
  (無法起 BeeCount Cloud 本機服務 + 無模擬器/裝置),邏輯依據是 Phase 3 的
  自動化測試 + 對照 Cloud 端原始碼(`sync_applier.py`/`projection.py`/
  `snapshot_builder.py`)逐欄位核對的 wire 契約,建議下次有裝置/模擬器可用
  時手動跑一次收尾驗證。
