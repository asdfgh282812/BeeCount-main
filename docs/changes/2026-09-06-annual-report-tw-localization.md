# 年度報表：移除人民幣符號、補齊繁體中文（台灣）在地化

## 背景

年度報表由兩個獨立維護的檔案組成：
- [`lib/pages/report/annual_report_page.dart`](../../lib/pages/report/annual_report_page.dart) — App 內的 7 頁輪播卡片
- [`lib/widgets/posters/annual_report_poster.dart`](../../lib/widgets/posters/annual_report_poster.dart) — 按下「生成分享海報」後渲染成長圖的版本

其中「年度洞察」「收支對比」兩頁，以及海報裡對應的區塊，是後續加上去的，當初完全沒有走 `AppLocalizations`／`app_zh_TW.arb`，而是直接把簡體中文文案寫死在 widget 裡；同時所有金額都用 `NumberFormat(..., 'zh_CN')` 格式化並手動加上 `¥` 字首。這台 App 是給台灣使用者用的記帳工具，顯示人民幣符號、簡體字都不恰當。

## 改動內容

1. **移除 `¥` 符號，數字保留**：兩個檔案裡所有金額顯示（總覽卡片、洞察平均值、收支對比長條、分類排行、月度最高/最低、特別時刻）都拿掉字首的 `¥`，只保留格式化後的數字本身。海報裡淨結餘旁本來就有的「元」單位字沒有變動（它不是貨幣符號，維持原樣）。
2. **`NumberFormat` locale 從 `'zh_CN'` 改成 `'zh_TW'`**：僅改這兩個檔案內的 12 處呼叫；`month_summary_poster.dart`／`year_summary_poster.dart`／`ledger_summary_poster.dart` 等其他海報維持原狀，不在本次範圍內。
3. **新增 24 個 l10n key**（`app_en.arb` 模板 + `app_zh_TW.arb`），把「年度洞察」「收支對比」兩頁原本寫死的簡體中文標題／副標題／描述文字，以及海報裡重複硬編碼、且部分跟頁面版本不同步的文案，全部改走 `AppLocalizations`。新 key 清單見兩份 arb 檔中 `annualReport*` 前綴那組。
4. **重用既有但先前沒被用到的 key**：海報 `_buildStatsSummary` 的「日均支出」「月均支出」標籤原本硬編碼，改用 arb 裡本來就有、但從未被引用的 `sharePosterAvgDailyExpense`／`sharePosterAvgMonthlyExpense`；圖例「收入」「支出」重用既有的 `searchSummaryIncome`／`searchSummaryExpense`，避免重複定義同義字串。
5. **單位字直接修正**：`笔`→`筆`、`个`→`個`（比照檔案裡原本就用字面量寫死的「天」「月」等單位字模式，未特別為此建立 l10n key）。

## 刻意不做的事

- **未動 `docs/CLOUD_SYNC_INTEGRATION.md` 或任何同步邏輯**：年度報表是純前端展示功能，資料來源不變。
- **未新增 NT$ 或其他貨幣前綴**：使用者明確要求「只拿掉 ¥ 符號，數字保留」，沒有要求加上台幣符號，所以維持純數字顯示。
- **`app_zh.arb`／`app_ko.arb` 未同步更新**：依專案既有政策，這兩個語系檔案已不再維護。
- **海報 `hideIncome` 隱藏收入機制未擴大範圍**：原本只隱藏收入相關兩處金額，其餘金額仍會顯示；這次沒有動這個既有邏輯，只是把顯示格式（符號、locale、文案語言）修正好。
