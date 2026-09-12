# 帳戶頁面單帳戶金額隱藏

設計文件:`docs/superpowers/specs/2026-09-13-account-hide-amount-design.md`

## 背景

App 已有全域「隱藏金額」開關(`hideAmountsProvider`,見「我的」頁面右上角
眼睛圖示),一按會遮住整個 App 的金額。使用者希望能更細緻地控制:在**帳戶
頁面**針對**單一帳戶**單獨設定要不要顯示金額,而不必連帶影響其他頁面或其他
帳戶。

## 入口位置

**帳戶頁面**([lib/pages/account/accounts_page.dart](../../lib/pages/account/accounts_page.dart))
每一列帳戶(獨立帳戶、合併帳單主帳戶/群組列、掛靠主帳戶的子帳戶列)右側都
新增一個小眼睛圖示按鈕,點擊直接切換該帳戶自己這一行的金額顯示/隱藏,無需
進入編輯頁。

## 改動

### 1. 資料庫 schema(`lib/data/db.dart`,v60 → v61)

`Accounts` 表新增一欄 `hideAmount`(bool,預設 `false`)。Migration 用既有
`_addColumnIfMissing` helper,無需回填(既有資料落 `false`,語意上等同「金額
不隱藏」)。測試見 `test/data/migration_v61_test.dart`。

跟既有的 `hidden`(整列從清單消失)、`includeInTotal`(排除淨值加總)是三個
互不干涉的獨立開關——`hideAmount` 純粹是帳戶頁面該列數字的顯示與否,不影響
任何金額計算/加總/小計。父帳戶列(合併帳單主帳戶)的小計數字永遠是子帳戶的
真實加總,不受任何子帳戶 `hideAmount` 影響;父帳戶列自己的眼睛圖示也只切換
它自己這一行,不影響子帳戶。

### 2. Repository 層

- `lib/data/repositories/account_repository.dart`:`updateAccount` 介面新增
  `hideAmount` 參數;新增便捷法 `setAccountHideAmount(id, hideAmount)`,跟既
  有 `setAccountHidden` 同款寫法。
- `lib/data/repositories/local/local_account_repository.dart`:裸實作,寫入
  邏輯跟其他 D6(缺鍵保留)語意欄位一致。
- `lib/data/repositories/local/local_repository.dart`:帶 change 追蹤的版
  本——`setAccountHideAmount` **必須**走本類已帶 `changeTracker` 的
  `updateAccount`,不能繞過去直接呼叫 `_accountRepo.setAccountHideAmount`
  (同 `setAccountHidden` 的教訓,否則狀態不會 push 到雲端)。`account` 是
  user-global 實體,記錄走 `recordUserGlobalChange`(`ledgerId` 固定為 0)。

### 3. 同步(`lib/cloud/sync/`,App ↔ App)

- `entity_serializer.dart`:`serializeAccount` 新增 `hideAmount` wire 欄
  位,跟 `hidden` 同款無條件 bool 送出。
- `sync_engine_apply.dart`:`_applyAccountChange` 新增 pull 端 apply 邏輯,
  跟 `hidden` 同款 D6 缺鍵保留語義——缺鍵時 update 不覆蓋本地,insert 缺鍵
  預設 `false`。

### 4. UI(`lib/pages/account/accounts_page.dart`)

- `_AccountCard`(獨立帳戶列 / 合併帳單主帳戶列):新增眼睛圖示按鈕
  (`Icons.visibility_outlined` / `Icons.visibility_off_outlined`,跟「我的」
  頁面全域開關同一組圖示),點擊呼叫
  `repositoryProvider.setAccountHideAmount(account.id, !account.hideAmount)`。
  該列 `AmountText` 改傳 `hide: rowHide`,其中
  `rowHide = ref.watch(hideAmountsProvider) || account.hideAmount`(全域開著
  時無論單帳戶設定為何都遮蔽)。
- `_ChildAccountRow`(合併帳單子帳戶樹狀列):同款眼睛圖示 + `rowHide` 邏
  輯。
- 兩個新增 l10n key:`accountAmountHide`/`accountAmountShow`(Tooltip 文
  案),已加進 `app_en.arb`/`app_zh_TW.arb`(依專案慣例不再維護
  `app_zh.arb`/`app_ko.arb`)。

### 5. 其他因 schema 變動需要同步補的呼叫點

`Accounts` 表新增非空欄位後,所有直接建構 `Account(...)`(而非透過
`AccountsCompanion.insert`)的呼叫點都需要補上 `hideAmount` 參數,涉及:
- `lib/data/repositories/local/local_transaction_repository.dart`(共享帳本
  synthetic Account,固定 `hideAmount: false`——SharedLedgerAccounts 鏡像表
  沒有這個 Owner 側個人狀態概念)
- `lib/providers/database_providers.dart`、`lib/utils/shared_ledger_picker_filter.dart`
  (同上,synthetic Account)
- `lib/pages/settings/widget_management_page.dart`(組件庫畫廊預覽用的範例
  帳戶)
- 對應的 widget 測試(`test/widget/*_view_test.dart` 等)裡的範例 `Account`

## 這次不做的(範圍外)

- 不新增「帳戶頁面專屬總開關」——沿用既有全域 `hideAmountsProvider`。
- 不修改 BeeCount-Cloud 網頁管理台的 UI 去顯示/操作這個欄位。
- **BeeCount-Cloud(`/Users/andy/BeeCount-Cloud`,另一個 git repo)的
  projection/snapshot 尚未同步補上這個欄位**——比照 `Categories.color` 欄位
  的先例,這次只做 App 端,Cloud 端(alembic migration + `sync_applier.py`
  merge-spec + `snapshot_builder.py` 快照欄位)留待後續在該 repo 單獨處理。
  App 端上線後、Cloud 端補齊前,已配對裝置間的**增量同步**仍會正常運作
  (Cloud 對未知 payload 欄位是整包存 JSON blob、原樣回傳);只有**全新裝置
  `/sync/full`** 這個路徑會在 Cloud 端補齊 migration 之前遺漏這個值,新裝置
  會看到預設值 `false`(金額不隱藏)。

## 測試

- `test/data/migration_v61_test.dart` —— schema/migration
- `test/repositories/account_hide_amount_test.dart` —— `updateAccount`/
  `setAccountHideAmount` 落值、change 記錄、absent 保護、不影響
  `getAllAccounts()`/`getNetWorthBreakdown`/`getAssetCompositionByType`
- `test/sync/account_hide_amount_apply_test.dart` —— pull apply 的 D6 缺鍵
  保留語義、顯式覆蓋、新增帳戶兩種情境

UI 部分(眼睛圖示點擊互動)未寫 widget test——`lib/pages/account/accounts_page.dart`
本身目前沒有任何既有 widget test 覆蓋(頁面依賴的 provider 數量大,現有測試
慣例只覆蓋 repository/sync 層,UI 层靠 `flutter analyze` 驗證),這次沿用同
一個慣例,沒有新增這個頁面的第一份 widget test。
