import 'dart:convert';

import '../../data/db.dart';

/// 实体序列化工具
/// 将本地 Drift 实体转为 JSON payload（用于 sync push）
/// 以及从 JSON payload 还原为本地实体
class EntitySerializer {
  // ==================== Transaction ====================

  static Map<String, dynamic> serializeTransaction(
    Transaction tx, {
    String? categoryName,
    String? categoryKind,
    String? categorySyncId,
    String? accountName,
    String? accountSyncId,
    String? fromAccountName,
    String? fromAccountSyncId,
    String? toAccountName,
    String? toAccountSyncId,
    String? ledgerSyncId,
    List<String>? tagNames,
    List<String>? tagSyncIds,
    List<Map<String, dynamic>>? attachments,
    List<Map<String, dynamic>>? splits,
  }) {
    // 同时带 *Name 和 *Id（syncId）到服务端。服务端的 read 会优先按 id 反查
    // snapshot 里当前 entity 的名字，名字字段只作为历史/兼容兜底。这样任何
    // 实体重命名都不依赖"每个引用位点的 cascade 改写"，兑现"按 id 取实时
    // 名字"的承诺。
    //
    // ledgerSyncId 是跨设备关键：change log 外层的 ledger_id 是推送方的本地
    // int id，对端设备可能匹配不上；payload 里带上 ledger 的 syncId，对端
    // apply 时能先按 syncId 找到本地账本，再用 int id 兜底。
    return {
      'syncId': tx.syncId,
      'type': tx.type,
      'amount': tx.amount,
      'happenedAt': tx.happenedAt.toUtc().toIso8601String(),
      'note': tx.note,
      // v33:商家。跟 note 同规则——恒发(不做 if != null 的省略),让显式 null
      // 能传达"清空商家"给 server(BeeCount Cloud _LEDGER_MERGE_SPECS["transaction"]
      // 已有对应 ("merchant","merchant") merge spec)。
      'merchant': tx.merchant,
      // 账单标记(D2 两个独立 bool)。camelCase 键与 server 端
      // _LEDGER_MERGE_SPECS / projection upsert 对齐 —— 改键名会让标记跨设备静默丢失。
      'excludeFromStats': tx.excludeFromStats,
      'excludeFromBudget': tx.excludeFromBudget,
      // v30 交易级多币种:原币种 + 折账本本位币快照(与 server 0018 两列对齐)。
      // 有值才发:NULL 发出去会被 server merge 视为"不更新"(None 被过滤),
      // 语义等价;省略保持 payload 干净。
      if (tx.currencyCode != null) 'currencyCode': tx.currencyCode,
      if (tx.nativeAmount != null) 'nativeAmount': tx.nativeAmount,
      // v45 跨幣別轉帳:轉入帳戶自己幣別的金額,只有跨幣別轉帳才非 null。
      // 有值才發(同 nativeAmount),wire key 用 camelCase toAmount,對齊
      // Cloud sync_applier.py 的 ("toAmount", "to_amount") merge spec。
      if (tx.toAmount != null) 'toAmount': tx.toAmount,
      // v34:退款关联。有值才发(省略等价"不更新"),wire key 必须是
      // refundOfId —— BeeCount Cloud sync_applier.py 既有 merge spec
      // ("refundOfId", "refund_of_sync_id") 已经这样约定,改键名会让退款
      // 关联跨设备同步不到。
      if (tx.refundOfSyncId != null) 'refundOfId': tx.refundOfSyncId,
      if (ledgerSyncId != null && ledgerSyncId.isNotEmpty)
        'ledgerSyncId': ledgerSyncId,
      'categoryName': categoryName,
      'categoryKind': categoryKind,
      if (categorySyncId != null && categorySyncId.isNotEmpty)
        'categoryId': categorySyncId,
      // null 时用空串而不是省略字段 / null。server _merge_from_spec 过滤
      // None 不过滤空串,空串到 upsert_tx 里 _as_str("") → None,projection
      // 写 NULL。这是"用户在 mobile 选'不选账户'/'清空账户'"能传达给 server
      // 的唯一路径 — 字段省略 / None 都会被 merge 视为"不更新",老 account
      // 永远保留。account_name 也必须空串,否则会看到 account_sync_id=NULL
      // 但 account_name="现金"的不一致状态(web 显示账户名还在 = 像没刷新)。
      // tx 没账户的初始状态(从来没选过)等价于"清空",也走这条逻辑,无害。
      'accountName': accountName ?? '',
      'accountId': accountSyncId ?? '',
      'fromAccountName': fromAccountName ?? '',
      'fromAccountId': fromAccountSyncId ?? '',
      'toAccountName': toAccountName ?? '',
      'toAccountId': toAccountSyncId ?? '',
      if (tagNames != null && tagNames.isNotEmpty) 'tags': tagNames.join(','),
      if (tagSyncIds != null && tagSyncIds.isNotEmpty) 'tagIds': tagSyncIds,
      // 即使是 `[]` 也必须写出来，不能变 null 后被 if-spread 过滤掉。否则
      // A 端删光所有附件时 payload 里完全没有 attachments 字段 → B 端没法
      // 区分"没发送附件信息"和"全删光了"，B 就永远同步不到删除。
      if (attachments != null) 'attachments': attachments,
      // v38 拆帳:同 attachments——恒发(即使 `[]`),否则 A 端把拆帳还原成
      // 单一分类后 B 端没法区分"没发送拆帳信息"和"拆帳被清空了"。
      // BeeCount Cloud 端对应 WriteTransactionCreateRequest.splits /
      // WriteTransactionUpdateRequest.splits(§2.4),wire 字段名 splits,
      // 明細内 categoryId 是分類的 syncId(同上面顶层 categoryId 语义)。
      if (splits != null) 'splits': splits,
      // v35:信用卡紅利回饋——使用者手動勾選的規則 syncId 列表。恒發(即使
      // `[]`)——本地已经用 syncId 存,不用像 tagIds 那样做本地 id→syncId
      // 转换。空 list 代表"这笔交易没有勾选任何回饋规则"(包含用户清空的场景)。
      'rewardRuleIds': tx.rewardRuleIds,
      // v36:週期性收支(recurring_rule)——這筆交易是哪條規則生成的 occurrence。
      // 跟 refundOfId 同款「有值才發」:目前沒有會把這個關聯清空的操作(刪除
      // occurrence 是整筆刪 tx,不是清空這個欄位),省略等價"不更新"。
      if (tx.recurringRuleId != null) 'recurringRuleId': tx.recurringRuleId,
      // 恒發(同 excludeFromStats/excludeFromBudget)——這個 bool 會被
      // 「修改此記錄」單筆改成 true,必須每次都帶上讓對端能同步這個切換。
      'recurringOccurrenceOverridden': tx.recurringOccurrenceOverridden,
      // v37 對帳模式/延後入帳:恒發(不是「有值才發」)——跟 refundOfId 不同,
      // 這兩個欄位有明確的清空動作(取消確認/取消延後入帳),必須讓 null 能
      // 傳達「清空」給 server,對齊 BeeCount Cloud sync_applier.py 的
      // _isoformat_or_none merge spec。省略或只在非 null 時才發會讓「取消」
      // 這個動作永遠同步不出去。
      'reconciledAt': tx.reconciledAt?.toUtc().toIso8601String(),
      'deferredPostingAt': tx.deferredPostingAt?.toUtc().toIso8601String(),
      // v39 借還款:這筆交易關聯的 Debt syncId。恒發(同 reconciledAt)——
      // 交易表單「關聯欠款」下拉的取消連結是明確動作([setTransactionDebtLink]
      // 傳 null),必須讓 null 能傳達給 server。BeeCount Cloud 端字段是
      // read_tx_projection.debt_sync_id,wire 字段名 debtId。
      'debtId': tx.debtSyncId,
      // v44 專案:這筆交易關聯的 Project syncId。恆發(同 debtId)——記帳
      // 表單「選擇專案」的取消連結是明確動作,必須讓 null 能傳達給
      // server。BeeCount Cloud 端字段是 read_tx_projection.project_sync_id,
      // wire 字段名 projectId。
      'projectId': tx.projectSyncId,
    };
  }

