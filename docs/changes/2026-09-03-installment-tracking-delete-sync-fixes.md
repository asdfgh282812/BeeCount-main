# 分期付款(Installment)實機試用後的第二輪修正:刪除卡死 + 刷新遺漏 + 本金/利息拆分

日期:2026-09-03
背景:子專案 1~4(`2026-09-03-installment-tracking-phase{1,2,3,4}.md`)+ 第一輪
實機修正(`2026-09-03-installment-tracking-ux-fixes.md`)完成後,使用者再次
實機試用回報 4 個問題,難度/優先順序不同,依序記錄在這裡。設計規格原文見
`docs/superpowers/specs/2026-09-02-installment-tracking-design.md`。

## 問題 A(最優先):刪除分期後,單筆交易「刪不掉」

### 症狀

使用者原話:「server 端跟 app 端有時候會發生我已經按刪除分期交易了,但是實際
的所有明細無法刪除,又因為單筆交易被綁定,我也無法單筆刪除」,並要求單筆刪除
時改成問「刪除單筆還是整個分期交易」。

### 根因調查(完整結論)

**現狀確認**:`LocalRepository.deleteTransaction` 原本對
`tx.installmentPlanSyncId != null` 無條件丟 `InstallmentManagedTransactionException`
——不管對應的 `InstallmentPlans` 列是否還存在。這是使用者卡住的**直接**原因:
一旦本地出現「交易/`InstallmentPeriods` 還在,但 plan 已經不見了」的孤兒狀態
(不管什麼原因造成),使用者就進退兩難——分期管理頁找不到這個計畫可以整筆刪除
(因為 plan 已經沒了),單筆交易又被這個檢查攔住刪不掉。**這部分已經修好(見下方
A1),不管根因調查結果如何都要做,因為這是使用者當下卡住的直接死結。**

**根因假說逐一驗證**(對照 `lib/cloud/sync/` 實際程式碼,不是憑空猜測):

1. **假說:多筆 change(N*2+1 筆)批次推送,其中一筆失敗導致整批中止但已成功
   的部分被誤標記完成** ——**不成立**。看了 `sync_engine.dart::_doPush`:
   `provider.pushChanges(changes: syncChanges)` 把整批 change 包在**一次
   HTTP 請求**裡送出;`await changeTracker.markPushed(...)` 只在
   `pushChanges` **完全成功回傳**(不拋例外)之後才執行,`pushChanges` 內部
   (`packages/flutter_cloud_sync/.../beecount_cloud_provider.dart::pushEntityChanges`)
   也是單一 POST `/sync/push`,沒有把一批 change 拆成多個獨立 HTTP 請求。
   Server 端(`BeeCount-Cloud/src/routers/sync/push.py::push_changes`)這批
   change 的 DB 寫入全部在**同一個 SQLAlchemy session**、`db.commit()`
   只在整個 for 迴圈跑完後呼叫一次;`apply_change_to_projection` 拋例外時
   直接 `raise`(檔案自己的 docstring 也寫明「整批單事務提交,一條壞
   change 炸會帶 traceback 日誌並 rollback 整批」)。所以**「部分成功部分
   失敗」在目前的傳輸層/server 端不會發生**——一批 change 要嘛全部 commit,
   要嘛整批因為例外全部不 commit(client 端這批也就全部不會被
   `markPushed`,下次會重試)。

2. **假說(真正成立的根因):pull apply 沒有檢查「本地是否有尚未推送的
   delete」,導致本地剛刪除、還沒推送成功時跑了一次 pull,把 server 上
   (還不知道這條刪除)的舊版資料複活回本地** ——**成立,這是主要根因**。
   看了 `sync_engine_apply.dart::applyRemoteChange`:對任何 entity type 的
   upsert,套用前完全沒有檢查本地是否已經有一條同一實體的、尚未推送的
   `local_changes` delete 記錄。分期計畫刪除是本 app 目前唯一「一次操作產生
   N*2+1 筆獨立 change」的高強度多筆刪除情境(對照:debt 刪除見下方第 3
   點,完全沒有這個曝險),窗口期內只要發生任何一次 pull(WS 重連觸發的
   auto-sync、`sync.sync()` 內部的 push 之後緊接著 pull、或使用者手動下拉
   刷新),而 server 這時候還沒收到本地那批 delete(推送還在進行中,或者
   還沒排到),pull 拿到的就是 server 上這批交易/period 被刪除**前**的舊
   版本,`_applyTransactionChange`/`_applyInstallmentPeriodChange` 這些
   upsert handler 會原樣把它們 UPSERT 回本地——使用者體感正是「我明明刪除
   了,結果它自己又跑回來」。這個 race **不是 installment 專屬**——
   `applyRemoteChange` 對全部 entity type 都是同一套邏輯,只是 installment
   的「一次操作 N 筆刪除」把這個本來就存在、視窗很窄的 race 放大成「常態性
   偶發」(一般交易刪除永遠只有 1 筆 change,中獎機率遠低於一次要等 13 筆
   change 都推送完成的分期計畫刪除)。

