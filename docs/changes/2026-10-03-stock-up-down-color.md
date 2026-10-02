# 股票漲跌顏色獨立設定(App 端,與 Web 同步)

## 為什麼
台灣習慣「紅漲綠跌」,但收支是「紅支出綠收入」(或相反),原本 `pnlColor` 沿用收支配色,
兩者無法同時符合習慣。Web 端已新增獨立設定,App 端對齊。

## 改了什麼
- `lib/providers/theme_providers.dart`:新增 `stockUpIsRedProvider`(預設 true = 紅漲綠跌)+ `stockUpIsRedInitProvider`
  (prefs `stockUpIsRed`);`_pushAppearanceToCloud` 的 appearance 包加入 `stock_up_is_red`。
  App 是整包 appearance PATCH,不帶這個 key 會把 Web 設的值清掉,所以必須在包內。
- `lib/providers/sync_providers.dart`:`_applyAppearanceFields` 下行套用 `stock_up_is_red`。
- `lib/providers/ui_state_providers.dart`:啟動時載入 init provider。
- `lib/pages/investment/investment_ui.dart`:`pnlColor` 改依 `stockUpIsRedProvider`,持股/已實現損益/漲跌幅全部共用。
  股利金額仍用收入色(本質是收入)。
- `lib/pages/settings/appearance_settings_page.dart`:新增「股票漲跌顏色」設定列與對話框。
- l10n(en / zh_TW)與 What's New(3.7.0)。

## 入口
我的 → 外觀設定 → 股票漲跌顏色。

## 未做
- `reconcileProfileToServer` 只在 server appearance 為空時補推,未加此 key(與其他較新 key 同)。