  // ==================== Account ====================

  static Map<String, dynamic> serializeAccount(
    Account account, {
    String? avatarCloudFileId,
    String? avatarCloudSha256,
  }) {
    return {
      'syncId': account.syncId,
      'name': account.name,
      'type': account.type,
      'currency': account.currency,
      'initialBalance': account.initialBalance,
      'sortOrder': account.sortOrder,
      if (account.creditLimit != null) 'creditLimit': account.creditLimit,
      if (account.billingDay != null) 'billingDay': account.billingDay,
      if (account.paymentDueDay != null) 'paymentDueDay': account.paymentDueDay,
      if (account.bankName != null) 'bankName': account.bankName,
      if (account.cardLastFour != null) 'cardLastFour': account.cardLastFour,
      if (account.note != null) 'note': account.note,
      // 主帳戶(合併帳單,§2.9 Phase 4):跟 tx 的 accountId 同款约定 —— 无条件
      // 发送 + 空串清空,server _merge_from_spec 只过滤 None,省略/null 都
      // 会被当"不更新",空串才是唯一能清掉挂靠关系的路径。
      'parentAccountId': account.parentAccountId ?? '',
      // 帳戶頭像:调用方(sync_engine_serialization.dart)决定语义 ——
      // null = 不传这俩键(本地头像没变 / 本次上传失败,不要用空串误清掉
      // server 现有值);空串 = 用户主动清空头像;非空 = 新上传成功的引用。
      if (avatarCloudFileId != null) 'avatarCloudFileId': avatarCloudFileId,
      if (avatarCloudSha256 != null) 'avatarCloudSha256': avatarCloudSha256,
      // 账户隐藏(#240)。非空 bool + 默认 false,同账单标记的
      // excludeFromStats/excludeFromBudget 无条件发送(不用 if-null 省略)。
      'hidden': account.hidden,
      // 不納入總餘額。对齐 server `include_in_total`(正极性,默认 true),
      // 无条件发送(同 hidden 的模式)。
      'includeInTotal': account.includeInTotal,
    };
  }

