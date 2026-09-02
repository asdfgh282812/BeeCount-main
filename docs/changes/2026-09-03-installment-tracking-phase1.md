# 分期付款(Installment)子專案 1:核心資料模型 + 建立 + 列表

日期:2026-09-03
對應設計文件:`docs/superpowers/specs/2026-09-02-installment-tracking-design.md`
(本次只做文件標示「子專案 1」的範圍:§1/§2/§3.1/§4/§5.1/§6/§7 第一項/§8)。
先例:`docs/changes/2026-08-21-debt-tracking.md`(同一套「新 Drift 表 +
Repository + entity_serializer/sync_apply + 獨立頁面群 + provider」工作模式)。

## 1. 資料模型(`lib/data/db.dart`)

新增 `InstallmentPlans`(計畫)+ `InstallmentPeriods`(期數明細)兩張表,
ledger-scoped,同 `Debts`/`Budgets` 那組模式(`id` 本地自增 + `syncId` 跨裝置
同步標識)。`Transactions` 新增 `installmentPlanSyncId`(text,nullable,存
syncId 字串,同 `debtSyncId`/`recurringRuleId` 的既有模式)。`schemaVersion`
48 → 49,`onUpgrade`/`onCreate` 都補了對應的建表 + 索引邏輯(`idx_installment_
plans_ledger`、`idx_installment_periods_plan`),照抄 v39(debts)/v44(projects)
的既有寫法。

`paidPeriods`/`nextPeriodAt`/`periodAmount` 不落地存,讀取時即時算(見下)。
`offsetBreakdownJson`(帳單分期沖銷)刻意不在這次加,留給子專案 4 用獨立
migration 補。

## 2. 攤還演算法(`lib/services/installment/installment_amortization.dart`)

純函式 `computeInstallmentPeriods`,逐行對照 BeeCount Cloud
`src/services/installment_amortization.py::compute_periods` 移植(該檔案是
權威來源,直接讀過原始碼而不是只讀設計文件的文字描述)。三種還款方式
(等額本金/等額本息/固定利息)、monthly/daily 計息、寬限期、取整與餘數分配
邏輯全部照搬,`equal_installment + daily` 的折現因子法也是直接搬 Python 版的
算法結構,不是重新推導。

**移植時修的兩個坑**(都是先寫錯、被鎖定測試值抓出來才修對,如實記錄):
1. `addMonths` 的負數月份年份進位:Dart 的 `~/`(truncating division)對負數
   跟 Python 的 `//`(floor division)語意不同,直接套用會讓
   `addMonths(2026-01-15, -1)` 算出 `2026-12-15` 而不是正確的
   `2025-12-15`,daily 計息的「虛擬上一期」日期算全錯。改用
   `total - (total % 12)` 先求出可整除的部分再除,避開這個陷阱。
2. `addMonths` 沒保留輸入的 UTC/本地時區旗標,导致 UTC 輸入拿回本地時間的
   輸出,鎖定測試值比對 `DateTime` 時直接不相等。改成依 `dt.isUtc` 選擇
   `DateTime.utc(...)` 或 `DateTime(...)` 建構。

等額本息 monthly 分支的 `(1+r)^m` 改用 `dart:math` 的 `pow()`(而不是手寫迴圈
累乘),盡量貼近 Python `**` 運算子背後也是呼叫 libm `pow()` 的路徑,減少
浮點尾差跟 Cloud 端對不上的機率(取整後理論上不影響鎖定測試值,但取整前的
中間值盡量對齐,方便以後真的要對比更精細的案例)。

測試:`test/services/installment_amortization_test.dart`,直接搬設計文件
§2 末尾列的 6 組鎖定測試值(數字最終來源是 Cloud
`tests/test_installment_amortization.py`),另外補了 4 組非法輸入的驗證測試
(不是文件要求的「6 組」之外,是額外加的邊界覆蓋)。14 個測試全過。

## 3. Repository(`installment_repository.dart` + `local_installment_repository.dart`)

委托模式掛進 `BaseRepository`/`LocalRepository`,同 `DebtRepository` 的結構。

- `createInstallmentPlan`:業務規則校驗(accountId 不可為 account_group 子卡、
  totalAmount>0、1≤periods≤600、interestRate≥0、0≤gracePeriodMonths<periods
  ——`categoryId` 必填這條靠 Dart 簽名 `required int categoryId` 在編譯期
  強制,不是執行期校驗)→ 呼叫 `computeInstallmentPeriods` 算排程 → 單一
  `db.transaction()` 內依序寫入 1 筆 `InstallmentPlans` + N 筆 `Transactions`
  (type=expense,不經過 `TransactionRepository.addTransaction`,直接用
  `db.into(db.transactions).insert(...)`——設計文件 §3.1 明確要求這樣,因為
  分期沒有幣別欄位,不需要 `addTransaction` 的匯率折算邏輯)+ N 筆
  `InstallmentPeriods`。`LocalRepository.createInstallmentPlan` 包一層,负责
  changeTracker 記錄(1 個 `installment_plan` + N 個 `installment_period` +
  N 個 `transaction`,皆 `recordLedgerChange`,不是 `recordUserGlobalChange`
  ——對齐 §4.3)。
