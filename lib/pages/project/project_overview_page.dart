import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/budget_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/budget_providers.dart';
import '../../providers/project_providers.dart';
import '../../services/data/category_service.dart';
import '../../styles/tokens.dart';
import '../../utils/currencies.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/biz.dart';
import '../../widgets/ui/ui.dart';
import '../budget/budget_edit_page.dart';
import '../budget/widgets/budget_progress_bar.dart';
import 'project_detail_page.dart';
import 'project_edit_page.dart';

/// 專案總覽頁(design doc §7),取代原本的 `BudgetPage`。頂部沿用總預算長條
/// (`type='total'` 的 `Budgets`,語意獨立於專案標記之外——design doc §0
/// 決策 2),下方是專案卡片列表。
class ProjectOverviewPage extends ConsumerStatefulWidget {
  // 作为底部导览「专案」分页时 true(隐藏返回箭头,同 AccountsPage.asTab)。
  final bool asTab;

  const ProjectOverviewPage({super.key, this.asTab = false});

  @override
  ConsumerState<ProjectOverviewPage> createState() =>
      _ProjectOverviewPageState();
}

class _ProjectOverviewPageState extends ConsumerState<ProjectOverviewPage> {
  bool _showArchived = false;

  bool _isEditorInShared(WidgetRef ref) {
    final l = ref.read(currentLedgerProvider).asData?.value;
    return l != null && l.isShared && l.myRole != 'owner';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEditorInShared = _isEditorInShared(ref);
    final projectsAsync = ref.watch(_showArchived
        ? allProjectUsagesIncludingDisabledProvider
        : projectUsagesProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.projectOverviewTitle,
            showBack: !widget.asTab,
            compact: true,
            actions: [
              IconButton(
                tooltip: _showArchived
                    ? l10n.projectHideArchived
                    : l10n.projectShowArchived,
                onPressed: () =>
                    setState(() => _showArchived = !_showArchived),
                icon: Icon(
                    _showArchived ? Icons.visibility_off : Icons.visibility),
              ),
              if (!isEditorInShared)
                IconButton(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ProjectEditPage())),
                  icon: const Icon(Icons.add),
                ),
            ],
          ),
          Expanded(
            child: projectsAsync.when(
              data: (projects) => _buildContent(context, ref, projects),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    List<ProjectWithUsage> projects,
  ) {
    final l10n = AppLocalizations.of(context);
    final currencyCode =
        ref.watch(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    final currencySymbol = getCurrencySymbol(currencyCode);
    final totalOverviewAsync = ref.watch(budgetOverviewProvider);
    final isEditorInShared = _isEditorInShared(ref);

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: 12.0.scaled(context, ref),
        vertical: 8.0.scaled(context, ref),
      ),
      children: [
        totalOverviewAsync.when(
          data: (overview) => _buildTotalBudgetSection(
              context, ref, overview, l10n, currencySymbol, isEditorInShared),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        SizedBox(height: 12.0.scaled(context, ref)),
        if (projects.isEmpty)
          _buildEmptyState(context, l10n, isEditorInShared)
        else
          ...projects.map((p) => Padding(
                padding: EdgeInsets.only(bottom: 10.0.scaled(context, ref)),
                child: _ProjectCard(
                  data: p,
                  currencySymbol: currencySymbol,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            ProjectDetailPage(projectId: p.project.id)),
                  ),
                ),
              )),
      ],
    );
  }

  Widget _buildTotalBudgetSection(
    BuildContext context,
    WidgetRef ref,
    BudgetOverview? overview,
    AppLocalizations l10n,
    String currencySymbol,
    bool isEditorInShared,
  ) {
    final budget = overview?.totalBudget;
    if (budget == null) {
      if (isEditorInShared) return const SizedBox.shrink();
      return SectionCard(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const BudgetEditPage())),
          child: Row(
            children: [
              Icon(Icons.add_circle_outline,
                  color: BeeTokens.iconSecondary(context)),
              const SizedBox(width: 8),
              Text(l10n.projectSetTotalBudgetCta,
                  style: TextStyle(color: BeeTokens.textSecondary(context))),
            ],
          ),
        ),
      );
    }

    return SectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.budgetMonthlyBudget,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: BeeTokens.textPrimary(context),
                ),
              ),
              if (!isEditorInShared)
                TextButton(
                  onPressed: () async {
                    final totalBudget =
                        await ref.read(totalBudgetProvider.future);
                    if (totalBudget != null && context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                BudgetEditPage(budget: totalBudget)),
                      );
                    }
                  },
                  child: Text(l10n.commonEdit),
                ),
            ],
          ),
          SizedBox(height: 16.0.scaled(context, ref)),
          BudgetProgressBar(
            used: budget.used,
            budget: budget.budget,
            showLabel: false,
            height: 12,
            currencySymbol: currencySymbol,
          ),
          SizedBox(height: 12.0.scaled(context, ref)),
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
                  Text('$currencySymbol${budget.used.toStringAsFixed(2)}',
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
                      '$currencySymbol${budget.remaining.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color:
                              budget.remaining >= 0 ? Colors.green : Colors.red)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    AppLocalizations l10n,
    bool isEditorInShared,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_outlined,
                size: 64, color: BeeTokens.textTertiary(context)),
            const SizedBox(height: 16),
            Text(l10n.projectOverviewEmptyHint,
                style:
                    TextStyle(fontSize: 16, color: BeeTokens.textSecondary(context))),
            const SizedBox(height: 24),
            if (!isEditorInShared)
              ElevatedButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProjectEditPage())),
                icon: Icon(Icons.add,
                    color: BeeTokens.buttonPrimaryText(context)),
                label: Text(l10n.projectAddCta),
                style: ElevatedButton.styleFrom(
                  backgroundColor: BeeTokens.buttonPrimary(context),
                  foregroundColor: BeeTokens.buttonPrimaryText(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final ProjectWithUsage data;
  final String currencySymbol;
  final VoidCallback onTap;

  const _ProjectCard({
    required this.data,
    required this.currencySymbol,
    required this.onTap,
  });

  String _periodLabel(AppLocalizations l10n) {
    final project = data.project;
    switch (project.periodType) {
      case 'yearly':
        return l10n.projectPeriodYearlyLabel(data.usage.periodStart.year);
      case 'fixed':
        final s = data.usage.periodStart;
        final e = project.periodEnd ?? data.usage.periodEnd;
        return '${s.month}/${s.day}–${e.month}/${e.day}';
      case 'monthly':
      default:
        return l10n.projectPeriodMonthlyLabel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final project = data.project;
    final usage = data.usage;

    return SectionCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(CategoryService.getCategoryIcon(project.icon),
                        color: Theme.of(context).colorScheme.primary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: BeeTokens.textPrimary(context)),
                    ),
                  ),
                  if (!project.enabled) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color:
                            BeeTokens.textTertiary(context).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(l10n.projectCardArchivedBadge,
                          style: TextStyle(
                              fontSize: 10,
                              color: BeeTokens.textTertiary(context))),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Text(_periodLabel(l10n),
                      style: TextStyle(
                          fontSize: 11, color: BeeTokens.textTertiary(context))),
                ],
              ),
              const SizedBox(height: 10),
              if (usage.budget == null)
                Text(l10n.projectCardPureTracking,
                    style:
                        TextStyle(fontSize: 12, color: BeeTokens.textTertiary(context)))
              else ...[
                BudgetProgressBar(
                  used: usage.used,
                  budget: usage.effectiveBudget!,
                  showLabel: false,
                  height: 6,
                  currencySymbol: currencySymbol,
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        '${l10n.budgetUsed} $currencySymbol${usage.used.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: BeeTokens.textSecondary(context))),
                    Text(
                        '${l10n.budgetRemaining} $currencySymbol${usage.remaining!.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: usage.remaining! >= 0
                                ? Colors.green
                                : Colors.red)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
