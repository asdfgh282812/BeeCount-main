import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/repositories/base_repository.dart';
import '../../data/repositories/local/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/budget_providers.dart';
import '../../services/attachment_service.dart';
import '../../services/billing/post_processor.dart';
import '../../styles/tokens.dart';
import '../../utils/account_type_utils.dart';
import '../../utils/card_reward_calc.dart';
import '../../utils/category_utils.dart';
import '../../utils/transaction_edit_utils.dart';
import '../../utils/shared_ledger_picker_filter.dart';
import '../../pages/attachment/attachment_preview_page.dart';
import '../category_icon.dart';
import '../ui/ui.dart';
import 'amount_text.dart';
import 'recurring_occurrence_dialogs.dart';

/// 点击交易时弹出的资讯卡:唯读展示,右上角退款/删除/复制/编辑四个动作,
/// 中间最大区块显示附图(没有图就显示分类图示+名称)。取代原本「点击直接进
/// 编辑页」的流程——编辑页现在只能从卡片的「编辑」按钮进入。
Future<void> showTransactionDetailCard(
  BuildContext context,
  WidgetRef ref,
  Transaction transaction,
  Category? category,
) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: BeeTokens.surfaceSheet(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => TransactionDetailCard(
      hostContext: context,
      hostRef: ref,
      transaction: transaction,
      category: category,
    ),
  );
}

class _AccountDisplay {
  final String name;
  final String type;
  const _AccountDisplay(this.name, this.type);
}

/// v38 拆帳:一筆拆分明細 + 反查到的分類物件(用來畫圖示/名稱;§7 共享
/// 帳本的 synthetic 分類也已經反查好,category==null 代表分類已被刪除
/// 等異常情況)。
typedef _ResolvedSplit = ({TransactionSplit row, Category? category});

class _DetailBundle {
  final _AccountDisplay? account;
  final List<Tag> tags;
  final List<TransactionAttachment> attachments;
  final List<Transaction> refunds;
  final List<CardRewardRule> rewardRules;
  final List<_ResolvedSplit> splits;

  const _DetailBundle({
    required this.account,
    required this.tags,
    required this.attachments,
    required this.refunds,
    required this.rewardRules,
    required this.splits,
  });
}

class TransactionDetailCard extends ConsumerStatefulWidget {
  /// 打开卡片那个页面的 context——用来在卡片关闭"之后"继续 push 编辑器
  /// 页面(卡片自己的 context 在 pop 之后就失效了)。
  final BuildContext hostContext;

  /// 打开卡片那个页面的 ref——同 [hostContext],卡片自己的 `ref`(来自这个
  /// State 自己的 `ConsumerState`)在 `Navigator.pop()` 之后、State 被
  /// dispose 掉就不能再用了。`_handleEdit` 等方法 pop 卡片后还要
  /// `await` 一段可能很久的使用者互动(例如週期規則的選擇彈窗),如果那之後
  /// 才用卡片自己的 `ref` 去 `ref.read(...)`,dispose 早就跑完了,会直接
  /// 丟 Riverpod 的 "used after dispose" 例外——整段 await 链没有
  /// try/catch,例外会静默变成 unhandled Future error,表现成「彈窗關閉但
  /// 沒有跳轉」。改用呼叫端(卡片還沒開啟前)傳進來、生命週期比卡片長的
  /// [hostRef]。
  final WidgetRef hostRef;
  final Transaction transaction;
  final Category? category;

  const TransactionDetailCard({
    super.key,
    required this.hostContext,
    required this.hostRef,
    required this.transaction,
    required this.category,
  });

  @override
  ConsumerState<TransactionDetailCard> createState() =>
      _TransactionDetailCardState();
}

class _TransactionDetailCardState extends ConsumerState<TransactionDetailCard> {
  late final Future<_DetailBundle> _bundleFuture;

  @override
  void initState() {
    super.initState();
    _bundleFuture = _loadBundle();
  }

