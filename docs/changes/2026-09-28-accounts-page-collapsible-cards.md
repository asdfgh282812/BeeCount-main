# 資產頁圖表區與投資市值卡可折疊

日期:2026-09-28

使用者要求:資產頁淨資產卡下半部的圖表(淨值趨勢/資產構成)和「投資市值(預估)」卡
都改成可以折疊。

## 入口

資產頁(底部「資產」分頁):

- 淨資產卡:「淨值趨勢 / 資產構成」切換列右側的 ⌃/⌄ 箭頭。折疊後只剩一行「淨值趨勢」
  (或「資產構成」,依目前選的視圖),整行可點開。
- 投資市值卡:標題列右側的 ⌃/⌄ 箭頭。折疊後標題列直接顯示市值與未實現損益%;
  有待確認股利時圖示右上角有提示點(見 `2026-09-28-stock-dividends.md`)。點卡片其它
  地方一樣進投資總覽。

## 實作

- `lib/providers/theme_providers.dart::sectionCollapsedProvider`:
  `StateNotifierProvider.family<…, bool, String>`,按區塊 key 各自存 SharedPreferences
  (`sectionCollapsed.netWorthChart`、`sectionCollapsed.investmentValue`),預設展開。
  寫法比照同檔的 `assetTrendViewProvider`。之後其它區塊要折疊,換個 key 就能用。
- `accounts_page.dart::_chartSectionHeader`:取代原本只有切換膠囊的那一列。圖表不能
  切換構成時(多幣種非折算)也會有這一列,不然沒地方放收合箭頭。
- `investment_market_value_card.dart`:只有資產頁那張(`navigateOnTap = true`)可以
  折疊;投資總覽頁上方那張永遠展開。
- 折疊狀態只存本機,不同步到 Cloud/其它裝置(是版面偏好,不是資料)。
