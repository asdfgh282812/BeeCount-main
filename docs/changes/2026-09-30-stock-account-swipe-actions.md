# 投資理財(股票)帳戶:不能調整餘額,滑動快捷改成買進/賣出/定期定額

Cloud/Web 端見 BeeCount Cloud repo `docs/STOCK_HOLDINGS_SD.md` §10.4。

## 為什麼

投資理財帳戶的餘額是「持股成本的帳面數」(買進時由交割帳戶轉進來、賣出時轉出)。
對它「調整餘額」會多出一筆 adjustment 交易,讓帳戶餘額跟持股成本對不上,金額就
跑掉。原本帳戶列表的滑動快捷(右滑調整餘額、左滑新增交易)對所有帳戶一視同仁,
投資帳戶也會露出這兩顆;而「新增交易」開的是一般收支表單,不是股票交易頁。

## 改了什麼

- `lib/providers/account_swipe_action_providers.dart`
  - `AccountSwipeAction` 新增 `stockBuy` / `stockSell` / `stockDca`。
  - 新增 `generalSwipeActionChoices`(一般帳戶可選)與 `stockSwipeActionChoices`
    (投資帳戶可選:無/買進/賣出/新增定期定額/編輯),兩組互不出現對方的動作。
  - `AccountSwipeSettingsNotifier` 參數化(預設值、儲存 key 前綴、允許的動作);
    新增 `stockAccountSwipeSettingsProvider`,key 前綴 `account_swipe_stock`,預設
    右滑買進、左滑賣出。讀到不在允許清單內的舊值一律退回預設。
- `lib/pages/account/accounts_page.dart`
  - `_SwipeActionRow` 依 `account.type == 'investment'` 選用股票那組設定。
  - 買進/賣出開 `StockTradeEditorPage(initialTradeType: buy/sell)`,新增定期定額
    開 `RecurringStockRuleEditorPage`。
  - 防呆:即使有人把 `adjustBalance` 送進投資帳戶,也只是打開帳戶詳情,不會開調整
    餘額視窗。
- `lib/pages/settings/appearance_settings_page.dart`:滑動快捷設定區塊下面多一組
  「投資帳戶 · 右滑/左滑操作」;選單依各自的 choices 列出動作。
- l10n:`accountSwipeActionStock{Buy,Sell,Dca}`、`accountSwipeStock{Right,Left}Label`、
  What's New `whatsNew370StockSwipe{Title,Desc}`。

## 入口

- 帳戶頁 → 在投資理財帳戶那一列向右滑(買進)/向左滑(賣出)。
- 改動作:我的 → 個性化設定 → 滑動快捷操作 → 「投資帳戶 · 右滑/左滑操作」。

## 刻意沒做

- 沒有在 Cloud 的 `balance-adjustment` 端點拒絕投資帳戶:舊資料可能已經有調整交易,
  伺服器端硬擋會讓舊客戶端寫入失敗;目前 App/Web 都已經不再提供入口。
- 已經存在的餘額調整交易不清理。

## 驗證

- `flutter analyze` 三個改動檔 0 error / 0 warning。
- App 畫面沒有在模擬器實際滑動驗證(模擬器停在登入頁,等使用者登入)。

## 追加:滑動快捷操作跟著帳號走(雲端同步)

原本刻意只存本機;改為併入 `/profile/me` 的 `appearance` 包,換裝置/重裝登入後自動還原。

- 新增 4 個 key:`account_swipe_left` / `account_swipe_right`(一般帳戶)、`account_swipe_stock_left` / `account_swipe_stock_right`(投資帳戶),值為 `AccountSwipeAction.name`。
- 上行:`account_swipe_action_providers.dart` 的 notifier 變更後呼叫 `pushAppearanceToCloud`(`theme_providers.dart` 新增的公開包裝,與其他外觀設定同一條推送管線)。
- 下行:`sync_providers.dart::_applyAppearanceFields` 呼叫 `applyFromServer`,只落本機、不回推;不認得的動作名稱忽略。
- Cloud 端 `appearance` 為自由 dict,不需改伺服器;舊版 App 推 appearance 時不帶這 4 個 key,新版收到缺欄位會保留本機值。
- 「AI 專案指定」原本就經 `ai_config.project_assign_mode` 同步,無需改動。
- Web 端目前不使用這些 key(滑動是 App 專屬手勢)。
