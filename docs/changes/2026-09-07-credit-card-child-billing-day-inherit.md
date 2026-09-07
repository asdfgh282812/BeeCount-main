# 合併帳單子帳戶結帳日未跟隨主帳戶群組

## 問題

使用者回報:主帳戶(信用卡群組)設定結帳日為 11 號,交易明細正確顯示
`2026/08/11 – 2026/09/11`;但底下的信用卡子帳戶(如「星展eco卡」)卻顯示
`2026/08/05 – 2026/09/05`——不是跟著主帳戶的 11 號,而是變成帳本層級的
「一般帳戶月結日」(`monthStartDay`)預設值。使用者確認這不是星展信用卡特有
的問題,所有信用卡子帳戶都一樣沒有跟著主帳戶跑。

## 根因

`lib/pages/account/account_detail_page.dart` 的 `_effectiveBillingDay`
(帳單週期/交易明細/帳戶資訊三個 tab 共用的唯一結帳日計算入口)在
2026-09-06 那次修正(讓「帳戶群組當彙總容器」用時退化對齊帳本
`monthStartDay`,而不是寫死每月 1 號)只處理了兩層:

1. `account.billingDay`(帳戶自己設的)
2. 帳本的 `monthStartDay`(退化預設)

但合併帳單設計上「主帳戶群組設一次結帳日/繳款日/額度,子帳戶
(`parentAccountId` 指向主帳戶 `syncId`)自己不用再各自設定」(見
`app_localizations_zh.dart` 對應文案),所以子帳戶自己的 `billingDay`
一定是 `null`。原本的兩層邏輯完全沒有「往上找主帳戶」這一步,子帳戶直接
掉進帳本 `monthStartDay` 的退化分支,跟主帳戶群組顯示的結帳日對不上。

`lib/providers/card_reward_rule_providers.dart` 的
`_resolveRewardAccountContext` 已經有正確的「往上找 parent 拿 billingDay」
邏輯,只是 `account_detail_page.dart` 沒有比照辦理。

## 修正

[account_detail_page.dart](../../lib/pages/account/account_detail_page.dart)
的 `_effectiveBillingDay` 補上中間這一層,順序變成:

1. 帳戶自己的 `billingDay`
2. 有 `parentAccountId` 時,從已載入的 `allAccountsStreamProvider` 清單裡
   用 `syncId` 找到主帳戶群組,拿它的 `billingDay`
3. 兩者都沒有時才退化對齊帳本 `monthStartDay`(2026-09-06 那次修正的行為,
   給「帳戶群組本身當彙總容器、底下不是信用卡」的情境用)

因為 `build()` 已經 `ref.watch(allAccountsStreamProvider)`,這裡改用
`ref.read` 直接找同一份清單,不用額外打 repository。

## 刻意不動的部分

「應繳日期」「信用額度」「紅利回饋規則」這幾個欄位(`account_detail_page.dart`
裡直接讀 `account.paymentDueDay`/`account.creditLimit` 的地方,以及
`accounts_page.dart` 的 `_buildBillingDueBadge`)維持原本只認帳戶自己欄位、
子帳戶不顯示的行為不變——這些欄位本來就設計成只在主帳戶群組頁面顯示一份,
不是這次回報的問題,也不屬於「結帳日期區間」這個 bug 的範圍。
