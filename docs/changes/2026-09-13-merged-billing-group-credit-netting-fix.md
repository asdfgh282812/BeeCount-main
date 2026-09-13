# 合併帳單群組「剩餘帳款」溢繳淨額修正

## 背景(使用者反饋)

使用者的「聯邦信用卡 主帳戶(群組)」帳單彙總卡片顯示:應繳金額 -465、已繳
金額 -23、回饋折抵 +23、剩餘帳款 -488。使用者反饋剩餘帳款應該跟應繳金額
一樣是 465,不該是 488。

## 根因

這個群組底下有多張子卡,其中一張子卡(聯邦M卡)在這期只有一筆 +23 的回饋金
收入、沒有其他消費,導致它自己的淨額(消費減已繳)變成 **負值**(即這張子卡
本身處於溢繳狀態)。

畫面上兩條計算路徑各自獨立,對「溢繳子卡」的處理不一致:

- **應繳金額**(`lib/pages/account/account_detail_page.dart` 的當期交易迴圈):
  把群組內所有子卡的交易攤在同一個池子裡加總淨額,回饋金收入正確地被淨額
  扣抵,結果是 -465(正確)。
- **剩餘帳款**(`accountBalanceAsOfProvider` → 舊版 `_dueAsOf` →
  `creditCardDueByChildAsOf`):是「先把每張子卡自己的淨額 floor 到 0、再
  加總」——聯邦M卡淨額 -23 被 floor 成 0 後,整張卡直接從加總裡被跳過
  (`if (dueNative <= 0.005) continue;`),它原本該拿去抵掉其他子卡欠款的
  -23 就這樣憑空消失,群組總額變成只剩另一張子卡自己的 488(結果是
  -488,比正確答案多了 23)。

「已繳金額 -23」其實不是真的繳款紀錄,只是 `剩餘帳款 − 應繳金額` 反推出來
的殘值,恰好等於這兩條路徑對溢繳子卡處理方式不同所產生的落差。

比對 BeeCount Cloud(`/Users/andy/BeeCount-Cloud/src/services/
credit_card_billing.py::compute_group_billing`)的既有實作,Cloud 端本來就
是分成兩個獨立產物:`per_child_remaining_due_signed`(每個子帳戶「可能為負」
的淨額,`remaining_due = sum(...)` 用這個做群組總額,只在總和上 floor)跟
`per_child_remaining_due`(`max(due, 0.0)`,分攤付款用的下限 0 版本)。App
端原本把這兩種語意混在同一個 `creditCardDueByChildAsOf` 裡,對外只暴露
floor 過的版本,`_dueAsOf` 又直接拿這個已經 floor 過的 map 去加總,才會跟
Cloud 的算法出現落差。

## 改動

`lib/providers/credit_card_billing_providers.dart`:

1. 新增私有共用查詢 `_signedDueByChildAsOf`——把原本
   `creditCardDueByChildAsOf` 裡「查每張子卡淨額」的邏輯抽出來,回傳**可能
   為負**的淨額 map(已結清 `abs(due) <= 0.005` 的子卡才會被排除,溢繳的子
   卡會保留負值),鏡射 Cloud `per_child_remaining_due_signed`。
2. `creditCardDueByChildAsOf`(分攤預覽 [credit_card_group_payment_page.dart]
   用)改成只是在 `_signedDueByChildAsOf` 的結果上取正值(`entry.value >
   0.005`),對外行為/既有測試(`test/providers/credit_card_due_by_child_test.dart`)
   完全不變——這個函式本來就是拿來決定「該對哪張卡繳多少錢」,不能對某張
   卡繳負數,floor-then-exclude 的語意本身沒有錯。
