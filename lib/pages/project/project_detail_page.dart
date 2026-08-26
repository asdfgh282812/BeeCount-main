import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/repositories/project_repository.dart' show ProjectWithUsage;
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/project_providers.dart';
import '../../services/data/category_service.dart';
import '../../styles/tokens.dart';
import '../../utils/category_utils.dart';
import '../../utils/currencies.dart';
import '../../widgets/biz/biz.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/ui/ui.dart';
import '../budget/widgets/budget_progress_bar.dart';
import 'project_edit_page.dart';

/// 專案詳情頁(design doc §7):完整統計 + 該專案的交易列表。
class ProjectDetailPage extends ConsumerWidget {
  final int projectId;

  const ProjectDetailPage({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final dataAsync = ref.watch(projectUsageProvider(projectId));

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          dataAsync.when(
            data: (data) => PrimaryHeader(
              title: data?.project.name ?? '',
              showBack: true,
              compact: true,
              actions: [
                if (data != null)
                  IconButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              ProjectEditPage(project: data.project)),
                    ),
                    icon: const Icon(Icons.edit_outlined),
                  ),
              ],
            ),
            loading: () => PrimaryHeader(title: '', showBack: true, compact: true),
            error: (_, __) => PrimaryHeader(title: '', showBack: true, compact: true),
          ),
          Expanded(
            child: dataAsync.when(
              data: (data) => data == null
                  ? Center(child: Text(l10n.projectOverviewEmptyHint))
                  : _ProjectDetailBody(data: data),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectDetailBody extends ConsumerWidget {
  final ProjectWithUsage data;

  const _ProjectDetailBody({required this.data});

  String _periodLabel(AppLocalizations l10n) {
    final project = data.project;
    final usage = data.usage;
    switch (project.periodType) {
      case 'yearly':
        return l10n.projectPeriodYearlyLabel(usage.periodStart.year);
      case 'fixed':
        final s = usage.periodStart;
        final e = project.periodEnd ?? usage.periodEnd;
        return '${s.year}/${s.month}/${s.day} – ${e.year}/${e.month}/${e.day}';
      case 'monthly':
      default:
        return l10n.projectPeriodMonthlyLabel;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final project = data.project;
    final usage = data.usage;
    final currencyCode =
        ref.watch(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    final currencySymbol = getCurrencySymbol(currencyCode);
    final txsAsync = ref.watch(_projectTransactionsProvider(project.syncId));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SectionCard(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(CategoryService.getCategoryIcon(project.icon),
                        color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(project.name,
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: BeeTokens.textPrimary(context))),
                        Text(_periodLabel(l10n),
                            style: TextStyle(
                                fontSize: 12,
                                color: BeeTokens.textTertiary(context))),
                      ],
                    ),
                  ),
                  if (!project.enabled)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color:
                            BeeTokens.textTertiary(context).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(l10n.projectCardArchivedBadge,
                          style: TextStyle(
                              fontSize: 11,
                              color: BeeTokens.textTertiary(context))),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (usage.budget == null)
                Text(l10n.projectDetailPureTrackingHint,
                    style: TextStyle(color: BeeTokens.textSecondary(context)))
              else ...[
                BudgetProgressBar(
                  used: usage.used,
                  budget: usage.effectiveBudget!,
                  showLabel: false,
                  height: 10,
                  currencySymbol: currencySymbol,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.budgetUsed,
                            style: TextStyle(
                                fontSize: 12,
                                color: BeeTokens.textSecondary(context))),
                        Text('$currencySymbol${usage.used.toStringAsFixed(2)}',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: BeeTokens.textPrimary(context))),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(l10n.budgetRemaining,
                            style: TextStyle(
                                fontSize: 12,
                                color: BeeTokens.textSecondary(context))),
                        Text(
                            '$currencySymbol${usage.remaining!.toStringAsFixed(2)}',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: usage.remaining! >= 0
                                    ? Colors.green
                                    : Colors.red)),
                      ],
                    ),
                  ],
                ),
                if (usage.carriedOver != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${l10n.projectDetailCarriedOverLabel}: '
                    '$currencySymbol${usage.carriedOver!.toStringAsFixed(2)}',
                    style:
                        TextStyle(fontSize: 12, color: BeeTokens.textSecondary(context)),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        txsAsync.when(
          data: (txs) => txs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(l10n.projectDetailNoTransactionsHint,
                        style:
                            TextStyle(color: BeeTokens.textTertiary(context))),
                  ),
                )
              : _TransactionsSection(transactions: txs),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ],
    );
  }
}

final _projectTransactionsProvider =
    FutureProvider.family<List<Transaction>, String?>((ref, syncId) async {
  ref.watch(projectRefreshProvider);
  if (syncId == null) return [];
  final repo = ref.watch(repositoryProvider);
  return repo.getTransactionsByProject(syncId);
});

class _TransactionsSection extends ConsumerWidget {
  final List<Transaction> transactions;

  const _TransactionsSection({required this.transactions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: FutureBuilder<List<Category>>(
        future: ref.read(repositoryProvider).getAllCategories(),
        builder: (context, snapshot) {
          final categories = {
            for (final c in snapshot.data ?? const <Category>[]) c.id: c,
          };
          return Column(
            children: [
              for (final entry in transactions.indexed) ...[
                if (entry.$1 > 0) BeeDivider.short(indent: 56 + 16, endIndent: 16),
                _buildRow(context, ref, entry.$2, categories),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildRow(BuildContext context, WidgetRef ref, Transaction t,
      Map<int, Category> categories) {
    final category = t.categoryId != null ? categories[t.categoryId] : null;
    final categoryName = CategoryUtils.getDisplayName(category?.name, context);
    final iconData =
        getCategoryIconData(category: category, categoryName: categoryName);

    return TransactionListItem(
      icon: iconData,
      category: category,
      title: t.note ?? '',
      categoryName: categoryName,
      amount: t.amount,
      currencyCode: t.currencyCode,
      nativeAmount: t.nativeAmount,
      isExpense: t.type == 'expense',
      happenedAt: t.happenedAt,
      hasSplits: t.hasSplits,
      showFullDate: true,
      onTap: () => showTransactionDetailCard(context, ref, t, category),
    );
  }
}
