# 日曆切換日期時明細動畫

- 範圍:`lib/pages/calendar/calendar_body.dart` 的 `_buildDateTransactionsList`。
- 問題:點選不同日期後,下方當日交易明細直接替換,視覺生硬。
- 做法:以 `ValueKey(日期)` 搭配 `AnimatedSwitcher`(220ms 淡入 + 輕微上滑)切換內容,外層 `AnimatedSize`(260ms easeOutCubic)讓高度平滑伸縮;舊內容用 Stack 疊放淡出,避免版面跳動。
- 入口:記帳(首頁)→ 日曆檢視 → 點選任一日期。
