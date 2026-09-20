# 修正紅利回饋明細頁週期跟帳戶頁對不上

## 問題

信用卡帳戶詳情頁「交易明細」tab 的帳單彙總卡片與紅利回饋分組卡片都顯示帳單週期
`2026/09/05 – 2026/10/05`（結帳日 5 號），但點進其中一條規則的「紅利回饋明細頁」
（`CardRewardDetailPage`）後，週期卻變成 `2026/09/01 – 2026/10/01`（退化成每月 1
號起算）。

## 根因

`account_detail_page.dart` 的帳單週期相關顯示都透過 `_effectiveBillingDay(account)`
解析「實際要用的結帳日」：優先用帳戶自己的 `billingDay`，沒有時（合併帳單子帳戶）
再退到主帳戶群組的 `billingDay`，兩者都沒有才退到帳本的 `monthStartDay`（見該方法
上方註解）。紅利回饋分組卡片（`_buildRewardSummaryCard`）也是呼叫這個方法算出
`billingDay` 餵給 `cardRewardAccountSummaryProvider`，所以列表上每條規則顯示的週期
是對的。

但點進規則卡片導到 `CardRewardDetailPage` 時，該頁直接讀
`widget.account.billingDay`（`card_reward_detail_page.dart:104`，改前），完全略過
`_effectiveBillingDay` 的解析鏈。當這個帳戶是合併帳單子帳戶、自己的 `billingDay`
是 `null`、要靠主帳戶群組的 `billingDay` 才能算出正確結帳日時，`widget.account.billingDay`
就是 `null`；`billingCyclePeriod(billingDay, offset)`（`lib/utils/card_reward_period.dart:32`）
在 `billingDay` 為 `null` 時會靜默退化成「每月 1 號」，於是明細頁顯示的週期跟同一頁
其他地方對不上。

## 修正

`CardRewardDetailPage` 新增建構子參數 `billingDay`（必填，型別 `int?`），改由
`account_detail_page.dart` 導頁時把已經算好的 `_effectiveBillingDay(account)` 傳進去
（`account_detail_page.dart` 導到 `CardRewardDetailPage` 的唯一呼叫處），頁面內部
`cardRewardRulePeriodSummaryProvider` 改讀 `widget.billingDay` 而不是
`widget.account.billingDay`。這樣列表頁跟明細頁用的是同一個已解析好的值，不會再
各自算一次、算出不同結果。

沒有另外抽共用 helper／provider——`_effectiveBillingDay` 目前是
`_AccountDetailPageState` 的私有方法，且 `CardRewardDetailPage` 只有這一個呼叫來源，
直接把算好的值透過建構子傳遞是影響範圍最小的修法。若之後 `CardRewardDetailPage`
出現第二個呼叫來源，屆時再考慮把 `_effectiveBillingDay` 抽成共用函式。

## 影響檔案

- [lib/pages/account/card_reward_detail_page.dart](../../lib/pages/account/card_reward_detail_page.dart)：新增必填的 `billingDay` 參數，取代原本讀 `widget.account.billingDay`。
- [lib/pages/account/account_detail_page.dart](../../lib/pages/account/account_detail_page.dart)：導頁到 `CardRewardDetailPage` 時傳入 `_effectiveBillingDay(account)`。
