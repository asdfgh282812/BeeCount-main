import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/repositories/project_repository.dart'
    show ProjectCategoryUsage, ProjectUsage;
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
import 'project_category_budget_edit_page.dart';
import 'project_edit_page.dart';

/// 專案詳情頁(design doc 2026-09-06):期間切換 + 出入帳統計條 + 分類子預算
/// 拆解 + 交易列表。取代舊版「單一進度條 + 全時間交易流水」。
class ProjectDetailPage extends ConsumerWidget {
  final int projectId;

  const ProjectDetailPage({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final dataAsync = ref.watch(projectDetailDataProvider(projectId));

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
                if (data != null) ...[
                  IconButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProjectCategoryBudgetEditPage(
                            project: data.project),
                      ),
                    ),
                    icon: const Icon(Icons.settings_outlined),
                  ),
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
              ],
            ),
            loading: () =>
                PrimaryHeader(title: '', showBack: true, compact: true),
            error: (_, __) =>
                PrimaryHeader(title: '', showBack: true, compact: true),
          ),
          Expanded(
            child: dataAsync.when(
              data: (data) => data == null
                  ? Center(child: Text(l10n.projectOverviewEmptyHint))
                  : _ProjectDetailBody(projectId: projectId, data: data),
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
  final int projectId;
  final ProjectDetailData data;

  const _ProjectDetailBody({required this.projectId, required this.data});

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
        if (data.offset == 0) return l10n.projectPeriodMonthlyLabel;
        final s = usage.periodStart;
        return '${s.year}/${s.month.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _openPeriodPicker(BuildContext context, WidgetRef ref) async {
    final project = data.project;
    if (project.periodType == 'fixed') return;
    final monthStartDay =
        ref.read(currentLedgerProvider).value?.monthStartDay ?? 1;
    final selected = await showPeriodRangeListPicker(
      context,
      periodType: project.periodType,
      currentOffset: data.offset,
      monthStartDay: monthStartDay,
    );
    if (selected != null) {
      ref.read(projectPeriodOffsetProvider.notifier).setOffset(
            projectId,
            selected,
          );
    }
  }

  double _resolvedCategoryBudgetAmount(
      ProjectCategoryBudget b, double effectiveBudget) {
    if (b.mode == 'percentage') {
      return effectiveBudget * (b.percentage ?? 0) / 100;
    }
    return b.fixedAmount ?? 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final project = data.project;
    final usage = data.usage;
    final currencyCode =
        ref.watch(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    final currencySymbol = getCurrencySymbol(currencyCode);

    final breakdown = data.breakdown;
    final expenseTotal =
        breakdown.fold<double>(0, (sum, b) => sum + b.expenseTotal);
    final incomeTotal =
        breakdown.fold<double>(0, (sum, b) => sum + b.incomeTotal);
    final netTotal = incomeTotal - expenseTotal;
    final recordCount = breakdown.fold<int>(0, (sum, b) => sum + b.recordCount);

    final budgetByCategory = {
      for (final b in data.categoryBudgets) b.categoryId: b,
    };
    final breakdownByCategory = <int, ProjectCategoryUsage>{
      for (final b in breakdown)
        if (b.categoryId != null) b.categoryId!: b,
    };
    final categoryById = {
      for (final c in data.allCategories) c.id: c,
    };
    final level1Categories =
        data.allCategories.where((c) => c.level == 1).toList();

    final allocated = <MapEntry<Category, ProjectCategoryUsage>>[];
    final unallocated = <MapEntry<Category, ProjectCategoryUsage>>[];
    for (final entry in breakdownByCategory.entries) {
      final category = categoryById[entry.key];
      if (category == null) continue;
      if (budgetByCategory.containsKey(entry.key)) {
        allocated.add(MapEntry(category, entry.value));
      } else {
        unallocated.add(MapEntry(category, entry.value));
      }
    }
    allocated
        .sort((a, b) => b.value.expenseTotal.compareTo(a.value.expenseTotal));
    unallocated
        .sort((a, b) => b.value.expenseTotal.compareTo(a.value.expenseTotal));
    final unset = level1Categories
        .where((c) => !breakdownByCategory.containsKey(c.id))
        .toList();

    double? unallocatedBudget;
    if (usage.effectiveBudget != null) {
      final allocatedSum = data.categoryBudgets.fold<double>(
          0,
          (sum, b) =>
              sum + _resolvedCategoryBudgetAmount(b, usage.effectiveBudget!));
      unallocatedBudget = usage.effectiveBudget! - allocatedSum;
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SectionCard(
          margin: EdgeInsets.zero,
          child: Row(
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
                child: Text(project.name,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: BeeTokens.textPrimary(context))),
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
        ),
        const SizedBox(height: 12),
        if (project.periodType == 'fixed')
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Center(
              child: Text(_periodLabel(l10n),
                  style: TextStyle(
                      fontSize: 13, color: BeeTokens.textTertiary(context))),
            ),
          )
        else
          PeriodRangeSelector(
            label: _periodLabel(l10n),
            onPrev: () =>
                ref.read(projectPeriodOffsetProvider.notifier).setOffset(
                      projectId,
                      data.offset + 1,
                    ),
            onNext: data.offset > 0
                ? () =>
                    ref.read(projectPeriodOffsetProvider.notifier).setOffset(
                          projectId,
                          data.offset - 1,
                        )
                : null,
            onTapLabel: () => _openPeriodPicker(context, ref),
          ),
        const SizedBox(height: 12),
        SectionCard(
          margin: EdgeInsets.zero,
          child: _StatsRow(
            expenseTotal: expenseTotal,
            incomeTotal: incomeTotal,
            netTotal: netTotal,
            recordCount: recordCount,
            currencySymbol: currencySymbol,
            l10n: l10n,
          ),
        ),
        if (usage.budget != null) ...[
          const SizedBox(height: 12),
          SectionCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                                    ? BeeTokens.success(context)
                                    : BeeTokens.error(context))),
                      ],
                    ),
                  ],
                ),
                if (usage.carriedOver != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${l10n.projectDetailCarriedOverLabel}: '
                    '$currencySymbol${usage.carriedOver!.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontSize: 12, color: BeeTokens.textSecondary(context)),
                  ),
                ],
                if (project.dailyBudgetEnabled && project.periodType != 'fixed')
                  ..._buildDailyBudgetLine(context, l10n, currencySymbol),
                if (unallocatedBudget != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    unallocatedBudget >= 0
                        ? l10n.projectDetailUnallocatedAmountLabel(
                            '$currencySymbol${unallocatedBudget.toStringAsFixed(2)}')
                        : l10n.projectDetailOverAllocatedAmountLabel(
                            '$currencySymbol${(-unallocatedBudget).toStringAsFixed(2)}'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: unallocatedBudget >= 0
                          ? BeeTokens.textSecondary(context)
                          : BeeTokens.error(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (allocated.isNotEmpty) ...[
          const SizedBox(height: 12),
          _CategoryGroupSection(
            title: l10n.projectDetailAllocatedGroupTitle,
            children: [
              for (final entry in allocated)
                _CategoryBudgetTile(
                  category: entry.key,
                  parent: entry.key.parentId != null
                      ? categoryById[entry.key.parentId]
                      : null,
                  usage: entry.value,
                  budgetAmount: usage.effectiveBudget == null
                      ? null
                      : _resolvedCategoryBudgetAmount(
                          budgetByCategory[entry.key.id]!,
                          usage.effectiveBudget!,
                        ),
                  currencySymbol: currencySymbol,
                  onTap: () =>
                      _openCategoryTransactions(context, ref, entry.key),
                ),
            ],
          ),
        ],
        if (unallocated.isNotEmpty) ...[
          const SizedBox(height: 12),
          _CategoryGroupSection(
            title: l10n.projectDetailUnallocatedGroupTitle,
            children: [
              for (final entry in unallocated)
                _CategoryBudgetTile(
                  category: entry.key,
                  parent: entry.key.parentId != null
                      ? categoryById[entry.key.parentId]
                      : null,
                  usage: entry.value,
                  budgetAmount: null,
                  currencySymbol: currencySymbol,
                  unallocatedLabel: l10n.projectDetailUnallocatedLabel,
                  onTap: () =>
                      _openCategoryTransactions(context, ref, entry.key),
                ),
            ],
          ),
        ],
        if (unset.isNotEmpty) ...[
          const SizedBox(height: 12),
          _UnsetCategorySection(
            title: l10n.projectDetailUnsetGroupTitle,
            categories: unset,
          ),
        ],
      ],
    );
  }

  List<Widget> _buildDailyBudgetLine(
      BuildContext context, AppLocalizations l10n, String currencySymbol) {
    final usage = data.usage;
    final effectiveBudget = usage.effectiveBudget;
    if (effectiveBudget == null) return const [];
    final totalDays = usage.periodEnd.difference(usage.periodStart).inDays;
    if (totalDays <= 0) return const [];

    double daily;
    if (data.project.dailyBudgetMode == 'fixed') {
      daily = effectiveBudget / totalDays;
    } else {
      final today = DateTime(
          DateTime.now().year, DateTime.now().month, DateTime.now().day);
      final remainingDays = usage.periodEnd.difference(today).inDays;
      daily = remainingDays > 0
          ? (effectiveBudget - usage.used) / remainingDays
          : 0;
    }

    return [
      const SizedBox(height: 8),
      Text(
        '${l10n.projectDetailDailyBudgetLabel}: $currencySymbol${daily.toStringAsFixed(2)}',
        style: TextStyle(fontSize: 12, color: BeeTokens.textSecondary(context)),
      ),
    ];
  }

  void _openCategoryTransactions(
      BuildContext context, WidgetRef ref, Category category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ProjectCategoryTransactionsPage(
          project: data.project,
          usage: data.usage,
          category: category,
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final double expenseTotal;
  final double incomeTotal;
  final double netTotal;
  final int recordCount;
  final String currencySymbol;
  final AppLocalizations l10n;

  const _StatsRow({
    required this.expenseTotal,
    required this.incomeTotal,
    required this.netTotal,
    required this.recordCount,
    required this.currencySymbol,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final maxValue = [expenseTotal, incomeTotal, netTotal.abs()]
        .fold<double>(0, (m, v) => v > m ? v : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _statLine(context, l10n.projectDetailExpenseLabel, expenseTotal,
            maxValue, BeeTokens.chartExpense(context)),
        const SizedBox(height: 10),
        _statLine(context, l10n.projectDetailIncomeLabel, incomeTotal, maxValue,
            BeeTokens.chartIncome(context)),
        const SizedBox(height: 10),
        _statLine(context, l10n.projectDetailNetTotalLabel, netTotal, maxValue,
            BeeTokens.info(context)),
      ],
    );
  }

  Widget _statLine(BuildContext context, String label, double value,
      double maxValue, Color color) {
    final ratio =
        maxValue > 0 ? (value.abs() / maxValue).clamp(0.02, 1.0) : 0.02;
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(label,
              style: TextStyle(
                  fontSize: 12, color: BeeTokens.textSecondary(context))),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Container(
              height: 8,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: ratio,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('$currencySymbol${value.toStringAsFixed(2)}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: BeeTokens.textPrimary(context))),
      ],
    );
  }
}

class _CategoryGroupSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _CategoryGroupSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: BeeTokens.textSecondary(context))),
            ),
          ),
          for (final entry in children.indexed) ...[
            if (entry.$1 > 0) BeeDivider.short(indent: 56 + 16, endIndent: 16),
            entry.$2,
          ],
        ],
      ),
    );
  }
}

