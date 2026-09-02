# 分期付款(Installment)子專案 3:退款流程 + 交易明細頁「編輯選擇」對話框整合

日期:2026-09-03
對應設計文件:`docs/superpowers/specs/2026-09-02-installment-tracking-design.md`
(本次只做文件標示「子專案 3」的範圍:§3.3(退款,全部)、§5.3(UI)、§7 第三項
(測試))。
先例:`docs/changes/2026-09-03-installment-tracking-phase1.md`(子專案 1)、
`docs/changes/2026-09-03-installment-tracking-phase2.md`(子專案 2)——本次
在兩者的基礎上繼續,`InstallmentPlans`/`InstallmentPeriods`/建立/列表/五個
狀態變更操作(`updatePeriodOverride`/`rebalanceFrom`/`earlyRepayPrincipal`/
`payoff`/`terminateFutureInstallments`)都已就緒,這次不動。

## 1. Repository:`refundPeriod`

`lib/data/repositories/installment_repository.dart` 新增介面方法
`refundPeriod(planId, txId, {amount?, note?, happenedAt?})`,對照
`../BeeCount-Cloud/src/routers/write/installment_plans.py:385-462`(權威實
作)移植。`lib/data/repositories/local/local_installment_repository.dart`
實作(委托模式,跟子專案 2 的五個狀態變更操作**同款分工**——不是介面方法
的 override,回傳 `List<InstallmentChange>` 供 `LocalRepository` 包裝層統一
記 ChangeTracker,理由同 phase2 文件「ChangeTracker 記錄方式」小節:這裡雖
然沒有刪除分支,但為了跟同一批「分期狀態變更操作」保持一致的呼叫慣例,沒有
另外走 phase1 的「操作前後各查一次比對」模式)。

行為:

- 依 `txId`(反查交易的本地 int id,對齊 `InstallmentPeriods.txId` 的欄位語
  意)在 `planId` 底下找到對應的 `InstallmentPeriod`;找不到 plan 或期數皆
  拋 `StateError`。
- 該期 `status=='refunded'` 時拋 `StateError`(拒絕重複退款)。
- 建立 1 筆 `type='income'` 交易:`amount` 預設該期 `totalAmount`(可用
  `amount` 覆寫,天然支援部分退款)、`note` 預設「分期退款」、
  `happenedAt` 預設 `DateTime.now()`、`accountId` 用 `plan.accountId`、
  `refundOfSyncId` 指回原交易的 `syncId`——**沿用一般交易退款既有的 v34
  `refundOfSyncId` 契約**(見 `TransactionEditUtils.refundTransaction`/
  `entity_serializer.dart` 的 `refundOfId` wire key),不是重新發明一套。
- **關鍵**:退款交易**刻意不寫 `installmentPlanSyncId`**——這是設計文件明
  確要求的行為,理由是避免這筆退款交易本身被
  `InstallmentManagedTransactionException`(子專案 2 下沉到
  `LocalRepository.deleteTransaction` 的攔截)誤判成「分期計畫管理的交
  易」而擋住使用者之後想刪除/編輯這筆退款記錄。已用測試驗證(見下方 §4)。
- 該期標記 `status='refunded'`,原交易(`txId` 對應那筆分期期數交易本身)
  不刪不改。
- **整筆退款不是這個方法的職責**——UI 直接呼叫既有的
  `deleteInstallmentPlan`(子專案 1 寫的,連已發生期交易一起刪),沒有重
  新實作。

`LocalRepository.refundPeriod` 的委托寫法跟 `updatePeriodOverride` 等五個
方法完全平行,新增在 `terminateFutureInstallments` 之後、
`_recordInstallmentChanges` 之前。

## 2. UI

### 2.1 `InstallmentEditChoiceDialog` / `InstallmentPeriodRefundChoiceDialog`

新檔 `lib/widgets/biz/installment_edit_choice_dialog.dart`:

