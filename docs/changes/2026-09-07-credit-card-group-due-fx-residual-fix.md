# 合併帳單群組「剩餘帳款」多幣別淨額換算修正

## 問題

使用者回報:同一個合併帳單群組（玉山信用卡，底下掛台幣子卡 + 一張外幣子
卡），帳戶詳情頁「帳單彙總卡片」顯示的「剩餘帳款」跟「群組繳款」頁算出來
的「應繳總額」對不上（4650 vs 4657，差 7 元）——App 端「繳費」頁面的數字
是對的，「剩餘帳款」顯示錯；BeeCount Cloud（伺服器/web 端）兩邊都跟著
App「剩餘帳款」一起算錯。

使用者已經先用外幣子卡自己的幣別把這期帳單全額繳清（消費多少、繳多少，
淨額剛好是 0），只剩台幣子卡還有應繳金額，理論上「剩餘帳款」應該就等於
台幣子卡的應繳金額（4657）。

## 根因

`credit_card_billing_providers.dart` 的 `_dueAsOf`（餵給「剩餘帳款」/
`accountBalanceAsOfProvider`）在合併帳單群組（子卡彼此可能幣別不同）情境
下，原本是「先把每個子卡的 `charged`/`paidTotal` 分別呼叫
`convertToLedgerCurrency: true` 折算成帳本本位幣、全部子卡加總後才相減」。

問題出在：折算用的 `nativeAmount` 是**交易當下**的匯率快照——消費那天的
匯率跟繳款那天的匯率不會完全一樣。對於一張已經用自己幣別淨額結清（消費
JPY 10000、繳款也是 JPY 10000）的外幣子卡，`charged` 折算成台幣可能是
2200，`paidTotal` 折算成台幣卻因為匯率跌了變成 2100——兩個獨立折算後的
數字相減，殘留了一筆 100 元的「匯差」，被誤當成「這張已結清的外幣子卡還
欠群組 100 元」疊加進合併群組的「剩餘帳款」總額。

而「群組繳款」頁（`credit_card_group_payment_page.dart` 的 `_loadDue`）
完全沒有做這個「先折算再相減」的動作，是先用每張子卡自己的幣別把
`charged`/`paidTotal` 相減算出淨額，淨額 <= 0.005 就直接濾掉不顯示——外幣
子卡在自己幣別下淨額本來就是 0，被正確濾掉，完全不會受匯差影響，所以群組
繳款頁的總額才會是對的。

（另外，群組繳款頁原本也完全沒有扣「分期帳單沖銷」`getOffsetTotalForAccount`
——這次順便補上，雖然此案例使用者確認沒有用過分期沖銷，屬於次要缺口。）

## 修法

在 `lib/providers/credit_card_billing_providers.dart` 新增共用函式
`creditCardDueByChildAsOf(repo, ids, cutoff)`：**先用每張子卡自己的幣別
算淨額**（`charged`（已扣分期沖銷）− `paidTotal`，都不折算），已結清
（`<= 0.005`）的子卡直接跳過、完全不進入换算流程；只有還沒結清、且是合併
帳單群組時，才對「這張還有應繳金額的子卡」重新呼叫一次
`convertToLedgerCurrency: true` 拿折算後的 `charged`/`paidTotal` 相減，
拿去跟其他子卡加總。

這樣已結清的子卡（不論幣別）永遠貢獻 0，徹底避開匯差殘值；真正還沒繳清的
跨幣別子卡，仍然會正確折算成帳本本位幣後才加總，不會退回 2026-09-05/06
修過的「不同幣別原始數字直接加總失真」舊 bug。

- `_dueAsOf`（原本的「剩餘帳款」計算，`accountBalanceAsOfProvider`/
  `defaultBillingPeriodOffsetProvider`/`creditCardBillingBadgeProvider`
  共用）現在只是把 `creditCardDueByChildAsOf` 的結果加總。
- `credit_card_group_payment_page.dart` 的 `_loadDue` 改成直接呼叫
  `creditCardDueByChildAsOf`，不再自己重寫一份（原本那份既沒扣分期沖銷，
  子卡跨幣別時也沒折算——這次順便讓它以後也能正確處理「外幣子卡真的還沒
  繳清」的情境，不再只靠使用者手動先把外幣卡繳清來繞過）。

新增測試 `test/providers/credit_card_due_by_child_test.dart`，重現「外幣
子卡已結清但匯差被誤算」與「外幣子卡真的還沒繳清時仍需折算加總」兩種情境。

## 範圍外 / 待辦

- **BeeCount Cloud（伺服器端）尚未修**：使用者回報伺服器端「剩餘帳款」跟
  「繳費金額」兩者都錯，需要在 `../BeeCount-Cloud` 的
  `src/services/credit_card_billing.py` 對應套用同一個「先淨額、已結清就
  跳過、沒結清才折算」邏輯，這次先只處理 App 端。
- 只排查、修正了「已結清子卡的匯差殘值」這一種情境；沒有進一步查證是否還
  有其他造成兩邊數字不一致的因素（使用者這次的實際落差剛好可以用這個根因
  完整解釋:100→對應到使用者原始回報的 7,量級吻合)。
