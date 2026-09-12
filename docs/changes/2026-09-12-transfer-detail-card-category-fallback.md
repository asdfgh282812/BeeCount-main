# 修正:雲端建立的轉帳交易分類名稱/圖示跟 App 端不一致

## 問題

在網頁端(BeeCount Cloud)建立的轉帳交易同步到 App 後:
1. 交易明細卡(`TransactionDetailCard`)分類名稱顯示成「預設分類」,而不是
   「轉帳」。
2. 名稱修好之後,發現分類**圖示**也跟預期不一樣:可愛圖示主題下應該顯示
   `swap_horiz`(雙向箭頭+綠點)這個轉帳專屬圖示,實際上卻顯示成通用的
   「無分類」fallback 圖示(書籤形狀+藍點,`_fallback.svg`)。且這個圖示
   問題在交易列表(`TransactionList`)跟明細卡(`TransactionDetailCard`)
   兩處表現不一致——即使套用了同樣的 UI 層 fallback 邏輯,列表仍持續顯示
   fallback 圖示,明細卡卻顯示正確的 `swap_horiz`。

## 根因

App 對「轉帳」的識別方式是 `Transaction.type == 'transfer'`
(`lib/data/db.dart`),但 App 自己建立轉帳時,會額外把 `categoryId` 指向
一個本機種子產生的虛擬分類(`kind == 'transfer'`,名稱「轉帳」、
`icon == 'swap_horiz'`,見 `lib/services/data/seed_service.dart` 的
`createTransferCategory` + `lib/widgets/transaction/transfer_form.dart`)。

網頁端建立轉帳不會帶任何 `categoryId`/`categoryName`(轉帳沒有分類概念),
拉取套用邏輯(`lib/cloud/sync/sync_engine_apply.dart`)原本因此把
`categoryId` 解析為 `null`,使得 `transactions.category_id` 這欄一直停在
`NULL`。

**名稱 bug**:`transaction_detail_card.dart` 的分類顯示邏輯單純呼叫
`CategoryUtils.getDisplayName(widget.category?.name, ...)`,`category == null`
時的 fallback 正是「預設分類」文字。`transaction_list.dart` 因為已有
`isTransfer` 特判(改用 `l10n.transferTitle`),所以列表本來就顯示正常。

**圖示不一致的真正原因(比表面的 UI fallback 更底層)**:`categoryId` 為
`NULL` 這件事本身其實有一個既有的**歷史修復機制**——
`SeedService.migrateTransferTransactions`(冪等,把所有
`type='transfer' AND (category_id IS NULL OR category_id != 虛擬分類id)`
的記錄一次性回填成虛擬轉帳分類 id)。但這個函式只在兩個時機被呼叫:
① `BeeDatabase.ensureSeed`(僅首次安裝、welcome 頁流程觸發)、
② `lib/data/db.dart` 的 `onUpgrade` 裡 `if (from < 14)` 這個**只在 schema
從 <14 升級時觸發一次**的分支。也就是說,v14 之後透過雲同步新產生、
`categoryId` 停在 `NULL` 的轉帳記錄,從來沒有機會被這個回填函式碰到,一直
維持 `NULL`,即使重新啟動 App 也不會自動修正。

而列表(`it.category`,來自 `LocalTransactionRepository._txJoins()` 的
`LEFT JOIN categories ON categories.id = transactions.category_id` 即時
Drift stream)跟明細卡(`widget.category`,只是開卡當下傳入的一次性快照)
在 `categoryId` 仍為 `NULL` 的情況下理論上都應該吃到同一顆全域快取的
`transferCategoryProvider` fallback、顯示一樣的圖示。但列表用的是虛擬列表
套件 `flutter_list_view` 做列渲染,不保證每次上層 Provider 變動都會重新
呼叫每一行的 builder(它主要跟著底層資料/捲動事件走,而不是任何 ambient
Provider);而明細卡是每次點開都整卡重建的 `showModalBottomSheet`,一定會
用到當下已解析好的 Provider 值。這使得單靠 UI 層 fallback 沒辦法保證兩處
一致——真正該修的是讓 `categoryId` 本身回到正確值,這樣兩邊都走同一條
「資料庫欄位變了 → Drift stream 自然推新值」的路徑,不必依賴任何 UI 層猜測。

## 修正

1. **名稱**:`transaction_detail_card.dart` 的 `_buildImageOrCategoryBlock`
   / `_buildNoteAmountRow` 新增 `isTransfer` 分支,直接用 `l10n.transferTitle`
   ("轉帳"),不再落到 `CategoryUtils.getDisplayName` 的預設分類 fallback。
2. **圖示(UI 層即時兜底)**:`transaction_detail_card.dart` 新增
   `_iconCategory(isTransfer)` helper、`transaction_list.dart` 新增對應的
   `iconCategory` 區域變數——`category` 為 null 且為轉帳時,改讀全域快取的
   `transferCategoryProvider`。這讓「當下這次渲染」有機會顯示對的圖示,但如
   上一節所述,不保證列表一定會即時重繪(見下一點才是真正治本的地方)。
3. **資料層回填(治本)**:
   - `sync_engine_apply.dart` 的 `_applyTransactionChange` 新增:解析出
     `categoryId == null` 且 `type == 'transfer'`(且非拆帳)時,呼叫
     `repo.getTransferCategory()` 把 `categoryId` 補齊——讓**之後新拉取**的
     轉帳交易一開始就是對的。
   - `lib/data/db.dart` 新增 `schemaVersion` v60,`onUpgrade` 補一個
     `if (from < 60)` 分支,再跑一次
     `SeedService.migrateTransferTransactions`——把**現有、已經卡在
     `categoryId IS NULL` 多年**的雲端轉帳記錄一次性回填。這一步是讓
     使用者現有資料在下次真正重啟(觸發 `onUpgrade`)後就自動修好、不必等
     這筆交易被重新同步一次。

## 影響範圍

UI 顯示 + 一次性資料回填(純 `UPDATE`,不改 schema/欄位),不影響 wire 契約
(欄位名稱/格式不變),不透過 ChangeTracker(跟 v14 當年的作法一致,回填
`categoryId` 這種本機渲染用途的欄位本來就不需要推送到雲端/其他裝置——
其他裝置各自的本機 migration 也會各自回填到各自的本機虛擬分類 id)。