- `InstallmentEditChoice` enum(`thisRecordOnly`/`rebalanceFromHere`/
  `earlyRepayPrincipal`/`payoff`)+ `showInstallmentEditChoiceSheet(context,
  {required bool planActive})`——`planActive=false`(計畫已 settled/
  terminated)時不提供「提前還本」/「提前繳清」兩個選項,對齊
  `installment_list_page.dart` 卡片本身只在 `status==active` 才顯示這兩顆
  按鈕的既有限制。單期覆寫/連同未來重算兩個選項不受這個限制(對齊
  `_PeriodListSection` 展開後的既有行為)。
- `InstallmentRefundChoice` enum(`periodOnly`/`wholePlan`)+
  `showInstallmentPeriodRefundChoiceSheet(context)`。
- 兩者的彈窗殼子(標題 + N 個選項 ListTile + 取消)複製自
  `recurring_occurrence_dialogs.dart` 的 `_showChoiceSheet`(週期規則編輯/
  刪除範圍二選一用的同一個版面)——那個函式是私有的,沒有直接 import 重
  用,獨立寫了一份小的 `_showChoiceSheet<T>` 泛型殼子,避免引入跨檔案的私
  有耦合;版面/樣式逐行對齊,行為上使用者感受不出差異。
- `InstallmentPeriodRefundSheet`(+ `InstallmentPeriodRefundInput`):「只退
  這一期」選定後的輸入表單,金額欄位預填該期 `totalAmount`(可覆寫)、備
  註留空(repo 端預設「分期退款」)、日期預設今天。版面殼子直接重用
  `installment_action_sheets.dart` 的 `SheetScaffold`/`sheetLabel`/
  `formatSheetDate`(那三個是子專案 2 的公開頂層宣告,不是私有的),沒有
  重畫一份。

### 2.2 `transaction_detail_card.dart`:取代子專案 1 的唯讀鎖定

子專案 1 在 `_buildHeader`/`build` 裡做的「`installmentPlanSyncId != null`
時編輯圖示灰掉 + tooltip 顯示鎖定文案 + 頂部顯示警示 banner」整段邏輯**移
除**,改成:

- **編輯**:`_handleEdit` 偵測到 `installmentPlanSyncId != null` 時呼叫新
  增的 `_handleInstallmentEdit`——先反查 plan + 對應的
  `InstallmentPeriod`(用 `period.txId == tx.id` 找,不是走 syncId,因為
  `InstallmentPeriods.txId` 本來就是本地 int),彈
  `showInstallmentEditChoiceSheet`,依選擇分派到 `_applyPeriodOverride`/
  `_applyRebalanceFromHere`/`_applyEarlyRepay`/`_applyPayoff` 四個方法,各
  自打開子專案 2 已經做好的對應 sheet(`PeriodOverrideSheet`/
  `RebalanceFromSheet`/`EarlyRepayPrincipalSheet`/`PayoffSheet`,全部從
  `installment_action_sheets.dart` 匯入,**沒有重寫一份**)並呼叫對應
  repository 方法。這整條路徑刻意**不** `Navigator.pop()` 卡片——四個分支
  都是「彈窗 → repo 呼叫 → 收尾」,不需要像一般交易編輯那樣離開卡片導頁到
  另一個頁面。操作成功/失敗都在卡片自己的 context 上收尾(跟既有的
  `_handleDelete` 同款風格),失敗時卡片留著方便使用者重試,成功時共用的
  `_finishInstallmentChange` 收尾方法負責刷新 provider(
  `installmentsRefreshProvider`/`statsRefreshProvider`/
  `budgetRefreshProvider`/`countsForLedgerProvider`)、觸發
  `PostProcessor.sync`、關閉卡片、在 overlay 上顯示成功 toast。
- **刪除**:**沒有改動**——`_handleDelete` 對
  `installmentPlanSyncId != null` 的攔截(早期 return + toast,提示改到分
  期管理頁操作整個計畫)維持子專案 1/2 的既有行為。設計文件 §5.3 只點名
  「編輯」入口要改成 `InstallmentEditChoiceDialog`,沒有要求刪除入口也跟
  著變——刪除攔截的統一收斂已經是子專案 2 在 repository 層
  (`LocalRepository.deleteTransaction` 拋
  `InstallmentManagedTransactionException`)+ UI 層
  (`TransactionEditUtils.deleteTransactionGuarded`)做完的事,這裡不重
  複、也不擴大範圍。
