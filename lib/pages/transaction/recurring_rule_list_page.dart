import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../styles/tokens.dart';
import '../../utils/transaction_edit_utils.dart';
import '../../widgets/biz/recurring_occurrence_dialogs.dart';
import '../../widgets/biz/recurring_rule_advanced_sheet.dart';
import '../../widgets/ui/ui.dart';
import 'recurring_rule_editor_page.dart';

/// 週期性收支規則列表(v2,對齊 Web 端規則總覽+編輯 Modal)——依 `enabled`
/// 分「進行中」/「已結束或已停用」兩組。每張規則卡片可展開看已生成的期數
/// 明細(單筆編輯/連同以後/刪除),規則本身支援快速啟停、終止未來週期、
/// 編輯全部欄位、刪除整條規則。
class RecurringRuleListPage extends ConsumerStatefulWidget {
  const RecurringRuleListPage({super.key});

  @override
  ConsumerState<RecurringRuleListPage> createState() =>
      _RecurringRuleListPageState();
}

class _RecurringRuleListPageState extends ConsumerState<RecurringRuleListPage> {
  final Set<int> _expandedRuleIds = {};

  void _toggleExpand(int ruleId) {
    setState(() {
      if (!_expandedRuleIds.remove(ruleId)) _expandedRuleIds.add(ruleId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final repo = ref.watch(repositoryProvider);
    final categoriesById = <int, Category>{
      for (final c in ref.watch(categoriesProvider).asData?.value ?? const [])
        c.id: c,
    };

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.recurringRuleListTitle,
            showBack: true,
          ),
          Expanded(
            child: StreamBuilder<List<RecurringTransaction>>(
              stream: repo.watchRulesByLedger(ledgerId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rules = snapshot.data!;
                if (rules.isEmpty) {
                  return _buildEmptyState(context, l10n);
                }
                final active = rules.where((r) => r.enabled).toList();
                final ended = rules.where((r) => !r.enabled).toList();
                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    if (active.isNotEmpty)
                      _buildSection(
                        context,
                        title:
                            '${l10n.recurringRuleListActive}(${active.length})',
                        rules: active,
                        categoriesById: categoriesById,
                      ),
                    if (ended.isNotEmpty)
                      _buildSection(
                        context,
                        title:
                            '${l10n.recurringRuleListEnded}(${ended.length})',
                        rules: ended,
                        categoriesById: categoriesById,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.repeat, size: 64, color: BeeTokens.textTertiary(context)),
          const SizedBox(height: 16),
          Text(
            l10n.recurringRuleListEmpty,
            style: TextStyle(
                fontSize: 14, color: BeeTokens.textSecondary(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<RecurringTransaction> rules,
    required Map<int, Category> categoriesById,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: BeeTokens.textSecondary(context),
              ),
            ),
          ),
          ...rules.map((r) => _RecurringRuleTile(
                key: ValueKey(r.id),
                rule: r,
                category: r.categoryId != null ? categoriesById[r.categoryId] : null,
                expanded: _expandedRuleIds.contains(r.id),
                onToggleExpand: () => _toggleExpand(r.id),
                onDelete: () => _confirmAndDelete(context, ref, r),
              )),
        ],
      ),
    );
  }

  Future<void> _confirmAndDelete(
      BuildContext context, WidgetRef ref, RecurringTransaction rule) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialog.confirm<bool>(
          context,
          title: l10n.recurringRuleDeleteConfirmTitle,
          message: l10n.recurringRuleDeleteConfirmMessage,
        ) ??
        false;
    if (!confirmed) return;

    final repo = ref.read(repositoryProvider);
    await repo.deleteRule(rule.id, deleteFutureOccurrences: true);
    final ledgerId = ref.read(currentLedgerIdProvider);
    ref.invalidate(countsForLedgerProvider(ledgerId));
    ref.read(statsRefreshProvider.notifier).state++;
    PostProcessor.sync(ref, ledgerId: ledgerId);
  }
}

class _RecurringRuleTile extends ConsumerWidget {
  final RecurringTransaction rule;
  final Category? category;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onDelete;

  const _RecurringRuleTile({
    super.key,
    required this.rule,
    required this.category,
    required this.expanded,
    required this.onToggleExpand,
    required this.onDelete,
  });

  IconData _typeIcon() {
    switch (rule.type) {
      case 'income':
        return Icons.arrow_downward;
      case 'transfer':
        return Icons.swap_horiz;
      default:
        return Icons.arrow_upward;
    }
  }