3. `_dueAsOf`(`accountBalanceAsOfProvider`/`defaultBillingPeriodOffsetProvider`/
   `creditCardBillingBadgeProvider` 共用,對應「上期欠款」/「剩餘帳款」/
   帳戶列表「可繳款」徽章)改成直接加總 `_signedDueByChildAsOf` 的**淨額**
   (可能為負),只在最後的**總和**上 floor 到 0,鏡射 Cloud
   `remaining_due = sum(per_child_remaining_due_signed.values())`。

不能反過來讓 `_dueAsOf` 繼續呼叫 `creditCardDueByChildAsOf` 再加總——那個
函式的回傳值刻意只留正值、已經 floor 過,拿來加總正是這次要修的 bug 本身,
兩份程式碼註解裡都加了對應提醒,避免未來又被合併回去。

## 影響範圍

- 帳戶詳情頁帳單彙總卡片「上期欠款」「剩餘帳款」(`accountBalanceAsOfProvider`)
- 信用卡「交易明細」tab 預設停留帳期(`defaultBillingPeriodOffsetProvider`,
  依賴同一組欠款計算掃描歷史帳期)
- 帳戶列表「可繳款」徽章(`creditCardBillingBadgeProvider`)
- 合併帳單群組繳款頁([credit_card_group_payment_page.dart](../../lib/pages/account/credit_card_group_payment_page.dart))
  預帶的「總金額」輸入框跟「目前應繳總額:X」提示文字——這個頁面原本直接把
  `creditCardDueByChildAsOf` 的 map 加總當預帶金額,同樣受這個 bug 影響
  (使用者實測回報:「剩餘帳款」修正後,這個頁面預帶的金額卻還是舊的錯誤
  數字 488)。**這一輪額外新增了公開函式 `creditCardGroupDueAsOf`**(單純
  包一層 `_dueAsOf`)給這個頁面呼叫,`_loadDue` 改成分開存 `_remainingDueByChild`
  (分攤預覽/`allocateCardPayment` 用,維持 `creditCardDueByChildAsOf` 的
  floor-then-positive 語意不變)跟 `_totalDue`(預帶金額/提示文字用,來自
  `creditCardGroupDueAsOf` 的淨額加總)兩個獨立 state,不要再用前者加總
  頂替後者。
- **不影響**:分攤預覽本身該對哪張子卡分配多少錢(`allocateCardPayment`,
  仍只吃正值),以及當期「應繳金額」/「回饋折抵」顯示(本來就是對的,見上面
  根因分析)。

## 這次不做的(範圍外)

僅限於單一子卡溢繳、有其他子卡欠款可抵的情境。若整個群組**所有**子卡加總
後仍是溢繳(理論上的「整組倒欠使用者錢」),`_dueAsOf` 仍然 floor 在 0(對齊
既有 `creditCardDueAsOf` 單卡層級的既定行為:「已清償或溢繳一律回傳 0,
溢繳結轉的顯示不是這個函式的職責」),不像 Cloud 的 `remaining_due` 允許
顯示負數(視為「目前應繳」欄位可以顯示溢繳)——這次只處理使用者實際回報的
問題(子卡間淨額互抵被弄丟),沒有連帶把「群組整體溢繳」這個新顯示狀態的
UI/文案設計進來,避免範圍蔓延。

## 測試

- `test/providers/credit_card_group_remaining_due_test.dart`(新增)——複現
  使用者的真實數字(子卡A消費820+回饋收入332→淨欠488、子卡B只有回饋收入
  23→淨額-23 溢繳),驗證 `creditCardDueByChildAsOf` 的分攤預覽 map 行為不
  變(溢繳子卡仍被排除、主卡仍是 488),同時驗證
  `accountBalanceAsOfProvider` 回傳正確的淨額群組總計 -465(而不是舊版
  bug 的 -488)。
  同一個測試也驗證了 `creditCardGroupDueAsOf`(群組繳款頁預帶金額用)同樣
  回傳 465,不是舊版的 488。
- `test/providers/credit_card_due_by_child_test.dart`(既有,跑過確認未
  回歸)——外幣子卡結清匯差殘值的既有規則不受影響。