  Future<_DetailBundle> _loadBundle() async {
    final repo = ref.read(repositoryProvider);
    final tx = widget.transaction;

    final Future<_AccountDisplay?> accountFuture;
    if (tx.accountId != null) {
      accountFuture = repo
          .getAccount(tx.accountId!)
          .then((a) => a == null ? null : _AccountDisplay(a.name, a.type));
    } else if (tx.accountSyncIdOverride != null && repo is LocalRepository) {
      // §7 共享账本:Editor 视角看 Owner 的交易,账户在 SharedLedgerAccounts
      // 镜像表,不在主表。
      accountFuture = (repo.db.select(repo.db.sharedLedgerAccounts)
            ..where((t) => t.syncId.equals(tx.accountSyncIdOverride!)))
          .getSingleOrNull()
          .then(
              (s) => s == null ? null : _AccountDisplay(s.name, s.accountType));
    } else {
      accountFuture = Future.value(null);
    }

    final tagsFuture = repo.getTagsForTransaction(tx.id);
    final attachmentsFuture = repo.getAttachmentsByTransaction(tx.id);
    final refundsFuture = tx.syncId != null
        ? repo.getRefundsOf(tx.syncId!)
        : Future.value(<Transaction>[]);
    final rewardRuleIds = tx.rewardRuleIds;
    final rewardRulesFuture = rewardRuleIds.isEmpty
        ? Future.value(<CardRewardRule>[])
        : Future.wait(rewardRuleIds.map(repo.getCardRewardRuleBySyncId))
            .then((rules) => rules.whereType<CardRewardRule>().toList());

    final account = await accountFuture;
    final tags = await tagsFuture;
    final attachments = await attachmentsFuture;
    final refunds = await refundsFuture;
    final rewardRules = await rewardRulesFuture;
    final splits = await _loadSplits(repo, tx);
    return _DetailBundle(
      account: account,
      tags: tags,
      attachments: attachments,
      refunds: refunds,
      rewardRules: rewardRules,
      splits: splits,
    );
  }

  /// v38 拆帳:反查每筆明細的分類物件,跟 `transaction_entry_form.dart`
  /// 的 `_resolveInitialSplits` 同一套邏輯(本地 categoryId 優先,查無再看
  /// categorySyncIdOverride 共享帳本兜底)。
  Future<List<_ResolvedSplit>> _loadSplits(
      BaseRepository repo, Transaction tx) async {
    if (!tx.hasSplits) return const [];
    final rows = await repo.getTransactionSplits(tx.id);
    final result = <_ResolvedSplit>[];
    for (final s in rows) {
      Category? cat;
      final override = s.categorySyncIdOverride;
      if (override != null && override.isNotEmpty && repo is LocalRepository) {
        cat = await repo.db
            .findCategoryBySyntheticId(syntheticIdForSyncId(override));
      } else if (s.categoryId != null) {
        cat = await repo.getCategoryById(s.categoryId!);
      }
      result.add((row: s, category: cat));
    }
    return result;
  }

  Future<void> _jumpToTransactionBySyncId(String syncId) async {
    final repo = ref.read(repositoryProvider);
    final target = await repo.getTransactionBySyncId(syncId);
    if (target == null) return;
    Category? targetCategory;
    if (target.categoryId != null) {
      targetCategory = await repo.getCategoryById(target.categoryId!);
    }
    if (!mounted) return;
    final hostContext = widget.hostContext;
    Navigator.of(context).pop();
    if (!hostContext.mounted) return;
    await showTransactionDetailCard(
        hostContext, widget.hostRef, target, targetCategory);
  }