class _CategoryBudgetTile extends StatelessWidget {
  final Category category;
  final Category? parent;
  final ProjectCategoryUsage usage;
  final double? budgetAmount;
  final String currencySymbol;
  final String? unallocatedLabel;
  final VoidCallback onTap;

  const _CategoryBudgetTile({
    required this.category,
    this.parent,
    required this.usage,
    required this.budgetAmount,
    required this.currencySymbol,
    this.unallocatedLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final categoryName = CategoryUtils.getDisplayName(category.name, context);
    final iconData =
        getCategoryIconData(category: category, categoryName: categoryName);
    final resolvedColor = CategoryUtils.parseColor(
        category.parentId != null ? parent?.color : category.color);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: resolvedColor ?? BeeTokens.surfaceCategoryIcon(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(iconData,
                  size: 18,
                  color: resolvedColor != null
                      ? Colors.white
                      : BeeTokens.iconCategory(context)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(categoryName,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: BeeTokens.textPrimary(context))),
                  if (budgetAmount != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: BudgetProgressBar(
                        used: usage.expenseTotal,
                        budget: budgetAmount!,
                        showLabel: false,
                        height: 6,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$currencySymbol${usage.expenseTotal.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: BeeTokens.textPrimary(context))),
                Text(
                  unallocatedLabel ?? '${usage.recordCount}',
                  style: TextStyle(
                      fontSize: 11, color: BeeTokens.textTertiary(context)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UnsetCategorySection extends StatefulWidget {
  final String title;
  final List<Category> categories;

  const _UnsetCategorySection({required this.title, required this.categories});

  @override
  State<_UnsetCategorySection> createState() => _UnsetCategorySectionState();
}

class _UnsetCategorySectionState extends State<_UnsetCategorySection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: BeeTokens.textSecondary(context))),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: BeeTokens.textTertiary(context)
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${widget.categories.length}',
                        style: TextStyle(
                            fontSize: 11,
                            color: BeeTokens.textTertiary(context))),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: BeeTokens.iconTertiary(context),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            for (final entry in widget.categories.indexed) ...[
              if (entry.$1 > 0)
                BeeDivider.short(indent: 56 + 16, endIndent: 16),
              _buildRow(context, entry.$2),
            ],
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, Category category) {
    final categoryName = CategoryUtils.getDisplayName(category.name, context);
    final iconData =
        getCategoryIconData(category: category, categoryName: categoryName);
    final resolvedColor = CategoryUtils.parseColor(category.color);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: resolvedColor ?? BeeTokens.surfaceCategoryIcon(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(iconData,
                size: 16,
                color: resolvedColor != null
                    ? Colors.white
                    : BeeTokens.iconCategory(context)),
          ),
          const SizedBox(width: 10),
          Text(categoryName,
              style: TextStyle(
                  fontSize: 13, color: BeeTokens.textPrimary(context))),
        ],
      ),
    );
  }
}

