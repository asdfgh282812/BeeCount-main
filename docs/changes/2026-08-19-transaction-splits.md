# 拆帳(單筆交易拆分到多個分類)

日期:2026-08-19
背景:BeeCount-Cloud(web/server,獨立 repo)已依 Moze 官方文件
(`doc.moze.app/record/split-categories`)實作「拆分類別」——單一交易、單一
總金額,拆成多筆分類明細,不是多人分帳。這次把同一套邏輯搬到 App 端,介面
依照使用者提供的 Moze 截圖(橫向圖示條 + 詳情頁堆疊明細)重做,資料模型/
同步契約對齊 web 端既有實作。範圍決策(使用者確認):只做「拆分類別」,不
做「同分類拆多帳戶」(web 端本身也不支援);拆帳明細圖示先用固定預設,不
支援使用者自訂;支援把拆帳「還原」成單一分類;分類統計/預算用量這次一併
展開拆帳明細(不延後到下一版)。

## 1. 資料模型:`Transactions.hasSplits` + 新表 `TransactionSplits`

**改了什麼**:`lib/data/db.dart` 的 `Transactions` 表加 `hasSplits`
(bool,預設 false)。新增子表 `TransactionSplits`:`id`,`transactionId`
(FK),`categoryId`(int?,同主表舊路徑),`categorySyncIdOverride`
(text?,共享帳本 Owner 虛擬分類走這個,同 `Transactions` 既有欄位的做法),
`amount`(real),`note`(text?),`sortOrder`(int)。`schemaVersion` 37 → 38。
每次存檔整組刪除重建(比照 `TransactionTags`/`TransactionAttachments` 既有
模式),不做增量 diff——跟 server 端 `read_tx_split_projection` 的
`_replace_tx_splits()` 同一種做法,因為明細沒有跨裝置穩定的自身識別碼。

**為什麼**:`hasSplits=true` 時主表 `categoryId`/`categorySyncIdOverride`
強制為 null(明細才有分類),對齊 server 端 `has_splits=true` 時
`category_sync_id` 也被清空的行為。

## 2. Repository:`TransactionSplitInput` 三態語義

**改了什麼**:`TransactionRepository.addTransaction`/`updateTransaction`
新增 `List<TransactionSplitInput>? splits` 參數(`transaction_repository.dart`)。
語義:`null`=不動既有拆帳狀態;`[]`=顯式清空(還原成單一分類,這時呼叫方
傳的 `categoryId` 才會生效寫回主表);非空列表=整組覆蓋(強制主表分類為
null)。新增 `getTransactionSplits(int transactionId)` 讀取明細。
`LocalTransactionRepository`/`LocalRepository` 都在同一個 `db.transaction()`
區塊內完成主表寫入 + 明細刪除重建,避免中途失敗留下不一致狀態。

**為什麼**:三態語義(而非單純 `List?`)是唯一能同時表達「表單沒碰過拆帳」
跟「使用者這次把拆帳清空了」兩種對 repo 行為不同的操作——如果只有
null/非空兩態,編輯時把拆帳還原成單一分類會被誤判成「不動」,留下孤兒
明細列 + `hasSplits` 卡在 true 的不一致狀態。

## 3. Sync 同步:`splits` 陣列隨交易 payload 恆發

**改了什麼**:`entity_serializer.dart::serializeTransaction` 新增
`splits` 參數,`if (splits != null) 'splits': splits`;三個 push 序列化
呼叫點(`sync_engine_serialization.dart` 的 `_serializeEntityForPush`/
`_pushAllEntities`/`_exportLedgerJson`)都改成查表附帶明細,**永遠**傳
陣列(即使 `[]`),同 `attachments` 的做法。`sync_engine_apply.dart` pull
時用 `payload.containsKey('splits')` 判斷:缺鍵=舊版 App/沒拆帳資訊,不動
本地;命中鍵(含 `[]`)=權威列表,整組刪除重建本地明細,並依陣列是否為空
決定 `hasSplits`/清空主表分類。明細內 `categoryId` 是分類的 **syncId**
字串(同頂層交易 `categoryId` 語義),不是本地 int id。

**為什麼**:拆帳明細不是獨立的 sync entity——沒有自己的 `syncId`,完全隨
父交易的 change record 一起推/拉,跟 web 端「非獨立 sync entity,純粹是
交易 payload 上的一個欄位」的設計一致,不需要新的 `entity_type`。

## 4. UI:新增/編輯表單的拆帳模式

