part of 'sync_engine.dart';

/// 同步健康检查 + 历史种子数据补登。
///
/// `checkSyncHealth` 是云同步页下拉刷新时调用的,对比本地 / server 计数,
/// UI 据此决定是否要触发一次 auto sync。`backfillUntrackedEntities` 给绕
/// 过 changeTracker 插入的本地实体(tag / account / category)补写 create
/// change,让它们能被 push 上去。
///
/// 这两个方法都是公开 API,但**不是** `SyncService` 接口方法,所以可以放
/// 在 extension 里。`getStatus` / `markLocalChanged` / `clearStatusCache`
/// 等 @override 接口实现必须留在主类里。
///
/// 注意:extension 名是 **public**(没有 `_` 前缀)——因为方法本身是 public
/// 且会被外部 caller(beecount_cloud_sync_page.dart)调用,private 扩展
/// 在 library 外不可见。命名特意避开顶层 `SyncEngineStatus` enum,叫
/// `SyncEngineHealthChecks` 区分。
extension SyncEngineHealthChecks on SyncEngine {
  /// 云同步页下拉刷新时用:对比本地 Drift 和 server `/read/ledgers/<id>/stats`
  /// 返回的计数,如果有差异就返回 hasDiff=true,UI 据此决定是否触发一次
  /// auto sync。server 端计数来源跟 web 实际展示一致(从最新 snapshot 读),
  /// 所以对得上 web 就代表"对端用户眼里的真实状态"。
  Future<SyncHealthReport> checkSyncHealth({required int ledgerId}) async {
    final ledger = await (db.select(db.ledgers)
          ..where((l) => l.id.equals(ledgerId)))
        .getSingleOrNull();
    if (ledger == null) {
      return SyncHealthReport.error('本地找不到 ledger=$ledgerId');
    }
    final serverLedgerId = ledger.syncId ?? ledger.id.toString();

    // ---------- 本地 per-ledger ----------
    // 只数有 syncId 的行,跟服务端口径对齐 —— 没 syncId 的行无法 push,
    // 云端不会有对应记录,统计它们会造成永久假阳性"本地比云端多"。
    final ledgerTxRows = await (db.select(db.transactions)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..where((t) => t.syncId.isNotNull()))
        .get();
    final localLedgerTx = ledgerTxRows.length;
    final ledgerTxIds = ledgerTxRows.map((t) => t.id).toList();
    // 本地交易附件:transaction_attachments 每 tx 一行 = server 端
    // attachment_kind='transaction' 的物理文件数。分类自定义图标独立统计
    // (见下面 localCategoryAttachments)。
    // 多笔交易可共享同一附件:已上传的按 cloudSha256 去重(server 端同样按
    // sha256 去重存 1 行)，未上传的按 fileName(各行独立)。避免把共享同一张图
    // 的 N 笔交易算成 N 个附件。
    int localLedgerAttachments = 0;
    if (ledgerTxIds.isNotEmpty) {
      final atts = await (db.select(db.transactionAttachments)
            ..where((a) => a.transactionId.isIn(ledgerTxIds)))
          .get();
      localLedgerAttachments =
          atts.map((a) => a.cloudSha256 ?? a.fileName).toSet().length;
    }
    final localLedgerBudgets = (await (db.select(db.budgets)
              ..where((b) => b.ledgerId.equals(ledgerId))
              ..where((b) => b.syncId.isNotNull()))
            .get())
        .length;

    // ---------- 本地 全量 ----------
    final localTotalTx = (await (db.select(db.transactions)
              ..where((t) => t.syncId.isNotNull()))
            .get())
        .length;
    // 全量交易附件 = 所有 tx 附件(分类图标不算)，同样按 cloudSha256 去重
    final localTotalAttachments =
        (await db.select(db.transactionAttachments).get())
            .map((a) => a.cloudSha256 ?? a.fileName)
            .toSet()
            .length;
    final localTotalBudgets = (await (db.select(db.budgets)
              ..where((b) => b.syncId.isNotNull()))
            .get())
        .length;

    // ---------- 本地 分类自定义图标 ----------
    // user-global,不分账本。跟 server attachment_kind='category_icon' 对齐。
    final localCategoryAttachments = (await (db.select(db.categories)
              ..where((c) => c.iconType.equals('custom'))
              ..where((c) => c.customIconPath.isNotNull()))
            .get())
        .length;

    // ---------- 本地 用户级 ----------
    final localAccounts = (await (db.select(db.accounts)
              ..where((a) => a.syncId.isNotNull()))
            .get())
        .length;
    final localCategories = (await (db.select(db.categories)
              ..where((c) => c.syncId.isNotNull()))
            .get())
        .length;
    final localTags =
        (await (db.select(db.tags)..where((t) => t.syncId.isNotNull())).get())
            .length;

    final unpushed =
        (await changeTracker.getUnpushedChangesForLedger(ledgerId)).length;

    // ---------- 远端 /read/ledgers/<id>/stats ----------
    try {
      final stats = await provider.readLedgerStats(ledgerId: serverLedgerId);
      return SyncHealthReport(
        ledgerTx:
            SyncCountPair(local: localLedgerTx, remote: stats.transactionCount),
        ledgerAttachments: SyncCountPair(
            local: localLedgerAttachments, remote: stats.attachmentCount),
        ledgerBudgets:
            SyncCountPair(local: localLedgerBudgets, remote: stats.budgetCount),
        totalTx:
            SyncCountPair(local: localTotalTx, remote: stats.transactionTotal),
        totalAttachments: SyncCountPair(
            local: localTotalAttachments, remote: stats.attachmentTotal),
        totalBudgets:
            SyncCountPair(local: localTotalBudgets, remote: stats.budgetTotal),
        categoryAttachments: SyncCountPair(
            local: localCategoryAttachments,
            remote: stats.categoryAttachmentTotal),
        accounts:
            SyncCountPair(local: localAccounts, remote: stats.accountTotal),
        categories:
            SyncCountPair(local: localCategories, remote: stats.categoryTotal),
        tags: SyncCountPair(local: localTags, remote: stats.tagTotal),
        unpushedChanges: unpushed,
      );
    } catch (e, st) {
      logger.warning('SyncEngine', 'checkSyncHealth 拉 stats 失败: $e', st);
      return SyncHealthReport(
        ledgerTx: SyncCountPair(local: localLedgerTx, remote: -1),
        ledgerAttachments:
            SyncCountPair(local: localLedgerAttachments, remote: -1),
        ledgerBudgets: SyncCountPair(local: localLedgerBudgets, remote: -1),
        totalTx: SyncCountPair(local: localTotalTx, remote: -1),
        totalAttachments:
            SyncCountPair(local: localTotalAttachments, remote: -1),
        totalBudgets: SyncCountPair(local: localTotalBudgets, remote: -1),
        categoryAttachments:
            SyncCountPair(local: localCategoryAttachments, remote: -1),
        accounts: SyncCountPair(local: localAccounts, remote: -1),
        categories: SyncCountPair(local: localCategories, remote: -1),
        tags: SyncCountPair(local: localTags, remote: -1),
        unpushedChanges: unpushed,
        error: e.toString(),
      );
    }
  }