  // ==================== ExchangeRateOverride ====================

  /// 字段与 server 端 projection.upsert_exchange_rate_override 一一对应;
  /// 方向:1 quote = rate base。
  static Map<String, dynamic> serializeExchangeRateOverride(
      ExchangeRateOverride o) {
    return {
      'syncId': o.syncId,
      'baseCurrency': o.baseCurrency,
      'quoteCurrency': o.quoteCurrency,
      'rate': o.rate,
      'updatedAt': (o.updatedAt ?? DateTime.now().toUtc()).toIso8601String(),
    };
  }

  // ==================== Category ====================

  static Map<String, dynamic> serializeCategory(
    Category category, {
    String? parentName,
    String? parentSyncId,
    String? iconCloudFileId,
    String? iconCloudSha256,
  }) {
    return {
      'syncId': category.syncId,
      'name': category.name,
      'kind': category.kind,
      'level': category.level,
      'sortOrder': category.sortOrder,
      'icon': category.icon,
      'iconType': category.iconType,
      if (category.customIconPath != null)
        'customIconPath': category.customIconPath,
      if (category.communityIconId != null)
        'communityIconId': category.communityIconId,
      // 自定义图标上传到云后的引用，让 web 端能直接拉到对应文件。
      if (iconCloudFileId != null) 'iconCloudFileId': iconCloudFileId,
      if (iconCloudSha256 != null) 'iconCloudSha256': iconCloudSha256,
      if (parentName != null) 'parentName': parentName,
      // 共享账本二级分类:parent 的稳定 syncId,server 端 projection.upsert_category
      // 直接用,不再依赖 parent_name 反查(同名 + 重命名场景更稳)。
      if (parentSyncId != null) 'parentSyncId': parentSyncId,
    };
  }

  // ==================== Tag ====================

  static Map<String, dynamic> serializeTag(Tag tag) {
    return {
      'syncId': tag.syncId,
      'name': tag.name,
      if (tag.color != null) 'color': tag.color,
      'sortOrder': tag.sortOrder,
    };
  }

  // ==================== Ledger ====================

  /// 账本元数据(名字 / 币种 / 月度起始日)的跨设备 payload。字段名对齐 server
  /// `WriteLedgerMetaUpdateRequest`,server materialize 时会用这些字段
  /// 更新 `ledger_snapshot` 的 top-level `ledgerName` / `currency`。
  /// `monthStartDay` 对齐 server `ReadLedgerOut.month_start_day`(1-28)。
  static Map<String, dynamic> serializeLedger(Ledger ledger) {
    return {
      'syncId': ledger.syncId,
      'ledgerName': ledger.name,
      'currency': ledger.currency,
      'monthStartDay': ledger.monthStartDay,
    };
  }

  // ==================== Budget ====================

  /// 预算的跨设备同步 payload。ledgerSyncId / categorySyncId 用于对端 apply
  /// 时把本地 int id 对齐过去(跟 transaction payload 同一套思路)。categoryId
  /// 仅分类预算有值。
  static Map<String, dynamic> serializeBudget(
    Budget budget, {
    String? ledgerSyncId,
    String? categorySyncId,
  }) {
    return {
      'syncId': budget.syncId,
      if (ledgerSyncId != null && ledgerSyncId.isNotEmpty)
        'ledgerSyncId': ledgerSyncId,
      'type': budget.type,
      if (categorySyncId != null && categorySyncId.isNotEmpty)
        'categoryId': categorySyncId,
      'amount': budget.amount,
      'period': budget.period,
      'startDay': budget.startDay,
      'enabled': budget.enabled,
    };
  }

