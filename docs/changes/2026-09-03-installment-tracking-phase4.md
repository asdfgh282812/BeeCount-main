# 分期付款(Installment)子專案 4:信用卡帳單分期沖銷

日期:2026-09-03
對應設計文件:`docs/superpowers/specs/2026-09-02-installment-tracking-design.md`
(本次只做文件標示「子專案 4」的範圍:§1.1 最後一句、§3.4(全部)、§5.4(UI)、
§7 第四項(測試))。
先例:`docs/changes/2026-09-03-installment-tracking-phase1.md`(子專案 1)、
`phase2.md`(子專案 2)、`phase3.md`(子專案 3)——本次在三者的基礎上繼續,
`InstallmentPlans`/`InstallmentPeriods`/建立/列表/五個狀態變更操作/退款流程都
已就緒,這次不動。**這是分期付款功能 4 個子專案的最後一塊,完成後整個功能
實作全部結束。**

## 0. 先搞懂「沖銷」到底是什麼語意(對照 Cloud 原始碼)

設計文件 §3.4 本身寫得比較精簡,動手前先讀了 `../BeeCount-Cloud/src/routers/
write/installment_plans.py`(`create_installment_plan_ep`)跟
`../BeeCount-Cloud/src/services/credit_card_billing.py`(`compute_offset_
totals`/`compute_group_billing`)確認語意,這裡记录关键结论,避免下一個
維護者重新逆向一次:

- **沖銷不是「不建立分期」**——即使 `offsetExistingBalance=true`,還是照樣呼叫
  `computeInstallmentPeriods` 產生 N 期 `InstallmentPeriods` + N 筆
  `Transactions`(跟一般分期完全一樣)。沖銷只是**額外**把
  `{accountSyncId: totalAmount}` 寫進 `offsetBreakdownJson`。
- 這張卡「既有的欠款」本來就是之前某些真實消費交易產生的,轉分期**不會刪除
  或修改**那些原始交易——沖銷的作用只是在讀「這張卡目前應繳多少」時,把這筆
  已經被轉成分期的金額從「應繳」裡扣掉,避免「舊消費」+「新分期各期」兩邊
  都被算成欠款(重複計入)。
- Cloud 端這個扣除**只影響 `remaining_due`(應繳/能不能重複轉分期的判斷)**,
  **不影響 `credit_used`(信用卡已用額度)**——見
  `credit_card_billing.py:236-245` 的註解:「轉成分期只是把『怎麼付』拆開,
  不代表額度立刻恢復」。App 端這次的實作跟這個決策對齐(見下方 §3)。

## 1. 資料模型(`lib/data/db.dart`)

`InstallmentPlans` 新增 `offsetBreakdownJson`(text,nullable)。`schemaVersion`
49 → 50,`onUpgrade` 補一段 `_addColumnIfMissing('installment_plans',
'offset_breakdown_json', ...)`,照抄 v46/v47 那種「單欄位 ALTER」的既有寫法
(不需要動 `onCreate`,`createAll()` 已經涵蓋新欄位)。

**JSON 內部結構自行設計**(設計文件把這個留給子專案 4 決定):
`{accountSyncId: amount}`——鍵是帳戶 [`Accounts.syncId`](不是本地 int
`accountId`)、值是這筆分期沖銷掉的金額。之所以選 syncId 當鍵而不是本地
int id,是因為這個欄位會透過 `entity_serializer.dart` 原封不動同步到其他
裝置——如果鍵是本地 int,裝置 A 建立的沖銷記錄同步到裝置 B 之後,B 本地的
`accountId` 很可能是不同的整數,`getOffsetTotalForAccount` 在 B 上就永遠比對
不到,沖銷會在 B 上悄悄失效(App 卻不會有任何錯誤提示)。用 syncId 當鍵才能
保證跨裝置比對正確,同時也跟 Cloud 用 `child_account_sync_id` 當鍵的形狀
一致。目前 App 只支援單一帳戶沖銷,所以這個 map 恆為單一 key,但沿用 map
形狀(而不是攤平成兩個欄位)是為了未來若要支援合併帳單群組分攤沖銷時不必
再改資料結構。