3. **借還款(debt tracking)對照組**:`LocalDebtRepository.deleteDebt` 只刪
   `Debts` 這一張表的一列,**不會**連帶刪除起點交易/還款交易(這些交易本身
   要嘛從沒被刪、要嘛透過反向路徑——刪交易觸發自動刪 debt,見
   `LocalRepository.deleteTransaction` 尾端的 `getDebtByOriginTransactionSyncId`
   +`deleteDebt` 那段,方向永遠是「先刪 1 筆交易 → 順帶刪 1 筆 debt」,不是
   「1 個操作刪 N 筆交易」)。也就是說 debt 完全沒有「一次操作產生多筆刪除
   change」這個曝險場景,不是「debt 踩過這個坑後用某種方式避開」,而是它的
   刪除語意天生就不會觸發它。這也印證了「多筆刪除 race」跟
   installment 的資料模型(1 個 plan 對應 N 個 period + N 筆交易,而且刪除
   計畫要求「連帶刪光」)直接相關,不是通用交易刪除路徑本身的問題。

### 是否需要動 BeeCount-Cloud

**判斷:不需要,純 App 端 race,App 端修好就夠**——理由:

- 上面第 1 點已經確認 server 端的批次推送本身是單一事務、原子性沒有問題。
- 第 2 點的 race 發生在 App 端自己的「pull apply 沒有檢查本地 pending
  delete」這個邏輯缺口,跟 server 端如何處理這批 change 完全無關——即使
  server 端把已刪除的資料回傳得再準確,App 端只要在「本地已刪除但還沒推送
  成功」跟「這時候跑了一次 pull」這個時間窗口內,就會把舊資料原樣寫回本地
  DB,這是 App 端 apply 邏輯的責任。
- 沒有修改 `/Users/andy/BeeCount-Cloud` 的任何檔案——只讀了
  `src/routers/sync/push.py`(確認批次推送的事務邊界)做為調查證據,沒有
  改動,也沒有 push/deploy 任何東西。

### A1:UI 層改成「plan 還在時問使用者、plan 不在時直接放行」

- `lib/data/repositories/local/local_repository.dart` 的 `deleteTransaction`:
  `installmentPlanSyncId != null` 時先查一次
  `_installmentRepo.getInstallmentPlanBySyncId(...)`——plan 還存在才丟
  `InstallmentManagedTransactionException`(維持既有行為);plan 已經不存在
  (孤兒)時放行,並順手清掉指向這筆交易的孤兒 `InstallmentPeriods` 列(如果
  有的話,連同 ChangeTracker 的 delete change 一起記)。
- `lib/utils/transaction_edit_utils.dart` 的
  `TransactionEditUtils.deleteTransactionGuarded`(全部單筆刪除入口的共用
  函式)重寫:
  - `installmentPlanSyncId != null` 時先查一次 plan 是否存在。
  - plan 不存在(孤兒)→ 直接呼叫 `repo.deleteTransaction`(現在會放行),
    不顯示任何提示。
  - plan 存在、`showFeedback == true`(單筆刪除場景)→ 彈新的
    `showInstallmentTransactionDeleteChoiceSheet`(`InstallmentTransactionDeleteChoice`
    二選一,新增在 `lib/widgets/biz/installment_edit_choice_dialog.dart`,
    版面/風格照抄既有的 `InstallmentPeriodRefundChoiceDialog`)——「只刪除
    這一筆」呼叫下方 A2 的 `deletePeriod`;「刪除整個分期計畫」走既有的
    `AppDialog.confirm` 二次確認 + `deleteInstallmentPlan`。
  - plan 存在、`showFeedback == false`(`search_page.dart` 批量刪除等靜默
    場景)→ 維持原本「攔下、跳過」的行為,不彈互動對話框打斷批量操作。