  /// 为"绕过 changeTracker 插入"的本地 tag / account / category / budget
  /// 补写 `create` 变更记录,让后续 push 能把它们推到云端。
  ///
  /// 典型场景:早期的种子代码(TagSeedService)直接 `db.into(...).insert()`,
  /// 不经 `LocalRepository.createTag` → 这批标签永远不会被 push。
  /// `checkSyncHealth` 检测到 `localTags > remoteTags` 且 `unpushed == 0` 时
  /// 调这个方法 backfill 一次,再触发 sync 就能把种子标签送上云。
  ///
  /// **危险操作,三道防护(2026-09-29 事故后加上)**:补写的 create 在 push 时
  /// 会把本机整行序列化推上去,server 按「有键就覆盖」合并。旧版对**所有**
  /// 没有 unpushed change 的实体都补写,一台本机资料不完整的设备(当时 pull
  /// 卡在 cursor 2081)下拉刷新一次,就把 56 个账户整行覆盖(名称清空、排序
  /// 归 0、头像清掉被 server GC)、建出 87 个 server 从没有过的分类。现在:
  /// 1. 有未解决的 pull 错误 → 不做(本机资料不可信)。
  /// 2. pull 没追上 server(从 app cursor 往后还拉得到 change)→ 不做。
  /// 3. 只补 server 上**不存在**的实体:syncId 已在 server 的一律跳过(它不是
  ///    「没被追踪」,重推只会用本机旧值覆盖);同名的(分类按 kind + 名称 +
  ///    父分类名)也跳过,避免推出重复名称的分类(见 62e559d 的 pull 卡死)。
  ///    拉 server 清单失败就整个不做。
  /// 返回补写的 change 数。
  Future<int> backfillUntrackedEntities({required int ledgerId}) async {
    final unresolvedErrors = await (db.select(db.syncPullErrors)
          ..where((t) => t.resolvedAt.isNull()))
        .get();
    if (unresolvedErrors.isNotEmpty) {
      logger.warning('SyncEngine',
          'backfillUntrackedEntities: 仍有 ${unresolvedErrors.length} 笔 pull 错误,跳过');
      return 0;
    }

    final ledger = await (db.select(db.ledgers)
          ..where((l) => l.id.equals(ledgerId)))
        .getSingleOrNull();
    if (ledger == null) return 0;
    final serverLedgerId = ledger.syncId ?? ledger.id.toString();

    final List<BeeCountCloudReadAccount> remoteAccounts;
    final List<BeeCountCloudReadCategory> remoteCategories;
    final List<BeeCountCloudReadTag> remoteTags;
    try {
      final since = await appCursor.read();
      final probe = await provider.pullChanges(
        since: since,
        limit: 1,
        persistCursor: false,
      );
      if (probe.changes.isNotEmpty) {
        logger.warning('SyncEngine',
            'backfillUntrackedEntities: pull 还没追上 server(cursor=$since),跳过');
        return 0;
      }
      remoteAccounts = await provider.readAccounts(ledgerId: serverLedgerId);
      remoteCategories =
          await provider.readCategories(ledgerId: serverLedgerId);
      remoteTags = await provider.readTags(ledgerId: serverLedgerId);
    } catch (e) {
      logger.warning(
          'SyncEngine', 'backfillUntrackedEntities: 取 server 状态失败,跳过: $e');
      return 0;
    }

    final allUnpushed =
        await changeTracker.getUnpushedChangesForLedger(ledgerId);
    final pendingSyncIds = {for (final c in allUnpushed) c.entitySyncId};
    int backfilled = 0;

    // Tags
    final tags = selectBackfillCandidates(
      local: await db.select(db.tags).get(),
      syncIdOf: (t) => t.syncId,
      keyOf: (t) => t.name,
      remoteSyncIds: {for (final r in remoteTags) r.id},
      remoteKeys: {for (final r in remoteTags) r.name},
      pendingSyncIds: pendingSyncIds,
    );
    for (final tag in tags) {
      try {
        await changeTracker.recordUserGlobalChange(
          entityType: 'tag',
          entityId: tag.id,
          entitySyncId: tag.syncId!,
          action: 'create',
        );
        backfilled++;
      } catch (e) {
        // 已存在的 change 会撞唯一约束,忽略即可。
        logger.debug('SyncEngine', 'backfill tag ${tag.syncId} skip: $e');
      }
    }

    // Accounts
    final accounts = selectBackfillCandidates(
      local: await db.select(db.accounts).get(),
      syncIdOf: (a) => a.syncId,
      keyOf: (a) => a.name,
      remoteSyncIds: {for (final r in remoteAccounts) r.id},
      remoteKeys: {for (final r in remoteAccounts) r.name},
      pendingSyncIds: pendingSyncIds,
    );
    for (final acc in accounts) {
      try {
        await changeTracker.recordUserGlobalChange(
          entityType: 'account',
          entityId: acc.id,
          entitySyncId: acc.syncId!,
          action: 'create',
        );
        backfilled++;
      } catch (e) {
        logger.debug('SyncEngine', 'backfill account ${acc.syncId} skip: $e');
      }
    }

    // Categories
    final localCategories = await db.select(db.categories).get();
    final localCategoryNames = {
      for (final c in localCategories) c.id: c.name,
    };
    final categories = selectBackfillCandidates(
      local: localCategories,
      syncIdOf: (c) => c.syncId,
      keyOf: (c) =>
          _categoryBackfillKey(c.kind, c.name, localCategoryNames[c.parentId]),
      remoteSyncIds: {for (final r in remoteCategories) r.id},
      remoteKeys: {
        for (final r in remoteCategories)
          _categoryBackfillKey(r.kind, r.name, r.parentName),
      },
      pendingSyncIds: pendingSyncIds,
    );
    for (final cat in categories) {
      try {
        await changeTracker.recordUserGlobalChange(
          entityType: 'category',
          entityId: cat.id,
          entitySyncId: cat.syncId!,
          action: 'create',
        );
        backfilled++;
      } catch (e) {
        logger.debug('SyncEngine', 'backfill category ${cat.syncId} skip: $e');
      }
    }

    logger.info('SyncEngine',
        'backfillUntrackedEntities: 共补写 $backfilled 条 sync_change');
    return backfilled;
  }

