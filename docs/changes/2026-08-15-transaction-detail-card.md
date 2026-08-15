# 交易資訊卡 + 退款 + 複製

日期:2026-08-15
背景:點擊交易列表原本會直接進 `TransactionEditorPage` 編輯。改成先彈出一張
唯讀的「交易資訊卡」(bottom sheet),右上角提供退款/刪除/複製/編輯四個動作,
中間最大區塊顯示附圖(沒有圖就顯示分類圖示+名稱)。退款、複製這兩個功能之前
完全沒有實作,已對照 BeeCount Cloud(`../BeeCount-Cloud`)網頁版既有邏輯補齊,
其中退款的伺服器端(`refund_of_sync_id`、`refundOfId` wire key、
`_assert_refund_target_not_already_refunded` 業務規則)早就上線,只是 App 端
從未接上。

## 1. 新增交易資訊卡

**改了什麼**:新檔案 [`lib/widgets/biz/transaction_detail_card.dart`](../../lib/widgets/biz/transaction_detail_card.dart),
`showTransactionDetailCard(context, ref, transaction, category)` 用既有的
bottom sheet 慣例(`isScrollControlled: true` + `BeeTokens.surfaceSheet` +
圓角頂部)開卡片。原本 5 個呼叫 `TransactionEditUtils.editTransaction()` 的
列表 onTap(`transaction_list.dart`、`tag_detail_page.dart`、
`search_page.dart`、`category_detail_page.dart` ×2、`calendar_page.dart`)
全部改呼叫這個函式;卡片內部的「編輯」按鈕才呼叫原本的 `editTransaction()`。

卡片版面:頂列左上關閉/右上退款+刪除+複製+編輯;中間依附件是否存在顯示全解
析度圖片(`AttachmentService.getAttachmentPath`,點擊進既有的
`AttachmentPreviewPage.fromTransaction`)或大尺寸分類圖示+名稱;下面依序是
備註+金額列、帳戶/標籤/商家/週期狀態/日期時間的兩欄細節列、以及(若這筆交易
已被退款)已退款清單。

**刻意不做**:設計稿裡的「紅利回饋」列(信用卡回饋規則,BeeCount Cloud 的
`card_reward_rule`)沒有對應的本地資料,這次不顯示這一欄。「單次/週期」列
直接讀取既有但目前寫入路徑從未使用的 `transactions.recurringId`——現況下永遠
顯示「單次」,純粹忠實反映現有資料,沒有新增任何功能。

## 2. 複製交易(無 schema 變更)

**改了什麼**:[`lib/utils/transaction_edit_utils.dart`](../../lib/utils/transaction_edit_utils.dart)
新增 `TransactionEditUtils.copyTransaction()`,把原本 `editTransaction()` 解析
tag/category/account override 的邏輯抽成共用的 `_resolveRefs()`,複製時開一個
新建模式的 `TransactionEditorPage`,帶入除了「日期」「附件」「退款關聯」以外
的所有欄位。

**為什麼日期不帶**:比照 BeeCount Cloud 網頁版「複製」的既有行為——複製出來
是全新獨立記錄,日期重設為現在,不寫任何資料庫關聯,附件也不複製。

## 3. 退款交易(新增 `refundOfSyncId` 欄位 + 同步)

**改了什麼**:

- [`lib/data/db.dart`](../../lib/data/db.dart):`Transactions` 表新增
  `refundOfSyncId`(nullable text,存原交易的 `syncId` 而非本地 int id,因為
  本地 id 跨裝置不穩定),`schemaVersion` 33→34。
- Repository 三層(`transaction_repository.dart` 抽象介面、
  `local_transaction_repository.dart` 實作、`local_repository.dart` 包裝層):
  `addTransaction()` 新增 `refundOfSyncId` 參數;新增
  `getRefundsOf(originalSyncId)`(查誰退了這筆交易)、既有的
  `getTransactionBySyncId()` 沿用。
- [`lib/cloud/sync/entity_serializer.dart`](../../lib/cloud/sync/entity_serializer.dart):
  `serializeTransaction` 有值才發 `refundOfId`(wire key **必須**是這個名字,
  跟 BeeCount Cloud `sync_applier.py` 既有的 merge spec
  `("refundOfId", "refund_of_sync_id")` 對齊,改名字會讓關聯跨裝置同步不到)。
- [`lib/cloud/sync/sync_engine_apply.dart`](../../lib/cloud/sync/sync_engine_apply.dart):
  `_applyTransactionChange` 用 `containsKey('refundOfId')` 判斷缺鍵時不覆蓋
  本地已有的關聯(跟 `excludeFromStats` 同款保護,不能比照 `merchant` 的「恆
  發/恆覆蓋」,因為舊版 App 送出的 payload 不會帶這個新鍵)。
- [`lib/utils/transaction_edit_utils.dart`](../../lib/utils/transaction_edit_utils.dart):
  `refundTransaction()` 開新建模式編輯器,類型對調(expense↔income)、金額
  (可改,天然支援部分退款)/備註/帳戶帶入原交易,分類留空讓使用者自己選(App
  沒有網頁版那種伺服器自動指定「退款」分類的機制)。
