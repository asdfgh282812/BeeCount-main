# 對帳模式 / 信用卡明細「一般記錄」未套用備註顯示方式設定

## 問題

「我的 → 備註顯示方式」（`noteDisplayModeProvider`，`lib/providers/theme_providers.dart`）可切換
`分類優先` / `備註優先`，並透過共用的 `composeTransactionRowTitle`
（`lib/widgets/biz/transaction_row_title.dart`）在首頁交易列表
（`TransactionListItem`）正確生效。但另外兩處各自手刻了自己的標題組字邏輯，
從未讀取這個設定，永遠固定顯示分類名：

- 對帳模式列表（`_StatementRow`，`lib/pages/account/account_reconciliation_page.dart`）：
  只有在完全沒有分類時才會退回顯示備註，有分類時備註直接被忽略、不會以
  括號附註顯示。
- 信用卡帳戶明細頁「一般記錄」列表（`TransactionTile`，
  `lib/pages/account/account_detail_page.dart`）：非轉帳、非拆帳的一般交易
  一律用分類名當主標題，備註只在不等於分類名時才接在後面當括號附註，未依
  設定切換成「備註優先」。

## 修正

兩處都改為呼叫共用的 `composeTransactionRowTitle(mode: ref.watch(noteDisplayModeProvider), categoryName: ..., title: tx.note ?? '')`，
渲染邏輯對齊 `TransactionListItem`：主標題用 `composed.primary`，若有
`composed.parenNote` 則以次要色小字附加在後面 `"  (備註)"`。

- `_StatementRow`：拆出 `composedTitle`（轉帳列維持原本 `l10n.transferTitle`
  邏輯不變，因為轉帳本來就沒有「分類」概念），並在 UI 上用 `Text.rich`
  取代原本純文字 `Text(title)`，讓備註優先模式下能顯示備註、分類優先模式下
  能在括號中看到備註。
- `TransactionTile`：一般交易分支與拆帳分支都改用
  `composeTransactionRowTitle`；轉帳分支維持原邏輯不變。

## 刻意不動的範圍

`card_reward_detail_page.dart` 的回饋明細列表（`_buildTransactionRow`）也有
類似但方向相反的寫死邏輯（永遠備註優先，`tx.note ?? displayName`），使用者
這次只回報「一般記錄」跟對帳模式，沒有提到回饋明細子頁，且不確定該頁固定
用備註優先是否為刻意設計，因此本次未一併修改。
