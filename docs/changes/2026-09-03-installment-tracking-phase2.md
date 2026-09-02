# 分期付款(Installment)子專案 2:狀態變更操作

日期:2026-09-03
對應設計文件:`docs/superpowers/specs/2026-09-02-installment-tracking-design.md`
(本次只做文件標示「子專案 2」的範圍:§0(核心不變量,全篇貫穿)、§3.2(全部
五個狀態變更操作)、§5.2(UI)、§7 第二項(測試))。
先例:`docs/changes/2026-09-03-installment-tracking-phase1.md`(子專案 1,本次
在它的基礎上繼續,`InstallmentPlans`/`InstallmentPeriods`/`Transactions.
installmentPlanSyncId` 等資料模型/序列化/建立/列表都已就緒,這次不動)。

## 1. Repository(`installment_repository.dart` + `local_installment_repository.dart`)

新增 5 個狀態變更方法,對照 `../BeeCount-Cloud/src/routers/write/
installment_plans.py`(權威來源)逐一移植,**各自獨立實作,沒有共用計算
邏輯**(設計文件 §0 明確要求):

- `updatePeriodOverride(periodId, {amount?, dueAt?, note?})`——單期覆寫,
  標記 `status='overridden'`;帶 `amount` 時 `principalAmount = max(amount -
  interestAmount, 0)`(利息不變);三個欄位互相獨立可選,任一非 null 時同步
  更新關聯交易的對應欄位。
- `rebalanceFrom(planId, periodNo, {interestRate, repaymentMethod?})`——連同
  未來重算,`firstPeriodAt` 用使用者點的那個 periodNo 本身的 `dueAt`(不是
  過濾後 targets 清單的第一筆,這個細節容易搞錯,照抄 Cloud
  `installment_plans.py:528`)。
- `earlyRepayPrincipal(planId, {paymentAmount, accountId?, happenedAt?})`——
  部分提前還本,清零閾值判斷 `remainingAfter <= 0.005`。
- `payoff(planId, {accountId?, happenedAt?})`——提前結清,`futurePeriods`
  **不排除** overridden(全部未到期期都刪,跟前兩者不同),應計利息用
  「下一個未到期期的原排程利息」近似。
- `terminateFutureInstallments(planId)`——終止未來分期,刪未到期期+交易,
  **不產生任何交易**。

四個涉及金額重算/刪除的操作(`rebalanceFrom`/`earlyRepayPrincipal`/
`payoff`/`terminateFutureInstallments`)都在單一 `db.transaction()` 內完成。

### 命名偏離設計文件的地方

設計文件 §3.2 把最後一個方法叫 `terminateFuture`,但 `RecurringRuleRepository`
(週期性收支功能)已經有一個同名但簽名不同的方法(`terminateFuture(int
ruleId)`,終止週期規則),兩者都掛在 `BaseRepository` 上會撞名。改叫
`terminateFutureInstallments`,在 `installment_repository.dart` 的
docstring 裡有記這個偏離原因。

### ChangeTracker 記錄方式:沒有跟 phase 1 完全一樣

Phase 1 的 `createInstallmentPlan`/`deleteInstallmentPlan` 用「操作前/後
各查一次資料庫,比對算出異動清單」的方式讓 `LocalRepository` 包裝層記
ChangeTracker。子專案 2 的操作內部混合了刪除跟更新(例如
`earlyRepayPrincipal` 到底走刪除分支還是重算分支,要等算出
`remainingAfter` 才知道),操作完之後那些被刪的列已經查不到了,不能照搬
phase 1 的「事後查一次」模式。

改成:`LocalInstallmentRepository` 的這 5 個方法**不是** `InstallmentRepository`
介面方法的 override(介面上宣告的簽名是 `Future<void>`),而是
`LocalInstallmentRepository` 自己額外的方法,回傳一個
`List<InstallmentChange>`(新增的小型資料類別,記錄「異動了哪個實體/
entityId/entitySyncId/ledgerId/action」)。每個操作在**執行當下**(還沒刪除
前)就把要記錄的異動記下來,回傳給 `LocalRepository` 的委托方法,由後者
統一迴圈呼叫 `changeTracker.recordLedgerChange`。

