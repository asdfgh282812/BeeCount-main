# 退款沖銷:App 統計改成跟 Cloud 同一口徑,回饋金一起沖掉

## 為什麼

以前 App 把退款當成一筆普通的反向交易:退掉 100 元的餐飲,統計會變成「支出 100、收入 100」。結餘沒錯,但收支兩邊都虛胖。Cloud 早就會沖銷退款,所以同一段期間 App 和 Web 的收支數字對不上。

回饋金也有類似問題:
- Cloud 自動入帳的回饋金,退款時會補一筆沖銷交易,但**只有在 Web 上按退款才會觸發**。在 App 按退款、同步上去,回饋收入會一直留著。
- 補出來的沖銷交易是一般支出,統計上沒有扣回回饋收入,而是多算一筆支出。
- 預估回饋(回饋明細頁)本來就會扣掉退款(App 在 `card_reward_rule_providers.dart`,Cloud 在 `card_rewards._qualifying_transactions`),這次沒動。

## 新口徑(App 與 Cloud 相同)

判斷依據只有 `refundOfSyncId`(wire:`refundOfId`)是否為空。

| 退款單類型 | 統計算成 | 範例 |
|---|---|---|
| income(退一筆支出) | 支出 −x | 退貨 |
| expense(退一筆收入) | 收入 −x | 回饋金沖銷、退還多收的款項 |

- **分類**:扣回原交易的分類。原交易拆帳就按明細金額比例分攤。查不到原交易(例如已刪除)才用退款單自己的分類。
- **日期**:算在退款單自己的日期,不回頭改原交易那一期。這跟信用卡帳單的做法一致,也不會讓已經結束的月份數字變動。所以只有退款、沒有原交易的那一期,某分類的淨額可能是負的。
- **原交易本身 `excludeFromStats`**:退款也不計入,不然會憑空多出一筆負數。
- **專案/商家**(App 統計報表、Cloud 比較矩陣的專案維度):退款單自己沒填,就沿用原交易的。帳戶維度一律用退款單自己的帳戶(錢退回哪裡)。
- **排行/筆數**:統計報表的「排行」、TOP3、收入/支出筆數都不算退款單。退款單只扣金額。
- **預算用量不變**,仍按原始消費計算。這是刻意的決定(2026-09-25 跟使用者確認的範圍)。

共用實作:App 在 `lib/utils/refund_netting.dart`,Cloud 在 `src/routers/read/workspace.py::_stat_legs`。

## App 端改動

- `lib/utils/refund_netting.dart`:新增 `statFlowOf(type, refundOfSyncId)`,回傳統計方向與正負號。
- `lib/data/repositories/local/local_statistics_repository.dart`
  - `totalsInRange` / `monthlyTotals` / `yearlyTotals` 共用 `_rangeTotals` 這段 SQL。退款記成反方向負值;原交易是否排除,用子查詢判斷(走 `idx_transactions_sync_id`)。
  - `totalsByCategory` / `totalsByCategoryWithHierarchy` 共用 `_categoryLegs`,在這裡把退款扣回原交易分類。順便把逐筆查分類改成預載分類 map,消掉原本的 N+1。
  - `totalsByDay` / `totalsByMonth` / `totalsByYearSeries` 共用 `_signedRows`。
  - 影響範圍:年度報告、分享海報、桌面小工具、AI 查詢、帳戶頁的總覽圖,以及首頁預載的月收支。
- `lib/data/repositories/local/local_report_loader.dart`、`lib/models/report/report_dataset.dart`
  - 統計報表的退款 leg:`type` 翻成反方向、`amount` 為負,`isRefund = true`。
  - `ReportAggregator` 的筆數和排行略過 `isRefund`。
- `lib/pages/statistics/tabs/category_tab.dart`、`lib/widgets/charts/category_pie_chart.dart`
  - 圓餅的扇形用「正值分類合計」當分母,淨額 ≤ 0 的分類不畫扇形。
  - 中間的總額用新參數 `centerTotal` 顯示淨額。
- `lib/widgets/biz/transaction_list.dart`:交易清單每日小計也沖銷退款。

沒有 schema 變更,也不需要 migration。

## Cloud 端改動(`/Users/andy/BeeCount-Cloud`)

- `src/routers/read/workspace.py`
  - `_stat_legs` 新增 `refund_target` 參數,並新增 `_load_refund_targets` 批次查原交易。
  - `workspace_analytics` 的核心迴圈改用 `_stat_legs`,不再自己維護一份拆帳和退款邏輯。比較報表、比較矩陣也會傳原交易進去。
- `src/routers/read/_shared.py::_projection_totals`(帳本卡片的收支):原交易排除統計時退款也不沖銷。
- `src/services/card_reward_payout.py`
  - `reverse_card_reward_payouts_for_refund` 產生的沖銷交易加上 `refundOfId = 回饋入帳交易`。統計因此把它當成收入的負值、扣回「回饋」分類。App 和 Web 的交易詳情也會把那筆回饋顯示成已退款。
  - 新增 `backfill_reward_reversal_refund_links`:替 2026-09-25 以前的沖銷交易補上 `refundOfId`,並寫一條 upsert SyncChange 讓 App 拉到(App 本地沒有 `rewardSourceTxId` 欄位)。`src/main.py` 啟動時跑一次;這個動作冪等,找不到唯一對應的回饋交易就跳過。
- `src/routers/sync/push.py`:App 推上來「新變成退款」的交易,也會呼叫 `reverse_card_reward_payouts_for_refund`。
  - 判斷方式:推送前 projection 裡這筆交易的 `refund_of_sync_id` 是空的。所以重推或編輯既有的退款不會重複沖銷。
  - 呼叫時機:整批 apply 完才處理。這樣沖銷交易的 change_id 一定大於回傳的 `server_cursor`,推送端下次 pull 就會拉到。
- 測試
  - `tests/test_refund_stats.py`:拆帳退款的期望值改成按比例扣回。
  - `tests/test_card_reward_payout.py`:新增 App 推送退款觸發沖銷、全額退款後收支歸零、舊資料補登 3 個案例。

## 已知限制

- `period_end`(整期結算)的回饋還是無法針對單筆退款精準沖銷。這是既有限制,見 `reverse_card_reward_payouts_for_refund` 的 docstring。
- 首頁/分類詳情頁的分類下鑽(`CategoryDetailPage`)是依分類列交易。退款單掛在自己的分類下,不會出現在原分類的清單裡,所以清單加總可能跟報表的分類淨額差一筆退款。統計報表有篩選時走的 `ReportTransactionsPage` 是依 leg 過濾,會把退款列進來。
- 專案詳情頁、帳戶頁的收支是各自的查詢,這次沒有改。
