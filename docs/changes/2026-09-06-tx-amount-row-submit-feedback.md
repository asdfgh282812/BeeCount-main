# 記帳表單:金額列改版 + 滑動送出補上錯誤提示

## 背景

使用者回報記帳表單(`transaction_entry_form.dart`)的金額列右側留了一大塊空白
(原本靠 `Spacer()` 把幣別/金額全部推到右邊),金額本身沒有框線不容易辨認是
可點的輸入區塊;另外「滑動送出」手勢在必填欄位(分類/金額)缺漏時完全沒有
任何提示,使用者只會覺得「滑了沒反應」。

## 變更內容

### `lib/widgets/biz/transaction_entry_form.dart`

- 金額表達式列:移除原本的 `Spacer()`(把內容推到右側),改成幣別 chip +
  手續費/折扣切換鍵靠左,金額本身包一層 `Border.all(color: BeeTokens.border)`
  的 `Container` 加框線,右側原本的留白改放一顆送出鍵
  (`_buildInlineSubmitButton`,key `inlineSubmitButton`)。連續運算中的
  「= 總額」預覽列與匯率換算列(`_buildCurrencySection`)的
  `mainAxisAlignment` 從 `end` 改回預設(靠左),對齊金額新位置。
- 新的送出鍵不管 `canSubmit` 是否成立都直接呼叫 `_submit()`——不是把按鈕
  disable 掉就沒事,而是讓 `_submit()` 自己的驗證分支決定要不要跳錯誤提示,
  跟小算盤原本的 ✓ 鍵(`onSave: _submit`)行為一致。
- `_submit()` 原本在「拆帳筆數/金額無效」「未選分類」「金額為 0」這三種情況
  下是靜默 `return`(不吭聲),現在都補上對應的 `showToast`。「未選帳戶」跟
  手續費/折扣負數的提示原本就有,沒動。

### `lib/widgets/biz/pull_to_submit_scroll_view.dart`

- 新增可選參數 `onBlockedSubmit`:手勢拉到武裝門檻、放開時若
  `canSubmit == false`,現在會呼叫這個 callback(預設 `null`,不影響其他
  沒接這個參數的呼叫端,如 `transfer_form.dart`/`debt_entry_form.dart`)。
  `transaction_entry_form.dart` 直接把 `_submit` 傳進去——複用同一份驗證/
  錯誤提示邏輯,不用另外重寫一份「為什麼滑不出去」的判斷。

### 新增 l10n key(`app_en.arb` + `app_zh_TW.arb`,依照專案現行只維護這兩個
檔案的慣例)

`txCategoryRequiredHint`、`txAmountRequiredHint`、`txSplitRequiredHint`。

## 刻意不做的事

- 沒有動 `transfer_form.dart`/`debt_entry_form.dart` 的滑動送出行為——
  `PullToSubmitScrollView` 的 `onBlockedSubmit` 是選配的,這兩個表單沒接,
  行為維持原樣(`transfer_form.dart` 的 `_submit()` 其實也有同樣「靜默
  return」的分支,但這次範圍只鎖定使用者回報的記帳表單畫面,沒有一併修)。
- 沒有移除或改寫 `PullToSubmitScrollView.canSubmit` 既有的門檻邏輯,只是
  新增了「被擋下時要不要多做一件事」的掛鉤點。
