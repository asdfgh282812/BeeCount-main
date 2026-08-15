import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../styles/tokens.dart';
import '../../widgets/biz/card_reward_rule_actions.dart';
import '../../widgets/ui/ui.dart';
import 'card_reward_rule_editor_page.dart';

/// 信用卡「紅利回饋列表」頁——依 `enabled` + `endsAt` 分成「進行中」/「已結束」
/// 兩組,各自支援拖曳排序,右上角「+」新增。
class CardRewardRuleListPage extends ConsumerStatefulWidget {
  final int accountId;
  final String accountName;

  const CardRewardRuleListPage({
    super.key,
    required this.accountId,
    required this.accountName,
  });

  @override
  ConsumerState<CardRewardRuleListPage> createState() =>
      _CardRewardRuleListPageState();
}

class _CardRewardRuleListPageState
    extends ConsumerState<CardRewardRuleListPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rulesAsync =
        ref.watch(cardRewardRulesForAccountProvider(widget.accountId));

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.cardRewardRuleListTitle,
            showBack: true,
            actions: [
              IconButton(
                onPressed: _addRule,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          Expanded(
            child: rulesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('${l10n.commonError}: $e')),
              data: (rules) {
                if (rules.isEmpty) {
                  return _buildEmptyState(l10n);
                }
                final now = DateTime.now();
                final active = rules
                    .where((r) =>
                        r.enabled &&
                        (r.endsAt == null || r.endsAt!.isAfter(now)))
                    .toList();
                final ended = rules
                    .where((r) =>
                        !r.enabled ||
                        (r.endsAt != null && !r.endsAt!.isAfter(now)))
                    .toList();
                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    if (active.isNotEmpty)
                      _buildSection(
                        title: l10n.cardRewardRuleActiveSection(active.length),
                        rules: active,
                        reorderable: true,
                      ),
                    if (ended.isNotEmpty)
                      _buildSection(
                        title: l10n.cardRewardRuleEndedSection(ended.length),
                        rules: ended,
                        reorderable: false,
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

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.card_giftcard_outlined,
              size: 64, color: BeeTokens.textTertiary(context)),
          const SizedBox(height: 16),
          Text(
            l10n.cardRewardRuleEmptyState,
            style: TextStyle(
                fontSize: 14, color: BeeTokens.textSecondary(context)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<CardRewardRule> rules,
    required bool reorderable,
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
          if (reorderable)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rules.length,
              onReorder: (oldIndex, newIndex) =>
                  _onReorder(rules, oldIndex, newIndex),
              itemBuilder: (context, index) => _CardRewardRuleTile(
                key: ValueKey(rules[index].id),
                rule: rules[index],
                onTap: () => _editRule(rules[index]),
                onCopy: () =>
                    duplicateCardRewardRule(context, ref, rules[index]),
                onDelete: () =>
                    confirmAndDeleteCardRewardRule(context, ref, rules[index]),
              ),
            )
          else
            ...rules.map((r) => _CardRewardRuleTile(
                  key: ValueKey(r.id),
                  rule: r,
                  onTap: () => _editRule(r),
                  onCopy: () => duplicateCardRewardRule(context, ref, r),
                  onDelete: () =>
                      confirmAndDeleteCardRewardRule(context, ref, r),
                )),
        ],
      ),
    );
  }

  Future<void> _onReorder(
      List<CardRewardRule> rules, int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    final reordered = List<CardRewardRule>.from(rules);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    final repo = ref.read(repositoryProvider);
    final updates = <({int id, int sortOrder})>[];
    for (var i = 0; i < reordered.length; i++) {
      updates.add((id: reordered[i].id, sortOrder: i));
    }
    await repo.updateCardRewardRuleSortOrders(updates);

    final activeLedgerId = ref.read(currentLedgerIdProvider);
    if (activeLedgerId > 0) {
      unawaited(PostProcessor.sync(ref, ledgerId: activeLedgerId));
    }
  }

  Future<void> _addRule() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CardRewardRuleEditorPage(
          accountId: widget.accountId,
          accountName: widget.accountName,
        ),
      ),
    );
  }

  Future<void> _editRule(CardRewardRule rule) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CardRewardRuleEditorPage(
          accountId: widget.accountId,
          accountName: widget.accountName,
          rule: rule,
        ),
      ),
    );
  }
}

class _CardRewardRuleTile extends StatelessWidget {
  final CardRewardRule rule;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  const _CardRewardRuleTile({
    super.key,
    required this.rule,
    required this.onTap,
    required this.onCopy,
    required this.onDelete,
  });

  String _rateLabel() {
    if (rule.rateType == 'fixed_amount') {
      final v = rule.rateValue;
      final s = v.toStringAsFixed(v == v.truncateToDouble() ? 0 : 2);
      return s;
    }
    final v = rule.rateValue;
    final s = v.toStringAsFixed(v == v.truncateToDouble() ? 0 : 2);
    return '$s%';
  }

  String _dateRangeLabel() {
    String fmt(DateTime? d) {
      if (d == null) return '';
      return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    }

    return '${fmt(rule.startsAt)} – ${fmt(rule.endsAt)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final capLabel = rule.capAmount != null
        ? l10n.cardRewardRuleCapUpTo(rule.capAmount!.toStringAsFixed(
            rule.capAmount == rule.capAmount!.truncateToDouble() ? 0 : 2))
        : l10n.cardRewardRuleCapNone;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              child: Icon(Icons.card_giftcard,
                  size: 20, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.label,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: rule.enabled
                            ? BeeTokens.textPrimary(context)
                            : BeeTokens.textTertiary(context)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_rateLabel()} | $capLabel',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: BeeTokens.textSecondary(context)),
                  ),
                  Text(
                    _dateRangeLabel(),
                    style: TextStyle(
                        fontSize: 11.5, color: BeeTokens.textTertiary(context)),
                  ),
                ],
              ),
            ),
            BeePopupMenu(
              tooltip: l10n.commonMore,
              items: [
                BeeMenuItem.action(
                  value: 'copy',
                  icon: Icons.copy_outlined,
                  label: l10n.cardRewardRuleCopy,
                ),
                BeeMenuItem.action(
                  value: 'delete',
                  icon: Icons.delete_outline,
                  label: l10n.cardRewardRuleDelete,
                  isDanger: true,
                ),
              ],
              onSelected: (value) {
                if (value == 'copy') onCopy();
                if (value == 'delete') onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}