  /// 从 server 的分类 projection 把一级分类颜色补回本机(只补本机为空的)。
  ///
  /// 背景(2026-09-29 实测):新设备登入回放全部 sync_changes 后,715 笔分类
  /// payload 没有任何一笔带 `color`——历史 payload 大多早于 v55 颜色功能,
  /// 或是 color 为 null 时 [EntitySerializer.serializeCategory] 直接省略该键
  /// 的推送;server 端的颜色是 sync_applier 按 merge spec 缺键保留、累积在
  /// user_category_projection.color 里的,只能透过 read API 取得。旧版
  /// `_applyCategoryChange` 还会把缺键当成清空(已修),所以已登入过的设备
  /// 本机颜色也可能早就被冲成 null,单靠 pull 永远恢复不了。
  ///
  /// 规则:只处理一级分类(二级分类不存色,渲染时继承父分类);只在本机
  /// color 为空、server 有值时写入——本机已有颜色一律不覆盖,避免盖掉使用者
  /// 在本机刚改、还没推上去的选择。按 syncId 对应。不经 changeTracker
  /// (这是把本机拉齐到 server 已知状态,不是新的本地改动,推回去会造成
  /// 推送环路),跟 [reconcileAccountBalances] 同一套原则。
  /// 返回补回的分类数。
  Future<int> restoreCategoryColorsFromServer({required int ledgerId}) async {
    final missing = await (db.select(db.categories)
          ..where((c) =>
              c.parentId.isNull() & c.color.isNull() & c.syncId.isNotNull()))
        .get();
    if (missing.isEmpty) {
      _categoryColorRestoreDone = true;
      return 0;
    }
    final ledger = await (db.select(db.ledgers)
          ..where((l) => l.id.equals(ledgerId)))
        .getSingleOrNull();
    if (ledger == null) return 0;
    final serverLedgerId = ledger.syncId ?? ledger.id.toString();

    final remote = await provider.readCategories(ledgerId: serverLedgerId);
    final colorBySyncId = <String, String>{
      for (final r in remote)
        if (r.id.isNotEmpty && (r.color ?? '').trim().isNotEmpty)
          r.id: r.color!.trim(),
    };

    var restored = 0;
    for (final local in missing) {
      final color = colorBySyncId[local.syncId];
      if (color == null) continue;
      await (db.update(db.categories)
            ..where((c) => c.id.equals(local.id) & c.color.isNull()))
          .write(CategoriesCompanion(color: d.Value(color)));
      restored++;
    }
    _categoryColorRestoreDone = true;
    logger.info('SyncEngine',
        '分类颜色对账:本机缺色一级分类 ${missing.length} 笔,从 server 补回 $restored 笔');
    return restored;
  }

