# 週期性交易管理介面 v2(規則就地編輯 + 批次同步未來交易 + Server 欄位遺漏修復)

延續 [2026-08-17-recurring-transactions-cloud-sync.md](2026-08-17-recurring-transactions-cloud-sync.md)
的 v1(只能檢視+整條刪除規則,無就地編輯入口)。使用者拿 Web 端
(`BeeCount-Cloud/frontend`)的規則總覽+編輯 Modal 截圖當參考,要求補齊 App
端的完整管理介面,並修復一個 Server 端排程生成交易欄位遺漏的 bug。

## 一、Server:`materialize_due_transfer_rules` 欄位遺漏修復

`BeeCount-Cloud/src/services/recurring_materializer.py` 有兩條生成路徑:
`refill_recurring_windows`(一般收支,提前批次續窗)已經帶齊
merchant/projectId/tagIds/baseAmount/fee/discount/rewardRuleIds;但
`materialize_due_transfer_rules`(轉帳/自動扣繳,到期才逐筆生成)一直只帶
`note`/`fromAccountId`/`toAccountId`,漏了其餘欄位——這是使用者回報「排程自
動生成的交易欄位顯示為 `--`」的真正成因(只發生在 transfer 類型規則上,一
般收支規則的路徑早就修過)。

`materialize_due_transfer_rules` 的 `item` dict 補上跟 `refill_recurring_windows`
同一組欄位(merchant/projectId/tagIds/baseAmount/feeAmount/feeLabel/
discountAmount/discountLabel/rewardRuleIds)。`categoryId` 不適用——轉帳規則
本來就沒有分類(`_assert_category_required` 已經擋掉)。

測試:`tests/test_recurring_rules.py` 新增
`test_transfer_recurring_rule_materializes_with_merchant_and_tags`,驗證帶
merchant + tag_ids 的 transfer 規則到期生成時這兩個欄位有正確帶到。
`project_id`/`reward_rule_ids` 沒有測——前者 server 端直接拒絕 transfer 規
則帶這個欄位(`_assert_project_exists`),後者 `_assert_reward_rules_valid`
要求 `account_id`,transfer 規則只有 from/to account,建立當下就會被擋,所
以這兩個欄位在 transfer 規則上實務上永遠是 null,程式碼裡的轉發邏輯只是跟
`refill_recurring_windows` 保持一致、防禦未來萬一開放。

## 二、App:規則列表頁 + 規則編輯頁重構

### 關鍵決策:批次套用到已生成的未來交易(刻意跟 Web 不同)

