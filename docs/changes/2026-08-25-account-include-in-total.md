# 帳戶「不納入總餘額」（account.includeInTotal）

## 背景

BeeCount Cloud 已經先實作了帳戶層級的「納入總餘額」開關
（`user_account_projection.include_in_total`，仿 Moze
[balance included](https://doc.moze.app/prepare/account/settings#balance-included)
語意），Web 面板可以直接切換。App 端一直沒有對應欄位，導致：

1. App 使用者沒有入口設定這個屬性。
2. 更重要的是——Web 端切換的值，因為 App 端本地 Drift schema 根本沒有這個欄位，
   拉取下來的 `includeInTotal` 鍵會被整個忽略，兩端狀態會不一致。

這次補上 App 端對應欄位，並打通雙向同步（App ↔ Cloud）。

## 極性決策：`includeInTotal`（正極性）而非 `excludedFromTotal`

App 內部已有一個外觀類似的先例——`Debts.excludedFromTotal`（負極性，預設
`false`）。但這次故意**沒有**沿用那個命名，而是直接對齊 Cloud 的正極性
`include_in_total`／wire key `includeInTotal`（預設 `true`）。

理由：這個欄位需要無條件在 push/pull 兩個方向上跟 server 逐位元組對齊
（server 端一律無條件送出這個鍵，跟 `hidden` 同一套「缺鍵保留」規則）。如果本地
欄位取名 `excludedFromTotal`，push/pull 兩處都要在極性上做一次反轉
（`excludedFromTotal: !payload['includeInTotal']`），這種隱性反轉最容易在未來
改動時漏改一邊、埋下同步方向不一致的 bug。直接讓本地欄位、wire key、預設值三者
語意完全相同，犧牲一點跟 `Debts.excludedFromTotal` 的內部命名一致性，換取同步
邊界的正確性。

## 改動範圍

- `lib/data/db.dart`：新增 `Accounts.includeInTotal`
  (`boolean().withDefault(const Constant(true))()`)；`schemaVersion` 43 →
  migration 用 `_addColumnIfMissing` 補欄位，預設 `1`（既有帳戶全部視為「納入」，
  升級後行為不變）。
- `lib/data/repositories/account_repository.dart` +
  `local/local_account_repository.dart` + `local/local_repository.dart`：
  `createAccount`/`updateAccount` 新增 `includeInTotal` 參數，`update` 走
  null-表示不改動的既有慣例（同 `hidden`）。
- `lib/cloud/sync/entity_serializer.dart`：`serializeAccount` 無條件帶
  `'includeInTotal': account.includeInTotal`（同 `hidden` 的模式，不用
  if-null 省略）。
- `lib/cloud/sync/sync_engine_apply.dart`：`_applyAccountChange` 用
  containsKey 缺鍵保留語義解析 `includeInTotal`；跟 `hidden` 的差異只在
  insert 缺鍵時的預設值——這裡預設 `true`（納入），`hidden` 預設 `false`。
- `lib/data/repositories/local/local_account_repository.dart`：6 個既有「總額」
  方法（`getNetWorthBreakdown`、`getNetWorthBreakdownByCurrency`、
  `getNetWorthDailyBalances`、`getNetWorthTrendSeries`、
  `getAssetCompositionByType`、`getAssetCompositionByTypeAndCurrency`）在取得
  帳戶清單後過濾掉 `includeInTotal == false` 的帳戶，仿
  `local_debt_repository.dart` `getNetDebtBalance` 的 `excludedFromTotal`
  先例。`getAllAccounts()`、清單/選擇器/帳戶詳情頁完全不受影響——帳戶本身
  一樣正常顯示、可以記帳，只有「總額」類統計會跳過它。
- `lib/pages/account/accounts_page.dart`：`_aggregateParentStats`（合併帳單
  主卡的子卡加總）也套用同一個過濾——子卡 `includeInTotal == false` 時，
  它的餘額不捲進主卡卡片顯示的合併總額，但收支統計（`expense`/`income`）
  不受影響，維持獨立口徑（跟 server 端 workspace.py 的處理方式對齊）。
- `lib/pages/account/account_edit_page.dart`：新增一個 `SectionCard` + `Switch`
  區塊（樣式抄自 `debt_editor_page.dart` 的「排除計入總額」區塊），放在
  主帳戶分組欄位之後、備註欄位之前，所有帳戶類型都會顯示；新建帳戶預設開
  （納入）。
- `lib/l10n/app_en.arb` + `app_zh_TW.arb`：新增 `accountIncludeInTotalLabel` /
  `accountIncludeInTotalHint`。依既有政策不補 `app_zh.arb`/`app_ko.arb`。
- `docs/CLOUD_SYNC_INTEGRATION.md`：新增 §1.3 記錄這個欄位的 wire 契約與
  影響範圍，供未來改動時查表。

## 刻意排除的範圍

- 帳戶備份/還原 JSON（`config_export_service.dart`）目前本來就沒有回帶
  `hidden`/`parentAccountId`/`avatarPath` 這類欄位，這次 `includeInTotal`
  沿用相同的既有限制，沒有額外補上——不是這次改動要處理的既有缺口。
- `local_account_repository.dart` 裡標注為死代碼的 `getAllAccountsTotalStats`
  沒有加過濾（沒有任何 UI 在用它）。
