# 刷卡建議空清單時顯示「可能為排除項」提示

## 背景

SwipeSmart 的 `ExclusionCategories` 機制會讓命中「一般消費回饋排除項目」
（例如保費、稅費）的消費，在沒有卡片針對該類別另外設定專屬回饋規則時，
`/api/recommend` 回傳空陣列。SwipeSmart 本身有 `GetExclusionReason` /
`/api/recommend/exclusion-reason` 可以查到後台填寫的詳細原因文字，但目前
只有 SwipeSmart 自己的網頁後台（`wwwroot/index.html`）在用，BeeCount App
沒有接這支 API。

之前 App 端刷卡建議清單為空時完全沒有任何提示，使用者容易誤以為是 bug
（詳見同一次對話：一開始誤判是 App 端快取或後端問題，實際上是這支功能本來
就沒有空清單的說明文案）。

## 入口

不是獨立入口,依附在既有的「新增/編輯交易」表單(`TransactionEntryForm`)刷卡推薦區塊上——選擇信用卡類帳戶並輸入金額/商家後,原本就會顯示 SwipeSmart 的推薦結果;這次只在推薦結果為空時,同一位置多顯示一行提示文字,不新增頁面或選單項目。

## 改動

`lib/widgets/biz/transaction_entry_form.dart`：

- 新增 `_lastRecommendationRawEmpty`，記錄 SwipeSmart 對目前這組（金額,
  商家）算出來的**原始**結果是否為空——跟既有的 `mapped`（過濾掉沒對應本地
  帳戶的建議，見 `_fetchRecommendation` 內原本的註解）分開追蹤，避免「其實
  有推薦、只是沒對到本地帳戶」被誤判成排除項。
- 新增 `_shouldShowRecommendationExcludedHint()`：只有在原始結果為空、且
  目前輸入的金額/商家仍跟上次查詢結果相符時才顯示提示（跟去重複查詢的
  `_lastRecommendationQuery` 用同一套「輸入是否已變動」判斷）。
- UI 新增一行小字提示（`transactionCardRecommendationExcludedHint`
  l10n key）：「此項可能為排除項，建議進網頁端查詢」。

## 刻意不做的事

- **沒有接 `/api/recommend/exclusion-reason`**：這支 API 回傳的 `Reason`
  文字是後台自由填寫的說明，長度不一，使用者本人已表示接進 App 顯示太長。
  改用固定的精簡提示文字，要看詳細原因請自行到 SwipeSmart 網頁後台查。
- **沒有處理「有推薦但沒對應本地帳戶」的情況**：這種情況維持原本的「不顯示
  任何東西」，不會被這次新增的提示文案覆蓋，因為那不是排除項造成的空清單。

## L10n

只新增 `app_en.arb` + `app_zh_TW.arb`（依 2026-08-17 起的政策，不再維護
`app_zh.arb` / `app_ko.arb`）。