  Future<void> _handleDelete() async {
    final l10n = AppLocalizations.of(context);
    final tx = widget.transaction;
    final repo = ref.read(repositoryProvider);

    // v36:週期規則生成的 occurrence 走「此記錄/連同未來週期」二選一彈窗
    // (對齐 MOZE 截圖語意,§2.2),純本地一次性交易維持原本的單一確認彈窗。
    if (tx.recurringRuleId != null) {
      final scope = await showRecurringDeleteChoiceSheet(context);
      if (scope == null || !mounted) return;
      await repo.deleteOccurrence(tx.id);
      if (scope == RecurringDeleteScope.thisAndFuture) {
        final rule = await repo.getRuleBySyncId(tx.recurringRuleId!);
        if (rule != null) await repo.terminateFuture(rule.id);
      }
      if (!mounted) return;
    } else {
      final confirmed = await AppDialog.confirm<bool>(
            context,
            title: l10n.deleteConfirmTitle,
            message: l10n.deleteConfirmMessage,
          ) ??
          false;
      if (!confirmed || !mounted) return;

      await repo.deleteTransaction(tx.id);
      if (!mounted) return;
    }

    final curLedger = ref.read(currentLedgerIdProvider);
    ref.invalidate(countsForLedgerProvider(curLedger));
    ref.read(statsRefreshProvider.notifier).state++;
    ref.read(budgetRefreshProvider.notifier).state++;
    ref.read(tagListRefreshProvider.notifier).state++;
    PostProcessor.sync(ref, ledgerId: curLedger);

    final overlay = Overlay.of(context);
    Navigator.of(context).pop();
    showToastOnOverlay(overlay, l10n.ledgersDeleted);
  }

  Future<void> _handleCopy() async {
    final hostContext = widget.hostContext;
    Navigator.of(context).pop();
    if (!hostContext.mounted) return;
    await TransactionEditUtils.copyTransaction(
        hostContext, widget.hostRef, widget.transaction, widget.category);
  }

  Future<void> _handleEdit() async {
    final hostContext = widget.hostContext;
    Navigator.of(context).pop();
    if (!hostContext.mounted) return;
    // 用 widget.hostRef(呼叫端、生命週期比這張卡片長的 ref),不要用這個
    // State 自己的 ref——上面这行 pop 之后卡片马上开始 dispose,
    // `editTransaction` 内部会先 `await showRecurringEditChoiceSheet(...)`
    // 等使用者选「此記錄/連同未來週期」,这段等待通常比卡片的 dispose 慢
    // 得多,等使用者选完,这个 State 早就 dispose 完了,自己的 ref 已失效。
    await TransactionEditUtils.editTransaction(
        hostContext, widget.hostRef, widget.transaction, widget.category);
  }

