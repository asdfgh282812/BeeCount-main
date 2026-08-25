# App ↔ BeeCount Cloud 同步契約總覽

給 AI 助理看的跨 repo 地圖。目的：使用者提出「改 App 端某功能」時，不用重新爬一遍
`lib/cloud/sync/` 六千行程式碼，也不用去猜雲端到底支不支援這個功能 —— 這份文件已經
把「現況邊界在哪」「改一個欄位要動哪幾個檔案」「加一個全新功能要動哪幾個檔案」都
釘死成可查表。

**兩個 repo 的相對位置**（本機路徑，两边各自独立 git repo，不是 monorepo）：
- App（Flutter，本文件所在）：`/Users/andy/BeeCount-main/BeeCount-main/`
- Cloud（FastAPI + React web，同步伺服器 + web 面板）：`/Users/andy/BeeCount-Cloud/`

Cloud 端的同步架構總覽在 `../BeeCount-Cloud/docs/SYNC_ARCHITECTURE.md`；Cloud 端的
逐項規範在 `../BeeCount-Cloud/CLAUDE.md`（尤其「新增或修改 Sync Entity 檢查清單」7
點 SOP）。這份文件是那份文件的 App 端鏡像 + 兩邊落差盤點，**兩份要一起看**。

---

## 1. 現況邊界：雲端支援的 14 種 entity，App 只做到 8 種

Cloud 端目前認得的 `entity_type`（`BeeCount-Cloud/src/sync_applier.py:70-74`，
`INDIVIDUAL_ENTITY_TYPES`）：

```
transaction, account, category, tag, budget, ledger,
exchange_rate_override, recurring_rule, installment_plan,
installment_period, debt, tx_template, card_reward_rule, project
```

App 端 `SyncEngine` 實際會 push/pull 的 `entityType`（`lib/cloud/sync/
sync_engine_apply.dart` 的 `switch (change.entityType)` case 列表 + `lib/cloud/sync/
sync_engine_serialization.dart` 的 push case 列表，兩處要一致）：

```
transaction, account, category, tag, budget,
exchange_rate_override, ledger, ledger_snapshot（全量快照，非增量 case）
```

**差集（Cloud 有、App 完全沒有 —— 連本地 Drift 表都不存在）**：

| entity_type | Cloud 對應功能 | App 現況 |
|---|---|---|
| `recurring_rule` | 週期性收支（Web「週期交易」頁） | **無**。App 有一個外觀很像的本地功能，見下方 §1.1 陷阱 |
| `installment_plan` / `installment_period` | 分期付款 | 完全沒有，`account_detail_page.dart` 裡的 "installment" 字樣只是信用卡帳單摘要文案，不是同一個東西 |
| `debt` | 借還款（Web「借還款」頁） | 完全沒有，`account_detail_page.dart` 裡的 "debt" 字樣只是負債類帳戶的估值文案（`valuationCurrentDebt` 等 l10n key），不是同一個東西 |
| `tx_template` | 交易範本（可套用的預設交易） | 完全沒有 |
| `card_reward_rule` | 信用卡回饋規則 | 完全沒有 |
| `project` | 專案（Phase 13，可掛在交易/週期規則上） | 完全沒有 |

**結論**：如果使用者要求「把 Web 上的週期交易/分期/借還款/範本/信用卡回饋/專案
搬到 App 上」，這不是「改一個既有同步欄位」，是「App 端從零生出一個全新 sync
entity」——工程量遠大於一般欄位改動，要照 §3 的清單走，並且要先跟使用者確認範圍
（是否要離線也能用、要不要跟現有本地功能合併，見下方 1.1）。

### 1.1 已知混淆陷阱：`RecurringTransactions` ≠ Cloud 的 `recurring_rule`

App 端 `lib/data/db.dart:165` 有一張 `RecurringTransactions` Drift 表，配
`lib/data/repositories/local/local_recurring_transaction_repository.dart`，是**純
本地功能**——`grep -rn "recordLedgerChange\|recordUserGlobalChange"` 對這個檔案是
零命中，完全沒有接上 `ChangeTracker`，不會同步到雲端，別的裝置看不到，Web 也看不到。

這跟 Cloud 的 `recurring_rule`（`BeeCount-Cloud/src/routers/write/
recurring_rules.py`，欄位包含 `merchant` / `projectId` / `tagIds` /
`advancedRuleJson` 等已經比 App 這張本地表豐富很多）是**兩個獨立概念，欄位對不
上**。如果要把週期交易接上雲端同步，不要直接把現有 `RecurringTransactions` 表接
`ChangeTracker` 就當作完工——要先比對 Cloud `recurring_rule` 的完整欄位集
（`BeeCount-Cloud/src/sync_applier.py:231-254` 的 `_LEDGER_MERGE_SPECS["recurring_rule"]`），
決定是擴充這張本地表還是重新設計。