這個安排刻意跟「不要把業務邏輯合併成共用函式」的警告分開看待:
`_applyComputedPeriod`/`_deletePeriodAndTx`(`local_installment_repository.
dart` 內的兩個私有 helper)是 `rebalanceFrom`/`earlyRepayPrincipal`/
`payoff`/`terminateFutureInstallments` 共用的,但它們只做「把已經算好的
`PeriodPlan` 寫回 DB」跟「刪除一期+其交易」這兩個純 I/O 動作,不包含
任何本金池計算/清零閾值判斷——那些業務判斷(`<=0.005` vs `<=0`、
overridden 隔離的加總邏輯)仍然在各自方法裡各自獨立寫一份,沒有合併。
**這是本次唯一一處跟設計文件字面警告有點擦邊的判斷,誠實記在這裡**:
如果之後要更嚴格地照字面執行「完全不共用任何東西」,可以把這兩個
helper 展開內聯到 4 個呼叫點,但目前判斷這個風險可接受。

## 2. 刪除攔截邊界(子專案 1 遺留的已知缺口)

Phase 1 的刪除攔截只做在 `transaction_detail_card.dart` 一個入口(見 phase 1
文件的「已知缺口」)。這次照 phase 1 文件的建議,把攔截**下沉到 repository
層**:

- `InstallmentManagedTransactionException`(新增,`installment_repository.
  dart`):`LocalRepository.deleteTransaction` 一開始就檢查
  `tx.installmentPlanSyncId != null`,是的話直接丟這個例外,不執行刪除。
- `LocalInstallmentRepository` 的 `earlyRepayPrincipal`/`payoff`/
  `terminateFutureInstallments` 刪除期數對應交易時,直接對
  `db.transactions` 做 `db.delete(...)`,**不經過** `LocalRepository.
  deleteTransaction`,所以不受這個攔截影響——這是設計上要的:repo 內部
  合法操作可以刪,一般 UI 入口不行。`test/repositories/local/
  installment_repository_test.dart` 的「deleteTransaction 攔截分期交易」
  測試群組同時驗證了這兩種情境。
- UI 層新增共用入口 `TransactionEditUtils.deleteTransactionGuarded`
  (`lib/utils/transaction_edit_utils.dart`):先做一次 client-side 預檢查
  (避免多繞一次 DB round trip),沒中的話呼叫 `repo.deleteTransaction`
  並 catch `InstallmentManagedTransactionException` 做第二層防線,回傳
  `bool` 告訴呼叫端刪了沒有。`showFeedback` 參數控制要不要順便跳 toast
  (批量刪除場景想自己彙總訊息,不要每被攔一筆跳一次)。
- 5 個原本各自散落的呼叫點全部改用這個共用入口:
  - `transaction_detail_card.dart`——維持原本「先攔在確認對話框之前」的
    UX(避免問了「確定刪除?」又說不行),`deleteTransactionGuarded` 在這裡
    主要是防禦性的第二層,實務上不會走到 false 分支。
  - `category_detail_page.dart`(兩處,`allLedgers=true/false` 各一份幾乎
    一樣的程式碼)。
  - `tag_detail_page.dart`。
  - `search_page.dart` 的批量刪除——**行為有調整**:原本任何一筆刪除拋
    錯就中止整個迴圈(不管是不是分期交易導致的),改成逐筆呼叫
    `deleteTransactionGuarded(showFeedback: false)`,跳過被攔的、繼續刪
    其餘選中的,最後彙總「刪了 N 筆」+「有 M 筆屬於分期計畫未刪」兩則
    訊息。這是本次主動做的行為修正,不只是套用共用入口。
  - `transaction_list.dart` 的滑動刪除——攔截點挪到 `confirmDismiss`
    (滑動確認階段就攔下、不彈確認對話框),而不是等到 `onDismissed`
    (那時候項目已經從畫面上滑走了,攔在那裡體驗更差)。

## 3. UI(`installment_list_page.dart` + 新增 `installment_action_sheets.dart`)

- `installment_list_page.dart` 從 `ConsumerWidget` 卡片改成
  `ConsumerStatefulWidget`(`_InstallmentCardState`),加一個 `_expanded`
  開關;展開後用既有的 `installmentPeriodsProvider(planId)` 顯示各期明細
  (`_PeriodListSection`/`_PeriodRow`),每列有「編輯」(`updatePeriodOverride`)
  跟「連同未來重算」(`rebalanceFrom`)兩個 `IconButton`——刻意用普通
  `IconButton` 不是 `PopupMenuButton`,對齐 `CLAUDE.md`/user memory 記錄的
  既有教訓(`PopupMenuButton.onSelected` 直接觸發 dialog 在 macOS target
  會 crash)。