  static const _categoryColorPaletteRepairTag =
      'category_color_palette_repair_20260929';

  /// 一次性:对仍然没有颜色的一级分类,按 v55 同一套色盘规则补指派颜色,
  /// 并登记 update 推回 server(**会写入云端**)。
  ///
  /// 背景:2026-09-29 旧版重复分类合并逻辑把使用者云端一组带色的一级分类
  /// 删掉(连 upsert 历史一起被 compact),server 上留下的同名那组本来就没
  /// 颜色,[restoreCategoryColorsFromServer] 没东西可补。原本的颜色本来就是
  /// v55 按「每个 kind 内依 sortOrder 顺序循环取 [kCategoryColorPalette]」
  /// 指派的,所以照同一套规则重算即可还原成一模一样的颜色。
  ///
  /// 规则(对照使用者原本 web 截图验证过):
  /// - 每个 kind 各自计数;transfer kind 跳过(虚拟分类,原本就没颜色)。
  /// - 一级分类依 (sortOrder, id) 排序,**同名只占一个色盘位置**(server 上
  ///   可能并存同名不同 syncId 的两笔,见 _pickCategoryKeeper)。
  /// - 没有 icon 且没有颜色的分类(web/server 流程建的系统分类,如「餘額調整」
  ///   「股利」)跳过——v55 时它们还不存在,原本就没有颜色,也不占色盘位置。
  ///   没 icon 但有颜色的(如「退款」)照样当锚点。
  /// - 同名组里已经有颜色的,以它当锚点:同组缺色的沿用同一色,之后的位置从
  ///   该色在色盘中的下一格接续。已有颜色一律不覆盖。
  ///
  /// 只在 pull 没有未解决错误时才跑(本机资料不完整时算出来的顺序会错),
  /// 成功跑完一次就用 [AppCursorStore.markBackfilled] 记下,不再重跑。
  /// 返回补指派的分类数。
  Future<int> repairMissingCategoryColorsOnce() async {
    if (await appCursor.hasBackfilled(_categoryColorPaletteRepairTag)) return 0;
    final pendingErrors = await db.select(db.syncPullErrors).get();
    if (pendingErrors.isNotEmpty) {
      logger.info(
          'SyncEngine', '分类色盘补指派:仍有 ${pendingErrors.length} 笔 pull 错误,暂不执行');
      return 0;
    }

    final rows = await (db.select(db.categories)
          ..where((c) => c.parentId.isNull() & c.kind.isNotValue('transfer'))
          ..orderBy([
            (c) => d.OrderingTerm.asc(c.kind),
            (c) => d.OrderingTerm.asc(c.sortOrder),
            (c) => d.OrderingTerm.asc(c.id),
          ]))
        .get();

    final assignments = computeCategoryPaletteRepair(rows);
    for (final entry in assignments.entries) {
      final cat = rows.firstWhere((c) => c.id == entry.key);
      await (db.update(db.categories)
            ..where((c) => c.id.equals(cat.id) & c.color.isNull()))
          .write(CategoriesCompanion(color: d.Value(entry.value)));
      final syncId = cat.syncId;
      if (syncId != null && syncId.isNotEmpty) {
        await changeTracker.recordUserGlobalChange(
          entityType: 'category',
          entityId: cat.id,
          entitySyncId: syncId,
          action: 'update',
        );
      }
    }
    await appCursor.markBackfilled(_categoryColorPaletteRepairTag);
    logger.info(
        'SyncEngine', '分类色盘补指派:补了 ${assignments.length} 笔一级分类颜色,已登记待推送');
    return assignments.length;
  }

