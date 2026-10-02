# 2026-09-29 backfillUntrackedEntities 加防護 + 帳戶金額「-0」

## 1. `backfillUntrackedEntities` 不再用本機舊資料覆蓋 server

檔案:`lib/cloud/sync/sync_engine_status.dart`

### 事故

一台本機資料不完整的裝置(模擬器殘留舊資料,pull 卡在 cursor 2081)在「雲同步」頁
下拉刷新。`CloudSyncPage._onRefresh` 看到本機帳戶/分類數 > server(`needsBackfill`),
呼叫 `backfillUntrackedEntities`。舊版對**每一個**沒有待推送 change 的帳戶、分類、
標籤補寫 `create`。push 時 `serializeAccount` / `serializeCategory` 會把本機整行
序列化上去,server `_merge_from_spec` 是「有鍵就覆蓋」,結果:

- 56 個帳戶被覆蓋:名稱清空、sortOrder 歸 0、信用額度等被舊值蓋回;
  `avatarCloudFileId=''` 把頭像清掉,server 隨即 GC 了頭像檔。
- 87 個 server 從沒有過的分類被建立出來。

server 資料已從 05:00 備份修回(裝置 `repair-20260929` 的 sync_changes)。

### 修法:三道防護,任何一道不過就整個不做

1. **有未解決的 pull 錯誤**(`sync_pull_errors.resolved_at IS NULL`)→ 本機資料不可信。
2. **pull 沒追上 server**:從 `appCursor` 往後 `pullChanges(limit: 1)` 還拉得到
   change → 本機還缺資料。事故當時就是這個情況。
3. **只補 server 上不存在的實體**:先用 `readAccounts` / `readCategories` /
   `readTags` 取 server 清單。
   - syncId 已在 server 的一律跳過。它不是「沒被追蹤」,重推只會用本機值覆蓋。
   - 同名的也跳過(分類比對 kind + 名稱 + 父分類名),避免推出重名分類。
     重名分類會讓 pull 卡死,見 62e559d。
   - 讀 server 清單失敗就不做。

篩選邏輯抽成 top-level `selectBackfillCandidates`,單測在
`test/cloud/sync/backfill_candidates_test.dart`。

這個函式原本的用途仍然保留:為種子程式碼繞過 changeTracker 直接 insert 的
實體補登 create。這些實體 server 上本來就沒有,三道防護都會放行。

### 刻意不在這次處理

- `sync_engine_serialization.dart` 的 account 分支:`avatarPath` 為空時固定送
  `avatarCloudFileId=''`,server 會清掉頭像並 GC 頭像檔。
  - 裝置沒下載到頭像(下載失敗、還沒 pull 完)時,只要一般編輯帳戶,也會把 server
    頭像清掉。
  - 要修得先區分「使用者主動清空」和「本機還沒拿到」,牽涉帳戶編輯頁,另開處理。
- `repairMissingCategoryColorsOnce` 的 pull 錯誤檢查也算進了已解決的錯誤,偏保守,沒動。

## 2. 帳戶金額顯示「-0」

- **現象**:資產頁有些餘額為 0 的信用卡子帳戶顯示紅色「-0」。
- **原因**:餘額是逐筆 double 加減出來的,會留下像 `-1.1e-13` 的浮點殘差。
  - `formatMoneyCompact` 依原值 `v < 0` 決定負號,但數字部分四捨五入後已經是 0,
    於是顯示成「-0」。
  - 顏色判斷(`displayValue < 0` → 紅色)也因此誤判。

修法:

- **`lib/data/repositories/local/local_account_repository.dart`**:
  `getAccountBalance` / `getAccountGlobalBalance` / `getAccountBalanceInLedger`
  回傳前經過 `_dropFloatNoise`,`|v| < 1e-6` 視為 0。
  - 門檻遠小於任何幣別的最小單位,真實小額餘額不受影響。
  - 從源頭修正,顏色判斷也跟著正確。
- **`lib/widgets/biz/format_money.dart`**:負號改依四捨五入到 `maxDecimals` 後的值
  判斷。這是保險:其它來源(折算、彙總)的 -0.004 之類的值,也不會顯示成「-0」。
- **`lib/utils/format_utils.dart`**:`formatBalance` / `formatBalanceFull` 同上,
  不再出現「-NT$0.00」。

單測:`test/widgets/format_money_negative_zero_test.dart`。
