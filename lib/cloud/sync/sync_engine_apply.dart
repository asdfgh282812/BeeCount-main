part of 'sync_engine.dart';

/// pull 路径上把远端变更应用到本地 Drift 的逻辑。`_applyRemoteChange` 是
/// 总入口分发器,按 entity_type 分到具体的 `_apply*Change` handler。
///
/// 这里所有方法都是 private(以 `_` 开头),只在主 library 内被 `_pull` 调
/// 用,所以 extension 可以保持 private。
extension SyncEngineApplyExt on SyncEngine {
  /// 应用单条远程变更到本地数据库
  /// 返回 true 表示已应用，false 表示跳过
  Future<bool> applyRemoteChange(BeeCountCloudSyncChange change) async {
    // 跳过本设备自己的变更
    final deviceId = await _getDeviceId();
    if (change.updatedByDeviceId == deviceId) return false;

    // 如果没有 payload 且不是删除操作，跳过（无法应用）
    if (change.payload == null && change.action != 'delete') {
      logger.debug('SyncEngine',
          'pull: 跳过无 payload 的变更 ${change.entityType}/${change.entitySyncId}');
      return false;
    }

    switch (change.entityType) {
      case 'transaction':
        await _applyTransactionChange(change);
        return true;
      case 'account':
        await _applyAccountChange(change);
        return true;
      case 'category':
        await _applyCategoryChange(change);
        return true;
      case 'tag':
        await _applyTagChange(change);
        return true;
      case 'budget':
        await _applyBudgetChange(change);
        return true;
      case 'recurring_rule':
        await _applyRecurringRuleChange(change);
        return true;
      case 'card_reward_rule':
        await _applyCardRewardRuleChange(change);
        return true;
      case 'exchange_rate_override':
        await _applyExchangeRateOverrideChange(change);
        return true;
      case 'ledger':
        await _applyLedgerChange(change);
        return true;
      case 'ledger_snapshot':
        // 全量快照在 fullPull 中处理，这里跳过
        return false;
      default:
        logger.warning('SyncEngine', '未知 entityType: ${change.entityType}');
        return false;
    }
  }

  // ==================== Apply 方法 ====================

