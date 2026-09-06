import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/project_providers.dart';
import '../../services/billing/post_processor.dart';
import '../../services/data/category_service.dart';
import '../../styles/tokens.dart';
import '../../utils/currencies.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/biz.dart';
import '../../widgets/biz/grouped_icon_grid.dart';
import '../../widgets/ui/ui.dart';

/// 專案新增/編輯頁(design doc §8)。比照 BudgetEditPage 的頁面骨架
/// (PrimaryHeader 存檔/刪除按鈕 + SectionCard 分段 ListView)。
class ProjectEditPage extends ConsumerStatefulWidget {
  final Project? project;

  const ProjectEditPage({super.key, this.project});

  @override
  ConsumerState<ProjectEditPage> createState() => _ProjectEditPageState();
}

class _ProjectEditPageState extends ConsumerState<ProjectEditPage> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  String? _selectedIcon;
  bool _pureTracking = false;
  String _periodType = 'monthly';
  DateTime? _periodStart;
  DateTime? _periodEnd;
  bool _carryoverEnabled = false;
  bool _visibleOnHome = true;
  bool _enabled = true;
  bool _isLoading = false;
  bool _incomeIncludedInBudget = false;
  bool _dailyBudgetEnabled = false;
  String _dailyBudgetMode = 'proportional';
  int? _reminderThresholdPercent;
  final _reminderCustomController = TextEditingController();

  bool get _isEditing => widget.project != null;

  static const _reminderPresets = [50, 80, 100, 120];

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    if (p != null) {
      _nameController.text = p.name;
      _selectedIcon = p.icon;
      _pureTracking = p.budgetAmount == null;
      if (p.budgetAmount != null) {
        _amountController.text = p.budgetAmount!.toStringAsFixed(0);
      }
      _periodType = p.periodType;
      _periodStart = p.periodStart;
      _periodEnd = p.periodEnd;
      _carryoverEnabled = p.carryoverEnabled;
      _visibleOnHome = p.visibleOnHome;
      _enabled = p.enabled;
      _incomeIncludedInBudget = p.incomeIncludedInBudget;
      _dailyBudgetEnabled = p.dailyBudgetEnabled;
      _dailyBudgetMode = p.dailyBudgetMode ?? 'proportional';
      _reminderThresholdPercent = p.reminderThresholdPercent;
      if (_reminderThresholdPercent != null &&
          !_reminderPresets.contains(_reminderThresholdPercent)) {
        _reminderCustomController.text = '$_reminderThresholdPercent';
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _reminderCustomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currencyCode =
        ref.watch(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    final currencySymbol = getCurrencySymbol(currencyCode);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: _isEditing ? l10n.projectEditTitle : l10n.projectAddTitle,
            showBack: true,
            compact: true,
            actions: [
              if (_isEditing)
                IconButton(
                  onPressed: _isLoading ? null : _deleteProject,
                  icon: const Icon(Icons.delete_outline),
                ),
              TextButton(
                onPressed: _isLoading ? null : _saveProject,
                child: Text(
                  l10n.commonSave,
                  style: TextStyle(
                    color: BeeTokens.textPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: 12.0.scaled(context, ref),
                vertical: 8.0.scaled(context, ref),
              ),
              children: [
                // 名稱 + icon
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.projectNameLabel,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: BeeTokens.textSecondary(context))),
                      SizedBox(height: 12.0.scaled(context, ref)),
                      Row(
                        children: [
                          InkWell(
                            onTap: _pickIcon,
                            borderRadius: BorderRadius.circular(10),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    CategoryService.getCategoryIcon(
                                        _selectedIcon),
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: BeeTokens.surface(context),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: const Icon(Icons.edit,
                                        size: 10, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 12.0.scaled(context, ref)),
                          Expanded(
                            child: TextField(
                              controller: _nameController,
                              style: TextStyle(
                                  fontSize: 16,
                                  color: BeeTokens.textPrimary(context)),
                              decoration: InputDecoration(
                                hintText: l10n.projectNameHint,
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.0.scaled(context, ref)),
                // 預算金額 / 純記錄
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(l10n.budgetAmountLabel,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: BeeTokens.textSecondary(context))),
                          Row(
                            children: [
                              Text(l10n.projectPureTrackingToggle,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: BeeTokens.textSecondary(context))),
                              Switch.adaptive(
                                value: _pureTracking,
                                onChanged: (v) =>
                                    setState(() => _pureTracking = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (!_pureTracking) ...[
                        SizedBox(height: 8.0.scaled(context, ref)),
                        TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d+\.?\d{0,2}')),
                          ],
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: BeeTokens.textPrimary(context)),
                          decoration: InputDecoration(
                            prefixText: '$currencySymbol ',
                            prefixStyle: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                color: BeeTokens.textPrimary(context)),
                            hintText: l10n.budgetAmountHint,
                            border: InputBorder.none,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 12.0.scaled(context, ref)),
                // 週期
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.projectPeriodTypeLabel,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: BeeTokens.textSecondary(context))),
                      SizedBox(height: 12.0.scaled(context, ref)),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                              value: 'monthly',
                              label: Text(l10n.projectPeriodMonthlyOption)),
                          ButtonSegment(
                              value: 'yearly',
                              label: Text(l10n.projectPeriodYearlyOption)),
                          ButtonSegment(
                              value: 'fixed',
                              label: Text(l10n.projectPeriodFixedOption)),
                        ],
                        selected: {_periodType},
                        onSelectionChanged: (s) =>
                            setState(() => _periodType = s.first),
                      ),
                      if (_periodType == 'fixed') ...[
                        SizedBox(height: 12.0.scaled(context, ref)),
                        Row(
                          children: [
                            Expanded(
                              child: _DateField(
                                label: l10n.projectPeriodStartLabel,
                                date: _periodStart,
                                onTap: () => _pickDate(isStart: true),
                              ),
                            ),
                            SizedBox(width: 12.0.scaled(context, ref)),
                            Expanded(
                              child: _DateField(
                                label: l10n.projectPeriodEndLabel,
                                date: _periodEnd,
                                onTap: () => _pickDate(isStart: false),
                              ),
                            ),
                          ],
                        ),
                      ],
                      SizedBox(height: 4.0.scaled(context, ref)),
                      AppListTile(
                        leading: Icons.autorenew,
                        title: l10n.projectCarryoverToggle,
                        trailing: Switch.adaptive(
                          value: _periodType == 'fixed'
                              ? false
                              : _carryoverEnabled,
                          onChanged: _periodType == 'fixed'
                              ? null
                              : (v) => setState(() => _carryoverEnabled = v),
                        ),
                        onTap: _periodType == 'fixed'
                            ? null
                            : () => setState(
                                () => _carryoverEnabled = !_carryoverEnabled),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.0.scaled(context, ref)),
                // 顯示設定
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      AppListTile(
                        leading: Icons.visibility_outlined,
                        title: l10n.projectVisibleOnHomeToggle,
                        trailing: Switch.adaptive(
                          value: _visibleOnHome,
                          onChanged: (v) => setState(() => _visibleOnHome = v),
                        ),
                        onTap: () =>
                            setState(() => _visibleOnHome = !_visibleOnHome),
                      ),
                      if (_isEditing)
                        AppListTile(
                          leading: Icons.toggle_on_outlined,
                          title: l10n.projectEnabledToggle,
                          trailing: Switch.adaptive(
                            value: _enabled,
                            onChanged: (v) => setState(() => _enabled = v),
                          ),
                          onTap: () => setState(() => _enabled = !_enabled),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: 12.0.scaled(context, ref)),
                // 收入併入預算 / 每日預算 / 預算提醒(design doc §6)
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppListTile(
                        leading: Icons.trending_up,
                        title: l10n.projectIncomeIncludedToggle,
                        trailing: Switch.adaptive(
                          value: _incomeIncludedInBudget,
                          onChanged: _pureTracking
                              ? null
                              : (v) =>
                                  setState(() => _incomeIncludedInBudget = v),
                        ),
                        onTap: _pureTracking
                            ? null
                            : () => setState(() => _incomeIncludedInBudget =
                                !_incomeIncludedInBudget),
                      ),
                      AppListTile(
                        leading: Icons.today_outlined,
                        title: l10n.projectDailyBudgetToggle,
                        trailing: Switch.adaptive(
                          value: _dailyBudgetEnabled,
                          onChanged: (_pureTracking || _periodType == 'fixed')
                              ? null
                              : (v) => setState(() => _dailyBudgetEnabled = v),
                        ),
                        onTap: (_pureTracking || _periodType == 'fixed')
                            ? null
                            : () => setState(() =>
                                _dailyBudgetEnabled = !_dailyBudgetEnabled),
                      ),
                      if (_dailyBudgetEnabled &&
                          !_pureTracking &&
                          _periodType != 'fixed') ...[
                        Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16.0.scaled(context, ref),
                              vertical: 4.0.scaled(context, ref)),
                          child: SegmentedButton<String>(
                            segments: [
                              ButtonSegment(
                                  value: 'fixed',
                                  label: Text(
                                      l10n.projectCategoryBudgetModeFixed)),
                              ButtonSegment(
                                  value: 'proportional',
                                  label: Text(l10n
                                      .projectCategoryBudgetModePercentage)),
                            ],
                            selected: {_dailyBudgetMode},
                            onSelectionChanged: (s) =>
                                setState(() => _dailyBudgetMode = s.first),
                          ),
                        ),
                        SizedBox(height: 4.0.scaled(context, ref)),
                      ],
                      AppListTile(
                        leading: Icons.notifications_outlined,
                        title: l10n.projectReminderToggle,
                        trailing: Switch.adaptive(
                          value: _reminderThresholdPercent != null,
                          onChanged: (v) => setState(
                              () => _reminderThresholdPercent = v ? 80 : null),
                        ),
                        onTap: () => setState(() => _reminderThresholdPercent =
                            _reminderThresholdPercent == null ? 80 : null),
                      ),
                      if (_reminderThresholdPercent != null) ...[
                        Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16.0.scaled(context, ref),
                              vertical: 4.0.scaled(context, ref)),
                          child: Wrap(
                            spacing: 8,
                            children: [
                              for (final preset in _reminderPresets)
                                ChoiceChip(
                                  label: Text('$preset%'),
                                  selected: _reminderThresholdPercent == preset,
                                  onSelected: (_) => setState(() {
                                    _reminderThresholdPercent = preset;
                                    _reminderCustomController.clear();
                                  }),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16.0.scaled(context, ref),
                              vertical: 4.0.scaled(context, ref)),
                          child: TextField(
                            controller: _reminderCustomController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              hintText: l10n.projectReminderCustomHint,
                              isDense: true,
                            ),
                            onChanged: (v) {
                              final parsed = int.tryParse(v);
                              if (parsed != null &&
                                  parsed >= 1 &&
                                  parsed <= 200) {
                                setState(
                                    () => _reminderThresholdPercent = parsed);
                              }
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickIcon() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BeeTokens.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.projectIconLabel,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: GroupedIconGrid(
                  selectedIcon: _selectedIcon,
                  kind: 'expense',
                  onIconSelected: (icon) => Navigator.pop(context, icon),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() => _selectedIcon = picked);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _periodStart : _periodEnd) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _periodStart = picked;
      } else {
        _periodEnd = picked;
      }
    });
  }

  Future<void> _saveProject() async {
    final l10n = AppLocalizations.of(context);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showToast(context, l10n.projectNameRequiredHint);
      return;
    }

    double? amount;
    if (!_pureTracking) {
      final amountText = _amountController.text.trim();
      if (amountText.isEmpty) {
        showToast(context, l10n.budgetAmountHint);
        return;
      }
      amount = double.tryParse(amountText);
      if (amount == null || amount <= 0) {
        showToast(context, l10n.budgetAmountHint);
        return;
      }
    }

    if (_periodType == 'fixed' &&
        (_periodStart == null || _periodEnd == null)) {
      showToast(context, l10n.projectPeriodFixedRequiredHint);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(repositoryProvider);
      final ledgerId = ref.read(currentLedgerIdProvider);

      // 收入併入預算/每日預算 在純記錄型專案上沒有意義,存檔時強制歸位,避免
      // UI 短暫顯示過的開關狀態殘留到資料庫(例如先開啟每日預算,再切成純記錄)。
      final effectiveIncomeIncluded =
          _pureTracking ? false : _incomeIncludedInBudget;
      final effectiveDailyBudgetEnabled =
          (_pureTracking || _periodType == 'fixed')
              ? false
              : _dailyBudgetEnabled;

      if (_isEditing) {
        await repo.updateProject(
          widget.project!.id,
          name: name,
          icon: _selectedIcon,
          clearIcon: _selectedIcon == null,
          budgetAmount: amount,
          clearBudgetAmount: _pureTracking,
          periodType: _periodType,
          periodStart: _periodType == 'fixed' ? _periodStart : null,
          clearPeriodStart: _periodType != 'fixed',
          periodEnd: _periodType == 'fixed' ? _periodEnd : null,
          clearPeriodEnd: _periodType != 'fixed',
          carryoverEnabled: _periodType == 'fixed' ? false : _carryoverEnabled,
          visibleOnHome: _visibleOnHome,
          enabled: _enabled,
          incomeIncludedInBudget: effectiveIncomeIncluded,
          dailyBudgetEnabled: effectiveDailyBudgetEnabled,
          dailyBudgetMode: _dailyBudgetMode,
          reminderThresholdPercent: _reminderThresholdPercent,
          clearReminderThresholdPercent: _reminderThresholdPercent == null,
        );
      } else {
        await repo.createProject(
          ledgerId: ledgerId,
          name: name,
          icon: _selectedIcon,
          budgetAmount: amount,
          periodType: _periodType,
          periodStart: _periodType == 'fixed' ? _periodStart : null,
          periodEnd: _periodType == 'fixed' ? _periodEnd : null,
          carryoverEnabled: _periodType == 'fixed' ? false : _carryoverEnabled,
          visibleOnHome: _visibleOnHome,
          incomeIncludedInBudget: effectiveIncomeIncluded,
          dailyBudgetEnabled: effectiveDailyBudgetEnabled,
          dailyBudgetMode: _dailyBudgetMode,
          reminderThresholdPercent: _reminderThresholdPercent,
        );
      }

      ref.read(projectRefreshProvider.notifier).state++;
      unawaited(PostProcessor.sync(ref, ledgerId: ledgerId));

      if (mounted) {
        showToast(context, l10n.projectSaveSuccess);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteProject() async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(repositoryProvider);
    final project = widget.project!;
    final syncId = project.syncId;
    final hasTransactions =
        syncId != null && await repo.projectHasTransactions(syncId);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.commonDelete),
        content: Text(hasTransactions
            ? l10n.projectArchiveInsteadConfirmBody
            : l10n.projectDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final ledgerId = ref.read(currentLedgerIdProvider);
      await repo.deleteProject(project.id);
      ref.read(projectRefreshProvider.notifier).state++;
      unawaited(PostProcessor.sync(ref, ledgerId: ledgerId));

      if (mounted) {
        showToast(
            context,
            hasTransactions
                ? l10n.projectArchiveSuccess
                : l10n.projectDeleteSuccess);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showToast(context, e.toString());
    }
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  const _DateField(
      {required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text =
        date == null ? label : '${date!.year}/${date!.month}/${date!.day}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: BeeTokens.surface(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: BeeTokens.border(context)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 16, color: BeeTokens.iconSecondary(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: date == null
                      ? BeeTokens.textTertiary(context)
                      : BeeTokens.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