### 1.2 已知混淆陷阱：App 沒有 `account_group` 帳戶類型（⚠️ 已過時，見下方 2026-08-15 補注）

> **2026-08-15 補注**：本節已經過時。v32（`accounts.parentAccountId` +
> `accounts.avatarPath`，「帳戶主卡分組」功能）之後，App 端 `Accounts.type`
> **已經支援** `account_group`（純管理容器帳戶，見 `lib/data/db.dart` 的
> `parentAccountId` 欄位、`lib/pages/account/accounts_page.dart` 的
> `_resolveDisplayType`、`lib/utils/account_type_utils.dart` 對
> `'account_group'` 的 icon/color/label 特判、`entity_serializer.dart` 序列化
> 的 `parentAccountId` 欄位)。下面「App 端合法值只有 cash, bank_card, ...
> 沒有 account_group」這句已不成立。這裡先標記出來,詳細比對 App/Cloud 兩邊
> account_group 語意是否完全一致(欄位、寫入路徑守衛等)留給下次真的要動
> 這塊的人重新確認、更新本節,不在這次順手改動的範圍內。

Cloud/Web 有 `account_type == "account_group"`（純管理容器帳戶，Phase 10/11，
`BeeCount-Cloud/CLAUDE.md` 的「帳戶群組限制」鐵律）。App 端 `Accounts.type` 欄位
（`lib/data/db.dart:44`）合法值只有 `lib/utils/account_type_utils.dart:45` 定義的
`cash, bank_card, credit_card, alipay, wechat, other, loan`，**沒有 `account_group`**。

意味著：使用者在 Web 建了一個帳戶群組，App pull 下來會被當成普通帳戶顯示（因為
App 端沒有特判邏輯把它隱藏/擋寫入）；如果 App 端某個寫入路徑（交易/週期規則/分
期）讓使用者選到這個帳戶當目標帳戶，push 到雲端時會被 Cloud 的
`_assert_account_not_group` 擋掉。動到「App 端選帳戶」相關 UI 時，如果雲端已經
有帳戶群組功能，這是一個要考慮的邊界情況（目前 App 端完全沒處理）。

### 1.3 `account.includeInTotal`（不納入總餘額，v43 新增，2026-08-25）

對齊 Cloud 的 `user_account_projection.include_in_total`（正極性 bool，預設
`true`=納入，仿 Moze「balance included」設定）。Wire key 是 mobile sync 專用的
camelCase `includeInTotal`（Cloud web REST API 走另一條 snake_case
`include_in_total`，跟本欄位無關）。Server 端一律無條件送出這個鍵（同 `hidden`
的模式），所以拉取一定會把伺服器現值帶進 App。

- 本地 Drift 欄位：`Accounts.includeInTotal`（`lib/data/db.dart`，v43 migration）
- Push：`entity_serializer.dart` `serializeAccount` 無條件帶 `includeInTotal`
- Pull：`sync_engine_apply.dart` `_applyAccountChange` 用 containsKey 缺鍵保留
  語義，insert 缺鍵預設 `true`（跟 server 預設一致，不是跟 `hidden` 的
  `false` 一樣）
- 影響範圍：只影響 `local_account_repository.dart` 6 個「總額」方法
  （`getNetWorthBreakdown*`、`getAssetCompositionByType*`）以及
  `accounts_page.dart` `_aggregateParentStats` 的主卡合併總額 —— 帳戶本身仍
  正常出現在清單/選擇器，可正常記帳，收支統計不受影響（跟 `hidden` 是獨立
  維度，兩者可以任意組合）

---

## 2. Scope 契約：user-global vs ledger-scoped（兩邊命名必須一致）

決定 `local_changes.ledgerId` 該填 `0` 還是真實帳本 id，兩邊各自維護一份白名單，
**新增/修改 entity 時兩邊都要記得改，這是最容易漏改的地方之一**：

