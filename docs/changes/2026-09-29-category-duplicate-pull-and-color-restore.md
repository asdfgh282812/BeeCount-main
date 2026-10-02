# 修正：重复分类导致 pull 卡死 / 删除云端分类，以及分类颜色补回

接续 [2026-09-29-category-color-pull-overwrite-fix.md](2026-09-29-category-color-pull-overwrite-fix.md)。
那份修正上线测试后，App 端的分类颜色底线仍然全部是灰色。这次用模拟器登入真实帐号实测，
找到三个问题。

## 实测观察

新设备登入后，从 cursor 0 回放 `/sync/pull`：

1. **pull 卡死**：套用 change_id=2310（一笔交易）时抛出 `Bad state: Too many elements`，
   stack 指向 `_SyncEngineResolvers._resolveCategoryId` 的 `getSingleOrNull()`。整页
   在同一个 transaction 里回滚，cursor 永远停在 2081，**之后的所有异动都进不来**。
   根本原因是云端历史真实存在两组同名、不同 syncId 的分类（两台设备在互相同步前各自
   建过预设分类），名字反查会命中多笔。
2. **历史 payload 没有 `color`**：回放拉到的 715 笔分类异动，没有任何一笔带 `color` key。
   这些 payload 大多早于 v55 颜色功能；另外 `EntitySerializer.serializeCategory` 在本机
   color 为 null 时会直接省略这个 key。server 端的颜色是 `sync_applier` 按 merge spec
   「缺键保留」累积在 `user_category_projection.color` 里的，只能透过 read API 取得。
   所以即使 pull 逻辑正确，本机已经是 null 的颜色也永远补不回来。
3. **合并重复分类时把 delete 推回 server（破坏性）**：`_resolveDuplicateCategories`
   在 parentName 反查命中多笔同名一级分类时，会保留 id 最小的一笔，删掉其余几笔，
   **并对被删的记一笔 `changeTracker` delete 推回 server**。同名但 syncId 不同的分类，
   在 server 端是两个都合法存在的实体。实测一次登入就删掉了使用者云端 12 个一级分类，
   而且 Cloud 删除实体时会连带清掉它的 upsert 历史（`_compact_entity_upsert_events`），
   无法从 sync_changes 复原。

## 修正

### `lib/cloud/sync/sync_engine_resolvers.dart` — `_resolveCategoryId`

改成 `get()` 全部命中，再确定性地挑一笔：有 syncId 的优先 → 一级分类优先 → id 最小。
只读，不合并，也不推送。pull 不会再卡在同一页。

### `lib/cloud/sync/sync_engine_apply.dart`

- `_resolveDuplicateCategories` 拆成三个 helper：
  - `_pickCategoryKeeper`：**只挑一笔、不改任何资料**。用在 parentName 反查，以及
    NULL-syncId 的预设分类收编。规则是有 syncId 的优先、其次 id 最小。
  - `_mergeSameSyncIdCategories`：只有**同一个 syncId** 在本机出现多笔时才合并（这在
    server 端是同一个实体，属于本机自己的脏数据）。会改指引用、删掉多余的本机副本，
    但**不推 delete**。
  - `_repointCategoryReferences`：把 7 张引用 categoryId 的表，加上子分类的 parentId，
    改指到新的分类。
- 解析 parentId 时优先用 payload 的 `parentSyncId`，没有才退回 `parentName`。
- delete 分支：删除一级分类时，如果本机还有另一笔同名、同 kind 的一级分类存活，就把
  子分类和交易等引用改挂过去，而不是连子分类一起删掉。server 端收敛同名重复时只会删
  其中一组，子分类在 server 眼里是按名字挂着的。
- 更新 `resolvedColor` 的注释：原本那段说「Cloud 尚未接上 color」，这是错的。

### `lib/cloud/sync/sync_engine_status.dart` — `restoreCategoryColorsFromServer`

新增方法：透过 `provider.readCategories`（`GET /read/ledgers/{id}/categories`，回传
`user_category_projection.color`）按 syncId 补回本机缺色的一级分类。规则如下：

- 只补「本机 color 为空、server 有值」的；本机已有颜色一律不覆盖。
- 不经 `changeTracker`。这是把本机拉齐到 server 已知状态，推回去会造成推送环路。
  原则跟 `reconcileAccountBalances` 相同。
