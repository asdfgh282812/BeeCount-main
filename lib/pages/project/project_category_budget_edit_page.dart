import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/project_providers.dart';
import '../../services/billing/post_processor.dart';
import '../../styles/tokens.dart';
import '../../utils/category_utils.dart';
import '../../utils/currencies.dart';
import '../../widgets/biz/biz.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/ui/ui.dart';

class _RowState {
  bool enabled;
  String mode;
  double? fixedAmount;
  double? percentage;
  bool carryoverEnabled;

  _RowState({
    this.enabled = false,
    this.mode = 'fixed',
    this.fixedAmount,
    this.percentage,
    this.carryoverEnabled = false,
  });
}

/// 分類子預算編輯頁(design doc 2026-09-06 §5):列出帳本下所有一級分類,逐一
/// 設定固定金額/按照比例的子預算分配。齒輪圖示從專案詳情頁進入。
class ProjectCategoryBudgetEditPage extends ConsumerStatefulWidget {
  final Project project;

  const ProjectCategoryBudgetEditPage({super.key, required this.project});

  @override
  ConsumerState<ProjectCategoryBudgetEditPage> createState() =>
      _ProjectCategoryBudgetEditPageState();
}

class _ProjectCategoryBudgetEditPageState
    extends ConsumerState<ProjectCategoryBudgetEditPage> {
  bool _loading = true;
  bool _saving = false;
  List<Category> _level1Categories = const [];
  final Map<int, _RowState> _rows = {};
  final Map<int, TextEditingController> _fixedControllers = {};
  final Map<int, TextEditingController> _percentControllers = {};

  bool get _pureTracking => widget.project.budgetAmount == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _fixedControllers.values) {
      c.dispose();
    }
    for (final c in _percentControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(repositoryProvider);
    final categories = await repo.getAllCategories();
    final existing = await repo.getProjectCategoryBudgets(widget.project.id);
    final existingByCategory = {for (final b in existing) b.categoryId: b};

    _level1Categories = categories.where((c) => c.level == 1).toList();
    for (final c in _level1Categories) {
      final existingBudget = existingByCategory[c.id];
      final row = _RowState(
        enabled: existingBudget != null,
        mode: existingBudget?.mode ?? 'fixed',
        fixedAmount: existingBudget?.fixedAmount,
        percentage: existingBudget?.percentage,
        carryoverEnabled: existingBudget?.carryoverEnabled ?? false,
      );
      _rows[c.id] = row;
      _fixedControllers[c.id] = TextEditingController(
        text:
            row.fixedAmount != null ? row.fixedAmount!.toStringAsFixed(0) : '',
      );
      _percentControllers[c.id] = TextEditingController(
        text: row.percentage != null ? row.percentage!.toStringAsFixed(0) : '',
      );
    }

    if (mounted) setState(() => _loading = false);
  }

  double get _totalAllocated {
    final budget = widget.project.budgetAmount;
    if (budget == null) return 0;
    var sum = 0.0;
    for (final entry in _rows.entries) {
      if (!entry.value.enabled) continue;
      if (entry.value.mode == 'percentage') {
        sum += budget * (entry.value.percentage ?? 0) / 100;
      } else {
        sum += entry.value.fixedAmount ?? 0;
      }
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currencyCode =
        ref.watch(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    final currencySymbol = getCurrencySymbol(currencyCode);
    final budget = widget.project.budgetAmount;

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.projectCategoryBudgetEditTitle,
            showBack: true,
            compact: true,
            actions: [
              TextButton(
                onPressed: _saving || _loading ? null : _save,
                child: Text(
                  l10n.commonSave,
                  style: TextStyle(
                      color: BeeTokens.textPrimary(context),
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final category in _level1Categories)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildCategoryCard(
                              context, category, currencySymbol),
                        ),
                      if (!_pureTracking && budget != null)
                        _buildFooter(context, l10n, currencySymbol, budget),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(
      BuildContext context, Category category, String currencySymbol) {
    final row = _rows[category.id]!;
    final categoryName = CategoryUtils.getDisplayName(category.name, context);
    final iconData =
        getCategoryIconData(category: category, categoryName: categoryName);
    final resolvedColor = CategoryUtils.parseColor(category.color);
    final l10n = AppLocalizations.of(context);

    return SectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                child: Text(categoryName,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: BeeTokens.textPrimary(context))),
              ),
              Text(l10n.projectCategoryBudgetEnableToggle,
                  style: TextStyle(
                      fontSize: 13, color: BeeTokens.textSecondary(context))),
              Switch.adaptive(
                value: row.enabled,
                onChanged: (v) => setState(() => row.enabled = v),
              ),
            ],
          ),
          if (row.enabled) ...[
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                    value: 'fixed',
                    label: Text(l10n.projectCategoryBudgetModeFixed),
                    enabled: !_pureTracking),
                ButtonSegment(
                    value: 'percentage',
                    label: Text(l10n.projectCategoryBudgetModePercentage),
                    enabled: !_pureTracking),
              ],
              selected: {_pureTracking ? 'fixed' : row.mode},
              onSelectionChanged: _pureTracking
                  ? null
                  : (s) => setState(() => row.mode = s.first),
            ),
            const SizedBox(height: 8),
            if (row.mode == 'fixed' || _pureTracking)
              TextField(
                controller: _fixedControllers[category.id],
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  prefixText: '$currencySymbol ',
                  isDense: true,
                ),
                onChanged: (v) =>
                    setState(() => row.fixedAmount = double.tryParse(v)),
              )
            else ...[
              TextField(
                controller: _percentControllers[category.id],
                keyboardType: const TextInputType.numberWithOptions(),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  suffixText: '%',
                  hintText: l10n.projectCategoryBudgetPercentageHint,
                  isDense: true,
                ),
                onChanged: (v) => setState(() {
                  row.percentage = double.tryParse(v)?.clamp(0, 100);
                }),
              ),
              if (widget.project.budgetAmount != null && row.percentage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '= $currencySymbol${(widget.project.budgetAmount! * row.percentage! / 100).toStringAsFixed(2)}',
                    style: TextStyle(
                        fontSize: 12, color: BeeTokens.textTertiary(context)),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, AppLocalizations l10n,
      String currencySymbol, double budget) {
    final allocated = _totalAllocated;
    final overAllocated = allocated > budget;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        l10n.projectCategoryBudgetFooterLabel(
          '$currencySymbol${allocated.toStringAsFixed(2)}',
          '$currencySymbol${budget.toStringAsFixed(2)}',
        ),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: overAllocated
              ? BeeTokens.error(context)
              : BeeTokens.textSecondary(context),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(repositoryProvider);
      for (final category in _level1Categories) {
        final row = _rows[category.id]!;
        if (row.enabled) {
          await repo.upsertProjectCategoryBudget(
            projectId: widget.project.id,
            categoryId: category.id,
            mode: _pureTracking ? 'fixed' : row.mode,
            fixedAmount:
                (_pureTracking || row.mode == 'fixed') ? row.fixedAmount : null,
            percentage: (!_pureTracking && row.mode == 'percentage')
                ? row.percentage
                : null,
            carryoverEnabled: row.carryoverEnabled,
          );
        } else {
          await repo.removeProjectCategoryBudget(
              widget.project.id, category.id);
        }
      }

      ref.read(projectRefreshProvider.notifier).state++;
      unawaited(PostProcessor.sync(ref, ledgerId: widget.project.ledgerId));

      if (mounted) {
        showToast(context,
            AppLocalizations.of(context).projectCategoryBudgetSaveSuccess);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