| entity_type | Scope | App 側白名單 | Cloud 側白名單 |
|---|---|---|---|
| account, category, tag, exchange_rate_override | user-global | `lib/cloud/sync/change_tracker.dart:36` `_userGlobalEntityTypes` | `src/sync_applier.py:81` `USER_GLOBAL_ENTITY_TYPES` |
| card_reward_rule | user-global | **App 沒有這個 entity（§1 差集）** | 同上（Cloud 端已把它列進去） |
| transaction, budget, ledger, ledger_snapshot | ledger-scoped | 同上檔案，反向邏輯（assert 不在白名單內） | 其餘全部 entity（`_LEDGER_MERGE_SPECS`） |
| recurring_rule, installment_plan, debt, tx_template, project | ledger-scoped | **App 沒有這個 entity** | 同上 |

App 端呼叫入口是 `ChangeTracker.recordUserGlobalChange` / `recordLedgerChange`
（`lib/cloud/sync/change_tracker.dart:46/71`），**禁止直接呼叫私有的 `_insert`**。
Scope 選錯的後果（已經在 mobile 踩過一次）：change 被記到錯的 `ledgerId`，
`_push()` 的兩個查詢（`getUnpushedChanges` / `getUnpushedChangesForLedger`）都撈
不到它，變更永遠卡在本地推不出去，且沒有任何錯誤訊息。

**實際呼叫點在哪**：不是照 CLAUDE.md 描述的「per-domain `Local*Repository`
mixin」分散呼叫——實測 `local_transaction_repository.dart` 對
`changeTracker` 呼叫是零命中。真正的呼叫點幾乎全部集中在
`lib/data/repositories/local/local_repository.dart`（一個 2300+ 行的檔案，`grep -n
"changeTracker!\.record" lib/data/repositories/local/local_repository.dart` 可以列出
全部呼叫點）。改動任何寫入路徑前，先用這個 grep 定位對應的 `record*Change` 呼叫，
不要假設它在看起來對應的 `local_<entity>_repository.dart` 裡。

---

## 3. Wire Payload 契約：camelCase key + 三態語義

Cloud 端**沒有** pydantic `alias_generator`（`BeeCount-Cloud/src/schemas.py` 沒有
camelCase 轉換），`/sync/push` 的 payload 是原始 dict，Cloud 端直接用
`_MergeSpec.fields` 裡寫死的字串 key（如 `"syncId"` / `"categoryId"` /
`"startDay"`）去 `payload.get(...)`——**App 序列化端的 key 字面字串本身就是契約**，
打錯字或改了 key 名字，雙方都不會報錯，只會靜默 merge 失敗（欄位永遠拿不到值）。

App 端序列化統一在 `lib/cloud/sync/entity_serializer.dart`（`EntitySerializer` 靜態
方法，每個 entity 一個 `serializeXxx`），對照的 Cloud 端 spec 在
`BeeCount-Cloud/src/sync_applier.py` 的 `_USER_MERGE_SPECS`（132行起）/
`_LEDGER_MERGE_SPECS`（221行起）——**改一邊的欄位名之前，先打開另一邊確認 key 對
不對得上**。

三態語義（`entity_serializer.dart` 裡每個欄位都要想清楚落在哪一態）：

1. **完全省略這個 key**（Dart 用 `if (x != null) 'key': x`）→ Cloud 端 merge 視為
   「不更新」，沿用現有值。
2. **傳 `null`** → 同上，Cloud 端 `_merge_from_spec` 只 filter `None`，等效於省略。
3. **傳空字串 `''`**（或空 list `[]`）→ 這是**唯一**能主動清空某欄位的方式（例如
   拿掉交易的帳戶、清空使用者頭像）。`entity_serializer.dart:56-62` 的註解把這條
   規則寫得很清楚：`accountId`/`accountName` 永遠無條件送出（`?? ''`），不能因為
   「這次沒改帳戶」就省略，否則使用者主動清空帳戶這個操作永遠傳不到雲端。

新增欄位時先問自己：這個欄位「使用者可以清空它」嗎？可以的話用第 3 態（無條件送
出 + 空字串/空 list 代表清空）；不行的話用第 1/2 態（`if (x != null)` 有條件送
出）。选错会导致"清空这个动作传不到云端"或"没改这个字段却被误清空"两种静默 bug
之一。

Attachments 這種 list 欄位還有一個更細的坑（`entity_serializer.dart:71-74`）：**列表
清空成 `[]` 時也要無條件帶出這個 key**，不能因為 `attachments.isNotEmpty` 之類的
判斷把空 list spread 掉，否則對端沒法區分「這次沒帶附件資訊」跟「全部刪光了」。

---

## 4. 改動「App 已支援」的既有 sync entity 欄位 —— 兩邊合併 SOP

