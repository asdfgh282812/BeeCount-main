# 新增交易「選擇帳戶」排序與主頁面不一致

## 問題

主頁面帳戶列表（`accounts_page.dart`）依 `type` → `sortOrder`（使用者可拖曳調整）排序；「新增交易」彈出的「選擇帳戶」（`account_card_picker.dart`）底層資料其實也來自同一個 `getAllAccounts()`（一樣是 `type` → `sortOrder`），但 `_AccountTypeSectionState._sorted()` 會用「已選帳戶置頂 + 最近使用（LRU）」重新排序整個分組，且對「兩者都沒被 LRU 記錄到」的帳戶，比較器回傳 `0`。Dart 的 `List.sort` 並不保證穩定排序，回傳 `0` 讓這些未使用過的帳戶相對順序變成不可預期，跟主頁面的手動排序看起來對不上。

## 修正

`lib/widgets/biz/account_card_picker.dart` 的 `_sorted()`：新增 `originalIndex`（來自 `widget.accounts` 原始順序，也就是 `getAllAccounts()` 給的 `sortOrder` 順序），當兩個帳戶都沒被 LRU 記錄到時，改用這個原始順序比較，而不是回傳 `0`。

## 取捨（刻意保留的行為）

「已選帳戶置頂」與「最近使用置頂」這兩個機制本身是刻意的功能（方便使用者重開選擇器時不用滑到底找常用帳戶），這次沒有移除；只修正「沒被最近使用記錄到」的帳戶要維持跟主頁面一致的 `sortOrder`。也沒有改動選擇器的分組方式（目前是純 `type` 平面分組，不像主頁面依 `parentAccountId` 做父子分組），使用者確認過這個範圍已足夠。