- [`lib/pages/transaction/transaction_editor_page.dart`](../../lib/pages/transaction/transaction_editor_page.dart):
  新增 `initialRefundOfSyncId`,只在新建分支的 `addTransaction()` 呼叫傳入。
- 新增 [`test/sync/transaction_refund_apply_test.dart`](../../test/sync/transaction_refund_apply_test.dart),
  比照 `transaction_exclude_flags_apply_test.dart` 的模式驗證插入/缺鍵保留。

**業務規則只做 App 端 best-effort**:一筆交易只能被退一次、退款單不能再被
退款——資訊卡用 `getRefundsOf()`/`refundOfSyncId != null` 在 UI 層 disable
退款按鈕,**不**在寫入路徑做伺服器等級的強制校驗。本 App 是 local-first,多
裝置離線建立時理論上仍可能競態出現兩筆退款,視為可接受的邊界情況。

**不需要改的地方**:其他雲端同步後端(Supabase/WebDAV/S3/iCloud,
`packages/flutter_cloud_sync_*`)只是通用 payload 傳輸層,不解讀特定欄位,
不用改。BeeCount Cloud 伺服器端這個功能本來就已經上線,不需要改動。

## 驗證

- `dart run build_runner build --delete-conflicting-outputs` 重新產生
  `db.g.dart`
- `flutter test`(637 個測試全過,含新增的 2 個退款 apply 測試)
- `flutter analyze` 無新增 error

## 5. 後續修正:刪除/退款後畫面不會立即更新

**問題**:資訊卡的刪除/退款/複製/編輯 4 個動作完成後,部分頁面的交易列表要
手動刷新才會反映最新狀態。

**根因分兩種**:

1. **`lib/pages/calendar/calendar_page.dart`**——月曆頁的每日交易/統計是
   `FutureProvider`(`lib/providers/calendar_providers.dart`),不會因 Drift
   寫入自動重算,得靠 `calendarRefreshProvider` 這個計數器手動觸發;舊的
   `TransactionEditUtils.editTransaction()` 直接呼叫並 `await`,呼叫方能在
   它關閉後接刷新邏輯,但改成 `showTransactionDetailCard()` 後,卡片內的
   複製/退款/編輯是先 `Navigator.pop()` 關卡片、再另外在 `hostContext` 上
   push 編輯器頁——呼叫方 `await showTransactionDetailCard(...)` 在卡片關閉
   當下就返回了,根本等不到編輯器頁真正存檔關閉。
2. **`lib/pages/transaction/search_page.dart`**——`_searchResults`(畫面上
   實際渲染的列表)是從 `_allTransactions`(Stream 驅動,會自動更新)在本地
   同步過濾出的 `State` 快照,只有打字/篩選/批次操作後才會重新計算,不會因
   為 Stream 有新資料就自動重跑。

**修法**:兩個頁面改成監聽 `statsRefreshProvider`(`lib/providers/statistics_providers.dart`,
全域「交易有變更」信號,`transaction_detail_card.dart` 的 `_handleDelete()`
與 `transaction_editor_page.dart` 的 `_handleSubmit()` 都會在變更真正完成的
當下 bump 它,不管是哪個頁面開的卡片、也不管是刪除還是後續另開的編輯器頁存
檔)——用 `ref.listen<int>(statsRefreshProvider, ...)` 觸發：calendar_page
bump `calendarRefreshProvider`,search_page 重跑 `_performSearchFromDb()`。
沒有依賴「`await showTransactionDetailCard(...)` 返回」這個時機點,因為那個
時機點對複製/退款/編輯而言是錯的(太早)。

同時補上 `transaction_detail_card.dart` 的 `_handleDelete()` 漏 bump 的
`tagListRefreshProvider`(`tag_detail_page.dart` 的標籤統計卡片靠它刷新，
舊版逐頁刪除邏輯有 bump，中心化後漏掉了）。

`tag_detail_page.dart`/`category_detail_page.dart` 的交易列表本身是 Drift
`.watch()` Stream 直接驅動，不需要額外處理。

**曾考慮但放棄的做法**:一度嘗試把 `calendarRefreshProvider`/
`tagListRefreshProvider` 直接塞進 `transaction_detail_card.dart` 的
`_handleCopy`/`_handleEdit`/`_handleRefund`,在它們內部 `await` 編輯器頁關閉
後再 bump——但那時資訊卡自己的 `State` 已經 `dispose`,`ref` 已失效
(`ref.read` 會拋異常),就算改用 `ProviderScope.containerOf(hostContext)`
繞過也是額外的跨 feature 耦合(widget 要認識 calendar/tag provider)。改用
`statsRefreshProvider` 更簡單:它本來就是全站既有的「任意交易變更」信號,時機
天然正確,不用碰卡片本身的生命週期。
