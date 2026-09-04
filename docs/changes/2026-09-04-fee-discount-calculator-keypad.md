# 手續費/折扣金額改用計算機鍵盤(修正誤觸)

延續 [2026-09-04-expense-income-fee-discount.md](./2026-09-04-expense-income-fee-discount.md)。
使用者實測後回報兩個問題:(1) 手續費/折扣金額欄位是系統鍵盤輸入,跟主金額的
計算機鍵盤體驗不一致;(2) 面板展開後,點面板裡任何空白處(標籤欄、幣別徽章、
容器間距)都會誤叫出「上面」的主金額小算盤——因為主金額那顆
`GestureDetector(key: amountDisplayTap)` 當時整個包住含面板在內的 Column,
面板展開後區域變高,幾何上整塊都落在這顆 GestureDetector 的命中範圍內。

## `lib/widgets/biz/transaction_entry_form.dart`

- 手續費/折扣金額改成跟主金額共用同一顆 `AmountCalculatorKeypad`,不再是
  `TextField` + 系統鍵盤。新增 `_AmountKeypadState`(純狀態 class,持有
  `amountStr`/`acc`/`op`,方法對齐主金額原本的 `_appendDigit` 等邏輯)給
  `_feeKeypad`/`_discountKeypad` 各自一份獨立的「連續運算」狀態,避免三份
  (主金額/手續費/折扣)重複邏輯。`_AmountKeypadTarget` enum(`main`/`fee`/
  `discount`)記在 `_activeAmountTarget`,決定唯一一顆鍵盤的 `_appendDigit`/
  `_backspace`/`_clearAll`/`_applyOp`/`_applyEquals` 這次要寫進哪一組狀態——
  main 分支的邏輯完全沒動,只是多包一層 target 判斷。
  - 鍵盤的 ✓ 鍵語意也跟著 target 走:`_activeAmountTarget == main` 時維持
    「送出整張表單」;fee/discount 時只是「收起鍵盤」(不然使用者在調整
    手續費時不小心按到 ✓ 會把整張交易存出去)。`canSubmit`/`isInCalcMode`
    傳給鍵盤的值也拆成 `keypadCanSubmit`/`keypadIsInCalcMode`,跟原本驅動
    「整張表單能不能存」的 `canSubmit`/`isInCalcMode` 分開,互不干擾。
  - 計算機鍵盤沒有負號數字鍵——負的手續費/折扣要靠運算子鍵組出來(例如
    「0 − 5」),`_submit()` 讀 `_feeKeypad.total`/`_discountKeypad.total`
    (已經套用運算子的結果),不是還沒按等號的 `amountStr` 原始字串。
- 修正「點面板任何地方都誤觸主金額鍵盤」:`amountDisplayTap` 這顆
  `GestureDetector` 現在只包主金額本身(含幣別/連續運算預覽/匯率換算列),
  手續費/折扣面板搬到它的手足節點(sibling),不再是子節點,面板裡的空白
  處自然不會再冒泡觸發它的 `onTap`。面板內金額文字改用新的
  `_buildKeypadAmountCell`——只包住金額文字這一小塊(不含幣別徽章、標籤欄、
  容器空白),點下去才切換 `_activeAmountTarget` 並叫出對應的鍵盤,對齐
  「點到金額才跳出來」的回饋。
- `_feeAmountCtrl`/`_discountAmountCtrl`(`TextEditingController`)跟
  `_feeAmountFocus`/`_discountAmountFocus`(`FocusNode`)整組移除——金額欄位
  不再是可聚焦的系統鍵盤 `TextField`。手續費/折扣的「名稱」欄
  (`_feeLabelCtrl`/`_discountLabelCtrl`)不受影響,仍是一般文字輸入。

## `lib/widgets/biz/amount_adjustment_panel.dart`

- `AdjustmentFieldRow` 新增可選的 `amountCellOverride`(`Widget?`)——非 null
  時取代原本金額 `TextField`,原本的 `amountCtrl`/`amountFocus`/`amountHint`
  改成可選(用建構子 `assert` 保底:沒給 `amountCellOverride` 時這三個仍然
  必填)。`transfer_form.dart` 沒有傳這個新參數,行為/外觀完全不變。

## 測試

`test/widgets/transaction_entry_form_fee_discount_test.dart` 全面改寫互動
方式(`enterText` → 點金額文字叫出鍵盤 + 點數字鍵),並新增一個案例專門驗證
「點面板空白處(標籤欄、幣別徽章)不會誤觸主金額鍵盤」。負數金額測試改用
「-」運算子鍵組出負值(而非原本 `enterText('-5')`,計算機鍵盤沒有負號數字
鍵)。`transfer_form_fee_discount_test.dart`(轉帳沿用系統鍵盤,不受影響)
跟其餘全套 `flutter test` 皆綠。