- 卡片本身在 `status == active` 時多三個 `TextButton`:部分還本
  (`earlyRepayPrincipal`)/提前結清(`payoff`)/終止未來分期
  (`terminateFutureInstallments`),非 active 時只留刪除按鈕。
- 新檔 `lib/widgets/biz/installment_action_sheets.dart`:4 個 bottom sheet
  (`PeriodOverrideSheet`/`RebalanceFromSheet`/`EarlyRepayPrincipalSheet`/
  `PayoffSheet`),角色跟版面風格對齐 phase 1 既有的
  `installment_draft_sheet.dart`(`InstallmentDraftSheet`)——只收集輸入、
  回傳一個結果物件,實際呼叫 repository 跟錯誤處理都在
  `installment_list_page.dart` 裡做,sheet 本身不碰 repository。
  - `PeriodOverrideSheet`:金額/到期日/備註三個欄位都以目前值預填,存檔
    一律送出目前顯示的三個值(不追蹤「使用者是否真的改過某欄位」)——這是
    刻意的簡化,詳見下方「跟設計文件的差異」。
  - `PayoffSheet` 額外顯示一個「預估結清金額」預覽區塊,算法跟 repo 內部
    `payoff()` 一致(已過去期數以外的剩餘本金 + 下一個未到期期的原排程
    利息近似值),純粹是給使用者心理準備,不是權威值。
  - 帳戶欄位留空 = 沿用 `plan.accountId`(repo 端的預設行為),UI 上用
    `installmentUseDefaultAccountHint` 提示。

## 4. l10n

只加到 `app_en.arb`/`app_zh_TW.arb`(既定政策),新增約 30 個 key,前綴
`installment*`,`flutter gen-l10n` 執行後 `app_zh.arb`/`app_ko.arb` 的
untranslated 警告是預期內的(fallback 回英文模板)。

## 5. 測試

`test/repositories/local/installment_repository_test.dart` 新增以下測試群組
(共 19 個新測試,加上 phase 1 既有的 9 個,這個檔案總共 28 個測試全過):

- `updatePeriodOverride`:amount 拆分規則(本金=新總額-利息,利息不變)、
  amount 小於 interest 時本金 clamp 到 0、只帶 dueAt/只帶 note 的獨立更新、
  periodId 不存在時拋 `StateError`。
- `rebalanceFrom`:**§0 核心不變量的關鍵測試**——範圍內混有一個 overridden
  期(本金鎖定成跟正常攤還不同的值),驗證重算後這個 overridden 期本金
  完全不動、也沒有被納入可分配本金池(重算結果的本金加總精確等於
  `totalAmount - priorPrincipal - overriddenInRangePrincipal`,不多不少);
  範圍內全部 overridden 時拋錯;剩餘本金 `<=0` 時拋錯;找不到 plan/periodNo
  時拋錯。
- `earlyRepayPrincipal`:兩種清零分支(`overriddenFuturePrincipal<=0.005`
  才真的 settled,否則 plan 維持 active 且 overridden 期原樣保留)、
  `remainingAfter>0` 時的重新攤還分支、超過可分配本金池時拋錯。
- `payoff`:近似應計利息(用下一個未到期期的原排程利息,不是精確按日計息)
  、不排除 overridden(全部未到期期都被刪,含 overridden 的)、
  `settleAmount<=0` 時不建立交易。
- `terminateFutureInstallments`:不產生任何交易、刪除未到期期(含
  overridden)、已過去期不受影響。
- `deleteTransaction` 攔截分期交易:一般呼叫被攔下且交易不會真的被刪、
  非分期交易正常刪除不受影響、repo 內部操作(`earlyRepayPrincipal`)刪
  期數交易不受攔截影響(隱含驗證 `terminateFutureInstallments` 的測試也是
  同一件事的佐證)。

新增 `test/widgets/transaction_edit_utils_delete_guarded_test.dart`(widget
測試,2 個測試全過):透過 `TransactionEditUtils.deleteTransactionGuarded`
的完整路徑(含 toast)驗證「分期交易被攔下、toast 正確顯示、交易不會被刪」
跟「一般交易正常刪除」兩種情境——這是本次要求的「一般 UI 入口刪除分期交易
被攔下」情境在 UI 層的驗證(repo 層的等價驗證見上面
`installment_repository_test.dart` 那組)。

### 用到的一個測試技巧值得記錄