**改了什麼**:`lib/widgets/biz/transaction_entry_form.dart`——分類選擇區
新增「拆帳」按鈕(`Icons.call_split`),點擊後把目前已選分類轉成第一筆明細
並開分類選單挑第二筆;啟用後分類區改成橫向圓形圖示條(比照截圖):最前面是
固定圖示的「多類別」聚合圖示(徽章顯示筆數 + 即時總額),依序是每筆明細的
分類圖示+金額,最後是「+」新增鍵。點某筆明細切換金鍵盤焦點到那一筆;再點
一次「目前已經是焦點」的那一筆,直接開換分類選單(長按也能到同一個選單,
外加移除這筆的選項,< 3 筆時不給移除,走還原)——初版只做長按換分類,實測
後發現「已經選好、焦點也在上面」的那一筆單點下去沒反應,會被誤以為分類選
了就不能再改,因此補上「再點一次=換分類」這個更直覺的路徑,長按選單原樣
保留。長按彙總圖示彈出「還原成單一分類」。金鍵盤沿用原本單一金額輸入的同一套狀態機
(`_amountStr`/`_acc`/`_op`),只是切換焦點時把目前值 commit 進
`_splits[i].amount`——**沒有**另外做 web 端那種「先打總額,再手動分配、
比對總和」的 UI:因為這裡的互動模型是「金額本來就是各筆加總」,總額永遠
自動等於明細總和,不存在對不上的狀態,少了一種驗證邏輯但更貼近 Moze 截圖
的操作方式。跟週期性收支互斥(兩者共用「這筆是什麼」的心智模型,同時開會
讓 `res.recurringDraft` 被靜默丟棄),互斥透過表單內部 `_recurringDraft`/
`_splits` 互相檢查完成;跟退款互斥透過 `TransactionEntryForm.allowSplit`
(由 `TransactionEditorPage` 依 `initialRefundOfSyncId` 決定)。編輯已存在
的拆帳交易會在 `initState` 自動回顯明細(`_resolveInitialSplits`)。

**刻意排除**:拆帳明細沒有帳戶欄位(對齊 web);聚合圖示不支援自訂(對齊
web 資料模型沒有對應欄位);轉帳分頁(`transfer_form.dart`)完全沒有拆帳
入口,因為它是獨立元件,沒有共用這份程式碼。

## 5. UI:交易明細頁與列表

**改了什麼**:`lib/widgets/biz/transaction_detail_card.dart` 主卡片
(`_buildImageOrCategoryBlock`/`_buildNoteAmountRow`)在 `hasSplits=true`
時把分類圖示/名稱換成固定「多類別」圖示+標籤,並在名稱旁加一個「拆帳」
徽章(比照既有「退款」徽章的 pill 樣式);新增 `_buildSplitSection` 堆疊
列出每筆明細(圖示+分類名+備註+金額),排在帳戶/標籤等欄位卡片之後。
`lib/widgets/biz/transaction_list_item.dart` 新增 `hasSplits` 參數,為
true 時同樣忽略傳入的分類、改顯示「多類別」圖示+標籤;5 個呼叫點
(`transaction_list.dart`、`search_page.dart`、`calendar_body.dart`、
`tag_detail_page.dart`、`category_detail_page.dart` ×2)都補上
`hasSplits: t.hasSplits`。`account_detail_page.dart` 的帳戶交易紀錄列表是
獨立手刻的(沒有共用 `TransactionListItem`),另外單獨加了同樣的判斷。

**刻意排除**(留給之後視需要再補):`card_reward_detail_page.dart` 的回饋金
關聯交易列表、桌面小工具 `lib/widget/views/recent_view.dart` 的「最近交易」
內容、CSV/JSON 匯出——這些跟 web 端目前的已知缺口(「CSV 匯出不含拆帳明細」)
同一類,影響範圍小、跟主要記帳流程無關,先不動。

## 6. 統計 / 預算:展開拆帳明細計算

**改了什麼**:`lib/data/repositories/local/local_statistics_repository.dart`
的 `totalsByCategory`/`totalsByCategoryWithHierarchy` 遇到
`hasSplits=true` 的交易時,不再落入「未分類」桶,改成批次查該交易的
`TransactionSplits`,依各自 `categoryId` 分別累加,金額乘上這筆交易的
折算比例(`nativeAmount / amount`,即多幣別交易的隱含匯率)。
`lib/data/repositories/local/local_budget_repository.dart` 的
`getBudgetUsage` 分類預算分支(raw SQL)加一條對 `transaction_splits` 的
`UNION`-style 補充查詢,套同一個「本分類或其子分類」的比對條件,金額同樣
按父交易折算比例縮放(`NULLIF` 防除以零)。

**為什麼**:對齊 BeeCount Cloud 的 `workspace_analytics`/預算用量查詢——
拆帳交易的每一筆明細各自算進它自己的分類,而不是整筆消失或錯記在原本
(其實不存在的)單一分類下。「總預算」(`budget.type == 'total'`)分支不受
影響,因為它統計的是整筆交易總額,不看分類。

## 7. 測試

- `test/data/repositories/local/transaction_splits_test.dart` — repository
  層 CRUD/三態語義/級聯刪除。
- `test/sync/transaction_splits_apply_test.dart` — pull 路徑的新增/還原/
  缺鍵保留三種情境。
- `test/widgets/transaction_split_entry_form_test.dart` — 表單端對端流程
  (選分類→輸入金額→拆帳→選第二分類→輸入金額→送出)。
- `test/repositories/transaction_splits_statistics_test.dart` — 分類統計/
  預算用量的拆帳展開 + 多幣別折算比例回歸測試。
- `test/data/sync_pull_errors_schema_test.dart` — 更新 `schemaVersion`
  斷言(37 → 38)。
