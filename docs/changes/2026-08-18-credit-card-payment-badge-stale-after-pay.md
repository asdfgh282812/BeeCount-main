# 繳款後帳戶列表「可繳款」徽章沒消失(provider 沒重算)

## 背景

使用者反饋(2026-08-18,附兩張截圖):

> 為什麼我已繳費，但還是可繳費呢？只有已到該期帳單日，且未繳才要出現這個提示

截圖情境:合併帳單群組帳戶「星展信用卡」(`account_group`,子卡星展eco卡/英雄聯盟卡)
剛透過 [CreditCardGroupPaymentPage](../../lib/pages/account/credit_card_group_payment_page.dart) 全額繳清
07/11–08/11 這期帳單(繳款記錄 819+3,440=4,259,帳戶詳情頁確實顯示「已繳清 ✅」),
但回到「資產管理」帳戶列表,該帳戶列仍顯示「可繳款 截止日 08/27」的紅色徽章。

## 根因

先查了 BeeCount Cloud(`/Users/andy/BeeCount-Cloud`)`routers/read/workspace.py:940-973` 跟
`frontend/packages/web-features/src/components/AccountListRow.tsx:217-222`——兩邊都是單純
`remaining_due > 0.01` 就顯示徽章,**沒有**「已到繳款截止日」這個額外條件,這是刻意的設計
(帳單一結清就提醒,不用等到快過期)。所以使用者建議的「只在已到截止日時才顯示」這個規則
**不是**這次的修法(跟 Cloud 兩端行為不一致,也違背了原本 App 端文件註解裡明確記錄的
「沒有額外的『N 天內』時間窗口限制」這個對齊 Cloud 的決定,見
[credit-card-payment-server-parity-fixes.md](2026-08-18-credit-card-payment-server-parity-fixes.md) 系列)。

真正的根因是 **provider 沒被重新計算**,是 stale-cache 問題,不是公式問題:

- [creditCardBillingBadgeProvider](../../lib/providers/credit_card_billing_providers.dart)、
  `accountBalanceAsOfProvider`、`defaultBillingPeriodOffsetProvider`、
  `creditCardPaymentPeriodRecordsProvider` 都是 `FutureProvider.family`(部分還是
  `.autoDispose`),內部呼叫 `repo.getCreditCardChargedAsOf`/`getCreditCardPaidTotal`——
  這些是一次性 `.get()` 查詢,**不是** Drift `.watch()` stream,寫入 DB 不會讓它們自動重算。
- 這幾個 provider 目前唯一的重算訊號是 `ref.watch(syncGenerationProvider)`——但這個
  counter 全專案只有 3 個地方會 bump,兩處是雲端 pull/push 完成事件(`sync_providers.dart`),
  一處是加入共享帳本(`join_shared_ledger_page.dart`)——**單純本機寫入(例如繳款轉帳)
  完全不會 bump 這個 counter**。
- [account_detail_page.dart](../../lib/pages/account/account_detail_page.dart)
  的 `_onAddPaymentRecord`(繳款記錄「+」按鈕的處理函式)在
  `CreditCardGroupPaymentPage` 關閉後,原本只有
  `ref.invalidate(accountStatementTransactionsProvider);` 這一行——漏了上面列的四個
  provider,`children.isEmpty`(單卡直接開轉帳表單)那個分支甚至完全沒有 invalidate。

為什麼帳戶詳情頁自己顯示的「已繳清」卻是對的:因為使用者是先回到帳戶列表(這個分頁
`accounts_page.dart` 全程沒被 unmount,`creditCardBillingBadgeProvider` 的 watcher 一直
掛著、從沒歸零過,`.autoDispose` 沒機會重建),再重新點進帳戶詳情頁——這是**全新的一次
`Navigator.push`**,`accountBalanceAsOfProvider` 對這個 widget 樹是第一次被 watch,拿到的
是全新算出來的值,不是舊的快取,所以剛好看起來是對的,掩蓋了列表頁那邊的 stale 問題。

## 改動

`lib/pages/account/account_detail_page.dart::_onAddPaymentRecord`:抽出
`_invalidateBillingProviders()`,涵蓋這次繳款可能影響到的全部信用卡帳單 provider
(`accountStatementTransactionsProvider`/`accountBalanceAsOfProvider`/
`creditCardBillingBadgeProvider`/`defaultBillingPeriodOffsetProvider`/
`creditCardPaymentPeriodRecordsProvider`),兩個分支(單卡直接轉帳、合併帳單群組分攤)
繳款完成後都呼叫它,不再只 invalidate 一個。

### 刻意不動的部分

- 沒有加「已到繳款截止日才顯示徽章」這個時間窗口——如上所述,查證過 Cloud 前後端都沒有
  這個概念,加了反而是 App 端自創、跟 Server 不一致的行為。
- 沒有把這些 provider 改成 Drift stream(每次寫入自動重算)——目前专案里这类信用卡帳單
  provider 統一走「呼叫端手動 invalidate」這個既有慣例(`accountStatementTransactionsProvider`
  原本就是這樣),這次只是把漏掉的幾個補齊,沒有換整個機制。
- `cardRewardAccountSummaryProvider`(紅利回饋彙總卡片)不在這次補的清單裡——繳款是
  transfer,不影響回饋金額計算,不需要跟著重算。

## 測試

純 provider-invalidation 修改,沒有新的可單元測試邏輯分支(`_invalidateBillingProviders`
只是呼叫既有 `ref.invalidate`,沒有計算邏輯)。

`flutter analyze`:835 issues,跟改動前同一個數字,0 個新增。
`flutter test`:766/766 全過。

沒有跑實機/模擬器手動驗證(這台機器沒有可用的 iOS Simulator/Android SDK)。
