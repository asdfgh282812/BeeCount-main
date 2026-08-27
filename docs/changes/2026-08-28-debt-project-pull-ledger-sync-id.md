# 修复:借还款/专案在 Cloud web 端新建后,App 端拉不到

## 问题

用户在 BeeCount Cloud 的 web 管理面板新增/编辑「借还款」记录后,server 端能看到,但
App 端「借还款」列表一直是空的(`还没有借还款记录`)。

## 根因

`lib/cloud/sync/sync_engine_apply.dart` 的 `_applyDebtChange`/`_applyProjectChange` 在
解析 pull 下来的变更时,要求 payload 里必须带 `ledgerSyncId` 键,拿它去反查本地
ledger 的 int id;查不到就直接跳过整条变更(且 pull cursor 照常前进,永久跳过):

```dart
final ledgerSyncId = payload['ledgerSyncId'] as String?;
...
final localLedgerId = await _resolveLedgerIdBySyncId(ledgerSyncId);
if (localLedgerId == null) {
  logger.info('SyncEngine', 'pull: 欠款 $syncId 的 ledgerSyncId=$ledgerSyncId 本地未就绪,跳过');
  return;
}
```

但 BeeCount Cloud 那边(`../BeeCount-Cloud/`)无论是写路径(`snapshot_mutator.py` 的
`create_debt`)还是快照重建(`snapshot_builder.py` 从 `ReadDebtProjection` 生成),
`debt`/`project` 的 payload 都**从来不带 `ledgerSyncId` 这个键**——这个键只有 App 自
己 push 变更时才会带上。也就是说,只要 debt/project 是在 web 端创建或编辑的,
App 拉到的这条变更 100% 会被判定为"账本本地未就绪"而丢弃;反过来 App 自己创建
的 debt/project 因为 push 出去的 payload 里有这个键,回环同步不受影响,所以问题
只在"web 建、App 拉"这个方向暴露。

对照 `budget`——Cloud 那边专门为 budget 在 `snapshot_builder.py`/
`snapshot_mutator.py` 里补发了 `ledgerSyncId`,所以 budget 没有这个问题;debt/
project 上线时漏做了同样的事。

`_applyTransactionChange`/`_applyRecurringRuleChange` 从未依赖 payload 里的
`ledgerSyncId`,而是直接用 change envelope 自带的 `change.ledgerId`(server 侧
`routers/sync/pull.py` 会把 ledger-scoped change 的 `ledger_id` 设成
`Ledger.external_id`,值域跟 payload 里的 `ledgerSyncId` 完全一致)。debt/
project/budget 的三个 apply 函数当初实现时忘了这个更简单可靠的来源。

delete 路径不受影响(只按 `syncId` 匹配),所以 web 端删除能正常同步——这也是
为什么现象是"web 端有记录、App 端没有"而不是"两边完全对不上"。

## 修复

`lib/cloud/sync/sync_engine_apply.dart`:`_applyDebtChange`/`_applyProjectChange`/
`_applyBudgetChange` 三处统一改成优先信 payload 里的 `ledgerSyncId`,缺键时
fallback 到 `change.ledgerId`:

```dart
final ledgerSyncId = (payload['ledgerSyncId'] as String?) ??
    (change.ledgerId.isEmpty ? null : change.ledgerId);
```

budget 目前其实不需要这个 fallback(Cloud 那边已经在发这个键),但一起加上是为了
避免以后 Cloud 端的 payload 组装逻辑变动时再次踩同一个坑。

### 历史数据补齐

这不是"App 不认识某个 entityType"那种能复用 `card_reward_rule_v35` 标记的场景——
是"认识,但因为查不到 ledger 而主动跳过",pull cursor 已经越过了这些历史
change_id,增量 pull 再也拉不回来。所以在 `_entityTypeBackfillTags`
(`lib/cloud/sync/sync_engine.dart`)新增两个独立 tag:`debt_ledger_sync_id_fix`、
`project_ledger_sync_id_fix`,让已经装过旧版本的设备在下次同步时触发一次
`replayAllChanges()`(从 change_id=0 全量重放),把之前被跳过的 debt/project 变更
重新拉回来。

### 测试

`test/sync/debt_apply_test.dart`、`test/sync/project_apply_test.dart` 各新增一个
用例,payload 故意不带 `ledgerSyncId` 键(还原 Cloud web 写入的真实形状),验证
靠 `change.ledgerId` fallback 仍能正确落地——此前所有测试用例的 fixture payload
都无一例外带着 `ledgerSyncId` 键,只覆盖了 App 自己 push 的形状,没能覆盖 Cloud
的真实形状,这也是这个 bug 没被测试捕获的原因。

## 遗留(有意不在本次处理)

- Cloud 端(`../BeeCount-Cloud/`)的 `snapshot_mutator.py`/`snapshot_builder.py`
  仍然不会在 debt/project payload 里补发 `ledgerSyncId`。App 侧的 fallback 已经
  能修复问题,但如果 Cloud 那边希望长期保持 wire contract 的一致性(像 budget
  那样),可以在 Cloud 仓库里补上对应字段——不在本仓库范围内。
- `docs/CLOUD_SYNC_INTEGRATION.md` 第 44、124 行仍写着 App 完全没有 `debt`
  entity,与 v39 之后的实际情况不符,是旧的遗留错误,建议后续一并更新。