- `lib/widgets/biz/transaction_detail_card.dart` 的 `_handleDelete`:對
  `installmentPlanSyncId != null` 的交易不再攔在最前面顯示 toast,改成直接
  委托給 `deleteTransactionGuarded`(它內部已經處理好孤兒放行/二選一/二次
  確認),不再疊一層通用的「確定刪除?」彈窗(避免三層彈窗疊加)。
- `lib/widgets/biz/transaction_list.dart` 的滑動刪除:原本在 `confirmDismiss`
  就用 `installmentPlanSyncId != null` 硬擋+toast(第一輪子專案 2 的暫時方
  案),這次也一併修掉——改成在 `confirmDismiss` 階段直接跑完整個
  `deleteTransactionGuarded` 互動流程(query plan → 二選一 → 可能的二次確
  認 → 實際刪除),用新增的 `_installmentDeletedInConfirmDismiss` 集合避免
  `onDismissed` 重複呼叫一次刪除。這是這次順手發現、原本沒有明確列在使用者
  回報清單裡的另一個「請去分期頁操作」殘留入口,一併修掉。
- `search_page.dart`/`category_detail_page.dart` 呼叫的都是同一個
  `deleteTransactionGuarded`,行為自動跟著改動同步更新,不用個別修改。

### A2:新增 `deletePeriod`——單純刪除一期

`InstallmentRepository`/`LocalInstallmentRepository`/`LocalRepository` 三層
都新增 `deletePeriod(int planId, int periodId)`:

- 刪除該筆 period + 其對應交易(`txId` 非 null 的話)。
- **不**重算/不動用其他期數的 principal/interest,也不牽涉「可分配本金池」
  概念——這是使用者要的「單純刪掉這一筆」,跟 `earlyRepayPrincipal`/`payoff`
  那種財務操作是不同語意,刻意不合併,不要因為「風格一致」就去動這條界線。
- 刪除後若這個計畫已經沒有任何 period,連帶刪除 plan 本身(自然收尾,避免
  留下 0 期的空殼計畫)。
- 跟子專案 2 的 5 個狀態變更操作同款分工:`LocalInstallmentRepository.deletePeriod`
  不是介面方法的 override(介面簽名 `Future<void>`),回傳
  `List<InstallmentChange>`,由 `LocalRepository.deletePeriod` 統一呼叫既有
  的 `_recordInstallmentChanges` 收尾——複用子專案 2 已經寫好的 ChangeTracker
  記錄管線,沒有重新發明一套。
- **設計取捨**:`deletePeriod` 校驗 `period.planSyncId == plan.syncId`(找不
  到 plan/period 或兩者不匹配都拋 `StateError`),跟 `updatePeriodOverride`
  等既有方法一致的錯誤處理風格。
- 測試(`test/repositories/local/installment_repository_test.dart` 新增
  group):「刪除單一期數不影響其他期數金額」「刪除最後一期連帶刪除 plan」
  「找不到 plan/period 拋 StateError」三個案例,加上 A1 修正對應的
  「plan 已不存在時 deleteTransaction 放行並清孤兒 period」「plan 仍存在時
  維持攔截」兩個案例。

### A3:pull apply 通用修法——套用 upsert 前檢查本地 pending delete

`lib/cloud/sync/change_tracker.dart` 新增
`ChangeTracker.hasPendingLocalDelete({entityType, entitySyncId})`——查
`local_changes` 是否有一條該實體、`action == 'delete'`、`pushedAt IS NULL`
的記錄。`lib/cloud/sync/sync_engine_apply.dart` 的 `applyRemoteChange` 在
switch 分派給具體 `_apply*Change` handler **之前**,對所有非 `delete` 的
action 呼叫這個檢查,命中就直接 `return false`(跳過這次 upsert)。