- **退款**:`_handleRefund` 偵測到 `installmentPlanSyncId != null` 時呼叫
  新增的 `_handleInstallmentRefund`——彈
  `showInstallmentPeriodRefundChoiceSheet`,「只退這一期」找到對應
  `InstallmentPeriod`(找不到也不擋在 UI 層,讓 `repo.refundPeriod` 自己
  的查找/拋錯邏輯把關,UI 只是退化成用 `tx.amount` 當金額欄位預填的兜
  底)、打開 `InstallmentPeriodRefundSheet`、呼叫 `repo.refundPeriod`;
  「整筆退款」走**既有的破壞性操作二次確認 pattern**——`AppDialog.confirm`
  (跟 `installment_list_page.dart` 刪除分期計畫、`transaction_detail_
  card.dart` 自己的 `_handleDelete` 是同一套 pattern,沒有自創新的確認
  UI),確認後直接呼叫 `deleteInstallmentPlan`。兩個分支最後都走同一個
  `_finishInstallmentChange` 收尾。

一般(非分期)交易的退款/編輯路徑完全不受影響——只是在原本的
`if (tx.installmentPlanSyncId != null)` 分支前面各加一個判斷分流,原本呼叫
`TransactionEditUtils.refundTransaction`/`TransactionEditUtils.
editTransaction` 的路徑沒有變動。

## 3. l10n

只加到 `app_en.arb`/`app_zh_TW.arb`(既定政策),新增 16 個 key,前綴
`installmentEditChoice*`/`installmentRefundChoice*`/
`installmentRefundWholePlan*`/`installmentPeriodRefund*` +
`installmentRefundSuccess`。`flutter gen-l10n` 執行後 `app_zh.arb`/
`app_ko.arb` 的 untranslated 警告是預期內的(fallback 回英文模板)。

沒有刪除子專案 1 的 `transactionInstallmentLockedBanner`/
`transactionInstallmentLockedDeleteMessage` 兩個 key——`
transactionInstallmentLockedDeleteMessage` 仍被 `_handleDelete`/
`TransactionEditUtils.deleteTransactionGuarded` 使用(見上方「刪除沒有改
動」);`transactionInstallmentLockedBanner` 雖然不再出現在
`transaction_detail_card.dart`,但 `transaction_editor_page.dart` 的存檔
orchestration 裡還留著子專案 1 加的防呆(「萬一有別的入口直接構造這個
page 略過 detail card 那層攔截」),繼續用同一個 key,沒有動它。

## 4. 測試

### 4.1 `test/repositories/local/installment_repository_test.dart`

新增 `group('refundPeriod', ...)`(5 個測試,連同既有的全部 33 個測試都
過):

- 預設金額 = 該期 `totalAmount`、note 預設「分期退款」;期數標記
  `refunded`;原交易(分期期數本身那筆)不刪不改。
- `amount`/`note`/`happenedAt` 可各自覆寫預設值。
- **同一期重複退款拒絕**:第二次呼叫 `refundPeriod` 拋 `StateError`,且
  不會多建第二筆退款交易。
- 找不到 plan 或對應期數(`txId`)時拋 `StateError`。
- **§3.3 的關鍵驗證**:退款交易不受 `InstallmentManagedTransactionException`
  攔截——建立退款交易後直接呼叫一般的 `repo.deleteTransaction(refundTx.
  id)`,驗證 `completes`(不拋例外)且交易真的被刪除,同時驗證「原本那期
  (退款來源)的交易依然存在、依然掛著 `installmentPlanSyncId`,不受這次
  刪除退款交易影響」。

用到 phase2 文件記錄過的同一個測試技巧:Drift 的 `dateTime()` 欄位讀回來
`isUtc` 一律是 `false`,`DateTime.==` 連 `isUtc` 旗標都比,`happenedAt`
覆寫值的斷言要用 `isAtSameMomentAs` 而不是 `==`。

