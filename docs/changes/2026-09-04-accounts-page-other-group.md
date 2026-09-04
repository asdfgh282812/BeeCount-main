# 帳戶總覽：借還款／分期付款移至列表底部並獨立成「其他」分组

## 變更內容

`lib/pages/account/accounts_page.dart`：

- 將 `_DebtEntryCard`（借還款/應收應付款項虛擬入口）與 `_InstallmentEntryCard`
  （分期付款虛擬入口）從「淨資產卡之後、資產/負債分组之前」移到整個帳戶列表
  最下方（資產分组、負債分组、其他未知類型分组之後，已隐藏帳戶分区之前）。
- 在這兩張卡片上方加了一個分组標題列（沿用 `commonOther` 字串「其他」+
  `Icons.more_horiz`），視覺上比照參考 App（Moze）把借還款/分期付款歸入
  獨立的「其他」分组呈現，也比照本頁其他分类標題（`_buildClassificationSection`）
  的排版風格（icon + 粗體標題）。

## 為什麼

使用者反饋這兩個虛擬入口卡片原本插在淨資產卡和「資產帳戶」分组中間，
視覺上比較突兀；改為放在列表最後並加上分组標題後，跟一般帳戶分类的排列
邏輯（資產 → 負債 → 其他 → 已隐藏）一致，也更貼近使用者參考的另一個記帳
App 的呈現方式。

## 刻意不做的事

沒有幫這個「其他」分组標題加小計金額。`_DebtEntryCard` 顯示的是「淨應收/
應付」（可正可負），`_InstallmentEntryCard` 顯示的是「未繳分期本金」（恆為
負債方向的金額），兩者語意不同、正負號規則也不同，直接相加當作分组小計
會誤導使用者，所以這次只加了標題文字，沒有像 `_buildClassificationSection`
那樣加總金額。這兩張卡片仍然是純 UI 入口，不是 `db.Account` 記錄，不影響
`_groupAccounts()`/`_AccountTypeGroup` 既有的分组資料流程。