**這是刻意選的保守修法**:侵入面只有 `applyRemoteChange` 這一個入口的一行
判斷式,對全部 entity type 一視同仁生效(不是只修 installment),不動任何
`_apply*Change` handler 內部邏輯,風險可控。等本地那條 delete change 之後
正常推送成功,兩端會自然收斂為一致(已刪除);萬一那條 delete 在 push 端因
LWW 被 server 拒絕(見下方「已知殘留風險」),之後對同一實體的合法新
upsert 一樣能正常應用——已用測試驗證這個「不是永久卡死」的邊界情況。

測試:`test/sync/installment_apply_test.dart` 新增
「本地剛刪除計畫但還沒推送成功時,遠端 upsert 不會把它複活回來」+「delete
change 標記已推送後,之後的合法 upsert 不受影響」兩個案例,透過
`SyncEngine.pull('')` 真實 seam 驗證,不是只測 `ChangeTracker` 本身。

### 已知殘留風險(誠實記錄,這次沒有修)

Push 端(`sync_engine.dart::_doPush`)呼叫 `provider.pushChanges(changes: syncChanges)`
成功後,**無條件**把這批全部 change 標記 `markPushed`,完全沒有讀
`SyncPushResponse` 裡的 `accepted`/`rejected`/`conflict_count` 欄位。對照
server 端(`push.py`):batch 裡個別 change 若因為 LWW(`existing_tuple >
incoming_tuple`,即 server 上已經有一條更新的 change)被拒絕,是用
`continue` 跳過**不拋例外**——整批請求依然回 200,只是那一條被記進
`rejected`/`conflict_samples`。這代表:如果本地那條 delete change 恰好在
push 當下輸給 LWW(多裝置場景下,其他裝置對同一實體有更新的一筆變更),
client 端會誤以為這條 delete「已經推送成功」而永久不再重試,但 server 上
那個實體其實還活著——下次 pull 會把它重新拉回來,而且這次**不會**被 A3 的
新檢查擋下(因為 client 端已經標記 pushed,`hasPendingLocalDelete` 查不到
了)。

這是一個真實存在、但**沒有在這次修**的殘留風險,原因:

1. 觸發條件比 A3 修的那個 race 窄很多——需要真的有另一台裝置對同一個實體
   在時間上更晚寫入,單一裝置使用者幾乎不會踩到。
2. 修法需要 client 端解析 `SyncPushResponse` 逐條比對哪些 change 真的被
   接受、哪些被拒絕(目前 `pushChanges`/`pushEntityChanges` 只回傳
   `void`,要往上傳遞這個結構需要改 `packages/flutter_cloud_sync` 的公開
   API,再改 `sync_engine.dart::_doPush` 只 `markPushed` 真正 accepted 的
   change id)——影響面比 A3 的一行判斷式大很多,不屬於「保守修法」的範圍。
3. 這個風險本來就是 LWW 決勝機制天生的權衡(某個 change 輸了決勝、被更新
   的資料蓋過去,這在多裝置同步系統裡某種程度是預期行為),不是這次「單裝
   置操作導致資料消失又出現」症狀的成因。

如果之後使用者在多裝置環境下再次回報類似症狀,回頭看這裡,评估要不要做
push 端的 per-change 追蹤。

## 問題 B:帳戶頁看不到「無未繳分期」但列表頁有進行中的計畫

`transaction_editor_page.dart` 的漏 bump `installmentsRefreshProvider` 已經
由使用者自己修好(見 `2026-09-03-installment-tracking-refresh-fixes.md`),
這次逐一比對 `InstallmentRepository` 全部寫入方法(create/delete/
updatePeriodOverride/rebalanceFrom/earlyRepayPrincipal/payoff/
terminateFutureInstallments/refundPeriod + 這次新增的 deletePeriod)跟每個
呼叫點:

- `installment_list_page.dart`:全部 6 個狀態變更/刪除操作都經由
  `_refreshAndSync()`(或內聯同款寫法)bump `installmentsRefreshProvider` +
  觸發 `PostProcessor.sync`——**沒有遺漏**。
- `installment_editor_page.dart`:建立計畫成功後 bump——**沒有遺漏**。
- `transaction_detail_card.dart`:全部分期狀態變更/退款經由
  `_finishInstallmentChange` 統一收尾——**沒有遺漏**。
- `transaction_editor_page.dart`:交易表單建立分期(使用者已自行修好)——
  **沒有遺漏**。