- `getInstallmentPlansWithStatus`:`paidPeriods`/`nextPeriodAt`/`periodAmount`
  逐行對齐設計文件 §1.1 公式(依 dueAt 排序後數 `dueAt<=now` 的期數;找第一個
  `dueAt>now` 的期當「下一期」;全部期數都過去時退回最後一期,不是 null)。
- `deleteInstallmentPlan`:整筆刪除連已發生期的交易也一併刪——**刻意跟子
  專案 2 的 `terminateFuture`(只刪未到期期)不對稱**,程式碼裡用大段
  comment 標註這個決策,避免以後被「修好」成一致。

新增了一個設計文件沒有明確列出、但 UI(`_InstallmentEntryCard`)需要的方法:
`getOutstandingPrincipalAllLedgers()`——跨帳本加總「尚未到期的分期本金」,
角色等同 `DebtRepository.getDebtBalancesByLedgerForAllLedgers`。判斷邏輯是
掃全部 `InstallmentPeriods` 取 `dueAt > now` 的 `principalAmount` 加總,子
專案 2 加入 `overridden`/退款狀態後這個計算可能需要重新檢視(目前所有期數
建立時都是 `generated`,子專案 1 範圍內這個簡化是安全的)。

測試:`test/repositories/local/installment_repository_test.dart`——建立計畫
生成正確期數/交易並互相連結、account_group 子卡校驗、金額/期數/利率/寬限期
邊界校驗、`getInstallmentPlansWithStatus` 的即時算公式(含「全部期數已過去」
邊界案例)、`active` 排序、整筆刪除連已發生期交易一起刪。12 個測試全過。

## 4. 同步

- `entity_serializer.dart`:`serializeInstallmentPlan`/
  `serializeInstallmentPeriod`,欄位對照 BeeCount Cloud
  `sync_applier.py::_LEDGER_MERGE_SPECS["installment_plan"/"installment_
  period"]`(直接讀了 Cloud 原始碼確認 wire key,不是憑設計文件猜)。
  **刻意不送 `paidPeriods`/`periodAmount`/`nextPeriodAt`**——這三個是兩端
  各自即時算的衍生欄位,設計文件 §4.1 明確排除。`serializeTransaction` 新增
  `installmentPlanId` 鍵,恆發(同 `debtId`/`projectId`)。
- `sync_engine_serialization.dart`:`_serializeEntityForPush` 加兩個 case,
  `_pushAllEntities` 加兩層迴圈(plan 迴圈裡巢狀 period 迴圈,同 budget/debt
  模式)。
- `sync_engine_apply.dart`:`_applyInstallmentPlanChange`/
  `_applyInstallmentPlanChange` 按 syncId upsert/delete,ledger/account/
  category 外鍵用既有 resolver 換本地 int id;`categoryId` 是 NOT NULL 欄位,
  本地分類還沒同步下來時**跳過整筆插入**(不像 account 外鍵可以先存 null),
  這是移植時做的一個判斷——設計文件沒有明確講這個邊界,照抄 debt 的「本地
  未就緒就跳過不建孤兒」精神類推過來的。`_applyInstallmentPeriodChange` 的
  `txId` 鍵在 wire 上是交易 syncId,這裡反查本地交易表換成本地 int id(換
  不到存 null,不阻擋 period 本身落地)。`_applyTransactionChange` 新增
  `installmentPlanId` 鍵的「缺鍵不覆蓋」處理(同 `debtId`)。

測試:`test/sync/installment_apply_test.dart`——plan/period 的 insert/
update(全量覆蓋)/delete、帳本或分類本地未就緒時跳過不建孤兒、period 的
txId 反查、transaction payload 的 `installmentPlanId` 恆發/缺鍵不覆蓋。
19 個測試全過。

## 5. UI

- `lib/pages/installment/installment_list_page.dart`:列表,`active` 排前面,
  每卡顯示總額/已繳期數/進度條/下一期日期/狀態徽章,提供刪除(帶二次確認)。
- `lib/pages/installment/installment_editor_page.dart`:建立表單(子專案 1
  只有建立,沒有編輯——建立後 totalAmount/periods/firstPeriodAt 都不可改)。
  進階區塊(計息週期/寬限期/取整開關/餘數位置)預設收合。年利率 UI 顯示
  整數/兩位小數百分比,內部存小數,轉換時用 `toStringAsFixed` 再轉回
  `double` 避免二進位浮點誤差殘留。
- `lib/widgets/biz/installment_draft_sheet.dart`:`InstallmentDraft` +
  `InstallmentDraftSheet`,角色對齐既有的 `RecurringRuleDraft`/
  `RecurringRuleAdvancedSheet`——`transaction_entry_form.dart` 的「設為分期」
  切換開啟這個彈窗收集攤還參數。
