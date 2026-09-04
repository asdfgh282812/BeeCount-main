# 帳戶清單「編輯排序」拖曳功能

## 背景

帳戶總覽頁（[accounts_page.dart](../../lib/pages/account/accounts_page.dart)）
的 `Accounts.sortOrder` 欄位、`updateAccountSortOrders` repository 方法、
`entity_serializer.dart` 的序列化都早已存在，但畫面上從未接上任何拖曳手勢——
`onReorder` callback 傳進 `_AccountTypeGroup` 之後就是死代碼，使用者完全感受不到
能拖曳排序。調查過程中還發現兩個更根本的缺口，這次一併補上：

1. `updateAccountSortOrders` 沒有走 `ChangeTracker`，拖曳排序即使做出來也只是
   本機生效，永遠不會同步到雲端/其它裝置。
2. BeeCount-Cloud 後端完全沒有 account 的 `sort_order`，read API 還是強制按
   名稱字母排序；網頁前端也是另外做了一次字母排序，且沒有任何拖曳套件。

本文件只涵蓋 App 端（Flutter）改動；BeeCount-Cloud 後端/前端的對應改動見該
repo 自己的 `docs/changes/` 記錄。

## App 端改動

### 1. `updateAccountSortOrders` 補上 ChangeTracker

[local_repository.dart](../../lib/data/repositories/local/local_repository.dart)：
原本直接委託 `_accountRepo.updateAccountSortOrders`，現在改成跟
`batchInsertAccounts` 同樣的模式——寫完 DB 後查出這些帳戶的 `syncId`，逐一呼叫
`changeTracker.recordUserGlobalChange(action: 'update')`（account 是
user-global 實體，一律 `recordUserGlobalChange`，不分 ledger）。

測試：`test/repositories/account_sort_order_test.dart`。

### 2. 「編輯排序」入口

放進帳戶頁既有的設定 bottom sheet（點右上角齒輪），新增一項「編輯排序」，
點擊後整頁進入拖曳模式（`_AccountsPageState._editingOrder`），頁首右側三個
圖示（新增/BeeAssets/設定）暫時換成單一「完成」按鈕退出。

新增 l10n key：`accountsEditOrder`（沿用既有 `commonFinish` 當「完成」文案，
沒有新增獨立 key）。

### 3. 兩層拖曳 UI

編輯模式下 `_AccountTypeGroup` 改用 `_buildReorderableBlocks`（兩層巢狀
`ReorderableListView`）取代原本的靜態 `Column`：

- **外層**：拖曳「頂層帳戶」（獨立帳戶 + 合併帳單主帳戶，含孤兒子帳戶降級的
  獨立 block）彼此的相對順序。
- **內層**（僅在有子帳戶的 block 內出現）：拖曳該主帳戶底下子帳戶彼此的順序。

兩層都用 `buildDefaultDragHandles: false` + `ReorderableDragStartListener`
只包住右側的拖曳手把圖示（`_ReorderableAccountRow`），而不是整列都能拖，
避免跟其它手勢搶焦點；編輯模式下帳戶卡片本身的滑動刪除/點擊導航/長按編輯
一律停用（`onTap`/`onEdit` 傳空實作），且不理會 `_collapsedParentIds`（一律
展開），否則使用者拖不到收合中的子帳戶。

排序模型沿用現有單一 `sortOrder` 整數：`_onReorderBlocks` 只重新編號本次
拖曳的頂層帳戶（子帳戶的 `sortOrder` 完全不動），`_onReorderChildren` 只重新
編號某一個父帳戶底下的子帳戶。兩者能互不干擾，是因為 `_buildAccountBlocks`
的分組邏輯（`topLevel` 清單 / `childrenByParent[syncId]`）本來就只看「同一批
帳戶之間的相對順序」，頂層帳戶跟子帳戶各自是獨立的相對順序空間。

取代了原本已死的 `_onReorder` 方法與 `_AccountTypeGroup.onReorder` 參數。

### 已知的 Dart 語法陷阱

實作過程中踩到一個 Dart 解析器的坑：三元運算子的分支裡直接寫
`cond ? a?[b] : c`（null-aware 索引緊接在 `?` 分支開頭）在目前專案用的 Dart
版本下會被解析器誤判成另一個三元運算式的開頭，報出一串看起來不相關的
`non_bool_condition` / `missing_identifier` 錯誤。解法是幫 `a?[b]` 加一層括號：
`cond ? (a?[b]) : c`。見 `_buildReorderableBlocks` 裡的 `cardStats` 計算。

## 刻意不做的部分

- 不支援跨 type 分類拖曳帳戶。
- 不支援把子帳戶拖到別的主帳戶底下（那是 `parentAccountId` 掛靠關係變更，
  屬於帳戶編輯頁的功能）。
- 「已隱藏」分區（`_HiddenAccountsSectionState`）不支援排序，維持原樣。

## 待辦（依賴 BeeCount-Cloud 對應改動）

App 端這次已經讓拖曳排序正確寫 `local_changes` 並推播同步，但雲端要能真正
存住 `sortOrder` 並在 read API 回傳、網頁前端要能顯示一致順序，需要
BeeCount-Cloud 那邊補齊 `sort_order` 欄位（模型/mutator/projection/read API）
跟新增批次排序 endpoint——這部分還沒做完，是這次功能能否端到端生效的前提。