- 這次 A2 新增的 `deletePeriod` 呼叫點(`transaction_edit_utils.dart` 的
  `_deleteManagedInstallmentTransaction`/`_deleteOrphanInstallmentTransaction`)
  ——新增時就直接寫對,bump `installmentsRefreshProvider` + 呼叫
  `PostProcessor.sync`。

**發現的真正遺漏(這次修掉)**:`lib/providers/credit_card_billing_providers.dart`
的 `defaultBillingPeriodOffsetProvider`/`accountBalanceAsOfProvider`/
`creditCardBillingBadgeProvider` 三個 provider(信用卡帳單彙總「應繳金額」
相關,`_dueAsOf` 內部讀 `getOffsetTotalForAccount`)只 `ref.watch(syncGenerationProvider)`。
追了 `syncGenerationProvider` 的 bump 邏輯(`sync_providers.dart`)發現它**只
在遠端 pull 真的 apply 到東西時才 bump**(`PullCompleted` 事件且
`applied > 0`)——本地寫入(例如 `installment_editor_page.dart` 建立一筆帶
`offsetExistingBalance` 的分期計畫)呼叫的 `PostProcessor.sync` 只 bump
`syncStatusRefreshProvider`/`ledgerListRefreshProvider`,不會直接 bump
`syncGenerationProvider`;而背景觸發的那次 `sync.sync()` 對「自己剛推送的
change」pull 回來時會被 `applyRemoteChange` 的
`change.updatedByDeviceId == deviceId` 檢查跳過(不計入 `applied`),所以
`PullCompleted(applied: 0)` 不會 bump `syncGenerationProvider`。結論:**本地
建立/刪除一筆帶沖銷的分期計畫,這三個 provider 完全不會自動刷新**,使用者
必須靠某個不相關的事件(例如遠端真的 pull 到別的東西)才會意外刷新——這正
是問題 D 描述的「換頁再回來才會刷新」的另一個真實例子(帳戶詳情頁的帳單彙
總卡片)。修法:三個 provider 都加上 `ref.watch(installmentsRefreshProvider)`,
跟其他頁面一致。

## 問題 C:列表頁看不到本金/利息拆分

`lib/pages/installment/installment_list_page.dart`:

- `_PeriodRow`(展開後的每期列表):原本只顯示 `totalAmount`,改成上下兩行
  ——上面維持 `totalAmount`(維持既有視覺重點),下面新增
  「本金 ¥X・利息 ¥Y」(`installmentPeriodPrincipalInterestLabel`)。純 UI
  呈現,`InstallmentPeriod.principalAmount`/`interestAmount` 欄位本來就存
  在,沒有動資料模型。
- `_InstallmentCardState`(卡片本身,collapse 狀態就看得到):進度條下方新
  增 `_buildPrincipalInterestSummary`——本金/利息各自的總計/已還/剩餘六個
  數字,`watch(installmentPeriodsProvider(plan.id))` 拿全部期數,依
  `dueAt <= now` 分「已還」、`dueAt > now` 分「剩餘」分別加總
  principalAmount/interestAmount。跟 `_openPayoff`/
  `transaction_detail_card.dart` 的 `_applyPayoff` 已有的「已過去/未過去」
  分組手法一致,**刻意獨立算一份、不抽共用函式**(純粹風格一致,這個計算
  本身不涉及 §0 核心不變量,不強制抽共用)。
- l10n 新增 `installmentPeriodPrincipalInterestLabel`/
  `installmentPrincipalSummaryLine`/`installmentInterestSummaryLine`(只加
  `app_en.arb`/`app_zh_TW.arb`)。
- 測試:`test/widgets/installment_list_page_principal_interest_test.dart`
  (新檔),透過整個 widget 樹渲染驗證計算結果(4 期計畫,直接把每期
  principal/interest/dueAt 改成可控固定值,2 期過去 2 期未來)——卡片摘要
  的六個數字、展開後每期的本金/利息文字都各自驗證。沒有把計算邏輯抽成獨立
  純函式(見上方說明),所以用 widget test 而不是純函式測試。

## 問題 D:「換頁再回來才會刷新」

使用者原話裡「交易已經刪除但交易還在」的描述,實質是問題 A 的同步 race(見
上方調查),已經在問題 A 處理(A1 UI 層放行 + A3 通用 pull 防護)。