`Accounts.syncId` 一般帳戶建立時一律會產生(`LocalAccountRepository.
createAccount` 的 `syncId ?? _uuid.v4()`),但為了不對「理論上不會發生、實務
上只有測試 fixture 才會出現」的 `syncId == null` 情況丟例外,寫入端跟讀取端
(`getOffsetTotalForAccount`)都用同一條 fallback 規則:`account.syncId ??
accountId.toString()`,兩邊保持對稱。

## 2. Repository

### 2.1 `createInstallmentPlan` 新增 `offsetExistingBalance` 參數

`lib/data/repositories/installment_repository.dart`(介面)+
`lib/data/repositories/local/local_installment_repository.dart`(實作)。校驗
順序(在既有的 §1.4 業務規則、`computeInstallmentPeriods` 呼叫之前):

1. `offsetExistingBalance=true` 但沒帶 `accountId` → `ArgumentError`。
2. 帳戶 `type == 'account_group'` → `ArgumentError`(見下方 §5「範圍決策」)。
3. 該帳戶目前可沖銷的應繳餘額(`getCreditCardOffsetableBalance`)`<= 0.005`
   → `ArgumentError`(視為沒有欠款可沖銷)。
4. `totalAmount > due + 0.01`(容許 0.01 浮點誤差,對齐 Cloud
   `req.total_amount > total_due + 0.01` 的判斷,設計文件字面沒提這個容差,
   是照抄 Cloud 補上的)→ `ArgumentError`。

通過校驗後 `offsetBreakdownJson = jsonEncode({accountSyncId: totalAmount})`,
一併寫進 `InstallmentPlansCompanion.insert`。**沖銷這部分本身不建立任何
`Transactions`**——這不是「跳過」什麼,而是本來就沒有一步是「為沖銷本身建
交易」;N 期分期交易照常生成,跟一般分期完全一樣。

### 2.2 兩個新查詢方法

- **`getOffsetTotalForAccount(accountId)`**:掃全部 `InstallmentPlans.
  offsetBreakdownJson`(不看 `status`——任何狀態的計畫只要沒被整筆刪除,沖銷
  就持續生效),依帳戶 key 加總。供 `credit_card_billing_providers.dart`
  扣除用。
- **`getCreditCardOffsetableBalance(accountId)`**:單一帳戶版的「目前應繳」
  公式(`getCreditCardChargedAsOf(now) - getOffsetTotalForAccount -
  getCreditCardPaidTotal`,floor at 0),跟 `credit_card_billing_providers.
  dart::_dueAsOf` 的單帳戶情境算法完全一致,是 `createInstallmentPlan`
  自己驗證時用的同一個權威來源,也給編輯頁 UI 顯示/夾上限用——**不會**跟
  實際校驗結果對不上。

這兩個方法跟子專案 1 的 `getOutstandingPrincipalAllLedgers` 一樣,是設計文件
沒有明確列出方法名、但實作/UI 需要而自行加的(同款「介面之外必要時補
方法」的既有模式)。

實作上直接 new 了一份 `LocalAccountRepository(db)`(`local_installment_
repository.dart` 內部),複用它既有、已被 `credit_card_billing_providers.
dart` 驗證過的 `getCreditCardChargedAsOf`/`getCreditCardPaidTotal`,不重寫
一份 SQL——`LocalAccountRepository` 本身是 `db` 的無狀態包裝,另外建一份不會
跟 `LocalRepository._accountRepo` 那份互相干擾。

### 2.3 `LocalRepository` 委托層

`createInstallmentPlan` 轉發新增的 `offsetExistingBalance` 參數;兩個新查詢
方法委托給 `_installmentRepo`,不涉及 ChangeTracker(純查詢)。

### 2.4 刪除計畫自動失效——驗證而非新增邏輯

按設計文件要求,`deleteInstallmentPlan`(子專案 1 寫的)**沒有改動**——
`offsetBreakdownJson` 只是 `InstallmentPlans` 表上一欄,整列被刪自然一起消
失。用測試(見 §6)驗證這一點,不是新寫清理程式碼。

## 3. 信用卡帳單彙總計算讀取 `offsetBreakdownJson`

### 3.1 先搞清楚 App 目前有哪些「帳單彙總/淨資產」計算

動手前先搜了一遍,確認目前有兩條**互相獨立**的計算路徑,行為/用途都不同:

