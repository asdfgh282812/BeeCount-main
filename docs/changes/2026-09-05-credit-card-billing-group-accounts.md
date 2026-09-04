# 信用卡帳單 off-by-one 修正 + 帳戶群組建立功能（App 端）

設計文件：`docs/superpowers/specs/2026-09-05-credit-card-billing-group-accounts-design.md`

## 1. 結帳日 off-by-one 修正

[lib/utils/card_reward_period.dart](../../lib/utils/card_reward_period.dart) 的
`mostRecentlyClosedBillingOffset()` 拿掉「結帳日當天視為已結清」的特例，
一律回傳 `-1`。原本結帳日當天（如帳單日 5 號）會被判定成「offset=0 這期
已結清」，提前一天顯示「可繳款」；修正後從隔天（6 號）起才會顯示。影響
兩處呼叫點：帳戶列表「可繳款」徽章（`credit_card_billing_providers.dart`）、
繳款備註文字（`credit_card_payment.dart`）。

**Cloud 端（`services/credit_card.py::most_recently_closed_cycle`）刻意不動**：
實際查了程式碼才發現這個函式被 `credit_card_billing.compute_group_billing`
共用，而這個函式本身又同時餵給三個地方——Web 帳單顯示、`accounts.py` 的
`card_payment_ep`（實際繳款分攤金額）、`credit_card_reminders.py`/
`credit_card_autopay.py`（到期提醒/自動扣款觸發時機），是刻意設計成「三處
共用同一個數字，避免顯示金額跟實際繳款金額兜不起來」。實測套用同一個
off-by-one 修正會讓 `test_statement_closed_reminder_fires_on_billing_day`、
`test_reminder_not_duplicated_for_same_cycle`、
`test_autopay_not_triggered_before_due_date` 三個既有測試失敗——因為這兩個
通知/自動扣款功能的觸發時機依賴的正是「結帳日當天=已結束」這個舊語意。
跟使用者確認後決定：這次完全不動 Cloud 端。App 端的「可繳款」徽章是純本地
計算（讀本地交易記錄），不依賴 Cloud 同步下來的欄位，因此 App 端修正本身
不受影響、獨立生效。Web 端「結帳日當天提早一天顯示可繳款」這個對應的一天
誤差目前維持原狀，留待未來獨立評估 Cloud 端金流分攤邏輯後再處理。

## 2. App 端新增「建立帳戶群組（主帳戶/合併帳單）」入口

之前 App 只能被動接收 Web 端建立好、同步下來的 `account_group` 帳戶，
[account_edit_page.dart](../../lib/pages/account/account_edit_page.dart)
的類型清單裡沒有這個選項。

- **入口A**：日常帳戶類型網格最後新增「主帳戶(群組)」卡片（獨立於
  `tradableAccountTypes`/`valuationAccountTypes` 兩份清單之外）。選中後
  額度/帳單日/還款日三個欄位全部收斂成選填（沿用同一組
  `_creditLimitController`/`_billingDay`/`_paymentDueDay`，因為信用卡跟
  群組互斥顯示、不會同時出現）。
- **入口C**：「主帳戶」下拉選單最上方新增「＋新增主帳戶」項目，點擊後彈出
  `_QuickCreateGroupSheet`（同一份表單欄位，差別只在容器是彈窗、且省略
  頭像設定——建立後可回到群組自己的編輯頁再補），成功後直接把目前正在編輯
  的帳戶掛靠上去。

不做「先選信用卡群組／一般帳戶群組」的前置選擇，分類展示完全靠子帳戶類型
事後推斷（沿用既有 `_resolveDisplayType` 邏輯，未改動）。

## 3. 主帳戶候選清單修正（對齊 server 限制）

`_loadParentCandidates()` 原本完全不篩選類型，任何無主帳戶都能被選成別人
的主帳戶，但 server 端規定主帳戶必須是 `account_group` 類型——選了普通
信用卡當主帳戶會在同步時被拒絕。修正為只列出 `type == 'account_group'`
的帳戶，同時排除自己、排除已經有掛靠的群組（禁巢狀）。不做子帳戶類型
一致性檢查——server 明確允許混合（有測試鎖住這個行為）。

## 4. 子帳戶欄位隱藏

信用卡表單裡，當 `parentAccountId != null`（已掛靠某個主帳戶）時，額度/
帳單日/還款日改顯示「額度/帳單日/還款日已移至主帳戶「{群組名稱}」管理」+
「前往設定」連結（導向該群組的編輯頁），欄位本身不再可編輯。本地資料庫
裡子卡自己的 `creditLimit`/`billingDay`/`paymentDueDay` 不清空（孤兒值，
移出群組可還原顯示，跟 server 端行為一致）。連帶修正了 `_save()` 裡信用卡
必填檢查——掛靠主帳戶的子卡不再強制要求自己填帳單日/還款日（先前這裡沒有
對應處理，若掛靠後從未填過會導致無法儲存）。

未掛靠的獨立信用卡在欄位上方新增提示文字，說明之後掛靠主帳戶會改用主帳戶
的共用設定。

## 5. 欄位驗證範圍改為 1-31

`_DayPickerTile` 的日期選擇網格從 28 格改成 31 格，對齊 server 實際允許
範圍（`AccountsPage.tsx`）。`db.dart`/`config_export_service.dart` 裡
「(1-28)」的欄位註解一併更新成「(1-31)」（純註解，DB 本身沒有實際的範圍
約束，不需要 migration）。

## 明確排除範圍（延續設計文件）

- 不做子帳戶類型一致性檢查、不做多選子帳戶一次性歸類精靈頁。
- 不實作 server 端已有但 App 本地 schema 尚未支援的「自動扣繳」欄位。
- 不重新設計「群組帳戶詳情頁」的花費統計/子卡分頁瀏覽體驗。
- Cloud 端 `most_recently_closed_cycle` 維持原狀（見上）。

## 已確認不需要改動的地方

- 交易頁的帳戶選擇器（`account_card_picker.dart`）已經排除 `account_group`
  類型，不會讓使用者對著純管理容器記帳——這是設計文件列的風險項，實際檢查
  後確認已有正確行為。

## 驗證

`flutter analyze`（無新增錯誤）、`dart format`、`flutter test`（1122 個
測試全數通過，含 `test/widgets/account_card_picker_test.dart`、
`test/sync/account_parent_apply_test.dart` 等跟帳戶群組相關的既有測試）。
未能在本機做 iOS 模擬器/瀏覽器的即時畫面驗證——執行環境的 Xcode 尚未
`xcode-select` 選定路徑（需要使用者密碼），Flutter Web target 因專案用了
`dart:ffi`/sqlite3 本來就編譯不過。