- `lib/widgets/biz/transaction_entry_form.dart`:expense tab 新增「設為分期」
  入口(`_buildInstallmentRow`/`_openInstallmentSheet`),只在新增模式顯示,
  跟「週期性收支」「拆帳」互斥(仿照既有 `_startSplitMode`/
  `_openRecurringSheet` 的互斥檢查寫法,雙向都擋)。`AmountEditorResult`
  新增 `installmentDraft` 欄位,非 null 時 `transaction_editor_page.dart`
  改呼叫 `createInstallmentPlan` 而不是 `addTransaction`(跟 v36
  `recurringDraft` 分支平行的角色)。
- `lib/pages/account/accounts_page.dart`:淨資產卡下方新增
  `_InstallmentEntryCard`(比照 `_DebtEntryCard`),跨帳本聚合「尚有未繳分期
  本金」,點擊導到當前帳本的 `InstallmentListPage`。
- 交易編輯基本鎖定(子專案 1 的暫時方案,子專案 3 會用
  `InstallmentEditChoiceDialog` 取代):`transaction_detail_card.dart` 偵測
  `installmentPlanSyncId != null` 時顯示警示 banner、編輯圖示點下去只會
  彈 toast 提示（不進編輯頁）、刪除被攔截並提示改到分期頁操作;
  `transaction_editor_page.dart` 的存檔 orchestration 裡也補了一層同樣的
  安全網(防呆用,正常路徑走不到,因為 detail card 已經先攔住)。

**已知缺口(誠實記錄,不是刻意隱藏)**:「刪除攔截」只做在
`transaction_detail_card.dart`(spec 明確點名的檔案)這一個入口。專案裡另外
還有 `search_page.dart`/`category_detail_page.dart`/`tag_detail_page.dart`/
`transaction_list.dart` 也各自有呼叫 `repo.deleteTransaction`
的路徑,這次**沒有**逐一加鎖——從那些入口刪掉一筆分期期數交易,目前不會被
攔截,會讓對應的 `InstallmentPeriods.txId` 變成指向不存在的交易(孤兒引用,
不影響已有資料完整性,但列表頁顯示的期數會跟交易對不上)。子專案 2/3 處理
狀態變更操作時建議一併重新檢視所有 `deleteTransaction` 呼叫點,或考慮把攔截
邏輯下沉到 repository 層(`LocalRepository.deleteTransaction` 本身)而不是
分散在各個 UI 入口——這次沒有下沉到 repo 層,是因為 debt 的還款交易/一般
交易都合法呼叫同一個 `deleteTransaction`,不能直接在 repo 層對所有
`installmentPlanSyncId != null` 的交易一律拒絕(子專案 2 的部分還本/提前結清
等操作本身也需要在 repo 內部刪除分期期數交易,不能被自己攔住)。

另一個已知的簡化:「設為分期」整合進 `transaction_entry_form.dart` 後沿用
了表單既有的「必須選帳戶才能送出」校驗(`_selectedAccountId == null` 時
擋下),但 spec 的資料模型层面 `accountId` 其實可以留空。獨立的
`InstallmentEditorPage`(從帳戶頁分期入口進入)沒有這個限制,可以不選帳戶
直接建立——兩個入口在這一點上行為不完全一致,是為了不改動
`transaction_entry_form.dart` 既有的帳戶必填邏輯(改了風險較高,那條校驗
其他交易類型都依賴)。

## 6. l10n

只加到 `app_en.arb`/`app_zh_TW.arb`(既定政策),`app_zh.arb`/`app_ko.arb`
不動,`flutter gen-l10n` 執行後兩個生成檔案的 zh/ko untranslated 警告是預期
內的(新 key 會 fallback 回英文模板)。

## 7. 明確排除(子專案 2/3/4 範圍,這次沒做)

- `updatePeriodOverride`/`rebalanceFrom`/`earlyRepayPrincipal`/`payoff`/
  `terminateFuture`(子專案 2 狀態變更操作)。
- `refundPeriod`、`InstallmentPeriodRefundChoiceDialog`、
  `InstallmentEditChoiceDialog`(子專案 3 退款流程)。
- `offsetExistingBalance`/`offsetBreakdownJson`(子專案 4 帳單分期沖銷)。
- `Debts.excludedFromTotal` 那組「排除計入總額」的對應功能,分期目前沒有
  類似開關。

## 8. 驗證

- `dart run build_runner build` 成功(兩次,分別在 db.dart 改完、以及全部
  改完後各跑一次)。
- `flutter analyze`:整個 repo 乾淨(0 error),既有的 warning/info 都是改動
  之前就存在的,沒有新增。
- `flutter test`:全專案 1015+ 個測試全過(含這次新增的 3 個測試檔共 45
  個測試),另外針對 `transaction_entry_form.dart`/`transaction_editor_page.
  dart` 相關的既有 widget 測試(`transaction_entry_form_test.dart`、
  `transaction_split_entry_form_test.dart`、
  `transaction_editor_page_tab_sync_test.dart`、
  `amount_editor_currency_test.dart`、
  `transaction_entry_form_swipesmart_test.dart`)單獨跑過確認沒有回歸。