  Future<void> _applyTransactionChange(BeeCountCloudSyncChange change) async {
    final syncId = change.entitySyncId;

    if (change.action == 'delete') {
      // delete 路径:先看 cache 拿 id(避免 N+1 SELECT);cache miss 再 DB
      final cachedTx = activePullCache?.transaction(syncId);
      int? existingId = cachedTx?.id;
      if (existingId == null && activePullCache == null) {
        final existing = await (db.select(db.transactions)
              ..where((t) => t.syncId.equals(syncId)))
            .getSingleOrNull();
        existingId = existing?.id;
      }
      if (existingId != null) {
        // 先清磁盘附件(原图 + 缩略图),再删 transaction_attachments 行 ——
        // 反过来就查不到 fileName 了。
        await _cleanupTxAttachmentFilesOnDisk(existingId);
        await (db.delete(db.transactionTags)
              ..where((tt) => tt.transactionId.equals(existingId!)))
            .go();
        await (db.delete(db.transactionAttachments)
              ..where((ta) => ta.transactionId.equals(existingId!)))
            .go();
        await (db.delete(db.transactions)
              ..where((t) => t.id.equals(existingId!)))
            .go();
        activePullCache?.removeTransaction(syncId);
        logger.debug('SyncEngine', 'pull: 删除交易 $syncId');
      }
      return;
    }

    // upsert
    final payload = change.payload!;
    // change.ledgerId 是 server 的 external_id（string）。本地 B 设备 auto-
    // increment int id 跟 server 不一致，必须按 syncId 查本地 int id。
    // 只有没命中时才 fallback 到直接 parse（向后兼容老数据 ledger_id 就是
    // int 字符串的场景）。
    final ledgerIdInt = await _resolveLedgerIdBySyncId(change.ledgerId) ??
        int.tryParse(change.ledgerId) ??
        -1;

    // 解析 payload 字段
    final type = payload['type'] as String? ?? 'expense';
    final amount = (payload['amount'] as num?)?.toDouble() ?? 0.0;
    final happenedAtStr = payload['happenedAt'] as String?;
    final happenedAt = happenedAtStr != null
        ? DateTime.tryParse(happenedAtStr)?.toLocal() ?? DateTime.now()
        : DateTime.now();
    final note = payload['note'] as String?;
    // v33:商家。跟 note 同款——entity_serializer.dart 恒发这个键(不省略),
    // 这里直接无条件读,不用 containsKey 保护。
    final merchant = payload['merchant'] as String?;
    // v34:退款关联。跟 excludeFromStats 同款「缺键不覆盖」——旧版 App 送出的
    // payload 不会带这个键，若无条件覆盖会把本地已有的关联清空。
    final hasRefundKey = payload.containsKey('refundOfId');
    final refundOfSyncId =
        hasRefundKey ? payload['refundOfId'] as String? : null;
    final categoryName = payload['categoryName'] as String?;
    final categoryKind = payload['categoryKind'] as String?;
    // web 端创建转账时 account_name/account_id 是 null,只填 from_account_*。
    // mobile 模型用 accountId 表示 from 账户,所以转账 payload 转换:
    //   - account_name = accountName ?? fromAccountName
    //   - accountId = payload.accountId ?? payload.fromAccountId
    // 否则 B 同步 A 转账 tx 时 accountId=null,picker 显示无账户。
    final isTransfer = type == 'transfer';
    final accountName = (payload['accountName'] as String?) ??
        (isTransfer ? payload['fromAccountName'] as String? : null);
    final toAccountName = payload['toAccountName'] as String?;

    // 解析关联实体 ID —— 优先用 syncId 映射（跨设备稳定），fallback 到名字。
    // payload 里的 categoryId / accountId / toAccountId 是 server snapshot.items[i]
    // 存的远端实体 syncId，B 设备 pull 后 category/account 已经上 syncId 了
    // （P1 的 fallback 给 seed 补的，或 pull 新插入带的），按 syncId 查一定命中。
    // 名字 fallback 兜住旧 snapshot payload 没 syncId 的老数据。
    // §7 v25:server payload.categoryId / accountId / toAccountId 是 syncId。
    // 主表反查不到时(Editor 视角看 Owner 的 tx),检查 SharedLedger* 表 —
    // 命中则写 *SyncIdOverride 字段(本地 int id 留 null)。
    final rawCategoryId = payload['categoryId'] as String?;
    int? categoryId = await _resolveCategoryIdBySyncId(rawCategoryId) ??
        await _resolveCategoryId(
          categoryName: categoryName,
          categoryKind: categoryKind,
        );
    String? categorySyncIdOverride;
    if (categoryId == null &&
        rawCategoryId != null &&
        rawCategoryId.isNotEmpty) {
      final shared = await (db.select(db.sharedLedgerCategories)
            ..where((t) => t.syncId.equals(rawCategoryId)))
          .getSingleOrNull();
      if (shared != null) categorySyncIdOverride = shared.syncId;
    }

    final rawAccountId = (payload['accountId'] as String?) ??
        (isTransfer ? payload['fromAccountId'] as String? : null);
    int? accountId = await _resolveAccountIdBySyncId(rawAccountId) ??
        await _resolveAccountId(
          accountName: accountName,
          ledgerId: ledgerIdInt,
        );
    String? accountSyncIdOverride;
    if (accountId == null && rawAccountId != null && rawAccountId.isNotEmpty) {
      final shared = await (db.select(db.sharedLedgerAccounts)
            ..where((t) => t.syncId.equals(rawAccountId)))
          .getSingleOrNull();
      if (shared != null) accountSyncIdOverride = shared.syncId;
    }

    final rawToAccountId = payload['toAccountId'] as String?;
    int? toAccountId = await _resolveAccountIdBySyncId(rawToAccountId) ??
        await _resolveAccountId(
          accountName: toAccountName,
          ledgerId: ledgerIdInt,
        );
    String? toAccountSyncIdOverride;
    if (toAccountId == null &&
        rawToAccountId != null &&
        rawToAccountId.isNotEmpty) {
      final shared = await (db.select(db.sharedLedgerAccounts)
            ..where((t) => t.syncId.equals(rawToAccountId)))
          .getSingleOrNull();
      if (shared != null) toAccountSyncIdOverride = shared.syncId;
    }

    // 查 existing 优先走 LookupCache(prime 时已全表加载 transactions 的
    // syncId / id / createdByUserId),消除 10k 条 = 10k 次 SELECT 的 N+1。
    // miss(冷启动新设备 / 老数据)再走 DB。
    final cachedTx = activePullCache?.transaction(syncId);
    int? existingId = cachedTx?.id;
    String? existingCreatedByUserId = cachedTx?.createdByUserId;
    if (existingId == null && activePullCache == null) {
      final existing = await (db.select(db.transactions)
            ..where((t) => t.syncId.equals(syncId)))
          .getSingleOrNull();
      existingId = existing?.id;
      existingCreatedByUserId = existing?.createdByUserId;
    }

    // 共享账本(v24):server 注入 createdByUserId / updatedByUserId,本地用来
    // 在 tx 末尾显示"X 记的"。payload 用 camelCase(server snapshot_mutator 出来的
    // 字段是 createdByUserId/updatedByUserId,跟 Drift 列名 createdByUserId /
    // lastEditedByUserId 对齐)。
    final createdByUserId = payload['createdByUserId'] as String?;
    final lastEditedByUserId =
        (payload['updatedByUserId'] as String?) ?? createdByUserId;

    // 账单标记(D6 缺键保留):payload 不含该键 → null → update 走
    // Value.absent() 不覆盖本地;含键(包括显式 false)→ 覆盖。insert 路径
    // null 落默认 false。键名 camelCase 与 server 契约对齐。
    final excludeStats = payload.containsKey('excludeFromStats')
        ? (payload['excludeFromStats'] as bool? ?? false)
        : null;
    final excludeBudget = payload.containsKey('excludeFromBudget')
        ? (payload['excludeFromBudget'] as bool? ?? false)
        : null;

    // v30 交易级多币种:payload 带键 → 用 payload 值;缺键(旧 App 的 change,
    // sync_changes 存的是原始 push payload,不经 server merge)→ 快照保护
    // (02 §七):update 时本地已有折算且 amount 未变 → 保留本地;amount 变了 →
    // 退化 =amount(1:1,L11 横幅可按当前汇率捞回,好过错值)。
    final hasCurrencyKey = payload.containsKey('currencyCode');
    final hasNativeKey = payload.containsKey('nativeAmount');
    final payloadCurrency =
        hasCurrencyKey ? (payload['currencyCode'] as String?) : null;
    final payloadNative =
        hasNativeKey ? (payload['nativeAmount'] as num?)?.toDouble() : null;

    // v35:信用卡紅利回饋——跟 excludeFromStats 同款「缺键不覆盖」,旧 payload
    // (老版本 App / 尚未支持此字段的其它客户端)不带这个键时不要清空本地已
    // 有的勾选。
    final hasRewardRuleIdsKey = payload.containsKey('rewardRuleIds');
    final rawRewardRuleIds = payload['rewardRuleIds'];
    final rewardRuleIdsJson = hasRewardRuleIdsKey
        ? (rawRewardRuleIds is List
            ? jsonEncode(rawRewardRuleIds.whereType<String>().toList())
            : null)
        : null;

    // v36:週期性收支(recurring_rule)反查字段。recurringRuleId 跟 refundOfId
    // 同款「缺键不覆盖」——entity_serializer.dart 只在非 null 时才发这个键。
    // recurringOccurrenceOverridden 跟 excludeFromStats 同款,恒发但仍做
    // containsKey 保护(旧客户端 / 尚未支持这个字段的其它来源不带这个键时,
    // 不要把本地已经标记的 true 冲回默认值 false)。
    final hasRecurringRuleIdKey = payload.containsKey('recurringRuleId');
    final recurringRuleId =
        hasRecurringRuleIdKey ? payload['recurringRuleId'] as String? : null;
    final hasRecurringOverriddenKey =
        payload.containsKey('recurringOccurrenceOverridden');
    final recurringOccurrenceOverridden = hasRecurringOverriddenKey
        ? (payload['recurringOccurrenceOverridden'] as bool? ?? false)
        : null;

    // v37 對帳模式/延後入帳:跟 excludeFromStats 同款「缺键不覆盖」——舊版
    // App/其它尚未支持這兩個欄位的客戶端不帶這些 key 時,不要清空本地已有的
    // 確認/延後標記。entity_serializer.dart 恒发这两个键(值可能是 null,
    // 代表使用者主動取消確認/取消延後),所以命中 key 时要能把 d.Value 写成
    // null(不是用 null 当"不更新"的兜底信号)。
    final hasReconciledKey = payload.containsKey('reconciledAt');
    final reconciledAtStr =
        hasReconciledKey ? payload['reconciledAt'] as String? : null;
    final reconciledAt = reconciledAtStr != null
        ? DateTime.tryParse(reconciledAtStr)?.toLocal()
        : null;
    // deferredPostingAt 是「純日期」欄位(對齊哪一期帳單,不是精確時刻),
    // 刻意不 `.toLocal()`——跟 BeeCount Cloud web 版 isoToDateInput 系列
    // helper 同一個理由:一律用 UTC 年月日當日期的權威表示,經過本地時區
    // 位移轉換反而會在寫入/讀出兩端使用不同時區的裝置間造成日期差一天。
    // 讀取端(reconciliation.dart::effectiveDate 等)一律要用 `.toUtc()`
    // 取年月日,不能直接讀 Drift 讀回來的本地 flavor 欄位。
    final hasDeferredPostingKey = payload.containsKey('deferredPostingAt');
    final deferredPostingAtStr =
        hasDeferredPostingKey ? payload['deferredPostingAt'] as String? : null;
    final deferredPostingAt = deferredPostingAtStr != null
        ? DateTime.tryParse(deferredPostingAtStr)
        : null;

    if (existingId != null) {
      // 更新 — createdByUserId 走"本地为 null 就回填,否则保持"的策略。
      final shouldBackfillCreator =
          existingCreatedByUserId == null && createdByUserId != null;
      // 快照保护:缺 nativeAmount 键时查本地旧行判断 amount 是否变化。
      d.Value<double?> nativeValue;
      if (hasNativeKey) {
        nativeValue = d.Value(payloadNative);
      } else {
        final oldTx = await (db.select(db.transactions)
              ..where((t) => t.id.equals(existingId!)))
            .getSingleOrNull();
        final oldNative = oldTx?.nativeAmount;
        if (oldNative != null && oldTx!.amount != amount) {
          nativeValue = d.Value(amount); // 旧客户端改了金额 → 退化 1:1
        } else {
          nativeValue = const d.Value.absent(); // 金额未变 → 保留本地折算
        }
      }
      await (db.update(db.transactions)..where((t) => t.id.equals(existingId!)))
          .write(TransactionsCompanion(
        type: d.Value(type),
        amount: d.Value(amount),
        happenedAt: d.Value(happenedAt),
        note: d.Value(note),
        merchant: d.Value(merchant),
        categoryId: d.Value(categoryId),
        accountId: d.Value(accountId),
        toAccountId: d.Value(toAccountId),
        categorySyncIdOverride: d.Value(categorySyncIdOverride),
        accountSyncIdOverride: d.Value(accountSyncIdOverride),
        toAccountSyncIdOverride: d.Value(toAccountSyncIdOverride),
        createdByUserId: shouldBackfillCreator
            ? d.Value(createdByUserId)
            : const d.Value.absent(),
        lastEditedByUserId: d.Value(lastEditedByUserId),
        excludeFromStats: excludeStats == null
            ? const d.Value.absent()
            : d.Value(excludeStats),
        excludeFromBudget: excludeBudget == null
            ? const d.Value.absent()
            : d.Value(excludeBudget),
        currencyCode: hasCurrencyKey
            ? d.Value(payloadCurrency)
            : const d.Value.absent(), // 缺键保留本地币种
        nativeAmount: nativeValue,
        refundOfSyncId:
            hasRefundKey ? d.Value(refundOfSyncId) : const d.Value.absent(),
        rewardRuleIdsJson: hasRewardRuleIdsKey
            ? d.Value(rewardRuleIdsJson)
            : const d.Value.absent(),
        recurringRuleId: hasRecurringRuleIdKey
            ? d.Value(recurringRuleId)
            : const d.Value.absent(),
        recurringOccurrenceOverridden: hasRecurringOverriddenKey
            ? d.Value(recurringOccurrenceOverridden!)
            : const d.Value.absent(),
        reconciledAt:
            hasReconciledKey ? d.Value(reconciledAt) : const d.Value.absent(),
        deferredPostingAt: hasDeferredPostingKey
            ? d.Value(deferredPostingAt)
            : const d.Value.absent(),
      ));
      // 更新标签和附件(existing 路径)
      await _syncTransactionTags(existingId, syncId, payload);
      await _syncTransactionAttachments(existingId, payload);
      logger.debug('SyncEngine', 'pull: 更新交易 $syncId');
    } else {
      // 插入
      final id = await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              ledgerId: ledgerIdInt,
              type: type,
              amount: amount,
              happenedAt: d.Value(happenedAt),
              note: d.Value(note),
              merchant: d.Value(merchant),
              categoryId: d.Value(categoryId),
              accountId: d.Value(accountId),
              toAccountId: d.Value(toAccountId),
              syncId: d.Value(syncId),
              createdByUserId: d.Value(createdByUserId),
              lastEditedByUserId: d.Value(lastEditedByUserId),
              categorySyncIdOverride: d.Value(categorySyncIdOverride),
              accountSyncIdOverride: d.Value(accountSyncIdOverride),
              toAccountSyncIdOverride: d.Value(toAccountSyncIdOverride),
              excludeFromStats: d.Value(excludeStats ?? false),
              excludeFromBudget: d.Value(excludeBudget ?? false),
              // 缺键的旧 payload:nativeAmount = amount(隐含汇率 1,与 v30
              // 迁移回填同口径,外币账户交易由 L11 检测捞回);currencyCode
              // 留 NULL(检测端 LEFT JOIN 账户币种兜底)。
              currencyCode: d.Value(payloadCurrency),
              nativeAmount: d.Value(hasNativeKey ? payloadNative : amount),
              refundOfSyncId: d.Value(refundOfSyncId),
              rewardRuleIdsJson: d.Value(rewardRuleIdsJson),
              recurringRuleId: d.Value(recurringRuleId),
              recurringOccurrenceOverridden:
                  d.Value(recurringOccurrenceOverridden ?? false),
              reconciledAt: d.Value(reconciledAt),
              deferredPostingAt: d.Value(deferredPostingAt),
            ),
          );
      // 写回 cache,后续同 syncId 的 update change 能命中
      activePullCache?.putTransaction(syncId, id, createdByUserId);
      // 同步标签和附件(新插入路径 — existing 必空,跳过相关 SELECT/DELETE)
      await _syncTransactionTags(id, syncId, payload, isNewlyInserted: true);
      await _syncTransactionAttachments(id, payload, isNewlyInserted: true);
      logger.debug('SyncEngine', 'pull: 新增交易 $syncId');
    }
  }

  Future<void> _applyAccountChange(BeeCountCloudSyncChange change) async {
    final syncId = change.entitySyncId;
    // ledger_id 也按 syncId 映射到本地 int。account 表 ledgerId 是 legacy
    // 字段，但 insert 时仍需填个有效值；映射失败再 fallback 到旧格式。
    final ledgerIdInt = await _resolveLedgerIdBySyncId(change.ledgerId) ??
        int.tryParse(change.ledgerId) ??
        -1;

    if (change.action == 'delete') {
      final existing = await (db.select(db.accounts)
            ..where((a) => a.syncId.equals(syncId)))
          .getSingleOrNull();
      if (existing != null) {
        await (db.delete(db.accounts)..where((a) => a.id.equals(existing.id)))
            .go();
        logger.debug('SyncEngine', 'pull: 删除账户 $syncId');
      }
      return;
    }

    // upsert
    final payload = change.payload!;
    // web 端 PATCH /accounts/{id} 用 `model_dump(exclude_unset=True)`
    // (routers/write/accounts.py::update_acc),只送用户实际改动的字段 ——
    // 广播给其它设备的 SyncChange.payload 就是这份 partial dict,不是
    // server 自己 merge 出的全量快照(那份只写回 server 自己的 projection,
    // 见 sync_applier.py::_merge_from_spec / merge_with_existing_user)。
    // 所以本端 apply **必须**对每个字段做 containsKey 保护,缺键 → 保留本地
    // 现值,不能落 ?? 默认值 —— 否则"web 只改 parentAccountId"这类 partial
    // 更新会把本地已有的 type/currency 等字段冲成 'cash'/'CNY'(实测事故:
    // 信用卡群组子卡被冲成现金+人民币)。跟 hidden/parentAccountId 同款
    // containsKey 范式,这里对齐到其余全部字段。
    final hasNameKey = payload.containsKey('name');
    final name = payload['name'] as String? ?? '';
    final hasTypeKey = payload.containsKey('type');
    final type = payload['type'] as String? ?? 'cash';
    final hasCurrencyKey = payload.containsKey('currency');
    final currency = payload['currency'] as String? ?? 'CNY';
    final hasInitialBalanceKey = payload.containsKey('initialBalance');
    final initialBalance =
        (payload['initialBalance'] as num?)?.toDouble() ?? 0.0;
    final hasSortOrderKey = payload.containsKey('sortOrder');
    final sortOrder = (payload['sortOrder'] as num?)?.toInt() ?? 0;
    final hasCreditLimitKey = payload.containsKey('creditLimit');
    final creditLimit = (payload['creditLimit'] as num?)?.toDouble();
    final hasBillingDayKey = payload.containsKey('billingDay');
    final billingDay = (payload['billingDay'] as num?)?.toInt();
    final hasPaymentDueDayKey = payload.containsKey('paymentDueDay');
    final paymentDueDay = (payload['paymentDueDay'] as num?)?.toInt();
    final hasBankNameKey = payload.containsKey('bankName');
    final bankName = payload['bankName'] as String?;
    final hasCardLastFourKey = payload.containsKey('cardLastFour');
    final cardLastFour = payload['cardLastFour'] as String?;
    final hasNoteKey = payload.containsKey('note');
    final note = payload['note'] as String?;

    // 账户隐藏(#240,D6 缺键保留):payload 不含该键 → null → update 走
    // Value.absent() 不覆盖本地;含键(包括显式 false)→ 覆盖。insert 路径
    // 缺键落默认 false(照抄交易 flags 的 containsKey 范式,见
    // _applyTransactionChange)。
    final hidden = payload.containsKey('hidden')
        ? (payload['hidden'] as bool? ?? false)
        : null;

    // 主帳戶(合併帳單,§2.9 Phase 4):跟 hidden 同款 containsKey 保护 ——
    // 老版本 App / 早于本次改动落的历史 sync_change 没有这个键,不能把
    // d.Value(null) 无条件写进去抹掉本地已经建好的挂靠关系。本端 App 自己
    // push 时(entity_serializer.dart)一律无条件带 ''/真实 syncId,所以正常
    // 情况下这个键总是存在。
    final hasParentAccountIdKey = payload.containsKey('parentAccountId');
    final parentAccountIdRaw =
        hasParentAccountIdKey ? payload['parentAccountId'] as String? : null;
    final parentAccountId =
        (parentAccountIdRaw == null || parentAccountIdRaw.isEmpty)
            ? null
            : parentAccountIdRaw;

    var existing = await (db.select(db.accounts)
          ..where((a) => a.syncId.equals(syncId)))
        .getSingleOrNull();

    // Fallback：syncId 查不到 → 本地可能是 seed 默认账户（syncId 为 NULL），
    // 按 name 匹配一条 NULL syncId 的行，把 syncId 补上，后面走 update 分支。
    // 这样 device B 首次 pull 远端账户不会再插第二份同名 seed。
    if (existing == null && name.isNotEmpty) {
      final seeded = await (db.select(db.accounts)
            ..where((a) => a.name.equals(name))
            ..where((a) => a.syncId.isNull()))
          .getSingleOrNull();
      if (seeded != null) {
        await (db.update(db.accounts)..where((a) => a.id.equals(seeded.id)))
            .write(AccountsCompanion(syncId: d.Value(syncId)));
        existing = seeded;
        logger.info(
            'SyncEngine', 'pull: 收编本地 seed 账户 name="$name" → syncId=$syncId');
      }
    }

    // 帳戶頭像:跟分类自定义图标同一套"文件名嵌 fileId,已下载就跳过"策略
    // (见下面 'category' 分支的详细注释)。avatarCloudFileId:
    //   非空字串 → 有云端头像,本地没有(或对不上)就入队下载
    //   空字串   → 用户主动清空头像 → 本地 avatarPath 也清空
    //   键缺失(null)→ 本次 push 头像上传暂时失败 / 老数据,不动本地
    final avatarCloudFileId = payload['avatarCloudFileId'] as String?;
    String? resolvedAvatarPath;
    bool needAvatarDownload = false;
    if (avatarCloudFileId != null && avatarCloudFileId.isNotEmpty) {
      if (existing != null &&
          (existing.avatarPath ?? '').contains(avatarCloudFileId)) {
        resolvedAvatarPath = existing.avatarPath;
      } else {
        resolvedAvatarPath = null;
        needAvatarDownload = true;
      }
    } else if (avatarCloudFileId == '') {
      resolvedAvatarPath = null;
    } else {
      resolvedAvatarPath = existing?.avatarPath;
    }

    final int localId;
    if (existing != null) {
      localId = existing.id;
      await (db.update(db.accounts)..where((a) => a.id.equals(localId)))
          .write(AccountsCompanion(
        name: hasNameKey ? d.Value(name) : const d.Value.absent(),
        type: hasTypeKey ? d.Value(type) : const d.Value.absent(),
        currency: hasCurrencyKey ? d.Value(currency) : const d.Value.absent(),
        initialBalance: hasInitialBalanceKey
            ? d.Value(initialBalance)
            : const d.Value.absent(),
        sortOrder:
            hasSortOrderKey ? d.Value(sortOrder) : const d.Value.absent(),
        creditLimit:
            hasCreditLimitKey ? d.Value(creditLimit) : const d.Value.absent(),
        billingDay:
            hasBillingDayKey ? d.Value(billingDay) : const d.Value.absent(),
        paymentDueDay: hasPaymentDueDayKey
            ? d.Value(paymentDueDay)
            : const d.Value.absent(),
        bankName: hasBankNameKey ? d.Value(bankName) : const d.Value.absent(),
        cardLastFour:
            hasCardLastFourKey ? d.Value(cardLastFour) : const d.Value.absent(),
        note: hasNoteKey ? d.Value(note) : const d.Value.absent(),
        hidden: hidden == null ? const d.Value.absent() : d.Value(hidden),
        parentAccountId: hasParentAccountIdKey
            ? d.Value(parentAccountId)
            : const d.Value.absent(),
        avatarPath: d.Value(resolvedAvatarPath),
      ));
      logger.debug('SyncEngine', 'pull: 更新账户 $syncId');
    } else {
      localId = await db.into(db.accounts).insert(
            AccountsCompanion.insert(
              ledgerId: ledgerIdInt,
              name: name,
              type: d.Value(type),
              currency: d.Value(currency),
              initialBalance: d.Value(initialBalance),
              sortOrder: d.Value(sortOrder),
              creditLimit: d.Value(creditLimit),
              billingDay: d.Value(billingDay),
              paymentDueDay: d.Value(paymentDueDay),
              bankName: d.Value(bankName),
              cardLastFour: d.Value(cardLastFour),
              note: d.Value(note),
              syncId: d.Value(syncId),
              hidden: d.Value(hidden ?? false),
              parentAccountId: d.Value(parentAccountId),
              avatarPath: d.Value(resolvedAvatarPath),
            ),
          );
      activePullCache?.putAccount(syncId, localId);
      logger.debug('SyncEngine', 'pull: 新增账户 $syncId');
    }

    // 入队头像下载任务,主事务 commit 后由 drainAccountAvatarQueue 并发处理,
    // 跟分类自定义图标(drainCustomIconQueue)同一套并发/重试机制。
    if (needAvatarDownload && avatarCloudFileId != null) {
      pendingAccountAvatarJobs.add(AccountAvatarDownloadJob(
        accountId: localId,
        cloudFileId: avatarCloudFileId,
      ));
    }

    // 登记"已从 server 拉到本地"的标记,防止 _backfillLegacyUserGlobalChanges
    // 误把 device B pull 来的实体当 legacy 重推。详见 [ChangeTracker.recordPulledFromServer]。
    await changeTracker.recordPulledFromServer(
      entityType: 'account',
      entityId: localId,
      entitySyncId: syncId,
      ledgerId: 0,
    );
  }

  Future<void> _applyCategoryChange(BeeCountCloudSyncChange change) async {
    final syncId = change.entitySyncId;

    if (change.action == 'delete') {
      final existing = await (db.select(db.categories)
            ..where((c) => c.syncId.equals(syncId)))
          .getSingleOrNull();
      if (existing != null) {
        // 先收集自身 + 子分类的 customIconPath 清磁盘。跟 LocalCategoryRepository
        // .deleteCategory 路径对齐,防止 sync pull 下来的分类删除留下孤立图标。
        await _cleanupCategoryIconFilesOnDisk([existing.id]);
        // 先删子分类再删自身(跟 LocalCategoryRepository 一致)
        await (db.delete(db.categories)
              ..where((c) => c.parentId.equals(existing.id)))
            .go();
        await (db.delete(db.categories)..where((c) => c.id.equals(existing.id)))
            .go();
        logger.debug('SyncEngine', 'pull: 删除分类 $syncId');
      }
      return;
    }

    // upsert
    final payload = change.payload!;
    final name = payload['name'] as String? ?? '';
    final kind = payload['kind'] as String? ?? 'expense';
    final level = (payload['level'] as num?)?.toInt() ?? 1;
    final sortOrder = (payload['sortOrder'] as num?)?.toInt() ?? 0;
    final icon = payload['icon'] as String?;
    final iconType = payload['iconType'] as String? ?? 'material';
    final parentName = payload['parentName'] as String?;

    // 解析 parentId
    int? parentId;
    if (parentName != null && parentName.isNotEmpty) {
      final parent = await (db.select(db.categories)
            ..where((c) => c.name.equals(parentName))
            ..where((c) => c.kind.equals(kind))
            ..where((c) => c.level.equals(1)))
          .getSingleOrNull();
      parentId = parent?.id;
    }

    var existing = await (db.select(db.categories)
          ..where((c) => c.syncId.equals(syncId)))
        .getSingleOrNull();

    // Fallback：syncId 查不到 → 本地可能是 seed 默认分类（syncId 为 NULL）。
    // 按 name + kind 匹配 NULL syncId 行，把 syncId 补上。避免 device B 首次
    // pull 远端分类插第二份同名 seed。
    if (existing == null && name.isNotEmpty) {
      final seeded = await (db.select(db.categories)
            ..where((c) => c.name.equals(name))
            ..where((c) => c.kind.equals(kind))
            ..where((c) => c.syncId.isNull()))
          .getSingleOrNull();
      if (seeded != null) {
        await (db.update(db.categories)..where((c) => c.id.equals(seeded.id)))
            .write(CategoriesCompanion(syncId: d.Value(syncId)));
        existing = seeded;
        logger.info('SyncEngine',
            'pull: 收编本地 seed 分类 name="$name" kind=$kind → syncId=$syncId');
      }
    }

    // §Phase 3:自定义图标的 customIconPath 处理。
    //
    // payload.customIconPath 是 **A 端的本地路径**(如 "custom_icons/12_172123.png"),
    // 直接写进本地 categories 表 → B 端 UI 读取时拼绝对路径 → 文件不存在 →
    // 显示无图标。所以**绝不能直接落 server 推下来的 path**。
    //
    // 正确策略:
    //   - 本地已有同 cloudFileId 的图标文件(existing.customIconPath 含 fileId)→
    //     保留 existing.customIconPath,不入队
    //   - 否则:apply 内 customIconPath 写 null(或保持 existing 旧值),把下载
    //     任务入队 [pendingCustomIconJobs];事务 commit 后 drainCustomIconQueue
    //     并发下载,完成时写真正的 B 端路径 "custom_icons/<fileId>.<ext>"
    //
    // 这样即使 drain 半路失败 / app 重启,UI 看到的是"无 icon"(占位)而不是
    // "指向不存在文件的死链接",且下次 sync 同 entity 再来一遍 change 时,
    // 入队条件命中(existing.customIconPath 仍不含 fileId)会重新下载。
    final cloudFileId = payload['iconCloudFileId'] as String?;
    String? resolvedCustomIconPath;
    bool needIconDownload = false;
    if (iconType == 'custom' && cloudFileId != null && cloudFileId.isNotEmpty) {
      if (existing != null &&
          (existing.customIconPath ?? '').contains(cloudFileId)) {
        // 本地已下载,保留路径,不重新下
        resolvedCustomIconPath = existing.customIconPath;
      } else {
        // 还没下载:写 null,等 drain 写本地路径
        resolvedCustomIconPath = null;
        needIconDownload = true;
      }
    } else if (iconType != 'custom') {
      // 非 custom(material / community)— customIconPath 不适用
      resolvedCustomIconPath = null;
    } else {
      // iconType=custom 但没 cloudFileId(老数据):保留 existing path 兜底
      resolvedCustomIconPath = existing?.customIconPath;
    }

    int? localCategoryId;
    if (existing != null) {
      localCategoryId = existing.id;
      await (db.update(db.categories)
            ..where((c) => c.id.equals(localCategoryId!)))
          .write(CategoriesCompanion(
        name: d.Value(name),
        kind: d.Value(kind),
        level: d.Value(level),
        sortOrder: d.Value(sortOrder),
        icon: d.Value(icon),
        iconType: d.Value(iconType),
        customIconPath: d.Value(resolvedCustomIconPath),
        communityIconId: d.Value(payload['communityIconId'] as String?),
        parentId: d.Value(parentId),
      ));
      logger.debug('SyncEngine', 'pull: 更新分类 $syncId');
    } else {
      localCategoryId = await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              name: name,
              kind: kind,
              level: d.Value(level),
              sortOrder: d.Value(sortOrder),
              icon: d.Value(icon),
              iconType: d.Value(iconType),
              customIconPath: d.Value(resolvedCustomIconPath),
              communityIconId: d.Value(payload['communityIconId'] as String?),
              parentId: d.Value(parentId),
              syncId: d.Value(syncId),
            ),
          );
      activePullCache?.putCategory(syncId, localCategoryId);
      logger.debug('SyncEngine', 'pull: 新增分类 $syncId');
    }

    // §Phase 3:入队下载任务,主事务 commit 后由 drainCustomIconQueue 并发处理。
    // needIconDownload 为 true 说明本地没有同 cloudFileId 的图标文件,
    // 此时 categories.customIconPath 已经写成 null,drain 完成后写真本地路径。
    if (needIconDownload && cloudFileId != null) {
      pendingCustomIconJobs.add(CustomIconDownloadJob(
        categoryId: localCategoryId,
        cloudFileId: cloudFileId,
        expectedPath: payload['customIconPath'] as String?,
      ));
    }

    // 登记"已从 server 拉到本地"标记,见 [_applyAccountChange] 同款注释。
    await changeTracker.recordPulledFromServer(
      entityType: 'category',
      entityId: localCategoryId,
      entitySyncId: syncId,
      ledgerId: 0,
    );
  }

  Future<void> _applyTagChange(BeeCountCloudSyncChange change) async {
    final syncId = change.entitySyncId;

    if (change.action == 'delete') {
      final existing = await (db.select(db.tags)
            ..where((t) => t.syncId.equals(syncId)))
          .getSingleOrNull();
      if (existing != null) {
        // 删除关联的 transactionTags
        await (db.delete(db.transactionTags)
              ..where((tt) => tt.tagId.equals(existing.id)))
            .go();
        await (db.delete(db.tags)..where((t) => t.id.equals(existing.id))).go();
        logger.debug('SyncEngine', 'pull: 删除标签 $syncId');
      }
      return;
    }

    // upsert
    final payload = change.payload!;
    final name = payload['name'] as String? ?? '';
    final color = payload['color'] as String?;
    final sortOrder = (payload['sortOrder'] as num?)?.toInt() ?? 0;

    var existing = await (db.select(db.tags)
          ..where((t) => t.syncId.equals(syncId)))
        .getSingleOrNull();

    // Fallback：syncId 查不到 → 按 name 匹配 NULL syncId 的 seed 行。
    if (existing == null && name.isNotEmpty) {
      final seeded = await (db.select(db.tags)
            ..where((t) => t.name.equals(name))
            ..where((t) => t.syncId.isNull()))
          .getSingleOrNull();
      if (seeded != null) {
        await (db.update(db.tags)..where((t) => t.id.equals(seeded.id)))
            .write(TagsCompanion(syncId: d.Value(syncId)));
        existing = seeded;
        logger.info(
            'SyncEngine', 'pull: 收编本地 seed 标签 name="$name" → syncId=$syncId');
      }
    }

    final int localId;
    if (existing != null) {
      localId = existing.id;
      await (db.update(db.tags)..where((t) => t.id.equals(localId)))
          .write(TagsCompanion(
        name: d.Value(name),
        color: d.Value(color),
        sortOrder: d.Value(sortOrder),
      ));
      logger.debug('SyncEngine', 'pull: 更新标签 $syncId');
    } else {
      localId = await db.into(db.tags).insert(
            TagsCompanion.insert(
              name: name,
              color: d.Value(color),
              sortOrder: d.Value(sortOrder),
              syncId: d.Value(syncId),
            ),
          );
      activePullCache?.putTag(syncId, localId);
      logger.debug('SyncEngine', 'pull: 新增标签 $syncId');
    }

    // 登记"已从 server 拉到本地"标记,见 [_applyAccountChange] 同款注释。
    await changeTracker.recordPulledFromServer(
      entityType: 'tag',
      entityId: localId,
      entitySyncId: syncId,
      ledgerId: 0,
    );
  }

  /// 应用预算变更。对齐 account/tag:按 syncId upsert,delete 走同样的路径。
  /// ledger/category 的外键在 payload 里以 syncId 形式带来,用
  /// _resolveLedgerIdBySyncId / _resolveCategoryIdBySyncId 换成本地 int id。
  Future<void> _applyBudgetChange(BeeCountCloudSyncChange change) async {
    final syncId = change.entitySyncId;

    if (change.action == 'delete') {
      final existing = await (db.select(db.budgets)
            ..where((b) => b.syncId.equals(syncId)))
          .getSingleOrNull();
      if (existing != null) {
        await (db.delete(db.budgets)..where((b) => b.id.equals(existing.id)))
            .go();
        logger.debug('SyncEngine', 'pull: 删除预算 $syncId');
      }
      return;
    }

    // upsert
    final payload = change.payload!;
    final ledgerSyncId = payload['ledgerSyncId'] as String?;
    final categorySyncId = payload['categoryId'] as String?;
    final type = payload['type'] as String? ?? 'total';
    final amount = (payload['amount'] as num?)?.toDouble() ?? 0.0;
    final period = payload['period'] as String? ?? 'monthly';
    final startDay = (payload['startDay'] as num?)?.toInt() ?? 1;
    final enabled = payload['enabled'] as bool? ?? true;

    // 先解析外键 —— 本地 ledger 找不到就 skip,等 ledger change 先到再说。
    final localLedgerId = await _resolveLedgerIdBySyncId(ledgerSyncId);
    if (localLedgerId == null) {
      logger.info('SyncEngine',
          'pull: 预算 $syncId 的 ledgerSyncId=$ledgerSyncId 本地未就绪,跳过');
      return;
    }
    final localCategoryId = await _resolveCategoryIdBySyncId(categorySyncId);

    final existing = await (db.select(db.budgets)
          ..where((b) => b.syncId.equals(syncId)))
        .getSingleOrNull();

    if (existing != null) {
      await (db.update(db.budgets)..where((b) => b.id.equals(existing.id)))
          .write(BudgetsCompanion(
        ledgerId: d.Value(localLedgerId),
        type: d.Value(type),
        categoryId: d.Value(localCategoryId),
        amount: d.Value(amount),
        period: d.Value(period),
        startDay: d.Value(startDay),
        enabled: d.Value(enabled),
        updatedAt: d.Value(DateTime.now()),
      ));
      logger.debug('SyncEngine', 'pull: 更新预算 $syncId');
    } else {
      await db.into(db.budgets).insert(BudgetsCompanion.insert(
            ledgerId: localLedgerId,
            type: d.Value(type),
            categoryId: d.Value(localCategoryId),
            amount: amount,
            period: d.Value(period),
            startDay: d.Value(startDay),
            enabled: d.Value(enabled),
            syncId: d.Value(syncId),
          ));
      logger.debug('SyncEngine', 'pull: 新增预算 $syncId');
    }
  }

  /// 應用週期性收支規則(v36,對齐 BeeCount Cloud recurring_rule)变更。
  /// ledger-scope,跟 [_applyBudgetChange] 同款「全量覆盖」語意——本端
  /// [EntitySerializer.serializeRecurringRule] push 时已经恆發規則的完整
  /// 當前值(BeeCount Cloud `_LEDGER_MERGE_SPECS["recurring_rule"]` 缺鍵才
  /// 由 server 補齐既有值),这里不用做 containsKey 保護。
  ///
  /// 規則生成的 occurrence 交易走既有 [_applyTransactionChange] 路徑(認得
  /// payload 里的 `recurringRuleId`/`recurringOccurrenceOverridden` 两个键
  /// 即可),这里只处理規則本身那一列。
  ///
  /// 範圍決策(2026-08-17):不解析 `projectId` /
  /// `baseAmount`/`feeAmount`/`feeLabel`/`discountAmount`/`discountLabel`
  /// ——App 端尚未實作,本地表也没有对应列,即使远端(Web)帶了這些欄位也
  /// 直接忽略。
  Future<void> _applyRecurringRuleChange(BeeCountCloudSyncChange change) async {
    final syncId = change.entitySyncId;

    if (change.action == 'delete') {
      final existing = await (db.select(db.recurringTransactions)
            ..where((r) => r.syncId.equals(syncId)))
          .getSingleOrNull();
      if (existing != null) {
        await (db.delete(db.recurringTransactions)
              ..where((r) => r.id.equals(existing.id)))
            .go();
        logger.debug('SyncEngine', 'pull: 刪除週期規則 $syncId');
      }
      return;
    }

    // upsert —— 跟 transaction/account 同款:change.ledgerId 是 server 的
    // external_id(string),recurring_rule payload 本身不带 ledgerSyncId
    // (Cloud merge spec 没有这个键,靠信封层的 ledger_id 反查)。
    final ledgerIdInt = await _resolveLedgerIdBySyncId(change.ledgerId) ??
        int.tryParse(change.ledgerId);
    if (ledgerIdInt == null) {
      logger.info('SyncEngine',
          'pull: 週期規則 $syncId 的 ledgerId=${change.ledgerId} 本地未就绪,跳过');
      return;
    }

    final payload = change.payload!;
    final type = payload['txType'] as String? ?? 'expense';
    final amount = (payload['amount'] as num?)?.toDouble() ?? 0.0;
    final note = payload['note'] as String?;
    final merchant = payload['merchant'] as String?;
    final frequency = payload['frequency'] as String? ?? 'monthly';
    final interval = (payload['interval'] as num?)?.toInt() ?? 1;
    final nextRunAtStr = payload['nextRunAt'] as String?;
    final nextRunAt = nextRunAtStr != null
        ? DateTime.tryParse(nextRunAtStr)?.toLocal() ?? DateTime.now()
        : DateTime.now();
    final endAtStr = payload['endAt'] as String?;
    final endAt =
        endAtStr != null ? DateTime.tryParse(endAtStr)?.toLocal() : null;
    final generatedUntilAtStr = payload['generatedUntilAt'] as String?;
    final generatedUntilAt = generatedUntilAtStr != null
        ? DateTime.tryParse(generatedUntilAtStr)?.toLocal()
        : null;
    final enabled = payload['enabled'] as bool? ?? true;

    // advancedRuleJson 在 wire 上是解码后的 Map(同 Cloud snapshot_builder 的
    // 形状),本地存 TEXT 列——这里重新 json.encode 回字串落库。防御性地也接受
    // 已经是字串的情况(理论上不该出现,但不因为格式意外而整条规则 apply 失败)。
    final rawAdvancedRule = payload['advancedRuleJson'];
    String? advancedRuleJson;
    if (rawAdvancedRule is Map || rawAdvancedRule is List) {
      advancedRuleJson = jsonEncode(rawAdvancedRule);
    } else if (rawAdvancedRule is String && rawAdvancedRule.isNotEmpty) {
      advancedRuleJson = rawAdvancedRule;
    }

    final categorySyncId = payload['categoryId'] as String?;
    final localCategoryId = await _resolveCategoryIdBySyncId(categorySyncId);
    final accountSyncId = payload['accountId'] as String?;
    final localAccountId = await _resolveAccountIdBySyncId(accountSyncId);
    final fromAccountSyncId = payload['fromAccountId'] as String?;
    final localFromAccountId =
        await _resolveAccountIdBySyncId(fromAccountSyncId);
    final toAccountSyncId = payload['toAccountId'] as String?;
    final localToAccountId = await _resolveAccountIdBySyncId(toAccountSyncId);

    final rawTagIds = payload['tagIds'];
    final tagSyncIdsJson = (rawTagIds is List && rawTagIds.isNotEmpty)
        ? jsonEncode(rawTagIds.whereType<String>().toList())
        : null;
    final rawRewardRuleIds = payload['rewardRuleIds'];
    final rewardRuleIdsJson =
        (rawRewardRuleIds is List && rawRewardRuleIds.isNotEmpty)
            ? jsonEncode(rawRewardRuleIds.whereType<String>().toList())
            : null;

    final existing = await (db.select(db.recurringTransactions)
          ..where((r) => r.syncId.equals(syncId)))
        .getSingleOrNull();

    final companion = RecurringTransactionsCompanion(
      ledgerId: d.Value(ledgerIdInt),
      type: d.Value(type),
      amount: d.Value(amount),
      note: d.Value(note),
      merchant: d.Value(merchant),
      categoryId: d.Value(localCategoryId),
      accountId: d.Value(localAccountId),
      fromAccountId: d.Value(localFromAccountId),
      toAccountId: d.Value(localToAccountId),
      tagSyncIdsJson: d.Value(tagSyncIdsJson),
      rewardRuleIdsJson: d.Value(rewardRuleIdsJson),
      frequency: d.Value(frequency),
      interval: d.Value(interval),
      advancedRuleJson: d.Value(advancedRuleJson),
      nextRunAt: d.Value(nextRunAt),
      endAt: d.Value(endAt),
      generatedUntilAt: d.Value(generatedUntilAt),
      enabled: d.Value(enabled),
      updatedAt: d.Value(DateTime.now()),
    );

    if (existing != null) {
      await (db.update(db.recurringTransactions)
            ..where((r) => r.id.equals(existing.id)))
          .write(companion);
      logger.debug('SyncEngine', 'pull: 更新週期規則 $syncId');
    } else {
      await db.into(db.recurringTransactions).insert(
            companion.copyWith(
              syncId: d.Value(syncId),
              createdAt: d.Value(DateTime.now()),
            ),
          );
      logger.debug('SyncEngine', 'pull: 新增週期規則 $syncId');
    }
  }

  /// 应用信用卡紅利回饋規則变更。user-global 实体,按 syncId upsert,跟
  /// account/tag 同款「全量覆盖」路径——App 自己 push 时(entity_serializer.dart
  /// serializeCardRewardRule)本来就无条件带出全部字段的当前真值,对齐
  /// BeeCount Cloud `projection.upsert_card_reward_rule` 的全量 UPSERT 语义
  /// (不是 partial merge,见该方法注释),这里 apply 不需要 containsKey 保护。
  ///
  /// 绑定的信用卡帐户(accountId)本地还没同步到时:先跳过,留给下次 pull
  /// 重试(账户是 user-global 实体,通常紧跟着一起推/拉,极少长期缺失)。
  Future<void> _applyCardRewardRuleChange(
      BeeCountCloudSyncChange change) async {
    final syncId = change.entitySyncId;

    if (change.action == 'delete') {
      final existing = await (db.select(db.cardRewardRules)
            ..where((r) => r.syncId.equals(syncId)))
          .getSingleOrNull();
      if (existing != null) {
        await (db.delete(db.cardRewardRules)
              ..where((r) => r.id.equals(existing.id)))
            .go();
        logger.debug('SyncEngine', 'pull: 删除信用卡紅利回饋規則 $syncId');
      }
      return;
    }

    final payload = change.payload!;
    final accountSyncId = payload['accountId'] as String?;
    final localAccountId = await _resolveAccountIdBySyncId(accountSyncId);
    if (localAccountId == null) {
      logger.info('SyncEngine',
          'pull: 紅利回饋規則 $syncId 的 accountId=$accountSyncId 本地未就绪,跳过');
      return;
    }

    final label = payload['label'] as String? ?? '';
    final rawCategoryIds = payload['categoryIds'];
    final categoryIdsJson =
        (rawCategoryIds is List && rawCategoryIds.isNotEmpty)
            ? jsonEncode(rawCategoryIds.whereType<String>().toList())
            : null;
    final rateType = payload['rateType'] as String? ?? 'percentage';
    final rateValue = (payload['rateValue'] as num?)?.toDouble() ?? 0.0;
    final rounding = payload['rounding'] as String? ?? 'round';
    final totalRounding = payload['totalRounding'] as String? ?? 'round';
    final calcBasis = payload['calcBasis'] as String? ?? 'transaction_date';
    final interval = payload['interval'] as String? ?? 'billing_cycle';
    final minSpendThreshold =
        (payload['minSpendThreshold'] as num?)?.toDouble();
    final minTxAmount = (payload['minTxAmount'] as num?)?.toDouble();
    final capAmount = (payload['capAmount'] as num?)?.toDouble();
    final capSharedKey = payload['capSharedKey'] as String?;
    final startsAt = (payload['startsAt'] as String?) != null
        ? DateTime.tryParse(payload['startsAt'] as String)?.toLocal()
        : null;
    final endsAt = (payload['endsAt'] as String?) != null
        ? DateTime.tryParse(payload['endsAt'] as String)?.toLocal()
        : null;
    final settlementType = payload['settlementType'] as String? ?? 'manual';
    final settlementDays = (payload['settlementDays'] as num?)?.toInt();
    final settlementMonthOffset =
        (payload['settlementMonthOffset'] as num?)?.toInt();
    final settlementDayOfMonth =
        (payload['settlementDayOfMonth'] as num?)?.toInt();
    final rewardAccountSyncId = payload['rewardAccountId'] as String?;
    final localRewardAccountId =
        await _resolveAccountIdBySyncId(rewardAccountSyncId);
    final note = payload['note'] as String?;
    final enabled = payload['enabled'] as bool? ?? true;

    final existing = await (db.select(db.cardRewardRules)
          ..where((r) => r.syncId.equals(syncId)))
        .getSingleOrNull();

    final companion = CardRewardRulesCompanion(
      accountId: d.Value(localAccountId),
      label: d.Value(label),
      categoryIdsJson: d.Value(categoryIdsJson),
      rateType: d.Value(rateType),
      rateValue: d.Value(rateValue),
      rounding: d.Value(rounding),
      totalRounding: d.Value(totalRounding),
      calcBasis: d.Value(calcBasis),
      interval: d.Value(interval),
      minSpendThreshold: d.Value(minSpendThreshold),
      minTxAmount: d.Value(minTxAmount),
      capAmount: d.Value(capAmount),
      capSharedKey: d.Value(capSharedKey),
      startsAt: d.Value(startsAt),
      endsAt: d.Value(endsAt),
      settlementType: d.Value(settlementType),
      settlementDays: d.Value(settlementDays),
      settlementMonthOffset: d.Value(settlementMonthOffset),
      settlementDayOfMonth: d.Value(settlementDayOfMonth),
      rewardAccountId: d.Value(localRewardAccountId),
      note: d.Value(note),
      enabled: d.Value(enabled),
      updatedAt: d.Value(DateTime.now()),
    );

    final int localId;
    if (existing != null) {
      localId = existing.id;
      await (db.update(db.cardRewardRules)..where((r) => r.id.equals(localId)))
          .write(companion);
      logger.debug('SyncEngine', 'pull: 更新紅利回饋規則 $syncId');
    } else {
      localId = await db.into(db.cardRewardRules).insert(
            companion.copyWith(
              syncId: d.Value(syncId),
              createdAt: d.Value(DateTime.now()),
            ),
          );
      logger.debug('SyncEngine', 'pull: 新增紅利回饋規則 $syncId');
    }

    await changeTracker.recordPulledFromServer(
      entityType: 'card_reward_rule',
      entityId: localId,
      entitySyncId: syncId,
      ledgerId: 0,
    );
  }

  /// 按币对收敛:双端离线各建同币对会产生两个 syncId,按 syncId insert 会撞
  /// idx_rate_override_pair 唯一索引;按币对 upsert + 吸收来包 syncId/updatedAt
  /// 实现收敛。
  ///
  /// 按币对收敛 + 依赖 pull 的 change_id 递增顺序实现 LWW(updatedAt 仅落库,
  /// 不参与决胜 —— 不要加 "incoming.updatedAt < existing.updatedAt 则跳过" 的
  /// 守卫,那会破坏 replayAllChanges 从 since=0 的重放)。
  ///
  /// apply 直写 db(本文件是 CLAUDE.md 白名单例外),不走 repo → 不记 change,
  /// 防反向 push。
  Future<void> _applyExchangeRateOverrideChange(
      BeeCountCloudSyncChange change) async {
    if (change.action == 'delete') {
      // delete 按 syncId 精确匹配:币对收敛把行的 syncId 换成新值后,
      // 针对旧 syncId 的 delete 是有意的 no-op(该币对已有更新的 override 存活)。
      await (db.delete(db.exchangeRateOverrides)
            ..where((t) => t.syncId.equals(change.entitySyncId)))
          .go();
      return;
    }
    final p = change.payload!;
    final base = (p['baseCurrency'] as String?)?.toUpperCase();
    final quote = (p['quoteCurrency'] as String?)?.toUpperCase();
    final rate = p['rate']?.toString();
    if (base == null || quote == null || rate == null || rate.isEmpty) {
      logger.warning('SyncEngine', 'exchange_rate_override payload 缺字段,跳过');
      return;
    }
    final updatedAt = DateTime.tryParse(p['updatedAt']?.toString() ?? '');
    final existing = await (db.select(db.exchangeRateOverrides)
          ..where((t) =>
              t.baseCurrency.equals(base) & t.quoteCurrency.equals(quote)))
        .getSingleOrNull();
    if (existing == null) {
      await db
          .into(db.exchangeRateOverrides)
          .insert(ExchangeRateOverridesCompanion.insert(
            baseCurrency: base,
            quoteCurrency: quote,
            rate: rate,
            syncId: d.Value(change.entitySyncId),
            updatedAt: d.Value(updatedAt),
          ));
    } else {
      await (db.update(db.exchangeRateOverrides)
            ..where((t) => t.id.equals(existing.id)))
          .write(ExchangeRateOverridesCompanion(
        rate: d.Value(rate),
        syncId: d.Value(change.entitySyncId),
        updatedAt: d.Value(updatedAt),
      ));
    }
  }

  /// 应用远程下发的账本元数据变更(名字 / 币种)。
  ///
  /// 跟其他 entity 不同:不在本地"新建"账本 —— 账本的创建走 fullPush /
  /// ledger_snapshot 路径。这里只负责"已存在的账本"的 meta 更新。找不到
  /// 对应的本地账本就跳过,等快照路径把它 seed 出来后再复用。
  Future<void> _applyLedgerChange(BeeCountCloudSyncChange change) async {
    final syncId = change.entitySyncId;
    if (change.action == 'delete') {
      // 账本删除走 'ledger_snapshot' 的 delete change,这里不处理 —— 避免
      // 跟 ledger_snapshot 重复触发。
      return;
    }
    final payload = change.payload;
    if (payload == null) return;

    // 用 get() 不用 getSingleOrNull(): 历史 bug 可能产生过 dup ledger 同
    // syncId,getSingleOrNull 撞多行抛 "Too many elements" 中断 replay。
    // 取第一行 + 清剩余 dup。
    final ledgerList = await (db.select(db.ledgers)
          ..where((l) => l.syncId.equals(syncId)))
        .get();
    final name = payload['ledgerName'] as String?;
    final currency = payload['currency'] as String?;
    // bool 不是 num,as num? 天然挡掉;越界 clamp。key 缺失 → null →
    // update 路径 Value.absent 不动原值(老 server payload 兼容)。
    final monthStartDay =
        ((payload['monthStartDay'] as num?)?.toInt())?.clamp(1, 28);
    if (ledgerList.isEmpty) {
      // 本地未就绪 — 之前的"跳过等 snapshot 路径"会导致 web 端新建账本时
      // app 拉到 ledger change 但永远不 insert,新账本永远不出现。
      //
      // 现在:payload 至少有 name + currency 时,主动 insert 一行本地
      // ledger。payload 缺关键字段时仍 skip(等下次 syncLedgersFromServer
      // 或 snapshot 拉到完整 meta)。
      if (name == null || name.isEmpty) {
        logger.info('SyncEngine',
            'pull: 账本 $syncId 本地未就绪 + payload 无 name,跳过(等 snapshot)');
        return;
      }
      // insert 必须给值:payload 缺 key 时取列默认 1(与 update 路径的
      // absent 语义不同 —— 新建行没有"原值"可保)。
      await db.into(db.ledgers).insert(LedgersCompanion.insert(
            name: name,
            currency: d.Value(currency ?? 'CNY'),
            syncId: d.Value(syncId),
            monthStartDay: d.Value(monthStartDay ?? 1),
          ));
      logger.info('SyncEngine',
          'pull: 新增账本 syncId=$syncId name=$name currency=${currency ?? "CNY"}');
      activePullCache?.putLedger(
          syncId,
          (await (db.select(db.ledgers)..where((l) => l.syncId.equals(syncId)))
                  .getSingle())
              .id);
      return;
    }
    final ledger = ledgerList.first;
    if (ledgerList.length > 1) {
      final dupIds = ledgerList.skip(1).map((l) => l.id).toList();
      logger.warning('SyncEngine',
          'pull: ledger.syncId=$syncId 撞多行 ${ledgerList.length},清除 dup id=$dupIds');
      await (db.delete(db.transactions)..where((t) => t.ledgerId.isIn(dupIds)))
          .go();
      await (db.delete(db.localChanges)..where((c) => c.ledgerId.isIn(dupIds)))
          .go();
      await (db.delete(db.ledgers)..where((l) => l.id.isIn(dupIds))).go();
    }

    final comp = LedgersCompanion(
      name: name != null ? d.Value(name) : const d.Value.absent(),
      currency: currency != null ? d.Value(currency) : const d.Value.absent(),
      monthStartDay: monthStartDay != null
          ? d.Value(monthStartDay)
          : const d.Value.absent(),
    );
    await (db.update(db.ledgers)..where((l) => l.id.equals(ledger.id)))
        .write(comp);
    logger.debug(
        'SyncEngine', 'pull: 更新账本 $syncId name=$name currency=$currency');
  }

  // ==================== Helper ====================

  /// 同步交易标签关联
  ///
  /// [txSyncId] 是 transaction.syncId(已知,由 caller 传入)— 避免每条 tx
  /// 都 `SELECT FROM transactions WHERE id = ?` 一次拿 syncId,这是 10k 条 =
  /// 10k 次 SELECT 的 N+1 大头。
  /// [isNewlyInserted] 为 true 时表示 transaction 是本次刚 INSERT 的,跳过
  /// "删旧关联"步骤(必然空)。
  Future<void> _syncTransactionTags(
    int transactionId,
    String txSyncId,
    Map<String, dynamic> payload, {
    bool isNewlyInserted = false,
  }) async {
    // 删除旧关联,按新 payload 重建(主表 + override)。新插入路径跳过 — 必空。
    if (!isNewlyInserted) {
      await (db.delete(db.transactionTags)
            ..where((tt) => tt.transactionId.equals(transactionId)))
          .go();
      await (db.delete(db.transactionTagOverrides)
            ..where((t) => t.transactionSyncId.equals(txSyncId)))
          .go();
    }

    final rawTagIds = payload['tagIds'];
    final tagIds = rawTagIds is List
        ? rawTagIds.whereType<String>().toList(growable: false)
        : const <String>[];
    final tagsStr = payload['tags'] as String?;
    final tagNamesFromStr = (tagsStr == null || tagsStr.isEmpty)
        ? const <String>[]
        : tagsStr
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

    final linkedLocalIds = <int>{};
    final overrideSyncIds = <String>{};

    if (tagIds.isNotEmpty) {
      for (var i = 0; i < tagIds.length; i++) {
        final syncId = tagIds[i];
        // 优先查 LookupCache(pull 路径已 prime),消除 N+1 tag SELECT
        final cachedTagId = activePullCache?.tagId(syncId);
        if (cachedTagId != null) {
          linkedLocalIds.add(cachedTagId);
          continue;
        }
        var tag = await (db.select(db.tags)
              ..where((t) => t.syncId.equals(syncId)))
            .getSingleOrNull();
        if (tag != null) {
          activePullCache?.putTag(syncId, tag.id);
          linkedLocalIds.add(tag.id);
          continue;
        }
        // 主表 miss → 查 SharedLedgerTags(Editor 视角看 Owner 的 tx 引用 Owner 的 tag)
        final shared = await (db.select(db.sharedLedgerTags)
              ..where((t) => t.syncId.equals(syncId)))
            .getSingleOrNull();
        if (shared != null) {
          overrideSyncIds.add(syncId);
          continue;
        }
        // 都 miss → name fallback(老协议),建本地 tag
        if (i < tagNamesFromStr.length) {
          final name = tagNamesFromStr[i];
          tag = await (db.select(db.tags)..where((t) => t.name.equals(name)))
              .getSingleOrNull();
          if (tag != null && (tag.syncId ?? '').isEmpty) {
            await (db.update(db.tags)..where((t) => t.id.equals(tag!.id)))
                .write(TagsCompanion(syncId: d.Value(syncId)));
          }
          if (tag != null) {
            activePullCache?.putTag(syncId, tag.id);
            linkedLocalIds.add(tag.id);
          }
        }
      }
    } else {
      // 完全没 tagIds 的老 payload:按 name 查,没有就建个带 syncId 的新 tag
      for (final name in tagNamesFromStr) {
        var tag = await (db.select(db.tags)..where((t) => t.name.equals(name)))
            .getSingleOrNull();
        if (tag == null) {
          final newSyncId = _uuid.v4();
          final id = await db.into(db.tags).insert(
                TagsCompanion.insert(
                  name: name,
                  syncId: d.Value(newSyncId),
                ),
              );
          activePullCache?.putTag(newSyncId, id);
          tag = await (db.select(db.tags)..where((t) => t.id.equals(id)))
              .getSingle();
        }
        linkedLocalIds.add(tag.id);
      }
    }

    // 批量插入 transactionTags + transactionTagOverrides,一次 db.batch
    // (单 fsync) 替代逐条 db.into().insert() (N 次小写入)。
    if (linkedLocalIds.isNotEmpty ||
        (txSyncId.isNotEmpty && overrideSyncIds.isNotEmpty)) {
      final now = DateTime.now().toUtc();
      await db.batch((b) {
        for (final tagId in linkedLocalIds) {
          b.insert(
            db.transactionTags,
            TransactionTagsCompanion.insert(
              transactionId: transactionId,
              tagId: tagId,
            ),
          );
        }
        if (txSyncId.isNotEmpty) {
          for (final sid in overrideSyncIds) {
            b.insert(
              db.transactionTagOverrides,
              TransactionTagOverridesCompanion.insert(
                transactionSyncId: txSyncId,
                tagSyncId: sid,
                createdAt: now,
              ),
            );
          }
        }
      });
    }
  }

  /// 同步交易附件关联（pull 时从 payload 创建/更新/删除本地附件记录）
  ///
  /// payload 里 attachments 的三种情况：
  ///   - 缺失（key 不存在）：legacy 调用 / 没附件信息 → 不动本地
  ///   - `[]`（空数组）：A 端把附件全删光了 → 本地同步删光
  ///   - `[...]`：权威列表 → 本地按 fileName 对齐,多余的删,缺的加
  ///
  /// [isNewlyInserted] 新插入 tx 路径,existing 必空,跳过 SELECT 省 N+1。
  Future<void> _syncTransactionAttachments(
    int transactionId,
    Map<String, dynamic> payload, {
    bool isNewlyInserted = false,
  }) async {
    // key 缺失 → legacy 行为，不碰本地
    if (!payload.containsKey('attachments')) return;
    final attachmentsList =
        (payload['attachments'] as List<dynamic>?) ?? const <dynamic>[];

    // 获取现有附件,按 fileName 索引。新插入路径 existing 必空,跳过 SELECT。
    final existing = isNewlyInserted
        ? const <TransactionAttachment>[]
        : await (db.select(db.transactionAttachments)
              ..where((a) => a.transactionId.equals(transactionId)))
            .get();
    final existingByFileName = {for (final a in existing) a.fileName: a};

    // 远端权威列表里的 fileName 集合
    final remoteFileNames = <String>{};

    // 收集 attachment 增/改/删的操作,统一用 db.batch 一次写,替代逐条
    /// db.into().insert / db.update().write / db.delete().go(N 次小 fsync)。
    final inserts = <TransactionAttachmentsCompanion>[];
    final updates = <({int id, TransactionAttachmentsCompanion data})>[];
    final attachmentsToDeleteFromDisk = <String>[];
    final deleteIds = <int>[];

    for (final att in attachmentsList) {
      final attMap = att as Map<String, dynamic>;
      final fileName = attMap['fileName'] as String? ?? '';
      if (fileName.isEmpty) continue;
      remoteFileNames.add(fileName);

      final cloudFileId = attMap['cloudFileId'] as String?;
      final cloudSha256 = attMap['cloudSha256'] as String?;

      if (existingByFileName.containsKey(fileName)) {
        final ex = existingByFileName[fileName]!;
        if (cloudFileId != null && ex.cloudFileId != cloudFileId) {
          updates.add((
            id: ex.id,
            data: TransactionAttachmentsCompanion(
              cloudFileId: d.Value(cloudFileId),
              cloudSha256: d.Value(cloudSha256),
            ),
          ));
        }
      } else {
        inserts.add(TransactionAttachmentsCompanion.insert(
          transactionId: transactionId,
          fileName: fileName,
          originalName: d.Value(attMap['originalName'] as String?),
          fileSize: d.Value(attMap['fileSize'] as int?),
          width: d.Value(attMap['width'] as int?),
          height: d.Value(attMap['height'] as int?),
          sortOrder: d.Value(attMap['sortOrder'] as int? ?? 0),
          cloudFileId: d.Value(cloudFileId),
          cloudSha256: d.Value(cloudSha256),
        ));
      }
    }

    for (final ex in existing) {
      if (remoteFileNames.contains(ex.fileName)) continue;
      deleteIds.add(ex.id);
      attachmentsToDeleteFromDisk.add(ex.fileName);
    }

    if (inserts.isNotEmpty || updates.isNotEmpty || deleteIds.isNotEmpty) {
      await db.batch((b) {
        if (inserts.isNotEmpty) {
          b.insertAll(db.transactionAttachments, inserts);
        }
        for (final u in updates) {
          b.update<TransactionAttachments, TransactionAttachment>(
            db.transactionAttachments,
            u.data,
            where: ($) => $.id.equals(u.id),
          );
        }
        if (deleteIds.isNotEmpty) {
          b.deleteWhere(db.transactionAttachments, ($) => $.id.isIn(deleteIds));
        }
      });
    }

    // 磁盘清理跑在事务外(IO 失败不影响 DB 状态)
    for (final fn in attachmentsToDeleteFromDisk) {
      try {
        final file = await _getAttachmentFile(fn);
        if (file != null && file.existsSync()) {
          await file.delete();
        }
      } catch (e, st) {
        logger.warning('SyncEngine', '删除本地孤立附件文件失败: $fn', st);
      }
    }
  }
}

// §Phase 3:`_detectIconExtension` 搬到 `attachments.dart`,因为自定义图标
// 下载从 _applyCategoryChange 内部移出,主事务只入队下载任务。原位置的函数
// 不再被任何路径调用,直接删除。