以下把 Cloud 端 CLAUDE.md 的 7 點 SOP 跟 App 端要動的位置合併成一張表。App 端範圍
限於 §1 App 已支援的 8 種 entity（transaction/account/category/tag/budget/
exchange_rate_override/ledger）。

| # | App 端要改的位置 | Cloud 端要改的位置 |
|---|---|---|
| 1 | `lib/data/db.dart` 新增 Drift column + `MigrationStrategy.onUpgrade` 加一個新 `schemaVersion` 分支（目前 32，SQLite DDL 不可回滾，改 migration 前務必讀清楚周圍版本號註解） | Alembic migration，`read_*_projection` 表加欄位 |
| 2 | `dart run build_runner build --delete-conflicting-outputs` 重新產生 `db.g.dart`（絕不手改這個檔案） | — |
| 3 | 對應 `lib/data/repositories/xxx_repository.dart`（介面）+ `local/local_xxx_repository.dart` 或 `local_repository.dart`（實作，見 §2 的「實際呼叫點在哪」提醒） | `src/projection.py` 的 `upsert_*`/`delete_*`/`rename_cascade_*` |
| 4 | `lib/cloud/sync/entity_serializer.dart` 對應 `serializeXxx` 加欄位（push 方向） | `src/sync_applier.py`：`_USER_MERGE_SPECS`/`_LEDGER_MERGE_SPECS` 加 field spec |
| 5 | `lib/cloud/sync/sync_engine_serialization.dart` 對應 `case 'xxx':` 塊，如果新欄位需要額外查表（像 budget 的 `categorySyncId` 要另外查 category 表）要在這裡組出來喂給 serializer | `src/sync_applier.py`：`_USER_UPSERT_DISPATCH`/`_LEDGER_UPSERT_DISPATCH` 通常不用改（除非新 entity），但要確認 spec 裡的 transform（`_json_loads_safe`/`_isoformat_or_none`）用對 |
| 6 | `lib/cloud/sync/sync_engine_apply.dart` 對應 `_applyXxxChange` 方法（pull 方向，遠端 payload → 本地 Drift row） | `src/routers/write/<entity>.py`（若 web 也要能編輯這欄位）+ `src/schemas.py` 對應 `Write*Request`（插入新 class 時 `old_string` 務必含到前一個 class 最後一行，Phase 13 踩過把 `closed_at` 切飛的坑，見 Cloud CLAUDE.md） |
| 7 | UI 層：對應 `lib/pages/<feature>/` 表單/顯示 + 若有計算邏輯要跟 Cloud 對應 service 保持算法一致（例如金額/匯率聯動，Cloud 端在 `sync_applier.py::_sync_native_amount_after_merge` 有一份，App 端要照著做，不要自己重新推導公式） | `src/routers/read/ledgers.py` 或 `workspace.py` SELECT 補欄位；**`src/snapshot_builder.py` 的 SELECT 極易漏**（決定 App `/sync/full` 首次同步/重裝能不能拿到這欄位） |
| 8 | `test/sync/` 新增一條 apply 測試（比照現有 `test/sync/account_partial_update_apply_test.dart` 風格：payload 只帶部分欄位，驗證其它欄位不被清空） | `tests/` 新增 `test_mobile_push_<entity>_partial_update_keeps_existing_fields` |

**額外檢查**：這個欄位如果會被「改名連動」（denormalized 欄位，如 transaction 上
的 `accountName`），要確認 Cloud 端 rename cascade（`sync_applier.py::
_detect_and_run_rename_cascade`）跟 App 端 pull apply 都會正確刷新，不要假設
App 端不需要處理——App 只要正確處理 pull 下來的完整新值就好，不用自己做 cascade
邏輯（cascade 是 Cloud 單邊的事，App 只是消費結果）。

---

## 5. 新增「App 完全沒有」的全新 entity type（§1 差集清單那 6 種）—— 完整清單

這比 §4 大得多，是「從零實作一個新同步實體」等級的工程。除了 §4 的全部 8 項，
額外要做：