- 本机没有缺色的一级分类时直接 return，不打 API。

`lib/cloud/sync/sync_engine.dart` 在主同步流程的 pull 之后呼叫一次（per-session flag
`_categoryColorRestoreDone`，失败不阻塞主同步）。

### `packages/flutter_cloud_sync/.../beecount_cloud_provider.dart`

`BeeCountCloudReadCategory` 新增 `color` 字段（解析 `json['color']`）。Cloud 端的
`ReadCategoryOut` 早就有这个字段，只是 App 没读。

### `lib/data/repositories/local/local_repository.dart` — `getTransferCategory`

第二次实测时又发现同一类问题：新设备回放到一半时，本机会暂时有多笔 transfer 分类，
UI 呼叫 `getTransferCategory()` 就会合并掉多余的，并对 dupe 记下 category delete，
连同交易 update 一起推回 server（实测推出了 2 笔 transfer 分类 delete）。现在改成只在
本机合并，不再登记任何 ChangeTracker 变更。回归测试见
`test/repositories/transfer_category_merge_local_only_test.dart`。

### `lib/cloud/sync/sync_engine_status.dart` — `repairMissingCategoryColorsOnce`（会写入云端）

被误删的那组分类，是 server 上唯一带颜色的一组，`restoreCategoryColorsFromServer`
没有东西可以补。对照使用者原本的 web 截图，原本的颜色就是 v55 按「每个 kind 内依
sortOrder 循环取 `kCategoryColorPalette`」指派的结果。所以用同一套规则重算，就能还原
成一模一样的颜色，再登记 update 推回 server，让 web 也恢复。规则的细节（同名只占一个
色盘位置、已有颜色的当锚点、没 icon 也没颜色的系统分类跳过、transfer 跳过）写在该
方法的文档里，纯计算部分抽成 `computeCategoryPaletteRepair` 以便单测。

执行条件：`restoreCategoryColorsFromServer` 成功之后，且 `sync_pull_errors` 为空（本机
资料不完整时算出来的顺序会错）。用 `AppCursorStore.markBackfilled(
'category_color_palette_repair_20260929')` 记录，每个帐号+设备只跑一次。经使用者同意后
在模拟器上跑过一次：补了 17 笔并推送，没有夹带其它变更。

## 测试

`test/cloud/sync/sync_engine_e2e_test.dart`：

- 「分类重复数据」group 改写。原本那个测试断言「dupe 的 delete 要推给其它设备」，钉住
  的正是这次的破坏性行为，已改为断言**不推 delete、不合并、不搬交易**。
- 新增测试：`parentSyncId` 优先；交易 categoryName 命中两笔时不抛例外，而且整页都有
  apply；server 删掉同名重复中的一笔时，子分类和交易改挂到存活的那笔；同 syncId 副本
  只在本机合并、不推送。
- 新增「分类颜色对账」group：缺色补回但不覆盖本机颜色、不产生 local_changes；没有缺色
  时不打 read API。
- 新增「分类色盘补指派」group：用使用者的真实分类资料验证每一个颜色都还原正确；只跑
  一次；还有 pull 错误时不执行。

`test/cloud/sync/_fakes/fake_beecount_cloud_provider.dart` 新增 `readCategories` override
（`serverCategories` / `readCategoriesCalls`）。

## 刻意不在本次范围内

- **已被删除的云端分类没有自动复原。** 实测误删了 12 个一级分类，第二次测试又误删了
  2 个 transfer 分类，这些都无法从 sync_changes 找回（upsert 历史已被 compact）。同名
  的另一组分类还在，颜色也已经由上面的补指派还原；如果要找回被删的实体本身，只能从
  Cloud 数据库备份复原。
- **没有改 Cloud 端。** `/sync/pull` 仍然回传原始 payload，不会用 projection 补齐缺键
  字段。如果之后其它字段也出现「历史 payload 缺键、只有 projection 有」的问题，可以考虑
  在 Cloud 端做类似 `_enrich_tx_payloads_with_user_ids` 的 pull enrichment。
- **不会主动收敛云端既有的同名重复分类。** 这应该由使用者在 Web 或 App 的分类管理里
  明确操作，不该由同步引擎在背景自动决定。