  /// 帐户关键字段(initialBalance/type/currency)本地 vs server 逐条比对,
  /// 不一致就直接以 server 为准覆盖本地。
  ///
  /// 背景:`sync_engine_apply.dart` 的 `_applyAccountChange` insert 分支(本机
  /// 第一次见到某个 syncId)对缺键字段落的是硬编码默认值(0.0/'cash'/'CNY'),
  /// 不像 update 分支有 containsKey 保护——如果本机对这个账户应用的第一条
  /// 变更恰好是 web 端 `exclude_unset=True` 的局部 PATCH(而不是携带全字段
  /// 的建账事件),就会把默认值当真实数据写死,此后本地这个字段永远卡在
  /// 错误值(后续局部 update 只会 absent() 保留,不会再纠正)。
  ///
  /// 这里用 `readAccounts`(user-global 全量快照读取,含完整 initialBalance/
  /// accountType/currency,不受 exclude_unset 影响)逐条核对本地是否跟 server
  /// 权威值一致,不一致就直接写回本地——不经 changeTracker(这是把本地拉
  /// 齐到 server 已知状态,不是产生新的本地改动去 push,否则会造成推送
  /// 环路)。返回修正的账户数,供调用方展示给用户。
  Future<int> reconcileAccountBalances({required int ledgerId}) async {
    final ledger = await (db.select(db.ledgers)
          ..where((l) => l.id.equals(ledgerId)))
        .getSingleOrNull();
    if (ledger == null) return 0;
    final serverLedgerId = ledger.syncId ?? ledger.id.toString();

    List<BeeCountCloudReadAccount> remoteAccounts;
    try {
      remoteAccounts = await provider.readAccounts(ledgerId: serverLedgerId);
    } catch (e) {
      logger.warning('SyncEngine', 'reconcileAccountBalances 拉取账户失败: $e');
      return 0;
    }

    var fixed = 0;
    for (final remote in remoteAccounts) {
      final local = await (db.select(db.accounts)
            ..where((a) => a.syncId.equals(remote.id)))
          .getSingleOrNull();
      if (local == null) continue;

      final needsBalanceFix = remote.initialBalance != null &&
          (local.initialBalance - remote.initialBalance!).abs() > 0.0001;
      final needsTypeFix =
          remote.accountType != null && local.type != remote.accountType;
      final needsCurrencyFix =
          remote.currency != null && local.currency != remote.currency;
      if (!needsBalanceFix && !needsTypeFix && !needsCurrencyFix) continue;

      await (db.update(db.accounts)..where((a) => a.id.equals(local.id)))
          .write(AccountsCompanion(
        initialBalance: needsBalanceFix
            ? d.Value(remote.initialBalance!)
            : const d.Value.absent(),
        type: needsTypeFix
            ? d.Value(remote.accountType!)
            : const d.Value.absent(),
        currency: needsCurrencyFix
            ? d.Value(remote.currency!)
            : const d.Value.absent(),
      ));
      fixed++;
      logger.info(
          'SyncEngine',
          'reconcileAccountBalances: 修正账户 ${remote.id}(${remote.name}) '
              'balance=$needsBalanceFix type=$needsTypeFix currency=$needsCurrencyFix');
    }
    return fixed;
  }
}