### App 端
1. `lib/data/db.dart` 新增整張 Drift `Table` class + `schemaVersion` bump + migration；記得加進 `@DriftDatabase(tables: [...])` 的 tables 列表（`lib/data/db.dart:427` 附近，仿照 `RecurringTransactions,` 那一行）
2. 新增 `lib/data/repositories/<entity>_repository.dart`（介面）+ `local/local_<entity>_repository.dart`（實作），並在 `BaseRepository`/`LocalRepository` 組裝進去（`lib/data/repositories/repositories.dart`、`local_repository.dart`）
3. `lib/cloud/sync/change_tracker.dart`：如果新 entity 是 user-global，把它加進 `_userGlobalEntityTypes`（第36行）白名單；ledger-scoped 則不用改這個檔案（白名單只列 user-global）
4. `lib/cloud/sync/entity_serializer.dart`：新增 `serializeXxx` 靜態方法，欄位 key 逐一對照 Cloud 端 `_MergeSpec.fields` 的 `payload_key`（見 §3），一個字都不能錯
5. `lib/cloud/sync/sync_engine_serialization.dart`：push 路徑加一個新 `case 'xxx':` 分支；如果這個 entity 需要 `fullPush`（首次同步把全部本地資料推上去）也要確認這裡有覆蓋到
6. `lib/cloud/sync/sync_engine_apply.dart`：pull 路徑加一個新 `case 'xxx':` 分支 + 對應 `_applyXxxChange` 方法，處理 create/update/delete 三種 action，並注意跨裝置 ID 解析（`sync_engine_resolvers.dart` 的 `_resolveXxxIdBySyncId` 模式，syncId ↔ 本地 int id 對應）
7. `lib/providers/` 新增對應 Riverpod provider（供 UI 讀寫）
8. `lib/pages/<feature>/` 新增畫面（App 目前完全沒有這個功能的任何 UI，是全新頁面，不是改既有頁面）
9. `test/sync/` + `test/repositories/` + `test/data/` 新增測試
10. **首次全量同步**：確認 Cloud 端 `snapshot_builder.py` 有沒有把這個 entity 放進 `/sync/full` 的回應，App 端 `fullPull` 路徑（`sync_engine.dart` 裡處理 `/sync/full` 回應的地方）要新增對應欄位的本地寫入邏輯，不然裝新機/重裝的使用者永遠拿不到這個 entity 的既有資料，只有之後的增量 push/pull 才看得到

### Cloud 端
沿用 §4 表格 Cloud 端那一整欄（因為這 6 種 entity 在 Cloud 上早就做完了，通常不用
再改 Cloud，除非 App 端需要一個目前只有 web 在用、Cloud 尚未在 read API 暴露的
欄位）。

### 決策點（先跟使用者確認，不要自己假設）
- 這個功能要不要支援離線建立（App 常常需要，Web 不一定）？如果要，App 端本地
  create 完要能立刻可用、稍後才同步，這對「syncId 什麼時候產生」（本地先產生
  UUID 當 syncId，還是等 server 回傳）有設計含意，照抄現有 `transaction`/
  `account` 的 syncId 產生時機（本地建立時就用 `_uuid.v4()` 產生，見
  `sync_engine.dart` 開頭 `const _uuid = Uuid();`）。
- Cloud 端這個 entity 有沒有「系統自動產生交易不可漏分類」這類特殊業務校驗
  （見 Cloud CLAUDE.md 的「特殊業務校驗規範」段落）？如果有，App 端對應的建立
  流程也要複製這個校驗規則，不要讓 App 端建出一筆會被 Cloud 拒收的 payload。

---

## 6. 常用指令備忘（App 端）

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # 改 db.dart / *.g.dart 依賴的檔案後必跑
flutter run --flavor dev
flutter test                                    # 全部
flutter test test/sync/                         # 只跑 sync 相關
flutter test test/sync/account_partial_update_apply_test.dart   # 單檔
dart format .
flutter analyze
flutter gen-l10n                                # 改了 lib/l10n/*.arb 之後
```

Commit message 慣例是中文 + Conventional Commits type（`feat:`/`fix:`/`refactor:`
等），例如 `feat: 添加预算功能`。

## 7. 改完怎麼驗證

- App 側：`flutter test`，尤其 `test/sync/`、`test/repositories/`、改到的 entity
  相關測試
- 端到端手動測（App 改一筆 → 看 Web 是否即時刷新；Web 改一筆 → 看 App pull 後
  是否即時刷新）：需要本機同時起 Cloud 端 `make dev-api`（帶 `--reload`，見 Cloud
  CLAUDE.md 的「本地 API server 沒帶 `--reload` 陷阱」）+ App 連到本機 Cloud
- 多裝置/多帳本場景：至少確認 user-global 實體在兩個帳本間不會互相污染
  （dedup 用 `source_change_id`，Cloud 端 SYNC_ARCHITECTURE.md §6 有除錯路徑）
- 若改到 §5 的全新 entity：額外測「首次同步/重裝」路徑（`/sync/full`），這是最
  容易漏測的路徑，因為日常開發都在測增量 push/pull
