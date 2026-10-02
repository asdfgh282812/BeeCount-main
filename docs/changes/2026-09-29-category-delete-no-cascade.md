# 2026-09-29 pull 刪除分類不再連帶刪子分類 + 分類樹對帳

## 現象

資料修復後，全新登入的裝置上有 1605 筆交易變成「無分類」(例如「薩爾達傳說 時之笛」
應該是 娛樂 › 遊戲)。Web 顯示正常。

## 原因(三個 App 端 bug 疊加)

1. **pull 刪除一級分類會連帶刪除本機子分類**。
   - 位置:`lib/cloud/sync/sync_engine_apply.dart` 的 `_applyCategoryChange` delete 分支。
   - server 刪一級分類不會級聯。子分類在 server 上照樣存活,只是用 `parentName`
     掛在那個名字上。
   - 損壞批次(change 26388 等)誤刪了 12 個一級分類。全新裝置回放全部歷史,回放到
     這幾筆 delete 時,本機就把底下的子分類一起刪掉。
   - 之後同 syncId 的子分類 upsert 回來,是新的本機 id,而且找不到父分類。
     交易的 `categoryId` 還指向舊 id,所以全部斷掉。
   - server 補回一級分類之後也接不回來。
2. **局部 upsert 沒帶 `parentName` / `parentSyncId` / `level` 時,父分類被清成 null**。
   - server merge 對缺鍵是保留原值,App 端卻用解析出來的 null 覆蓋。
   - `level` 缺鍵時則被預設成 1。
3. **`repairMissingCategoryColorsOnce` 只看 `parentId IS NULL` 判斷一級分類**。
   - 上面那些找不到父分類的子分類被當成一級分類,補了顏色並推上 server。
   - 實際推了 69 筆,只改到顏色:payload 沒帶 parentName,server 保留了原本的父子
     關係。
   - `restoreCategoryColorsFromServer` 有同樣的判斷,一起修。

## 修法

- **delete 分支**:
  - 有同名存活的一級分類 → 跟原本一樣,把引用改掛過去。
  - 沒有 → 只把子分類的 `parentId` 摘掉,不刪除,本機 id 不變,交易引用不會斷。
- **upsert 分支**:
  - payload 沒有 `level` 鍵 → 保留本機 level。
  - level ≠ 1 且沒有 `parentName` / `parentSyncId` 鍵 → 保留本機 `parentId`。
- **補色的兩個函式**:改成同時要求 `level = 1`。
- **新增 `reconcileCategoriesFromServer`**(`sync_engine_status.dart`):
  - 每個 session 在 pull 之後跑一次,排在顏色對帳之前,掛在 `SyncEngine.sync` 裡。
  - 只改本機,不經 changeTracker,不推送。步驟:
    1. server 有、本機沒有的分類補插回來。一級分類先插,custom 圖示排入下載佇列。
    2. 依 server 的 `level` / `parentName` 接回父分類。同 kind + 名稱的一級分類有
       多筆時,優先選 server 上還存活的。本機找不到父分類就不動。
    3. `categoryId` 指向不存在分類的交易:分頁讀 server 的交易(每頁 1000 筆),
       用交易的 `category_id`(分類 syncId)接回。
       - 少數舊交易在 server 上只有 denormalized 的分類名稱,改用 kind + 名稱比對。
       - 只有真的有斷掉的交易時才會讀交易 API。
  - 有未解決的 pull 錯誤時不跑。
  - 已壞掉的裝置更新 App 之後,下次同步就會自己修好。
  - 對模擬器那份壞掉的資料庫試算:69 個子分類接回父分類,1605 筆交易全部接回。

單測:`test/cloud/sync/category_tree_sync_test.dart`。fake provider 補上了
`readTransactions`。

## 刻意不在這次處理

- **交易明細、預算、分期等引用斷掉的分類 id**:這次對帳沒有處理。
  - 要知道它們原本的分類 syncId,得再讀各自的 server API。
  - 這次事故的主要影響是交易。
- **server 上那 69 個子分類多出來的顏色**:需要另外用 server 寫入修正,
  子分類的顏色本來就應該是 null。
- **每台裝置各自建一個「轉帳」分類造成的重複**(server 上現在有 3 個):
  這是既有行為,跟本次無關。