1. **`lib/providers/credit_card_billing_providers.dart`**(`_dueAsOf`,被
   `accountBalanceAsOfProvider`/`creditCardBillingBadgeProvider`/
   `defaultBillingPeriodOffsetProvider` 共用)——`account_detail_page.dart`
   信用卡帳戶詳情頁「帳單彙總卡片」的「應繳金額」/「剩餬帳款」、帳戶列表
   「可繳款」徽章都靠這個。對齐 Cloud `credit_card_billing.py::
   compute_group_billing`/`compute_cycle_period_billing` 的 `remaining_due`
   /`per_child_remaining_due`。
2. **`LocalAccountRepository.getAccountBalance`**(被 `getNetWorthBreakdown`
   /`getNetWorthBreakdownByCurrency`/`getNetWorthTrendSeries` 等淨資產計算
   共用)——純粹加總這個帳戶身上全部 `expense`/`income`/`transfer`/
   `adjustment` 交易,不管信用卡帳單週期概念。對齐 Cloud `workspace.py`
   算 `balance`/`net_worth` 的邏輯。

**只改了第 1 條**(`_dueAsOf` 加一行 `charged -= await repo.
getOffsetTotalForAccount(id)`),**沒有改第 2 條**(`getAccountBalance`/淨
資產計算維持原樣)。理由:

- 這是直接對照 `../BeeCount-Cloud/src/services/credit_card_billing.py` 逐行
  確認過的——`compute_offset_totals` 只被 `compute_group_billing`/
  `compute_cycle_period_billing` 呼叫(算 `remaining_due`),Cloud 的
  `workspace.py`(算 `balance`/`net_worth`,對應 App 的 `getAccountBalance`/
  淨資產計算)**完全沒有**任何 `offset` 相關的程式碼路徑,搜了整個檔案確認
  過。也就是說 Cloud 自己的淨資產計算就是不讀這個欄位的。
- `getAccountBalance` 是全 App 極高頻共用的方法(交易列表顯示的帳戶餘額、
  CSV 匯出、對帳、`getAccountGlobalBalance`/`getAccountBalanceInLedger` 等
  多個地方間接依賴同一套邏輯),改動它的風險遠高於範圍明確得多的
  `_dueAsOf`。

**這是一個跟設計文件字面(§3.4:「既有的信用卡帳單彙總計算(帳戶餘額/淨資產
相關方法)要讀 offsetBreakdownJson」)不完全一致的判斷,誠實記錄在這裡,也
在 §7「已知限制」裡再提一次給使用者看**:設計文件的措辭把「帳戶餘額」/
「淨資產」也點名了,但實際去對照 Cloud 原始碼後,Cloud 自己的淨資產/帳戶
餘額計算並不讀這個欄位,只有「應繳」計算讀。我判斷設計文件這句話的「帳戶
餘額」實際上指的就是「信用卡帳單彙總卡片顯示的應繳/剩餬帳款那個數字」
(account_detail_page.dart 裡程式碼註解自己就叫它「帳戶餘額」的 asOf
快照),不是廣義的「這個帳戶的淨資產貢獻」。如果之後使用者反饋淨資產也需要
扣沖銷,再回來對照這裡的決策改。

### 3.2 已知的殘留量化落差(繼承自 Cloud,不是這次引入的新 bug)

