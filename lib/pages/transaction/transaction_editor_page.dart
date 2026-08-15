import 'package:drift/drift.dart' as d;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/budget_providers.dart';
import '../../data/db.dart';
import '../../data/repositories/local/local_repository.dart';
import '../../utils/shared_ledger_picker_filter.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/transaction_entry_form.dart'
    show TransactionEntryForm, AmountEditorResult;
import '../../widgets/transaction/transfer_form.dart';
import '../../styles/tokens.dart';
import '../../services/billing/post_processor.dart';
import '../../services/attachment_service.dart';
import '../../services/data/tx_author_service.dart';

/// 交易编辑器页面
/// 支持创建/编辑收入、支出和转账记录
///
/// 三个分页都是单页式表单(比照 Moze 参考图):支出/收入用
/// `TransactionEntryForm`,转账用 `TransferForm`(v2 起也改成单页式,拿掉了
/// 「先选账户方格 → 再弹 AmountEditorSheet modal」的两步流程,`AmountEditorSheet`
/// 已删除)。类别/账户、金额、名称、商家、标签/附件/旗标、日期一次呈现。
class TransactionEditorPage extends ConsumerStatefulWidget {
  final String initialKind; // 'expense', 'income', or 'transfer'
  final int? initialCategoryId;
  final String? initialNote; // 用于金额输入弹窗回填备注
  final String? initialMerchant; // v33:回填商家
  final double? initialAmount;
  final DateTime? initialDate;
  final int? editingTransactionId;
  final int? initialAccountId;
  final int? initialToAccountId; // 转账时的目标账户
  final List<int>? initialTagIds; // 初始标签ID列表
  final bool initialExcludeFromStats; // 不计入收支，编辑模式回显
  final bool initialExcludeFromBudget; // 不计入预算，编辑模式回显
  // v30 多币种编辑回显(推隐含汇率用)
  final String? initialCurrencyCode;
  final double? initialNativeAmount;

  const TransactionEditorPage({
    super.key,
    required this.initialKind,
    this.initialCategoryId,
    this.initialNote,
    this.initialMerchant,
    this.initialAmount,
    this.initialDate,
    this.editingTransactionId,
    this.initialAccountId,
    this.initialToAccountId,
    this.initialTagIds,
    this.initialExcludeFromStats = false,
    this.initialExcludeFromBudget = false,
    this.initialCurrencyCode,
    this.initialNativeAmount,
  });

  @override
  ConsumerState<TransactionEditorPage> createState() =>
      _TransactionEditorPageState();
}