Drift 的 `dateTime()` 欄位讀回來時 `isUtc` 一律是 `false`(即使寫入時是
`DateTime.utc(...)`),而 Dart 的 `DateTime.==`(不是 `isAtSameMomentAs`)
連 `isUtc` 旗標都比,不是單純比較 `microsecondsSinceEpoch`——一開始直接寫
`expect(updated.dueAt, newDueAt)` 會誤判成失敗(即使兩者是同一個時間點),
用 `isAtSameMomentAs` 才對。這個坑不影響現有程式邏輯(production code 本身
沒有這個問題,`InstallmentPeriodsCompanion`/`TransactionsCompanion` 寫入
跟讀出都在同一套 Drift 轉換規則下,不會有時區位移),純粹是測試斷言方式
要留意。

## 6. 跟設計文件不完全一致的地方(誠實記錄)

1. **ChangeTracker 記錄方式**(見上方 §1「ChangeTracker 記錄方式」小節)
   ——設計文件沒有明確規定要怎麼記,子專案 2 的操作內部刪除+更新混合的
   特性讓 phase 1 的「事後查一次」模式不適用,改成「操作當下即時記異動
   清單」,這是本次的實作判斷。
2. **`_applyComputedPeriod`/`_deletePeriodAndTx` 兩個純 I/O helper 被
   `rebalanceFrom`/`earlyRepayPrincipal`/`payoff`/
   `terminateFutureInstallments` 共用**——跟 §0「各自獨立照抄,不合併成
   共用函式」的字面警告有點擦邊,但共用的只是「寫入一個已經算好的
   `PeriodPlan`」跟「刪除一期+其交易」這兩個沒有業務判斷分支的機械動作,
   本金池計算/清零閾值判斷本身仍然各自獨立。詳見上方說明,如果覺得這個
   判斷不夠保守,可以進一步展開成完全內聯。
3. **`terminateFuture` 改名 `terminateFutureInstallments`**——避免跟
   `RecurringRuleRepository.terminateFuture` 撞名(見上方說明)。
4. **`PeriodOverrideSheet` 三個欄位一律全量送出**(不追蹤使用者是否真的
   改過某個欄位)——`updatePeriodOverride` repository 方法本身完整支援
   三者獨立可選的部分更新語意(有測試覆蓋這點),但 UI 表單是一般「編輯
   表單」的樣子(三個欄位都預填目前值),存檔一律送出目前顯示的值,這跟
   `transaction_entry_form.dart` 等既有編輯表單的慣例一致。換句話說:
   repository 層的「部分更新」能力保留給未來如果要做更精細的 UI(比如只
   改備註不碰金額的輕量彈窗)使用,這次的 UI 沒有用到那個彈性。
5. **`payoff`/`earlyRepayPrincipal` 的帳戶/日期輸入表單沒有做「只在
   status==active 才能開啟」以外的額外限制**——例如沒有校驗「這個
   accountId 是不是 account_group 的子卡」(createInstallmentPlan 建立時
   會擋,但這裡沒有複用那個校驗)。Cloud 端的對應端點也沒有做這個校驗
   (`early_repay_installment_principal_ep`/`payoff_installment_plan_ep`
   直接用 `req.account_id or plan.get("accountId")`,沒有再次檢查子卡),
   所以這裡對齐 Cloud 行為,不是遺漏。

## 7. 明確排除(子專案 3/4 範圍,這次沒做)

- `refundPeriod`、`InstallmentPeriodRefundChoiceDialog`、
  `InstallmentEditChoiceDialog`(子專案 3 退款流程 + 交易明細頁編輯選擇
  整合)。
- `offsetExistingBalance`/`offsetBreakdownJson`(子專案 4 帳單分期沖銷)。
- `transaction_detail_card.dart`/`transaction_editor_page.dart` 對分期交易
  的唯讀鎖定機制維持 phase 1 的暫時方案(banner + 阻止進編輯頁),沒有
  改成子專案 3 才要做的 `InstallmentEditChoiceDialog` 四選一。

## 8. 驗證

- `flutter analyze`:整個 repo 0 error(跟改動前一致);新增的幾個
  info(`use_build_context_synchronously`)是這個 codebase 既有的普遍模式
  (全庫已有 125 處同款用法),不是新引入的問題類型。
- `flutter test`:全專案 1036 個測試全過,含這次新增的 19 個 repository
  測試 + 2 個 widget 測試。