  // ==================== CardRewardRule ====================

  /// 信用卡紅利回饋規則。**注意**:跟本檔案其它 serialize 方法不同,BeeCount
  /// Cloud 端這個 entity 的 upsert(`projection.py::upsert_card_reward_rule`)
  /// 不走 `_merge_from_spec` 的「只覆盖 payload 里非 None 的字段」合并语义,
  /// 而是每次全量 UPSERT 全部欄位(`_upsert()` docstring:「主键撞了就 UPDATE
  /// 其他所有列」)。這裡因此**不做任何 `if (x != null)` 省略**——每個欄位
  /// 每次都要把本地當前真值(包含 null)完整帶上,省略等於把該欄位覆蓋成
  /// server 端 `payload.get(x) or <default>` 的預設值,不是"維持原值"。
  static Map<String, dynamic> serializeCardRewardRule(
    CardRewardRule rule, {
    required String accountSyncId,
    String? rewardAccountSyncId,
  }) {
    return {
      'syncId': rule.syncId,
      'accountId': accountSyncId,
      'label': rule.label,
      'categoryIds': rule.categoryIds,
      'rateType': rule.rateType,
      'rateValue': rule.rateValue,
      'rounding': rule.rounding,
      'totalRounding': rule.totalRounding,
      'calcBasis': rule.calcBasis,
      'interval': rule.interval,
      'minSpendThreshold': rule.minSpendThreshold,
      'minTxAmount': rule.minTxAmount,
      'capAmount': rule.capAmount,
      'capSharedKey': rule.capSharedKey,
      'startsAt': rule.startsAt?.toUtc().toIso8601String(),
      'endsAt': rule.endsAt?.toUtc().toIso8601String(),
      'settlementType': rule.settlementType,
      'settlementDays': rule.settlementDays,
      'settlementMonthOffset': rule.settlementMonthOffset,
      'settlementDayOfMonth': rule.settlementDayOfMonth,
      'rewardAccountId': rewardAccountSyncId,
      'note': rule.note,
      'enabled': rule.enabled,
    };
  }

  // ==================== RecurringRule ====================

  /// 週期性收支規則(v36,對齐 BeeCount Cloud recurring_rule)。ledger-scope,
  /// 跟 [serializeBudget] 同款語意:BeeCount Cloud
  /// `sync_applier.py::_LEDGER_MERGE_SPECS["recurring_rule"]` 走
  /// `projection.upsert_recurring_rule` 全量 UPSERT(缺鍵/null 由 server 端
  /// merge 從既有列補齐),所以這裡把規則當下的完整值都帶上,`if != null`
  /// 只是省略空值(效果等同顯式傳 null,不是「刻意不更新」)。
  ///
  /// **範圍決策(2026-08-17)**:刻意不帶 `projectId` /
  /// `baseAmount`/`feeAmount`/`feeLabel`/`discountAmount`/`discountLabel`
  /// ——App 端尚未實作專案關聯與手續費/折扣功能,本地 `RecurringTransactions`
  /// 表也没有对应列。
  static Map<String, dynamic> serializeRecurringRule(
    RecurringTransaction rule, {
    String? categorySyncId,
    String? accountSyncId,
    String? fromAccountSyncId,
    String? toAccountSyncId,
  }) {
    return {
      'syncId': rule.syncId,
      // 注意:wire 字段是 txType,不是 type——跟 Transaction 的
      // serializeTransaction 不同(那边就叫 type),这里照抄 Cloud
      // ReadRecurringRuleProjection.tx_type 的 merge spec key 名。
      'txType': rule.type,
      'amount': rule.amount,
      'note': rule.note,
      if (categorySyncId != null && categorySyncId.isNotEmpty)
        'categoryId': categorySyncId,
      if (accountSyncId != null && accountSyncId.isNotEmpty)
        'accountId': accountSyncId,
      if (fromAccountSyncId != null && fromAccountSyncId.isNotEmpty)
        'fromAccountId': fromAccountSyncId,
      if (toAccountSyncId != null && toAccountSyncId.isNotEmpty)
        'toAccountId': toAccountSyncId,
      'merchant': rule.merchant,
      'tagIds': rule.tagSyncIds,
      'frequency': rule.frequency,
      'interval': rule.interval,
      'nextRunAt': rule.nextRunAt.toUtc().toIso8601String(),
      if (rule.endAt != null) 'endAt': rule.endAt!.toUtc().toIso8601String(),
      'enabled': rule.enabled,
      if (rule.generatedUntilAt != null)
        'generatedUntilAt': rule.generatedUntilAt!.toUtc().toIso8601String(),
      // advancedRuleJson 本地存 TEXT 列(json 字串),wire 上跟 Cloud
      // snapshot_builder 的形状对齐——傳解碼後的 Map,不是雙重編碼的字串。
      if (rule.advancedRuleJson != null && rule.advancedRuleJson!.isNotEmpty)
        'advancedRuleJson': jsonDecode(rule.advancedRuleJson!),
      'rewardRuleIds': rule.rewardRuleIds,
    };
  }