class _TransactionEditorPageState extends ConsumerState<TransactionEditorPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    // 设置初始tab: 0=支出, 1=收入, 2=转账
    if (widget.initialKind == 'income') {
      _tab.index = 1;
    } else if (widget.initialKind == 'transfer') {
      _tab.index = 2;
    } else {
      _tab.index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ledgerId = ref.watch(currentLedgerIdProvider);
    return Scaffold(
      body: Column(
        children: [
          // 紧凑顶部：去除多余留白 + 选中下划线
          PrimaryHeader(
            title: '',
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            bottom: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: TabBar(
                            controller: _tab,
                            isScrollable: false,
                            labelColor: BeeTokens.textPrimary(context),
                            unselectedLabelColor:
                                BeeTokens.textSecondary(context),
                            indicator: UnderlineTabIndicator(
                              borderSide: BorderSide(
                                  width: 2,
                                  color: BeeTokens.textPrimary(context)),
                              insets: const EdgeInsets.symmetric(horizontal: 0),
                            ),
                            tabs: [
                              Tab(
                                  text: AppLocalizations.of(context)!
                                      .categoryExpense),
                              Tab(
                                  text: AppLocalizations.of(context)!
                                      .categoryIncome),
                              Tab(
                                  text: AppLocalizations.of(context)!
                                      .transferTitle),
                            ],
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(AppLocalizations.of(context)!.commonCancel,
                            style: TextStyle(
                                color: BeeTokens.textPrimary(context))),
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                TransactionEntryForm(
                  kind: 'expense',
                  initialCategoryId: widget.initialCategoryId,
                  initialDate: widget.initialDate ?? DateTime.now(),
                  initialAmount: widget.initialAmount,
                  initialNote: widget.initialNote,
                  initialMerchant: widget.initialMerchant,
                  initialAccountId: widget.initialAccountId,
                  initialTagIds: widget.initialTagIds,
                  ledgerId: ledgerId,
                  editingTransactionId: widget.editingTransactionId,
                  initialExcludeFromStats: widget.initialExcludeFromStats,
                  initialExcludeFromBudget: widget.initialExcludeFromBudget,
                  initialCurrencyCode: widget.initialCurrencyCode,
                  initialNativeAmount: widget.initialNativeAmount,
                  onSubmit: (c, r) => _handleSubmit(c, 'expense', r),
                ),
                TransactionEntryForm(
                  kind: 'income',
                  initialCategoryId: widget.initialCategoryId,
                  initialDate: widget.initialDate ?? DateTime.now(),
                  initialAmount: widget.initialAmount,
                  initialNote: widget.initialNote,
                  initialMerchant: widget.initialMerchant,
                  initialAccountId: widget.initialAccountId,
                  initialTagIds: widget.initialTagIds,
                  ledgerId: ledgerId,
                  editingTransactionId: widget.editingTransactionId,
                  initialExcludeFromStats: widget.initialExcludeFromStats,
                  initialExcludeFromBudget: widget.initialExcludeFromBudget,
                  initialCurrencyCode: widget.initialCurrencyCode,
                  initialNativeAmount: widget.initialNativeAmount,
                  onSubmit: (c, r) => _handleSubmit(c, 'income', r),
                ),
                TransferForm(
                  onTransferComplete: () {
                    // 关闭交易编辑器
                    Navigator.pop(context);
                  },
                  initialFromAccountId: widget.initialAccountId,
                  initialToAccountId: widget.initialToAccountId,
                  editingTransactionId: widget.editingTransactionId,
                  initialAmount: widget.initialAmount,
                  initialNote: widget.initialNote,
                  initialMerchant: widget.initialMerchant,
                  initialDate: widget.initialDate,
                  initialTagIds: widget.initialTagIds,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 存檔 orchestration——原本是 `AmountEditorSheet.onSubmit` 的 callback
  /// body(見改版前 git 歷史),整段搬過來,行為不變:synthetic id 處理、
  /// shared-ledger override、附件儲存、tag 主表/override 分流、
  /// `PostProcessor.sync`、provider 刷新。
  Future<void> _handleSubmit(
      Category c, String kind, AmountEditorResult res) async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    final repo = ref.read(repositoryProvider);
    final attachmentService = ref.read(attachmentServiceProvider);
    int transactionId;
    // §7 v25:Category 是来自 SharedLedger* 的 synthetic (id<0)时,
    // categoryId 留 null,override 走 syncId。同理对 account/toAccount。
    // res.accountId 可能也是 synthetic(Account picker 用同一规则)。
    final isSyntheticCategory = c.id < 0;
    final isSyntheticAccount = res.accountId != null && res.accountId! < 0;
    final categoryIdForWrite = isSyntheticCategory ? null : c.id;
    // synthetic / picker 返 null 时账户 id 写 null。
    // addTransaction 的 accountId 是 int?(直接传 null 即写 null);
    // updateTransaction 的 accountId 是 dynamic,dart null 被解释成
    // Value.absent(=不更新该字段) → 用户选"不选择账户"无效;必须显式
    // 传 d.Value<int?>(null) 才会真清空旧 accountId。
    final accountIdForAdd = isSyntheticAccount ? null : res.accountId;
    final accountIdForUpdate = d.Value<int?>(accountIdForAdd);
    final categoryOverride = isSyntheticCategory ? c.syncId : null;
    final accountOverride = isSyntheticAccount
        ? await _resolveSyncIdByAccountId(res.accountId!, ledgerId)
        : null;
    if (widget.editingTransactionId != null) {
      // 编辑模式：使用repository更新交易
      await repo.updateTransaction(
        id: widget.editingTransactionId!,
        type: kind,
        amount: res.amount,
        categoryId: categoryIdForWrite,
        note: res.note,
        merchant: res.merchant,
        happenedAt: res.date,
        accountId: accountIdForUpdate,
        categorySyncIdOverride: categoryOverride,
        accountSyncIdOverride: accountOverride,
        excludeFromStats: res.excludeFromStats,
        excludeFromBudget: res.excludeFromBudget,
        currencyCode: res.currencyCode,
        nativeAmount: res.nativeAmount,
      );
      transactionId = widget.editingTransactionId!;
      // 共享账本:本地 lastEditedByUserId 立即回填,UI 头像组直接展示
      // 当前 user 为编辑人(否则要等 server 下次 pull 才回来)
      await TxAuthorService.markEdited(ref, transactionId);
    } else {
      transactionId = await repo.addTransaction(
        ledgerId: ledgerId,
        type: kind,
        amount: res.amount,
        categoryId: categoryIdForWrite,
        happenedAt: res.date,
        note: res.note,
        merchant: res.merchant,
        accountId: accountIdForAdd,
        categorySyncIdOverride: categoryOverride,
        accountSyncIdOverride: accountOverride,
        excludeFromStats: res.excludeFromStats,
        excludeFromBudget: res.excludeFromBudget,
        currencyCode: res.currencyCode,
        nativeAmount: res.nativeAmount,
      );
      // 共享账本:新建本地 tx 也回填创建人 + 编辑人(同一个 user)
      await TxAuthorService.markCreated(ref, transactionId);
    }
    // 保存待上传的附件
    if (res.pendingAttachments.isNotEmpty) {
      await attachmentService.saveAttachments(
        transactionId: transactionId,
        sourceFiles: res.pendingAttachments,
        startIndex: 0,
      );
      // 刷新附件列表缓存
      ref.read(attachmentListRefreshProvider.notifier).state++;
    }
    // 更新标签关联
    // §7 共享账本:tag.id < 0 是 synthetic(Owner tag from SharedLedger*),
    // 主表 Tags 没该行,不能直接写 transaction_tags.tag_id。分两类:
    // - 正数 id → 写 transaction_tags 主表(老路径)
    // - 负数 id → 走 SharedLedgerTags 反查 syncId → 写 transaction_tag_overrides
    final normalTagIds = res.tagIds.where((id) => id >= 0).toList();
    final syntheticTagIds = res.tagIds.where((id) => id < 0).toList();

    if (normalTagIds.isNotEmpty) {
      await repo.updateTransactionTags(
        transactionId: transactionId,
        tagIds: normalTagIds,
      );
      ref.read(tagListRefreshProvider.notifier).state++;
    } else if (widget.editingTransactionId != null) {
      // 编辑模式没主表 tag → 清掉旧主表关联
      await repo.removeAllTagsFromTransaction(transactionId);
      ref.read(tagListRefreshProvider.notifier).state++;
    }

    // §7 写 override:先反查 tx.syncId + 把 synthetic tag_id 翻译成
    // Owner tag syncId,再 upsert 进 TransactionTagOverrides
    if (repo is LocalRepository) {
      final txRow = await (repo.db.select(repo.db.transactions)
            ..where((t) => t.id.equals(transactionId)))
          .getSingleOrNull();
      final txSyncId = txRow?.syncId;
      if (txSyncId != null) {
        await (repo.db.delete(repo.db.transactionTagOverrides)
              ..where((t) => t.transactionSyncId.equals(txSyncId)))
            .go();
        if (syntheticTagIds.isNotEmpty) {
          final allShared =
              await repo.db.select(repo.db.sharedLedgerTags).get();
          final now = DateTime.now().toUtc();
          for (final sid in syntheticTagIds) {
            for (final s in allShared) {
              if (syntheticIdForSyncId(s.syncId) == sid) {
                await repo.db.into(repo.db.transactionTagOverrides).insert(
                      TransactionTagOverridesCompanion.insert(
                        transactionSyncId: txSyncId,
                        tagSyncId: s.syncId,
                        createdAt: now,
                      ),
                    );
                break;
              }
            }
          }
          ref.read(tagListRefreshProvider.notifier).state++;
        }
        // 这里**不再**重复 recordLedgerChange(transaction:update)。
        // 之前为了"override 变化也走 push"专门补一条 update,但
        // - addTransaction / updateTransaction 已经登记过一次 change
        // - _serializeEntityForPush('transaction') 在 push 时**统一**读 DB
        //   最新状态(包括 transaction_tag_overrides 表),payload 自然含
        //   最新 overrides
        // 结论:那条补登记的 update 跟前面的 create/update 推同样 payload,
        // 服务端 sync_changes 表凭空多一条 row(已观察到共享账本 Editor
        // 创建 tx 时 1 秒内 2 条 identical upsert)。直接砍。
      }
    }
    // 统一处理：自动/手动同步与状态刷新（后台静默）
    PostProcessor.sync(ref, ledgerId: ledgerId);
    // 刷新：账本笔数与全局统计
    ref.invalidate(countsForLedgerProvider(ledgerId));
    ref.read(statsRefreshProvider.notifier).state++;
    // 刷新：预算数据
    ref.read(budgetRefreshProvider.notifier).state++;
    // 更新小组件数据（后台执行，不阻塞UI）
    if (mounted) {
      updateAppWidget(ref, context);
    }
    // 先关闭页面，再播放反馈
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    // 反馈：轻微触感 + 系统点击音
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
  }

  /// §7 v25:account picker 返 synthetic Account(id<0)时,把 id 反查
  /// SharedLedgerAccounts 拿 syncId,写到 tx.accountSyncIdOverride。
  /// 失败返 null,调用方应回到 accountId int 路径(synthetic 不一致时的兜底)。
  Future<String?> _resolveSyncIdByAccountId(int accountId, int ledgerId) async {
    if (accountId >= 0) return null;
    final repo = ref.read(repositoryProvider);
    if (repo is! LocalRepository) return null;
    // 反查:本地 ledger.syncId → SharedLedgerAccounts ledgerSyncId 范围
    final ledger = await (repo.db.select(repo.db.ledgers)
          ..where((l) => l.id.equals(ledgerId)))
        .getSingleOrNull();
    if (ledger?.syncId == null) return null;
    final rows = await (repo.db.select(repo.db.sharedLedgerAccounts)
          ..where((t) => t.ledgerSyncId.equals(ledger!.syncId!)))
        .get();
    for (final r in rows) {
      if (syntheticIdForSyncId(r.syncId) == accountId) return r.syncId;
    }
    return null;
  }
}