  Future<void> _handleRefund() async {
    final hostContext = widget.hostContext;
    Navigator.of(context).pop();
    if (!hostContext.mounted) return;
    await TransactionEditUtils.refundTransaction(
        hostContext, widget.hostRef, widget.transaction, widget.category);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tx = widget.transaction;
    final isTransfer = tx.type == 'transfer';
    final isAdjustment = tx.type == 'adjustment';
    final isExpense = tx.type == 'expense';
    final isRefundTx = tx.refundOfSyncId != null;

    return SafeArea(
      top: false,
      child: FutureBuilder<_DetailBundle>(
        future: _bundleFuture,
        builder: (context, snapshot) {
          final bundle = snapshot.data;
          final refunds = bundle?.refunds ?? const <Transaction>[];
          final alreadyRefunded = refunds.isNotEmpty;

          String? refundDisabledReason;
          if (isTransfer || isAdjustment) {
            refundDisabledReason = l10n.txDetailRefundDisabledType;
          } else if (isRefundTx) {
            refundDisabledReason = l10n.txDetailRefundDisabledIsRefund;
          } else if (alreadyRefunded) {
            refundDisabledReason = l10n.txDetailRefundDisabledAlreadyRefunded;
          }
          final canRefund = refundDisabledReason == null;

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context, l10n, canRefund, refundDisabledReason),
                  _buildImageOrCategoryBlock(context, bundle),
                  _buildNoteAmountRow(context, l10n, isExpense, isTransfer,
                      isAdjustment, isRefundTx),
                  const SizedBox(height: 8),
                  _buildDetailRows(context, l10n, bundle),
                  _buildSplitSection(context, l10n, bundle),
                  _buildRewardSection(context, l10n, bundle),
                  if (alreadyRefunded)
                    _buildRefundedList(context, l10n, refunds),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n,
      bool canRefund, String? refundDisabledReason) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            color: BeeTokens.iconSecondary(context),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          Tooltip(
            message: refundDisabledReason ?? l10n.txDetailRefund,
            child: IconButton(
              icon: const Icon(Icons.replay),
              color: canRefund
                  ? BeeTokens.iconSecondary(context)
                  : BeeTokens.iconTertiary(context),
              onPressed: canRefund ? _handleRefund : null,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: BeeTokens.iconSecondary(context),
            tooltip: l10n.commonDelete,
            onPressed: _handleDelete,
          ),
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            color: BeeTokens.iconSecondary(context),
            tooltip: l10n.txDetailCopy,
            onPressed: _handleCopy,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            color: BeeTokens.iconSecondary(context),
            tooltip: l10n.commonEdit,
            onPressed: _handleEdit,
          ),
        ],
      ),
    );
  }

  Widget _buildImageOrCategoryBlock(
      BuildContext context, _DetailBundle? bundle) {
    final attachments = bundle?.attachments ?? const <TransactionAttachment>[];
    if (attachments.isEmpty) {
      final categoryKind = widget.category?.kind ??
          (widget.transaction.type == 'income' ? 'income' : 'expense');
      // v38 拆帳:没有单一分类可显示,固定用「多類別」聚合图示+标签。
      final displayName = widget.transaction.hasSplits
          ? AppLocalizations.of(context).txSplitAggregateLabel
          : CategoryUtils.getDisplayName(widget.category?.name, context,
              kind: categoryKind);
      return Container(
        width: double.infinity,
        height: 220,
        alignment: Alignment.center,
        color: BeeTokens.surfaceElevated(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.transaction.hasSplits
                ? Icon(Icons.apps,
                    size: 88, color: BeeTokens.iconSecondary(context))
                : CategoryIconWidget(
                    category: widget.category,
                    categoryName: displayName,
                    size: 88,
                  ),
            const SizedBox(height: 12),
            Text(
              displayName,
              style: BeeTextTokens.title(context)
                  .copyWith(color: BeeTokens.textPrimary(context)),
            ),
          ],
        ),
      );
    }

    final first = attachments.first;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AttachmentPreviewPage.fromTransaction(
              transactionId: widget.transaction.id,
            ),
          ),
        );
      },
      child: SizedBox(
        width: double.infinity,
        height: 220,
        child: FutureBuilder<String>(
          future: ref
              .read(attachmentServiceProvider)
              .getAttachmentPath(first.fileName),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Container(color: BeeTokens.surfaceElevated(context));
            }
            return Image.file(
              File(snapshot.data!),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: BeeTokens.surfaceElevated(context),
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_outlined,
                    color: BeeTokens.iconTertiary(context), size: 48),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNoteAmountRow(BuildContext context, AppLocalizations l10n,
      bool isExpense, bool isTransfer, bool isAdjustment, bool isRefundTx) {
    final tx = widget.transaction;
    final categoryKind =
        widget.category?.kind ?? (tx.type == 'income' ? 'income' : 'expense');
    // v38 拆帳:没有单一分类可显示,固定用「多類別」聚合标签。
    final categoryDisplayName = tx.hasSplits
        ? l10n.txSplitAggregateLabel
        : CategoryUtils.getDisplayName(widget.category?.name, context,
            kind: categoryKind);
    final noteText = (tx.note != null && tx.note!.isNotEmpty)
        ? tx.note!
        : categoryDisplayName;

    Widget badge(String label, {VoidCallback? onTap}) {
      final content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: BeeTokens.iconSecondary(context).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: BeeTokens.textSecondary(context),
          ),
        ),
      );
      return onTap == null ? content : GestureDetector(onTap: onTap, child: content);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          tx.hasSplits
              ? Icon(Icons.apps,
                  size: 22, color: BeeTokens.iconSecondary(context))
              : CategoryIconWidget(
                  category: widget.category,
                  categoryName: categoryDisplayName,
                  size: 22,
                ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    noteText,
                    style: BeeTextTokens.title(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (tx.hasSplits) ...[
                  const SizedBox(width: 6),
                  badge(l10n.txSplitBadge),
                ],
                if (isRefundTx) ...[
                  const SizedBox(width: 6),
                  badge(l10n.txDetailRefundBadge, onTap: () {
                    final original = tx.refundOfSyncId;
                    if (original != null) _jumpToTransactionBySyncId(original);
                  }),
                ],
              ],
            ),
          ),
          AmountText(
            value: isAdjustment
                ? tx.amount
                : isExpense
                    ? -tx.amount
                    : tx.amount,
            signed: !isTransfer,
            currencyCode: tx.currencyCode,
            showCurrency: tx.currencyCode != null,
            decimals: 2,
            style: BeeTextTokens.title(context).copyWith(
              color: isAdjustment
                  ? (tx.amount >= 0
                      ? BeeTokens.incomeColor(context, ref)
                      : BeeTokens.expenseColor(context, ref))
                  : isTransfer
                      ? BeeTokens.textPrimary(context)
                      : isExpense
                          ? BeeTokens.expenseColor(context, ref)
                          : BeeTokens.incomeColor(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailItem(BuildContext context, IconData icon, String text) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 16, color: BeeTokens.iconTertiary(context)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: BeeTokens.textSecondary(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRows(
      BuildContext context, AppLocalizations l10n, _DetailBundle? bundle) {
    final tx = widget.transaction;
    final account = bundle?.account;
    final tags = bundle?.tags ?? const <Tag>[];
    final firstTagName = tags.isNotEmpty ? tags.first.name : '—';
    final merchant =
        (tx.merchant != null && tx.merchant!.isNotEmpty) ? tx.merchant! : '—';
    final repeatText =
        tx.recurringRuleId == null ? l10n.txDetailOnce : l10n.txDetailRecurring;
    final dateText =
        '${tx.happenedAt.year}/${tx.happenedAt.month.toString().padLeft(2, '0')}/${tx.happenedAt.day.toString().padLeft(2, '0')}';
    final timeText =
        '${tx.happenedAt.hour.toString().padLeft(2, '0')}:${tx.happenedAt.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              account != null
                  ? Expanded(
                      child: Row(
                        children: [
                          AccountTypeIcon(type: account.type, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              account.name,
                              style: TextStyle(
                                fontSize: 13,
                                color: BeeTokens.textSecondary(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _detailItem(
                      context, Icons.account_balance_wallet_outlined, '—'),
              _detailItem(context, Icons.sell_outlined, firstTagName),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _detailItem(context, Icons.storefront_outlined, merchant),
              _detailItem(context, Icons.event_repeat, repeatText),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _detailItem(context, Icons.calendar_today_outlined, dateText),
              _detailItem(context, Icons.access_time, timeText),
            ],
          ),
        ],
      ),
    );
  }

  /// 若交易有勾選紅利回饋規則,在日期/時間下方顯示每條規則的名稱、費率與
  /// 該筆交易的預估回饋金——沒有套用任何規則時整塊不佔空間。實際入帳金額
  /// 仍由 Server 端排程計算,這裡只用 [estimateCardRewardForRule] 現場估算
  /// (同記帳表單的估算公式,見 lib/utils/card_reward_calc.dart)。
  Widget _buildRewardSection(
      BuildContext context, AppLocalizations l10n, _DetailBundle? bundle) {
    final rules = bundle?.rewardRules ?? const <CardRewardRule>[];
    if (rules.isEmpty) return const SizedBox.shrink();
    final tx = widget.transaction;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.txDetailRewardSectionTitle,
            style: TextStyle(
              fontSize: 13,
              color: BeeTokens.textSecondary(context),
            ),
          ),
          const SizedBox(height: 4),
          ...rules.map((rule) {
            final estimated = estimateCardRewardForRule(rule, tx.amount);
            final rateLabel = rule.rateType == 'percentage'
                ? '${rule.label} ${_trimRateZeros(rule.rateValue)}%'
                : rule.label;
            return Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Row(
                children: [
                  Text(
                    '➤ ',
                    style: TextStyle(
                        fontSize: 13, color: BeeTokens.textTertiary(context)),
                  ),
                  Expanded(
                    child: Text(
                      rateLabel,
                      style: TextStyle(
                        fontSize: 13,
                        color: BeeTokens.textPrimary(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AmountText(
                    value: estimated,
                    signed: false,
                    currencyCode: tx.currencyCode,
                    showCurrency: true,
                    decimals: 2,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: BeeTokens.incomeColor(context, ref),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// v38 拆帳:堆疊列出每筆拆分明細(圖示+分類名+備註+金額),排在附件/
  /// 分類主圖示區之後、其餘欄位卡片之前——比照截圖裡「主卡片 + 下方明細
  /// 列表」的排版。
  Widget _buildSplitSection(
      BuildContext context, AppLocalizations l10n, _DetailBundle? bundle) {
    final splits = bundle?.splits ?? const <_ResolvedSplit>[];
    if (splits.isEmpty) return const SizedBox.shrink();
    final tx = widget.transaction;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.txSplitDetailTitle,
            style: TextStyle(
              fontSize: 13,
              color: BeeTokens.textSecondary(context),
            ),
          ),
          const SizedBox(height: 4),
          ...splits.map((s) {
            final name = s.category != null
                ? CategoryUtils.getDisplayName(s.category!.name, context,
                    kind: s.category!.kind)
                : l10n.commonUncategorized;
            return Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Row(
                children: [
                  CategoryIconWidget(
                    category: s.category,
                    categoryName: name,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 14,
                            color: BeeTokens.textPrimary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (s.row.note != null && s.row.note!.isNotEmpty)
                          Text(
                            s.row.note!,
                            style: TextStyle(
                              fontSize: 12,
                              color: BeeTokens.textTertiary(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  AmountText(
                    value: tx.type == 'income' ? s.row.amount : -s.row.amount,
                    signed: true,
                    currencyCode: tx.currencyCode,
                    showCurrency: tx.currencyCode != null,
                    decimals: 2,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tx.type == 'income'
                          ? BeeTokens.incomeColor(context, ref)
                          : BeeTokens.expenseColor(context, ref),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _trimRateZeros(double v) {
    final s = v.toStringAsFixed(2);
    return s.contains('.')
        ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : s;
  }

  Widget _buildRefundedList(
      BuildContext context, AppLocalizations l10n, List<Transaction> refunds) {
    final total = refunds.fold<double>(0, (sum, r) => sum + r.amount);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.replay,
                  size: 16, color: BeeTokens.iconTertiary(context)),
              const SizedBox(width: 6),
              Text(
                l10n.txDetailRefundedTotal,
                style: TextStyle(
                  fontSize: 13,
                  color: BeeTokens.textSecondary(context),
                ),
              ),
              const Spacer(),
              AmountText(
                value: total,
                signed: false,
                decimals: 2,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: BeeTokens.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...refunds.map((r) {
            final rDate =
                '${r.happenedAt.year}/${r.happenedAt.month.toString().padLeft(2, '0')}/${r.happenedAt.day.toString().padLeft(2, '0')}';
            return InkWell(
              onTap: () {
                final syncId = r.syncId;
                if (syncId != null) _jumpToTransactionBySyncId(syncId);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(rDate,
                        style: TextStyle(
                            fontSize: 12,
                            color: BeeTokens.textTertiary(context))),
                    const Spacer(),
                    AmountText(
                      value: r.amount,
                      signed: false,
                      decimals: 2,
                      style: TextStyle(
                          fontSize: 12,
                          color: BeeTokens.textSecondary(context)),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right,
                        size: 16, color: BeeTokens.iconTertiary(context)),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
