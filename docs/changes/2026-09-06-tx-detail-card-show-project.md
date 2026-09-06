# 交易資訊卡顯示所屬專案

## 變更內容

`lib/widgets/biz/transaction_detail_card.dart`:

- `_DetailBundle` 新增 `project` 欄位;`_loadBundle` 依 `Transaction.projectSyncId` 呼叫既有的
  `repo.getProjectBySyncId(...)`(與 `transaction_entry_form.dart` 解析 `_selectedProject` 用的是
  同一支方法)反查 `Project`。
- `_buildDetailRows` 在帳戶/標籤那一列之後,若交易有指定專案,新增一整列顯示專案圖示
  (`CategoryService.getCategoryIcon(project.icon)`)+ 專案名稱;沒有指定專案時整列不佔空間
  (比照 `_buildRewardSection` 的「查無資料就不顯示」寫法)。

## 為什麼

記帳時可以在輸入表單(`transaction_entry_form.dart` 的 `_buildProjectRow`)幫交易掛上專案,
但點開交易資訊卡回顧時看不到這筆交易屬於哪個專案,使用者需要重新打開編輯頁才能確認。

## 取捨

- 專案列沒有額外文字標籤(跟帳戶/標籤/商家/日期等既有欄位一致,只靠圖示 + 內容辨識),
  沒有新增 l10n key。
- 沒有拿專案去跟其他欄位配對成同一列(例如標籤),而是獨立一整列——避免更動既有
  帳戶/標籤、商家/週期、日期/時間三組配對的版面,降低回歸風險。