/// [SyncEngineHealthChecks.backfillUntrackedEntities] 的纯筛选部分,抽出来
/// 方便单测。只留下:有 syncId、没有待推送 change、server 上没有同 syncId、
/// 也没有同 [keyOf](比对前 trim)的本机实体。
List<T> selectBackfillCandidates<T>({
  required Iterable<T> local,
  required String? Function(T) syncIdOf,
  required String Function(T) keyOf,
  required Set<String> remoteSyncIds,
  required Set<String> remoteKeys,
  required Set<String> pendingSyncIds,
}) {
  final keys = {for (final k in remoteKeys) k.trim()};
  return [
    for (final e in local)
      if ((syncIdOf(e) ?? '').isNotEmpty &&
          !pendingSyncIds.contains(syncIdOf(e)) &&
          !remoteSyncIds.contains(syncIdOf(e)) &&
          !keys.contains(keyOf(e).trim()))
        e,
  ];
}

String _categoryBackfillKey(String kind, String name, String? parentName) =>
    '$kind\u0000${name.trim()}\u0000${(parentName ?? '').trim()}';

/// [SyncEngineHealthChecks.repairMissingCategoryColorsOnce] 的纯计算部分,
/// 抽出来方便单测。[rows] 必须是一级分类,且已按 (kind, sortOrder, id) 排序。
/// 返回 `categoryId → 要补的颜色`,只包含目前没有颜色的分类。
Map<int, String> computeCategoryPaletteRepair(List<Category> rows) {
  bool hasColor(Category c) => (c.color ?? '').trim().isNotEmpty;
  final out = <int, String>{};
  final byKind = <String, List<Category>>{};
  for (final r in rows) {
    byKind.putIfAbsent(r.kind, () => []).add(r);
  }
  for (final list in byKind.values) {
    // 同名分组,保留第一次出现的顺序(Dart Map 字面量默认 LinkedHashMap)
    final groups = <String, List<Category>>{};
    for (final c in list) {
      if ((c.icon ?? '').trim().isEmpty && !hasColor(c)) continue;
      groups.putIfAbsent(c.name.trim(), () => []).add(c);
    }
    var next = 0;
    for (final group in groups.values) {
      final anchor = group.where(hasColor).firstOrNull;
      final String color;
      if (anchor != null) {
        color = anchor.color!.trim();
        final idx = kCategoryColorPalette
            .indexWhere((p) => p.toUpperCase() == color.toUpperCase());
        next = idx >= 0 ? idx + 1 : next + 1;
      } else {
        color = kCategoryColorPalette[next % kCategoryColorPalette.length];
        next++;
      }
      for (final c in group) {
        if (!hasColor(c)) out[c.id] = color;
      }
    }
  }
  return out;
}