### 4.2 `test/widgets/transaction_detail_card_installment_test.dart`(新檔)

7 個 widget 測試,透過 `showTransactionDetailCard` 整條路徑驗證(不是只測
對話框本身回傳值),對齐要求的「`InstallmentEditChoiceDialog` 四個選項各
自正確導向對應操作、整筆退款正確呼叫 `deleteInstallmentPlan`」:

- 點編輯圖示彈出四選一對話框(取代唯讀鎖定 banner)。
- 選「修改此記錄」→ `updatePeriodOverride` 真的把期數標記 `overridden`。
- 選「修改連同未來」→ `rebalanceFrom` 成功執行(用成功 toast 文字驗證,
  重算細節已經在 repository 測試覆蓋過,這裡只驗證 UI 接得上)。
- 選「提前還本」→ `earlyRepayPrincipal` 真的建立一筆「分期部分還本」交
  易。
- 選「提前繳清」→ `payoff` 真的把計畫標記 `settled`。
- 選「只退這一期」→ `refundPeriod` 真的把期數標記 `refunded`、產生一筆
  `installmentPlanSyncId` 為 null 的退款交易。
- 選「整筆退款」→ 二次確認彈窗後真的呼叫 `deleteInstallmentPlan`(計畫
  跟全部交易一併消失)。

## 5. 跟設計文件不完全一致/自行判斷的地方(誠實記錄)

1. **`createThreePeriodPlan` 測試 helper 的 `firstPeriodAt` 用「現在 + 10
   天」而不是寫死日期**——一開始寫死 `DateTime.utc(2026, 1, 1)`,結果
   `earlyRepayPrincipal`/`payoff` 測試在系統當前日期(2026-09)下全部期數
   都已經「過去」,`earlyRepayPrincipal` 因為可分配本金池已經是 0 而合法
   地拋出「超過剩餘本金」,不是我原本要測的東西。這不是設計文件的問題,是
   我自己一開始沒注意到相對時間的坑,修正後改用相對「現在」的未來日期。
2. **`InstallmentEditChoiceDialog` 的 4 個選項圖標/殼子用了獨立複製的
   `_showChoiceSheet` 私有函式**,沒有把 `recurring_occurrence_dialogs.
   dart` 的同名私有函式重構成共用元件——兩邊各自不到 70 行,重構成共用
   元件的收益不足以抵銷「兩個看起來語意不同(週期規則 vs 分期計畫)的功
   能耦合到同一個共用檔案」的成本,判斷維持現狀比較安全。
3. **「只退這一期」時,若在 UI 層反查不到對應的 `InstallmentPeriod`(理
   論上不會發生),不在 UI 層擋下**,而是讓 `repo.refundPeriod` 自己的查
   找邏輯拋 `StateError`,UI 只是把預填金額退化成 `tx.amount`。這是為了
   不在 UI 層重複一份 repo 已經有的「找不到期數」判斷邏輯。
4. **`_applyPayoff` 的預覽結清金額計算跟 `installment_list_page.dart` 的
   `_openPayoff` 重複了一份**(已過去期數以外的剩餘本金 + 下一個未到期期
   的原排程利息近似值)——這是子專案 2 已經承認的既有簡化模式(純 UI 預
   覽,不是權威值,見 phase2 文件),這次只是在第二個入口(交易明細頁)
   照搬同一份邏輯,沒有進一步抽成共用函式。

## 6. 明確排除(子專案 4 範圍,這次沒做)

- `offsetExistingBalance`/`offsetBreakdownJson`/信用卡帳單分期沖銷。
- `account_detail_page.dart` 信用卡帳戶詳情頁的「轉為分期」入口。

## 7. 驗證

- `flutter analyze`:整個 repo 0 error(跟改動前一致);唯一新增的 info 是
  新測試檔案頂部的 `dangling_library_doc_comments`(這個 codebase 已有幾
  十個測試檔案是同款模式,不是新引入的問題類型)。
- `flutter test`:全專案 1048 個測試全過(1036 個既有 + 5 個新
  `refundPeriod` repository 測試 + 7 個新 widget 測試)。