完成問題 B 的審計後,額外發現並修掉的另一個真實例子:
`credit_card_billing_providers.dart` 的三個 `.autoDispose` provider 只
`watch(syncGenerationProvider)`,而 `syncGenerationProvider` 只在遠端 pull
真的 apply 到東西時才 bump——本地建立/刪除分期計畫這種純本地寫入涵蓋不到,
使用者停留在帳戶詳情頁時數字不會自動更新,需要離開頁面再回來(Riverpod
`autoDispose` provider 重新訂閱時才會重新計算)才看得到最新值,正好符合
「換頁再進去才會刷新」的描述。這個已經在問題 B 一併修掉(見上方)。

**判斷:問題 A + B 的修正已經涵蓋使用者描述的全部現象,沒有再額外發明「每次
進頁面強制重新查詢」這種通用機制**——那會跟現有的 Riverpod provider 快取/
watch 架構衝突,而且審計下來沒有找到問題 A/B 涵蓋不到、非同步/非
provider-watch 遺漏的殘留刷新問題。`transaction_list.dart` 的滑動刪除入口
(見問題 A1)算是這次額外發現、原本沒被使用者明確提到的同類「請去別的頁面
操作」殘留入口,已經一併修掉,但它跟「換頁才刷新」屬於不同性質(那個是硬性
攔截,不是刷新遺漏)。

## 改動檔案清單

- `lib/data/repositories/installment_repository.dart`——新增 `deletePeriod`
  介面方法。
- `lib/data/repositories/local/local_installment_repository.dart`——實作
  `deletePeriod`。
- `lib/data/repositories/local/local_repository.dart`——`deleteTransaction`
  加入 plan 存在性檢查(A1)+ 孤兒 period 清理;新增 `deletePeriod` 委托
  (A2)。
- `lib/cloud/sync/change_tracker.dart`——新增 `hasPendingLocalDelete`(A3)。
- `lib/cloud/sync/sync_engine_apply.dart`——`applyRemoteChange` 套用
  `hasPendingLocalDelete` 檢查(A3)。
- `lib/widgets/biz/installment_edit_choice_dialog.dart`——新增
  `InstallmentTransactionDeleteChoice`/
  `showInstallmentTransactionDeleteChoiceSheet`(A1)。
- `lib/utils/transaction_edit_utils.dart`——`deleteTransactionGuarded` 重寫
  (A1)。
- `lib/widgets/biz/transaction_detail_card.dart`——`_handleDelete` 改走共用
  入口(A1)。
- `lib/widgets/biz/transaction_list.dart`——滑動刪除改走共用入口的完整互動
  流程(A1,額外發現)。
- `lib/services/maintenance/orphan_record.dart`/`orphan_scanner.dart`/
  `orphan_cleaner.dart`——新增 A11/A12/A13 三種分期孤兒檢測(A4,保底自救
  工具)。
- `lib/providers/credit_card_billing_providers.dart`——三個 provider 補
  `installmentsRefreshProvider`(B/D)。
- `lib/pages/installment/installment_list_page.dart`——本金/利息拆分 UI
  (C)。
- `lib/l10n/app_en.arb`/`app_zh_TW.arb`——新增 l10n key(A1 + C)。
- 測試:`test/repositories/local/installment_repository_test.dart`、
  `test/maintenance/orphan_scanner_test.dart`、
  `test/maintenance/orphan_cleaner_test.dart`、
  `test/sync/installment_apply_test.dart`、
  `test/widgets/transaction_edit_utils_delete_guarded_test.dart`(改寫)、
  `test/widgets/installment_list_page_principal_interest_test.dart`(新檔)。
- **沒有修改** `/Users/andy/BeeCount-Cloud` 的任何檔案(只讀取
  `src/routers/sync/push.py` 作為調查證據,結論是純 App 端 race,不需要動
  server 端,見上方「是否需要動 BeeCount-Cloud」)。

## 驗證

- `flutter analyze`:跟改動前的 issue 清單(error/warning 層級)完全一致
  (用 diff 比對過,零新增),新增的 info 都是既有模式
  (`use_build_context_synchronously` 等)。
- `flutter test`:全專案 1075 個測試全過(1057 個既有 + 這次新增 18 個),
  1 個既有的網路相關測試 skip(跟這次改動無關,沙盒環境沒有外網存取)。
