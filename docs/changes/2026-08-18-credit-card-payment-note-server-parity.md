# 信用卡繳款交易的備註文字對齊 Server 端

## 背景

使用者反饋(2026-08-18):

> server 端的繳費行為與app 端有點不一樣，app 的繳費只會寫轉帳，而server 端的雖然也是轉帳，但他會多了備註等相關訊息（不完全是轉帳等效交易）
> 請查看web (server ）端的繳費如何實做，把他寫到app 端裡（只要抄繳費就好了）

查了 BeeCount Cloud（`../BeeCount-Cloud`）`src/routers/write/accounts.py::card_payment_ep`，繳款寫入的
transfer 交易除了金額/帳戶等一般欄位外，`note` 會依規則自動產生：

```python
note = req.note
if not note:
    cycle_start, cycle_end = billing["cycle_start"], billing["cycle_end"]
    note = f"信用卡繳款(帳單 {cycle_start.isoformat()}~{cycle_end.isoformat()})"
...
tx_note = f"{note}(溢繳結轉)" if not req.note else note  # 打到群組自己身上那筆(溢繳結轉)
```

其中 `cycle_start`/`cycle_end` 來自 `credit_card_billing.compute_group_billing` 內部呼叫的
`credit_card.most_recently_closed_cycle(now.date(), billing_day)`——**「最近一次已結帳」的那一期**,
不是使用者發起繳款時畫面上正在看哪個帳期。

App 端原本的 `credit_card_group_payment_page.dart::_cycleLabel()` 直接拿呼叫端傳進來的
`widget.period`(=帳戶詳情頁「交易明細」tab 當下瀏覽的 `_billingPeriodOffset`,可能是任何一期)
組出 `"YYYY/MM/DD – YYYY/MM/DD"` 這種文字,兩個問題:
1. 文字格式跟 server 對不上(`/`+en-dash vs. `-`+`~`,沒有「信用卡繳款(帳單 ...)」中文字樣)。
2. **更關鍵**——週期來源錯了:使用者若在當期(尚未結束)畫面點「繳款」,備註會寫成當期,但
   实际上這筆錢多半是在繳「已結帳、要在繳款截止日前付清」的上一期帳單,跟 server 的語意不一致。
   這正是這個 session 稍早「繳款記錄改用 FIFO 期別歸屬」那個修正
   (`docs/changes/2026-08-18-credit-card-payment-record-attribution-restore.md`)想解決的同一類問題,
   只是這次是「寫入時的備註文字」而不是「顯示時的分組」。

## 改動

### `lib/utils/credit_card_payment.dart`

新增純函式 `creditCardPaymentNote({required int? billingDay, bool isOverflowToGroup = false})`:
- 用 `mostRecentlyClosedBillingOffset(billingDay)` + `billingCyclePeriod(billingDay, offset)`
  (鏡射 Cloud `most_recently_closed_cycle`)算出「最近一次已結帳」的週期,`period.start` 是查詢用的
  inclusive-both 邊界,要 `-1 天`換回結帳日本身(跟 `account_detail_page.dart::_formatCycleLabel`
  同一個換算方式)。
- 文字格式逐字對齊 server 的 f-string:`信用卡繳款(帳單 {ISO 起}~{ISO 迄})`,`isOverflowToGroup`
  時加註 `(溢繳結轉)` 後綴,對齊 `tx_note = f"{note}(溢繳結轉)"`。
- 放進這個檔案(而不是留在頁面私有方法)是因為檔案標頭本來就寫明「純函式,不依賴 Drift/Riverpod,
  方便單元測試」,`billingDay`→note 是同樣性質的純字串生成,獨立出來才能不靠 pump widget 直接單元測試。

### `lib/pages/account/credit_card_group_payment_page.dart`

`_submit()` 把原本的 `_cycleLabel()`(已刪除)換成呼叫 `creditCardPaymentNote`:
- 打給各子卡的 transfer:`note: creditCardPaymentNote(billingDay: widget.account.billingDay)`。
- 打給群組自己(溢繳結轉,`entry.key == widget.account.id`)的 transfer:多傳
  `isOverflowToGroup: true`。
- 對應移除了不再使用的 `../../utils/card_reward_period.dart` import(邏輯已搬進
  `credit_card_payment.dart`)。

### 刻意不動的部分

- `widget.period` 仍然保留、仍然用在 `_loadDue()` 算「應繳金額」預帶值的 cutoff——這是「使用者在
  哪一期畫面按繳款、就預帶那一期的應繳金額」的既有行為,跟這次只改「備註文字用哪一期」無關,使用者
  也沒有要求改這部分。
- server 允許呼叫端傳自訂 `req.note` 覆蓋預設值;App 端這個頁面本來就沒有讓使用者編輯備註的欄位,
  所以只實作了「無自訂 note」的自動產生分支,沒有加對應的可選覆蓋參數(YAGNI——沒有 UI 入口用不到)。
- `allocateCardPayment`(分攤金額演算法)、`_loadDue`(應繳金額查詢公式)這些跟「這筆交易怎麼分錢」
  相關的邏輯本來就已經照抄 server,這次沒有再碰。

## 測試

`test/utils/credit_card_payment_test.dart` 新增 `creditCardPaymentNote` group(3 個測試):
- 格式對齊 server 的「信用卡繳款(帳單 起~迄)」,週期取「最近一次已結帳」的那期(用實際的
  `mostRecentlyClosedBillingOffset`/`billingCyclePeriod` 現算期望值比對,避免依賴寫死的日期跟
  `DateTime.now()` 對不上)。
- `isOverflowToGroup` 正確加註「(溢繳結轉)」後綴。
- `billingDay` 為 `null` 時(退化成每月 1 號起算)不拋例外。

`flutter analyze`:835 issues,跟改動前同一個數字,0 個新增。
`flutter test`:766/766 全過(改動前 763 + 這次新增 3 個)。

沒有跑實機/模擬器手動驗證(這台機器沒有可用的 iOS Simulator/Android SDK,跟本 repo 先前幾次改動
記錄的限制一樣)。
