import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../styles/tokens.dart';
import '../../widgets/biz/recurring_rule_advanced_sheet.dart';
import '../../widgets/ui/ui.dart';

/// 週期性收支規則列表(v36,取代舊版純本地「周期記帳」頁)——依 `enabled`
/// 分「進行中」/「已結束」兩組,同 `card_reward_rule_list_page.dart` 的分組
/// 慣例。v1 範圍:只提供檢視 + 整條規則刪除,不支援就地編輯規則設定(規則
/// 的欄位/排程只能透過新增交易時的「週期」入口一次性建立,見
/// docs/changes 對這個範圍決策的說明)。
class RecurringRuleListPage extends ConsumerWidget {
  const RecurringRuleListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final repo = ref.watch(repositoryProvider);

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
                        ref: ref,
                      ),
                    if (ended.isNotEmpty)
                      _buildSection(
                        context,
                        title:
                            '${l10n.recurringRuleListEnded}(${ended.length})',
                        rules: ended,
                        ref: ref,
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
    required WidgetRef ref,
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

class _RecurringRuleTile extends StatelessWidget {
  final RecurringTransaction rule;
  final VoidCallback onDelete;

  const _RecurringRuleTile({
    super.key,
    required this.rule,
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
  Widget build(BuildContext context) {
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

    return InkWell(
      onTap: null,
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
              child: Icon(_typeIcon(),
                  size: 20, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$title · ${rule.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: rule.enabled
                            ? BeeTokens.textPrimary(context)
                            : BeeTokens.textTertiary(context)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    draft.summary(l10n),
                    style: TextStyle(
                        fontSize: 12.5,
                        color: BeeTokens.textSecondary(context)),
                  ),
                ],
              ),
            ),
            BeePopupMenu(
              tooltip: l10n.commonMore,
              items: [
                BeeMenuItem.action(
                  value: 'delete',
                  icon: Icons.delete_outline,
                  label: l10n.commonDelete,
                  isDanger: true,
                ),
              ],
              onSelected: (value) {
                if (value == 'delete') onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}
