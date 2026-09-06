# 分类颜色 push backfill：修复「手机设了色，web 端看不到」

## 背景

用户反馈：在手机 App 上给「交通」分类设置了颜色（红色），但 web 端打开同一
个分类的编辑弹窗，20 色调色盘里没有任何色块显示为选中态；web 端分类管理页
/ 分类选择器的圆形图标底色也是灰色。

排查确认 BeeCount-Cloud（web + 后端）这条链路本身没有问题——`sync_applier.py`
`_MERGE_SPECS`、`projection.py`、`snapshot_builder.py`、read/write endpoints 都
正确处理 `color` 字段，web 端表单回填 / swatch 选中判断的逻辑也都正确。也就
是说：如果服务器真的收到了 `color` 值，web 端 100% 能正确显示。问题是服务器
上这条分类的 `color` 就是 `NULL`——手机端从来没有把这个值推上去。

## 根因

`lib/data/db.dart` 的 v55 migration（分类专属颜色）最初直接用
`customStatement` 回填既有一级分类的 `color`，完全绕过了
`ChangeTracker`/`local_changes` outbox，跟正常的 `createCategory`/
`updateCategory` 写入路径不一样，不会产生任何 sync push 事件。这个 bug 在
`01c417b`（2026-09-06 18:48）已经修过一次：在同一个 `if (from < 55)` 迁移块
里补插一条 unpushed 的 `local_changes` 行,下次同步时 `_doPushUserGlobalEntities`
会重新序列化并推送。

**但这个修法对已经跑过旧版 v55 migration 的设备无效**：迁移块按
schemaVersion 转换（`from < 55`）只跑一次，装了这版新 app 的老设备本机
schemaVersion 早就 ≥55，不会重新进入这个 `if` 块。这些设备的分类颜色会永久
卡在「本机有、服务器 NULL」的状态，直到用户手动重新编辑保存那个分类。

`sync_engine.dart` 里已有的 `_backfillLegacyUserGlobalChanges`（v19 syncId 
回填踩过的同一类坑）也救不了这个场景——它的判断依据是「这个 syncId 在
`local_changes` 里完全没有任何记录」，而这批分类是「早就同步过、只是后来
`color` 字段被 outbox 之外的路径偷改」，`local_changes` 里本来就有旧的
upsert 记录，会被这套逻辑当成「已知」而跳过。

## 修复

`lib/cloud/sync/sync_engine.dart` 新增 `_backfillLegacyCategoryColorPush`：

- 用 `AppCursorStore.hasBackfilled`/`markBackfilled`（跟 pull 方向的
  entity-type backfill 共用同一套 per 账号+设备持久化标记基建，语义换成
  push 方向）记录「这台设备这个账号是否已经成功跑过一次」，跨 app 版本、
  跨 session 只需要成功跑一次。
- 无条件扫一遍本机「一级分类且 `color` 非空」的全部记录，对每一条补插一条
  `update` local_changes（不看这个 syncId 是否已经在 `local_changes` 里有
  记录——这正是跟 `_backfillLegacyUserGlobalChanges` 的区别）。补的这条
  change 序列化时带上分类当前的完整状态，等价于把这个分类重新 upsert 一次，
  幂等、无副作用。
- 挂在 `_doPushUserGlobalEntities()` 里，跟已有的 `_userGlobalLegacyBackfilled`
  一起、在每次 `pushUserGlobalEntities()` 时检查（标记落地后是一次廉价的
  SharedPreferences 读取，可以忽略不计）。

`lib/data/db.dart` 里 2026-09-06 当天已经修过的 v55 migration 本身不需要动
（对全新安装、或还没升过 v55 的设备已经是完整正确的）。

## 测试

`test/cloud/sync/sync_engine_e2e_test.dart` 新增 `group('v55 分类颜色 push
backfill')`：

1. 模拟「分类早就正常同步过一次（`local_changes` 有旧记录且已标记 pushed），
   之后 `color` 被 outbox 之外的路径直接改掉」的场景 → 首次
   `pushUserGlobalEntities()` 应该补推这条分类的最新状态。
2. 补推标记落地后，即使又出现新的「legacy 有色」分类，也不会再触发一次全量
   扫描（这套 backfill 只保证「成功跑过一次」，不是每次 push 都全量重扫）。
3. 没有设色的分类不受影响，不会被误推。

## 给已经受影响的用户的临时解法

在等到装有这次修复的新版本之前，用户可以在手机 App 打开受影响分类的编辑页，
不改任何内容直接按「储存」——这会走正常的 `updateCategory` 写入路径（有走
同步追踪），下次同步后 web 端就能看到颜色。