/// 分類鑽入頁:該專案 + 該分類 + 該期間的交易明細(design doc §4.4 第 8 點)。
/// 用 [getTransactionsByProject] 的 start/end 篩選拿到該期間全部交易,再前端
/// 過濾 categoryId(單一專案單期交易量通常不大,過濾成本可忽略)。
class _ProjectCategoryTransactionsPage extends ConsumerWidget {
  final Project project;
  final ProjectUsage usage;
  final Category category;

  const _ProjectCategoryTransactionsPage({
    required this.project,
    required this.usage,
    required this.category,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final categoryName = CategoryUtils.getDisplayName(category.name, context);
    final syncId = project.syncId;

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: '${project.name} · $categoryName',
            showBack: true,
            compact: true,
          ),
          Expanded(
            child: syncId == null
                ? Center(child: Text(l10n.projectDetailNoTransactionsHint))
                : FutureBuilder<List<Transaction>>(
                    future:
                        ref.read(repositoryProvider).getTransactionsByProject(
                              syncId,
                              start: usage.periodStart,
                              end: usage.periodEnd,
                            ),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final txs = snapshot.data!
                          .where((t) => t.categoryId == category.id)
                          .toList();
                      if (txs.isEmpty) {
                        return Center(
                            child: Text(l10n.projectDetailNoTransactionsHint));
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: txs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final t = txs[index];
                          return TransactionListItem(
                            icon: getCategoryIconData(
                                category: category, categoryName: categoryName),
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
                            onTap: () => showTransactionDetailCard(
                                context, ref, t, category),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