  // ==================== Debt ====================

  /// 借還款(v39,對齐 BeeCount Cloud `debt` sync entity)。ledger-scope,
  /// 跟 [serializeBudget] 同款「全量帶上當下值」語意。
  ///
  /// **dueAt / note / closedAt / categoryId 恒發**(同 reconciledAt/
  /// deferredPostingAt 那組慣例)——這幾個欄位都有明確的清空動作
  /// ([DebtRepository.updateDebt] 的 clearDueAt/clearNote/clearCategoryId、
  /// [DebtRepository.reopenDebt]),省略或只在非 null 時才發會讓「清空/重開」
  /// 這個動作永遠同步不出去。direction / counterpartyName / principalAmount
  /// 建立後不可改,恒為當下值,不需要 null 判斷。originTransactionSyncId 只在
  /// 建立時寫入、之後永遠不變,沒有清空動作,維持「非 null 才發」慣例即可。
  /// excludedFromTotal(v42)是一般的 bool 開關,恒發,跟 direction 同款。
  /// 對齐 BeeCount Cloud `sync_applier.py::_LEDGER_MERGE_SPECS["debt"]`——改
  /// 欄位前先去那邊核對,一字之差會讓整個欄位靜默同步失敗。
  static Map<String, dynamic> serializeDebt(
    Debt debt, {
    String? ledgerSyncId,
    String? categorySyncId,
  }) {
    return {
      'syncId': debt.syncId,
      if (ledgerSyncId != null && ledgerSyncId.isNotEmpty)
        'ledgerSyncId': ledgerSyncId,
      'direction': debt.direction,
      'counterpartyName': debt.counterpartyName,
      'principalAmount': debt.principalAmount,
      'dueAt': debt.dueAt?.toUtc().toIso8601String(),
      'note': debt.note,
      'closedAt': debt.closedAt?.toUtc().toIso8601String(),
      'categoryId': categorySyncId,
      if (debt.originTransactionSyncId != null &&
          debt.originTransactionSyncId!.isNotEmpty)
        'originTxId': debt.originTransactionSyncId,
      'excludedFromTotal': debt.excludedFromTotal,
    };
  }

  // ==================== Project ====================

  /// 專案(v44,對齐 BeeCount Cloud `project` sync entity)。ledger-scope,
  /// 跟 [serializeBudget]/[serializeDebt] 同款「全量帶上當下值」語意——
  /// 每個欄位都恆發(即使 null),因為 icon/budgetAmount/periodStart/
  /// periodEnd 都有明確的清空動作([ProjectRepository.updateProject] 的
  /// clearIcon/clearBudgetAmount/clearPeriodStart/clearPeriodEnd),省略
  /// 或只在非 null 時才發會讓「清空」這個動作永遠同步不出去。對齐
  /// BeeCount Cloud `sync_applier.py::_MERGE_SPECS["project"]`——改欄位前
  /// 先去那邊核對,一字之差會讓整個欄位靜默同步失敗。
  static Map<String, dynamic> serializeProject(
    Project project, {
    String? ledgerSyncId,
  }) {
    return {
      'syncId': project.syncId,
      if (ledgerSyncId != null && ledgerSyncId.isNotEmpty)
        'ledgerSyncId': ledgerSyncId,
      'name': project.name,
      'icon': project.icon,
      'budgetAmount': project.budgetAmount,
      'periodType': project.periodType,
      'periodStart': project.periodStart?.toUtc().toIso8601String(),
      'periodEnd': project.periodEnd?.toUtc().toIso8601String(),
      'carryoverEnabled': project.carryoverEnabled,
      'visibleOnHome': project.visibleOnHome,
      'enabled': project.enabled,
      'sortOrder': project.sortOrder,
    };
  }

  // ==================== JSON Encode ====================

  static String toJsonString(Map<String, dynamic> payload) {
    return jsonEncode(payload);
  }

  static Map<String, dynamic> fromJsonString(String json) {
    return jsonDecode(json) as Map<String, dynamic>;
  }
}
