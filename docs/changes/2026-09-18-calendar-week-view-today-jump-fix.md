# 修正日历週检视下「今天」跳到月初的问题

## 问题

日历（`lib/pages/calendar/calendar_body.dart`）收起为週检视后，点击右上角「今天」按钮，视图会跳到当月 1 号所在的那一週，而不是今天所在的那一週。

## 原因

`jumpToToday()` 一律把 `_focusedMonth` 设成 `DateTime(now.year, now.month, 1)`（月初）。

`_focusedMonth` 在月检视下确实恒为月初，但在週检视下它被 TableCalendar 当作「要显示哪一週」的定位锚点——参见 `onFormatChanged` 切换到週检视时的逻辑（约 line 303），那里特地带上 `_selectedDay` 的完整日期而非月初，就是为了避免这个问题。`jumpToToday()` 没有遵守同一契约，恒传月初，于是在週检视下退化成「跳到月初所在週」。

## 修复

`jumpToToday()`（[calendar_body.dart:97](../../lib/pages/calendar/calendar_body.dart)）改为按当前 `_calendarFormat` 分支：
- 週检视：`_focusedMonth = DateTime(now.year, now.month, now.day)`，与 `onFormatChanged` 一致。
- 月检视：保持原本的 `DateTime(now.year, now.month, 1)`。

`jumpToMonth()`（年月选择器入口）未改动——它本身只用于选年月，不涉及「日」，语义上恒为月初是对的，且该入口不会在週检视下触发这个問題路径。
