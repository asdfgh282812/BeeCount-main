# 對帳清單顯示手續費/折扣小字提示

## 背景

對帳模式(`lib/pages/account/account_reconciliation_page.dart`)逐筆列出這期帳單的交易,
但金額欄只顯示淨額。使用者在交易明細卡(`showTransactionDetailCard`)已經能看到
「(內含 手續費 NT$36)」這類小字提示,對帳清單卻沒有,對到有手續費/折扣的帳單筆時
只能點開明細卡或自己心算差額,拖慢對帳速度。

## 變更

- [`lib/widgets/biz/transaction_detail_card.dart`](../../lib/widgets/biz/transaction_detail_card.dart):
  將原本 `_TransactionDetailCardState._buildFeeDiscountSubtitle` 內的組字邏輯抽成
  頂層函式 `buildFeeDiscountSubtitle(context, l10n, tx)`,State 內的方法改成呼叫它,
  行為不變。抽出來是為了讓對帳清單也能直接引用,不重複同一段「手續費/折扣本體有
  自訂標籤就用標籤,否則用預設 hint 文案,兩者都有時用分隔符串接」的邏輯。
- [`lib/pages/account/account_reconciliation_page.dart`](../../lib/pages/account/account_reconciliation_page.dart):
  `_StatementRow` 在日期文字下方,非轉帳交易時加一行 `buildFeeDiscountSubtitle(...)`,
  跟明細卡同樣的樣式(12sp、`textTertiary` 色)、同樣的資料來源
  (`Transaction.feeAmount`/`discountAmount`/`feeLabel`/`discountLabel`)。轉帳交易
  本來就不會有手續費/折扣欄位語意(轉帳的手續費用另一組欄位是給「轉帳損益」的,
  這裡的小字提示只適用一般收支),所以沿用明細卡同款的 `!isTransfer` 判斷跳過。

## 範圍外

- 沒有調整這兩個手續費/折扣欄位本身的記帳/編輯流程,只補顯示。
- 沒有動到 `signedStatementAmount`(對帳清單金額欄本身仍是淨額,不拆手續費)。
