# 明細月曆：切換月份時保留選中的「日」

## 問題

明細頁月曆（`lib/pages/calendar/calendar_body.dart`）點擊上一月/下一月箭頭（或左右滑動翻頁）時，`_onPageChanged` 會直接把 `_selectedDay` 清成 `null`，導致翻頁後選中日期消失、下方「當日交易列表」跟著收起。

使用者期望：例如目前選中 9/7，翻到下個月應停在 10/7；翻到上個月停在 8/7；若目標月沒有對應天數（例如從 1/31 翻到只有 30 天/28 天的月份），則停在該月最後一天。

## 修改

`lib/pages/calendar/calendar_body.dart`：

- 新增 `_clampDayToMonth(day, month)`：以 `DateTime(month.year, month.month + 1, 0).day` 算出目標月天數，把「日」鉗制到合法範圍。
- `_onPageChanged`：翻頁時改用 `_clampDayToMonth(_selectedDay!.day, focusedMonth)` 保留日期，而非清空為 `null`。
- `jumpToMonth`（頭部「年/月 ▾」選擇器跳轉）套用同一邏輯，保持與滑動翻頁一致的語義（程式碼中原本的註解已註明兩者應同語義）。

`_onDaySelected`、`jumpToToday` 不受影響，仍分別為「手動點選某日」「跳回今天」的既有行為。

## 未變更範圍

- 沒有 `_selectedDay`（理論上不會發生，`initState` 一律設為今天）時翻頁仍維持 `null`，不強行選中任何日期。
