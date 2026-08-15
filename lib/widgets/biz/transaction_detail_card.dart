import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/repositories/local/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/budget_providers.dart';
import '../../services/attachment_service.dart';
import '../../services/billing/post_processor.dart';
import '../../styles/tokens.dart';
import '../../utils/account_type_utils.dart';
import '../../utils/category_utils.dart';
import '../../utils/transaction_edit_utils.dart';
import '../../pages/attachment/attachment_preview_page.dart';
import '../category_icon.dart';
import '../ui/ui.dart';
import 'amount_text.dart';

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

class _DetailBundle {
  final _AccountDisplay? account;
  final List<Tag> tags;
  final List<TransactionAttachment> attachments;
  final List<Transaction> refunds;

  const _DetailBundle({
    required this.account,
    required this.tags,
    required this.attachments,
    required this.refunds,
  });
}

class TransactionDetailCard extends ConsumerStatefulWidget {
  /// 打开卡片那个页面的 context——用来在卡片关闭"之后"继续 push 编辑器
  /// 页面(卡片自己的 context 在 pop 之后就失效了)。
  final BuildContext hostContext;
  final Transaction transaction;
  final Category? category;

  const TransactionDetailCard({
    super.key,
    required this.hostContext,
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

    final account = await accountFuture;
    final tags = await tagsFuture;
    final attachments = await attachmentsFuture;
    final refunds = await refundsFuture;
    return _DetailBundle(
      account: account,
      tags: tags,
      attachments: attachments,
      refunds: refunds,
    );
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
    await showTransactionDetailCard(hostContext, ref, target, targetCategory);
  }

  Future<void> _handleDelete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialog.confirm<bool>(
          context,
          title: l10n.deleteConfirmTitle,
          message: l10n.deleteConfirmMessage,
        ) ??
        false;
    if (!confirmed || !mounted) return;

    final repo = ref.read(repositoryProvider);
    await repo.deleteTransaction(widget.transaction.id);
    if (!mounted) return;

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
        hostContext, ref, widget.transaction, widget.category);
  }

  Future<void> _handleEdit() async {
    final hostContext = widget.hostContext;
    Navigator.of(context).pop();
    if (!hostContext.mounted) return;
    await TransactionEditUtils.editTransaction(
        hostContext, ref, widget.transaction, widget.category);
  }

  Future<void> _handleRefund() async {
    final hostContext = widget.hostContext;
    Navigator.of(context).pop();
    if (!hostContext.mounted) return;
    await TransactionEditUtils.refundTransaction(
        hostContext, ref, widget.transaction, widget.category);
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
      final displayName = CategoryUtils.getDisplayName(
          widget.category?.name, context,
          kind: categoryKind);
      return Container(
        width: double.infinity,
        height: 220,
        alignment: Alignment.center,
        color: BeeTokens.surfaceElevated(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CategoryIconWidget(
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
    final categoryDisplayName = CategoryUtils.getDisplayName(
        widget.category?.name, context,
        kind: categoryKind);
    final noteText = (tx.note != null && tx.note!.isNotEmpty)
        ? tx.note!
        : categoryDisplayName;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          CategoryIconWidget(
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
                if (isRefundTx) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      final original = tx.refundOfSyncId;
                      if (original != null)
                        _jumpToTransactionBySyncId(original);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: BeeTokens.iconSecondary(context)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        l10n.txDetailRefundBadge,
                        style: TextStyle(
                          fontSize: 11,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                    ),
                  ),
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
        tx.recurringId == null ? l10n.txDetailOnce : l10n.txDetailRecurring;
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
