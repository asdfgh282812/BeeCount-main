# 資產(帳戶)頁:繳費/調整餘額後離開再進來金額沒更新

## 問題

使用者反饋:在帳戶詳情頁完成「合併帳單群組繳款」或用滑動快捷操作「調整餘額」後,
回到資產總覽頁(`AccountsPage`),淨資產/資產構成/各帳戶餘額仍顯示舊值,要等到
之後某個「有 bump 到刷新訊號」的動作(例如再記一筆一般交易)才會跟著更新。

## 根因

`lib/providers/statistics_providers.dart` 裡淨資產/資產構成/帳戶統計那批
`FutureProvider`(`allAccountStatsProvider`/`netWorthBreakdownByCurrencyProvider`/
`assetCompositionProvider`/`accountStatsProvider` 等)都是靠 `ref.watch(statsRefreshProvider)`
這顆全域 tick 才會重算,不是 Drift stream——本機寫入不會自動觸發,必須呼叫端在
交易寫入後手動 `ref.read(statsRefreshProvider.notifier).state++`。一般記帳/轉帳
(`transaction_editor_page.dart`、`widgets/transaction/transfer_form.dart`)都有補這一步,
但以下兩個路徑漏了:

1. `lib/pages/account/account_detail_page.dart` 的 `_invalidateBillingProviders()`——
   合併帳單群組繳款(`CreditCardGroupPaymentPage._submit`)是直接呼叫
   `repo.insertTransactionsBatch`,不像單卡繳款走 `TransferForm`,完全沒有任何地方
   bump 這顆 tick;`_invalidateBillingProviders()` 原本只 invalidate 帳戶詳情頁自己的
   信用卡帳單相關 provider,沒有波及資產總覽頁那批統計。
2. `lib/utils/account_quick_actions.dart` 的 `showBalanceAdjustmentDialog()`——只
   invalidate 了單一帳戶的 `accountStatsProvider(account.id)`,同樣沒有 bump 全域 tick,
   資產總覽頁的淨資產/資產構成仍是舊值。

## 修正

在上述兩處各補一行 `ref.read(statsRefreshProvider.notifier).state++;`(跟其他呼叫端
一致的既有慣例),讓這兩個動作完成後資產總覽頁能立即重算並顯示新金額,不需要
額外一次不相關的操作才「順便」刷新。

## 範圍外

- 帳戶對帳頁(`account_reconciliation_page.dart`)的「已對帳/延遲入帳」標記只改
  `reconciledAt` 中繼資料,不影響交易金額/餘額,不在此次修正範圍。
- 沒有引入頁面級的「離開再進來強制刷新」機制(例如 `RouteObserver`)——
  `AccountsPage` 是底部導覽列 `IndexedStack` 常駐頁籤,只要寫入端正確 bump
  `statsRefreshProvider`,即使頁籤在背景也會立即重算,不需要额外的「返回頁面」
  觸發點;真正該修的是遺漏 bump 的寫入路徑本身。