  Map<String, dynamic>? _decodeAdvancedRule() {
    final raw = rule.advancedRuleJson;
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // 忽略格式錯誤的舊資料,當作沒有進階規則。
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final draft = RecurringRuleDraft(
      frequency: rule.frequency,
      interval: rule.interval,
      advancedRule: _decodeAdvancedRule(),
      endAt: rule.endAt,
    );
    final title = (rule.note != null && rule.note!.isNotEmpty)
        ? rule.note!
        : (rule.merchant ?? rule.type);
    final subtitleParts = <String>[draft.summary(l10n)];
    if (category != null) subtitleParts.insert(0, category!.name);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: BeeTokens.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BeeTokens.border(context)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_typeIcon(),
                      size: 20, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$title · ${rule.amount.toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: rule.enabled
                                      ? BeeTokens.textPrimary(context)
                                      : BeeTokens.textTertiary(context)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _buildStatusBadge(context, l10n),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitleParts.join(' · '),
                        style: TextStyle(
                            fontSize: 12.5,
                            color: BeeTokens.textSecondary(context)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Switch(
                  value: rule.enabled,
                  onChanged: (v) => ref
                      .read(repositoryProvider)
                      .setRuleEnabled(rule.id, v)
                      .then((_) {
                    final ledgerId = ref.read(currentLedgerIdProvider);
                    PostProcessor.sync(ref, ledgerId: ledgerId);
                  }),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onToggleExpand,
                  child: Text(expanded
                      ? l10n.recurringRuleCollapse
                      : l10n.recurringRuleExpand),
                ),
                TextButton(
                  onPressed: () => _confirmTerminateFuture(context, ref),
                  child: Text(l10n.recurringRuleTerminateFutureLabel),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RecurringRuleEditorPage(rule: rule),
                    ),
                  ),
                  child: Text(l10n.commonEdit),
                ),
                TextButton(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(
                      foregroundColor: BeeTokens.error(context)),
                  child: Text(l10n.commonDelete),
                ),
              ],
            ),
          ),
          if (expanded) _OccurrenceList(rule: rule),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (rule.enabled
                ? BeeTokens.success(context)
                : BeeTokens.textTertiary(context))
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        rule.enabled
            ? l10n.recurringRuleEnabledLabel
            : l10n.recurringRuleDisabledLabel,
        style: TextStyle(
          fontSize: 11,
          color: rule.enabled
              ? BeeTokens.success(context)
              : BeeTokens.textTertiary(context),
        ),
      ),
    );
  }

  Future<void> _confirmTerminateFuture(
      BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialog.confirm<bool>(
          context,
          title: l10n.recurringRuleTerminateFutureConfirmTitle,
          message: l10n.recurringRuleTerminateFutureConfirmMessage,
        ) ??
        false;
    if (!confirmed) return;
    final repo = ref.read(repositoryProvider);
    await repo.terminateFuture(rule.id);
    final ledgerId = ref.read(currentLedgerIdProvider);
    ref.invalidate(countsForLedgerProvider(ledgerId));
    ref.read(statsRefreshProvider.notifier).state++;
    PostProcessor.sync(ref, ledgerId: ledgerId);
  }
}

class _OccurrenceList extends ConsumerWidget {
  final RecurringTransaction rule;

  const _OccurrenceList({required this.rule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.watch(repositoryProvider);
    final syncId = rule.syncId;
    if (syncId == null || syncId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<List<Transaction>>(
      future: repo.getOccurrencesForRule(syncId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final occurrences = snapshot.data!;
        if (occurrences.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              l10n.recurringRuleOccurrencesEmpty,
              style: TextStyle(
                  fontSize: 13, color: BeeTokens.textTertiary(context)),
            ),
          );
        }
        return Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: BeeTokens.divider(context))),
          ),
          child: Column(
            children: occurrences
                .map((t) => _OccurrenceTile(rule: rule, transaction: t))
                .toList(),
          ),
        );
      },
    );
  }
}

class _OccurrenceTile extends ConsumerWidget {
  final RecurringTransaction rule;
  final Transaction transaction;

  const _OccurrenceTile({required this.rule, required this.transaction});

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(
            _fmtDate(transaction.happenedAt),
            style: TextStyle(fontSize: 13, color: BeeTokens.textPrimary(context)),
          ),
          const SizedBox(width: 8),
          Text(
            transaction.amount.toStringAsFixed(2),
            style: TextStyle(fontSize: 13, color: BeeTokens.textPrimary(context)),
          ),
          if (transaction.recurringOccurrenceOverridden) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: BeeTokens.warning(context).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                l10n.recurringOccurrenceOverriddenLabel,
                style: TextStyle(fontSize: 10, color: BeeTokens.warning(context)),
              ),
            ),
          ],
          const Spacer(),
          if (!transaction.recurringOccurrenceOverridden)
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RecurringRuleEditorPage(
                    rule: rule,
                    anchorTransactionId: transaction.id,
                  ),
                ),
              ),
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: Text(l10n.recurringOccurrenceUpdateFrom,
                  style: const TextStyle(fontSize: 12)),
            ),
          TextButton(
            onPressed: () async {
              final repo = ref.read(repositoryProvider);
              final category = transaction.categoryId != null
                  ? await repo.getCategoryById(transaction.categoryId!)
                  : null;
              if (!context.mounted) return;
              await TransactionEditUtils.editTransaction(
                context,
                ref,
                transaction,
                category,
                forcedScope: RecurringEditScope.thisOnly,
              );
            },
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Text(l10n.recurringOccurrenceEdit,
                style: const TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: () async {
              final repo = ref.read(repositoryProvider);
              await repo.deleteOccurrence(transaction.id);
              final ledgerId = ref.read(currentLedgerIdProvider);
              ref.invalidate(countsForLedgerProvider(ledgerId));
              ref.read(statsRefreshProvider.notifier).state++;
              PostProcessor.sync(ref, ledgerId: ledgerId);
            },
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: BeeTokens.error(context)),
            child: Text(l10n.recurringOccurrenceDelete,
                style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
