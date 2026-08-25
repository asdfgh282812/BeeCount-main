# 帳戶資訊頁直接切換「納入總餘額」+ 分類標題列合計餘額小計

## 背景

[2026-08-25-account-include-in-total.md](2026-08-25-account-include-in-total.md)
補上了 `Account.includeInTotal` 這個欄位，但當時的入口只有「編輯帳戶」頁——使用者
要改這個開關得先點鉛筆進編輯頁、找到開關、切換、再存檔離開，比起「帳戶資訊」tab
上一堆唯讀欄位多繞了一層。同時，帳戶總覽頁的分類清單（現金/銀行/信用卡…）標題列
只顯示帳戶數量，沒有像 BeeCount Cloud 網頁面板那樣顯示這個分類的合計餘額，使用者
想看「這個分類到底有多少錢」得自己心算清單裡每一筆。這次一併處理這兩個回饋。

## 改動範圍

### 1. 「帳戶資訊」tab 的「納入總餘額」開關改成即時可切換

- `lib/pages/account/account_detail_page.dart`：
  - `_InfoSwitchRow` 從「一律 `onChanged: null` 的唯讀占位開關」改成
    `onChanged`/`hint` 皆為選填——不傳 `onChanged` 時維持原本唯讀占位行為
    （目前只剩信用卡「可用額度不足提醒」還在用這個模式），傳了就是可以切換、
    並在標籤下方多顯示一行說明文字的真開關。
  - 新增 `_liveAccount(account)`：從 `allAccountsStreamProvider`（Drift 的
    live watch stream）裡找同一筆帳戶的最新狀態。這一頁的 `account` 原本是
    `widget.account`——建構當下傳進來的快照，切換開關後資料庫值變了但這個
    快照不會自動更新；改讀 stream 裡的即時資料就不用額外呼叫
    `ref.invalidate`，寫入後 Drift stream 自動推新值、UI 自動重繪。
  - 新增 `_toggleIncludeInTotal`：直接呼叫既有的
    `repo.updateAccount(id, includeInTotal: v)`（沿用
    `account_edit_page.dart` 已經在用、也已經打通 push 同步的同一條路徑），
    失敗才跳 toast，成功不特別提示（開關本身的視覺變化就是回饋）。
  - 「納入總餘額」這一列的 label/hint 文字改用跟編輯頁完全相同的
    `accountIncludeInTotalLabel`/`accountIncludeInTotalHint`（不再用只有這裡
    在用的 `accountIncludeInNetWorthLabel`，該 key 保留在 arb 檔裡不動，只是
    不再被引用）。

- `lib/pages/account/account_edit_page.dart`：移除「不納入總餘額」那個
  `SectionCard`+`Switch` 區塊。`_includeInTotal` 欄位本身保留（`initState`
  仍從 `widget.account?.includeInTotal ?? true` 帶入、`_save()` 仍原樣寫回），
  純粹拿掉這裡的 UI 入口——新建帳戶預設值（納入）跟既有的儲存邏輯都不變，
  只是不能再從編輯頁改這個欄位，改到帳戶資訊頁去改。

### 2. 帳戶總覽分類標題列加「合計餘額」小計

- `lib/pages/account/accounts_page.dart`：`_AccountTypeGroup`（現金/銀行/
  信用卡…這類分類的標題列 + 帳戶清單容器）新增
  `_computeGroupSubtotals`/`_buildGroupSubtotal`，在標題列的帳戶數量徽章跟
  展開箭頭之間插入兩個數字：**納入總額的小計 / 這個分類全部帳戶小計（不論
  是否納入）**，用 `/` 分隔，前者用該分類的 typeColor 加粗、後者用
  tertiary 顏色，對齊 web 端「合計餘額」的呈現方式。
  - 分類內帳戶幣種一致時直接加總（不轉幣），跟既有
    `_buildClassificationSection`（資產/負債大分類）的單一幣種小計同一個
    邏輯；有多種幣種時用既有的 `convertBetweenCurrencies` 折算成主幣種
    （`baseCurrencyProvider`/`effectiveRatesProvider`，跟頁面其它折算口徑
    同一組），缺有效匯率的帳戶兩個小計都跳過、不計入，並在小計前面加一個
    橙色警示圖示——不假裝按 1.0 折算（沿用 README D5 這個既有原則）。
  - 兩個 `AmountText` 都吃預設的 `hideAmountsProvider`（隱藏金額）狀態，
    跟頁面其它金額顯示一致，不需要額外處理。
  - 整組小計包在 `Flexible(child: FittedBox(fit: BoxFit.scaleDown))` 裡，
    避免帳戶名稱長、幣種多、金額位數多時把標題列撐到溢位。
  - `widget.allStats` 還在載入（`null`）時 `_computeGroupSubtotals` 直接回傳
    `null`，呼叫端整段跳過不渲染，避免資料還沒到齊先閃一個假的 `0 / 0`。

## 刻意排除的範圍

- 沒有比照既有的「淨資產卡」/「資產分類小計」（`_buildGroupConvertedSubtotal`）
  加上「點擊看每幣種明細」的彈窗互動——這次只是把數字列出來，互動式明細彈窗
  之後有需要再補，避免這次改動範圍過大。
- 沒有在標準帳戶清單（`_AccountCard`）或選帳戶的底部彈窗
  （`account_card_picker.dart`）幫每一筆帳戶加上幣別代碼＋折算切換鈕（web
  端子帳戶列已有這個功能，見 `_ChildAccountRow`）——這次的需求範圍明確只到
  分類標題列的合計餘額,幣別標示留待之後有需要再處理。