Web 的規則編輯 Modal(`RecurringRulesPanel.tsx`)只更新規則本身,**不會**回
頭套用到已經生成的未來交易——程式碼裡有明確註解說明這是刻意設計("既有規
則的 occurrence 已經生成完,編輯規則本身不會回頭重新套用")。批次套用只透
過「連同以後」這個 occurrence 專屬動作(anchor 在一筆具體交易上)。

使用者這次明確要求 App 端反過來:編輯規則本身時就要批次套用到未來、未被
單獨編輯過的交易。**這是刻意讓 App 跟 Web 行為不一致**,已跟使用者確認過。
如果之後要讓兩邊統一,需要另外評估要往哪個方向對齊。

範圍決策:
- `frequency`/`interval`/`endAt` 的變更不回頭搬動已生成 occurrence 的
  `happenedAt`——只影響規則本身 + 之後「還沒長出來」的期數,理由跟 Web 一
  致(避免大規模改日期的高風險操作)。
- 例外:新 `endAt` 若早於某些已生成、尚未發生、未被單獨編輯過的
  occurrence,直接刪除這些超出新結束時間的期數(不然「結束時間」欄位改了
  卻沒有任何效果)。已 overridden 的例外保留。
- 型別(支出/收入/轉帳)編輯時鎖死不可改,跟 Web 一致。
- 進階規則(星期幾/每月第幾天的細部模式)不開放編輯——理由同 Web 隱藏這塊
  UI 的原因:已生成的 occurrence 日期不會回頭搬動,重新配置對既有規則沒有
  實際意義。

### 為什麼不需要改 BeeCount Cloud 的 sync 端

App 是透過 `SyncEngine` 的 generic push/pull 協議同步(本地算完整批交易+規
則的變更,推一批 upsert/delete),不是呼叫 Web 專用的 REST 端點(如
`/recurring-rules/{id}/update-from/{tx_id}`)。`EntitySerializer.serializeRecurringRule`
(`lib/cloud/sync/entity_serializer.dart`)已經涵蓋這次要編輯的每個欄位
(nextRunAt/endAt/frequency/interval/amount/categoryId/accountId/merchant/
tagIds/rewardRuleIds),Server 端的 generic apply 路徑本來就吃這些欄位,不
需要任何新端點或欄位改動。

### 檔案改動

- `lib/data/repositories/recurring_rule_repository.dart` +
  `lib/data/repositories/local/local_repository.dart`
  (`updateRuleAndFuture`):`anchorTransactionId` 改成可選,新增
  `anchorDate`——有 anchor 交易時維持既有語意(給「連同以後」用),沒有時用
  `anchorDate`(預設現在)當批次更新起點,給規則列表頁「編輯」直接進來的入
  口用。新增 `nextRunAt`/`endAt`/`clearEndAt` 參數(只寫規則列)+ endAt 收
  斂時的例外刪除邏輯。新增 `setRuleEnabled`(規則列表頁 Switch 用)、
  `getOccurrencesForRule`(展開明細用)。既有呼叫點
  (`transaction_editor_page.dart`/`transfer_form.dart`)全部用命名參數,行
  為不變。
- `lib/pages/transaction/recurring_rule_editor_page.dart`(新檔案):獨立的
  規則編輯頁,對齊 Web 編輯 Modal 的欄位集合(類型唯讀顯示、金額、分類、帳
  戶或轉出/轉入帳戶、商家、標籤、紅利回饋規則、頻率、間隔、下次執行時間、
  結束時間)。選擇器全部複用既有元件——`CategorySelector`(透過
  `showCategorySelector`)、`AccountCardPicker`、`TagSelector`、
  `CardRewardRuleSelector`、`showTransactionDatePicker`——沒有重造任何一個。
  存檔前用 `AppDialog.confirm` 提示會套用到未來交易。同一個頁面透過
  `anchorTransactionId` 是否為 null 服務兩種入口:規則列表的「編輯」(null)
  跟期數明細的「連同以後」(非 null)。
- `lib/pages/transaction/recurring_rule_list_page.dart`(整頁重寫):規則卡
  片新增快速啟停 Switch、展開/收起期數明細、終止未來週期、編輯全部欄位;
  展開後逐筆顯示日期/金額/「已單獨編輯」標籤,提供連同以後/編輯單筆/刪除
  三個動作。分組維持既有 `enabled` 布林兩組(進行中/已結束或已停用)。
- `lib/utils/transaction_edit_utils.dart`(`TransactionEditUtils.editTransaction`):
  新增可選 `forcedScope` 參數——規則列表頁的期數明細「編輯」按鈕已經是明確
  的「只改這一筆」語意(旁邊就有獨立的「連同以後」按鈕),不該再跳一次「此
  記錄/連同未來週期」選擇彈窗問一次已經問過的問題,傳
  `RecurringEditScope.thisOnly` 直接跳過該彈窗。其餘既有呼叫點不受影響
  (參數預設 null,行為不變)。

### l10n

新增字串只加進 `app_en.arb` + `app_zh_TW.arb`(依照既有政策,見
[[feedback-l10n-policy-change]]),已跑 `flutter gen-l10n`。

### 測試

- `test/repositories/recurring_rule_repository_test.dart`:新增
  anchor-by-date(`anchorTransactionId` 為 null)路徑、預設用現在當起點、
  endAt 收斂刪除(含已 overridden 例外保留)、`setRuleEnabled`、
  `getOccurrencesForRule` 五個測試。
- `test/widgets/recurring_rule_editor_page_test.dart`(新檔案):欄位回填、
  anchor 為 null 的批次套用(含跳過已 overridden 的期數)、anchor 非 null
  的「連同以後」只影響 anchor 之後的期數。
- `test/widgets/recurring_rule_list_page_test.dart`(新檔案):卡片渲染、展
  開顯示期數明細、Switch 切換、刪除單筆期數。
- **新踩到的坑**(`recurring_rule_list_page_test.dart`):`RecurringRuleListPage`
  用 `StreamBuilder` 直接訂閱 `repo.watchRulesByLedger(...)`——真的 Drift
  `.watch()` 在記憶體 db 上訂閱時,widget 樹 dispose 後會留一個沒觸發的取消
  訂閱 Timer,踩到 `flutter_test` 的嚴格 timer 檢查(`!timersPending`)判失
  敗,而且不是靠加長 `pump()` 能解決的(這個 Timer 是 dispose 過程本身排
  的,不是等一段時間後才觸發的那種)。跟 `transfer_form_account_hidden_test.dart`
  對 `transactionAttachmentsProvider`(同樣是真 `.watch()` StreamProvider)
  的處理手法一致:測試裡用一個 `_TestListRepo extends LocalRepository`,只
  覆寫 `watchRulesByLedger` 改成 `Stream.fromFuture(getRulesByLedger(...))`
  (一次性查詢包成 Stream,不走真的 `.watch()`),其餘方法照樣用真正的
  `LocalRepository` 實作。代價:規則啟停後 UI 不會透過這個假 Stream 自動重
  新分組(只發一次),所以「切換 Switch」那個測試只驗證有正確呼叫到
  repo 層(欄位語意已經在 repository test 測過),不驗證 UI 即時重新分組。
- 沿用既有已知坑(見
  [2026-08-17-recurring-transactions-cloud-sync.md](2026-08-17-recurring-transactions-cloud-sync.md)
  跟
  [2026-08-17-recurring-edit-entry-and-tab-sync-fixes.md](2026-08-17-recurring-edit-entry-and-tab-sync-fixes.md)):
  存檔流程會經 `PostProcessor.sync` 碰到沒 mock 的雲同步 provider 鏈,
  `pumpAndSettle()` 永遠不會 settle;`showToast`/`LoggerService` 各自有 2
  秒防抖/自動關閉的真 Timer。全部改用固定次數的有界 `pump()` + override
  `beecountCloudProviderInstance`。

此環境依然沒有可用的 iOS 模擬器/Android SDK(`xcode-select` 未指向
Xcode.app,需要使用者 sudo 密碼),沒法手動點按驗證——全部用真實
widget-interaction test 覆蓋,建議之後找機會在真機上手動走一次完整流程
(尤其是頻率/間隔/日期選擇器這幾個目前只驗證了資料流、沒驗證 picker UI 本
身互動的部分)。

## 驗證

- Server:`cd BeeCount-Cloud && pytest tests/test_recurring_rules.py tests/test_recurring_schedule.py -q`
- App:`flutter analyze`(乾淨,無新增 issue)、`flutter test`(全量)。