因為 §3.1 的決策(不改 `getAccountBalance`/淨資產),存在一個使用者可能會
觀察到的現象,誠實記錄:轉成沖銷分期之後,舊的欠款交易本身沒有被刪除或修改
——當新分期各期陸續到期、產生的交易被 `getAccountBalance` 算進「已發生」
的餘額時,這張卡的**淨資產貢獻**/**帳戶餘額顯示**會比實際欠款更負(因為舊
消費 + 新分期各期兩邊都被 `getAccountBalance` 算進去了),要等到分期全部
繳清才會回到正確值。**這不是這次改動引入的 bug,是 Cloud 自己的既有設計就
是這樣**(§3.1 已確認 Cloud 的 workspace 淨資產計算完全不讀
`offset_breakdown_json`)。「應繳金額」(帳單彙總卡片顯示的那個數字)在整個
過程中都是正確的,不受這個落差影響。

## 4. 同步

`entity_serializer.dart::serializeInstallmentPlan` 新增 `offsetBreakdownJson`
鍵,恆發(同 `note` 的模式,null 也發)——對齐 Cloud `sync_applier.py` 的
`("offsetBreakdownJson", "offset_breakdown_json")`。內容已經是
syncId-keyed 的 JSON 字串,兩端不需要轉換鍵值,原樣傳遞即可。
`sync_engine_apply.dart::_applyInstallmentPlanChange` 的 upsert 分支(update
跟 insert 兩處)都補上這個欄位的讀取/寫入。

## 5. UI

### 5.1 `installment_editor_page.dart`

新增 `initialAccountId`/`initialOffsetExistingBalance` 兩個建構參數,給
`account_detail_page.dart` 的「轉為分期」按鈕預填用;一般從分期列表頁 FAB
進入時兩者都是預設值,行為跟子專案 1~3 一致。

帳戶選好且是 `credit_card` 類型時才顯示「沖銷現有欠款」卡片(`account_
group`/其他類型不顯示,見下方「範圍決策」)。切換開啟時非同步呼叫
`getCreditCardOffsetableBalance` 查目前可沖銷金額,沒有欠款時自動跳回關閉
狀態並提示。「勾選時鎖定 totalAmount 上限為目前欠款金額」(設計文件 §5.4)
的實作是:在 `_totalAmountController` 上掛一個 listener,使用者打字超過
`_offsetableDue` 時即時把輸入夾回上限值(不是把欄位設成唯讀——允許部分沖銷,
使用者可以打比上限小的數字)。存檔前另外再做一次防禦性校驗(`_save` 裡),
repository 端還有第三層權威校驗,三層都在同一個數字上,不會互相打架。

換帳戶(或清空帳戶)時會重置沖銷開關跟已查到的上限值,避免殘留上一張卡的
數字誤導使用者。

### 5.2 `account_detail_page.dart`

信用卡帳戶詳情頁「交易明細」tab 的帳單彙總卡片下方新增「轉為分期」按鈕
(`_buildConvertToInstallmentButton`,樣式對齐既有「帳戶資訊」tab 的
「立即繳款」`OutlinedButton.icon`),點擊帶 `initialAccountId: account.id`
進 `InstallmentEditorPage`;`initialOffsetExistingBalance` 只在
`account.type == 'credit_card'`(不是 `account_group`)時為 `true`——群組
場景下這顆按鈕退化成單純「幫你把 accountId 預填好」的捷徑,沖銷開關不會
自動勾選(因為群組不支援沖銷,見下方「範圍決策」),使用者仍可以在編輯頁
自己選單一子卡再手動勾選。

## 6. 範圍決策:不支援合併帳單群組(`account_group`)的沖銷

設計文件 §3.4 沒有明確提到群組場景怎麼處理。讀了 Cloud 原始碼後發現 Cloud
是支援的——`compute_card_payment_allocations` 會把沖銷金額按各子卡目前應繳
比例分攤(跟繳款分攤同一套演算法),`offset_breakdown` 會是多個子卡各自的
金額。

這次**刻意不做群組沖銷**,`createInstallmentPlan(offsetExistingBalance:
true)` 遇到 `account.type == 'account_group'` 直接拋 `ArgumentError`,UI
上也只在選了單一信用卡時才顯示沖銷開關。理由:

- 群組的「應繳」需要先聚合全部子卡(`resolve_billing_children`)再按比例
  分攤,這條路徑目前只存在於 `credit_card_billing_providers.dart`(Riverpod
  provider 層,靠 UI 傳入 `extraIdsKey`),repository 層(`LocalInstallment
  Repository`)目前沒有「查詢某個 `account_group` 底下所有子卡」的方法,
  要嘛新增這條查詢路徑,要嘛把分攤演算法整個搬進 repository 層——工作量
  明顯超出這次「加一個沖銷開關」的範圍。
- 單一信用卡(App 裡絕大多數使用者的實際場景)已經完整支援,群組沖銷可以
  留給之後有需求時再做一個獨立的小改動,不阻塞這次的主要功能。

這是這次唯一一處在設計文件沒有明確要求的地方主動縮小範圍,誠實記錄。

## 7. l10n

只加到 `app_en.arb`/`app_zh_TW.arb`(既定政策),8 個新 key,前綴
`installmentOffset*`/`installmentConvertToInstallmentButton`。
`flutter gen-l10n` 執行後 `app_zh.arb`/`app_ko.arb` 的 untranslated 警告是
預期內的(fallback 回英文模板)。

## 8. 測試

`test/repositories/local/installment_repository_test.dart` 新增
`group('offsetExistingBalance / 帳單分期沖銷(子專案4)', ...)`(7 個新測試,
連同既有的全部 40 個測試都過):

- `offsetExistingBalance=true` 但沒帶 `accountId` → `ArgumentError`。
- 目前應繳餘額 `<= 0.005`(沒有欠款)→ `ArgumentError`。
- `totalAmount` 超過目前應繳餘額 → `ArgumentError`。
- `account_group` 帳戶 → `ArgumentError`(範圍決策,見 §6)。
- **沖銷成功**:驗證帳戶上的交易數只多了 N 期分期交易(沒有額外一筆「沖銷」
  交易)、`offsetBreakdownJson` 內容正確(含帳戶 syncId 跟金額)、
  `getOffsetTotalForAccount`/`getCreditCardOffsetableBalance` 讀出來的值
  正確(**這是 §3 那條「避免重複計入」要求的直接驗證**,不只是驗證寫入,
  也驗證讀取端真的把數字扣對了)。
- 部分沖銷:`totalAmount` 小於目前欠款時,只沖銷實際轉換的部分,剩餘欠款
  正確反映。
- **刪除分期計畫後沖銷記錄自動失效**:刪除前 `getOffsetTotalForAccount`
  正確、刪除後歸零,原本被沖銷掉的舊欠款重新算回應繳餘額(這是設計文件
  §3.4「不需要額外清理邏輯」的直接驗證,順便確認了 phase1 的
  `deleteInstallmentPlan` 確實自動涵蓋這點,沒有另外改動它)。

### 驗證

- `dart run build_runner build` 成功兩次(db.dart 改完後一次、全部改完後
  再一次確認冪等)。
- `flutter analyze`:整個 repo 0 error(跟改動前一致);info/warning 數量
  (860)沒有因為這次改動增加新的問題類型(逐一核對過,新增的檔案/區塊都是
  乾淨的)。
- `flutter test`:全專案 **1055** 個測試全過(1048 個既有 + 7 個新
  `offsetExistingBalance` repository 測試),沒有回歸。

## 9. 對整個分期功能(4 個子專案)的整體觀察

這次順手看過前三個子專案的程式碼跟文件,以下是**沒有明確要求我修但值得
使用者知道**的既有觀察,這次刻意沒有動手改:

1. **§3 提到的淨資產/帳戶餘額殘留落差**(見上方 §3.2)是這次子專案 4 才會
   真正出現的現象(沒有沖銷功能之前不會發生),但它的根因是「淨資產計算
   不讀 offsetBreakdownJson」這個**這次主動做的範圍決策**,不是遺留 bug。
   如果之後使用者反饋這個很困擾,回頭看 §3.1 的決策理由再評估要不要把
   `getAccountBalance` 也改成讀取 offset(需要仔細評估對其他呼叫點的
   影響)。
2. **群組(`account_group`)沖銷不支援**(見 §6)——如果之後有使用者需要對
   合併帳單的信用卡群組做帳單沖銷,需要先在 repository 層補一個「查詢群組
   子卡」的方法,再照抄 Cloud `compute_card_payment_allocations` 的分攤
   演算法。
3. Phase 1 文件記錄的「`transaction_entry_form.dart` 的『設為分期』入口
   沿用了表單既有的帳戶必填校驗,跟獨立 `InstallmentEditorPage` 行為不
   完全一致」、phase 2 文件記錄的「`_applyComputedPeriod`/
   `_deletePeriodAndTx` 兩個 I/O helper 被多個狀態變更操作共用」、phase 3
   文件記錄的「`InstallmentEditChoiceDialog` 用獨立複製的 `_showChoiceSheet`
   沒有跟 `recurring_occurrence_dialogs.dart` 共用」——這幾個都是前三個
   子專案自己文件裡已經誠實記錄過的已知簡化,這次沒有再重新檢視或改動,
   附註在這裡方便使用者一次看到分期功能全部 4 個子專案累積下來的已知
   簡化清單全貌。
4. 整個分期功能(4 個子專案)到這裡**全部完成**——核心資料模型/建立/列表
   (子專案 1)、狀態變更操作(子專案 2)、退款+編輯選擇整合(子專案 3)、
   信用卡帳單分期沖銷(子專案 4)。沒有發現任何額外的、範圍在 4 個子專案
   之內卻被遺漏的功能點。
