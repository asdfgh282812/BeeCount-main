import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/report/report_dataset.dart';
import '../../models/report/report_filter.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../utils/category_utils.dart';
import '../../widgets/ui/ui.dart';

/// 報表篩選條件總覽(對齊 MOZE「篩選條件」):每個維度一列,顯示目前的
/// 包含/排除摘要,點進去逐項勾選。
///
/// 兩種用法:
/// - [reportId] 非 null:直接改那份已儲存報表的篩選(報表頁的篩選按鈕)。
/// - [reportId] 為 null:編輯草稿,按「儲存」時 pop 回傳新的 [ReportFilter]
///   (新增/編輯報表頁用)。
class ReportFilterPage extends ConsumerStatefulWidget {
  final String? reportId;
  final ReportFilter? initial;

  const ReportFilterPage({super.key, this.reportId, this.initial})
      : assert(reportId != null || initial != null);

  @override
  ConsumerState<ReportFilterPage> createState() => _ReportFilterPageState();
}

class _ReportFilterPageState extends ConsumerState<ReportFilterPage> {
  late ReportFilter _filter;
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filter = widget.initial ??
        ref.read(reportStoreProvider).byId(widget.reportId!)?.filter ??
        ReportFilter.none;
    _minCtrl.text = _fmt(_filter.minAmount);
    _maxCtrl.text = _fmt(_filter.maxAmount);
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  static String _fmt(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
  }

  ReportFilter _withAmounts() {
    double? parse(String s) => double.tryParse(s.trim());
    return _filter.copyWith(
      minAmount: () => parse(_minCtrl.text),
      maxAmount: () => parse(_maxCtrl.text),
    );
  }

  Future<void> _save() async {
    final result = _withAmounts();
    if (widget.reportId != null) {
      final store = ref.read(reportStoreProvider.notifier);
      final def = ref.read(reportStoreProvider).byId(widget.reportId!);
      if (def != null) await store.update(def.copyWith(filter: result));
      if (mounted) Navigator.pop(context);
    } else {
      Navigator.pop(context, result);
    }
  }

  String _summary(AppLocalizations l10n, KeySetFilter f) {
    if (!f.isActive) return l10n.reportFilterAll;
    return f.mode == FilterMode.include
        ? l10n.reportFilterSummaryInclude(f.selectedCount)
        : l10n.reportFilterSummaryExclude(f.selectedCount);
  }

  Future<void> _pick({
    required String title,
    required KeySetFilter current,
    required List<ReportFilterOption> Function(ReportFilterOptions) options,
    required ReportFilter Function(KeySetFilter) apply,
    bool translateCategory = false,
    Map<String, List<String>> Function(ReportFilterOptions)? children,
  }) async {
    final result = await Navigator.of(context).push<KeySetFilter>(
      MaterialPageRoute(
        builder: (_) => ReportFilterPickerPage(
          title: title,
          initial: current,
          options: options,
          children: children,
          translateCategory: translateCategory,
        ),
      ),
    );
    if (result != null) setState(() => _filter = apply(result));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final f = _filter;

    Widget row(String title, KeySetFilter current, VoidCallback onTap) =>
        ListTile(
          title: Text(title),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_summary(l10n, current),
                  style: TextStyle(
                      color: current.isActive
                          ? BeeTokens.primary(context)
                          : BeeTokens.textTertiary(context))),
              Icon(Icons.chevron_right, color: BeeTokens.iconTertiary(context)),
            ],
          ),
          onTap: onTap,
        );

    return Scaffold(
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.reportFilter,
            showBack: true,
            compact: true,
            actions: [
              IconButton(
                tooltip: l10n.commonSave,
                onPressed: _save,
                icon: Icon(Icons.check, color: BeeTokens.textPrimary(context)),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(
                  bottom: 24 + MediaQuery.of(context).viewPadding.bottom),
              children: [
                row(
                    l10n.reportTabAccount,
                    f.accounts,
                    () => _pick(
                          title: l10n.reportTabAccount,
                          current: f.accounts,
                          options: (o) => o.accounts,
                          apply: (v) => _filter.copyWith(accounts: v),
                        )),
                row(
                    l10n.reportTabCategory,
                    f.categories,
                    () => _pick(
                          title: l10n.reportTabCategory,
                          current: f.categories,
                          options: (o) => o.categories,
                          children: (o) => o.childCategoryKeys,
                          translateCategory: true,
                          apply: (v) => _filter.copyWith(categories: v),
                        )),
                row(
                    l10n.reportTabProject,
                    f.projects,
                    () => _pick(
                          title: l10n.reportTabProject,
                          current: f.projects,
                          options: (o) => o.projects,
                          apply: (v) => _filter.copyWith(projects: v),
                        )),
                row(
                    l10n.reportTabName,
                    f.names,
                    () => _pick(
                          title: l10n.reportTabName,
                          current: f.names,
                          options: (o) => o.names,
                          apply: (v) => _filter.copyWith(names: v),
                        )),
                row(
                    l10n.reportTabMerchant,
                    f.merchants,
                    () => _pick(
                          title: l10n.reportTabMerchant,
                          current: f.merchants,
                          options: (o) => o.merchants,
                          apply: (v) => _filter.copyWith(merchants: v),
                        )),
                row(
                    l10n.reportSectionTags,
                    f.tags,
                    () => _pick(
                          title: l10n.reportSectionTags,
                          current: f.tags,
                          options: (o) => o.tags,
                          apply: (v) => _filter.copyWith(tags: v),
                        )),
                row(
                    l10n.reportSectionCounterparties,
                    f.counterparties,
                    () => _pick(
                          title: l10n.reportSectionCounterparties,
                          current: f.counterparties,
                          options: (o) => o.counterparties,
                          apply: (v) => _filter.copyWith(counterparties: v),
                        )),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(l10n.reportFilterAmountRange,
                      style: BeeTextTokens.label(context)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                          child: _amountField(_minCtrl, l10n.reportFilterMin)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('–'),
                      ),
                      Expanded(
                          child: _amountField(_maxCtrl, l10n.reportFilterMax)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(l10n.reportFilterRecordTypes,
                      style: BeeTextTokens.label(context)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final (type, label) in [
                        ('expense', l10n.homeExpense),
                        ('income', l10n.homeIncome),
                        ('transfer', l10n.reportOtherTypes),
                      ])
                        FilterChip(
                          label: Text(label),
                          selected: f.recordTypes.contains(type),
                          onSelected: (sel) {
                            final next = {...f.recordTypes};
                            sel ? next.add(type) : next.remove(type);
                            if (next.isEmpty) return; // 至少留一種
                            setState(() =>
                                _filter = _filter.copyWith(recordTypes: next));
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: Text(l10n.reportFilterClear),
                    onPressed: () => setState(() {
                      _filter = ReportFilter.none;
                      _minCtrl.clear();
                      _maxCtrl.clear();
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountField(TextEditingController c, String hint) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );
}

/// 單一維度的包含/排除勾選頁。
class ReportFilterPickerPage extends ConsumerStatefulWidget {
  final String title;
  final KeySetFilter initial;
  final List<ReportFilterOption> Function(ReportFilterOptions) options;
  final Map<String, List<String>> Function(ReportFilterOptions)? children;
  final bool translateCategory;

  const ReportFilterPickerPage({
    super.key,
    required this.title,
    required this.initial,
    required this.options,
    this.children,
    this.translateCategory = false,
  });

  @override
  ConsumerState<ReportFilterPickerPage> createState() =>
      _ReportFilterPickerPageState();
}

class _ReportFilterPickerPageState
    extends ConsumerState<ReportFilterPickerPage> {
  late FilterMode _mode = widget.initial.mode;
  late final Set<String> _selected = {...widget.initial.values};
  late bool _none = widget.initial.includeNone;
  String _query = '';

  /// 勾父分類 = 連同子分類;取消某個子分類時父分類也要取消,不然 entry 仍會
  /// 透過父分類 key 命中(見 `ReportEntry.categoryKeys`)。
  void _toggle(String key, bool on, Map<String, List<String>> children) {
    setState(() {
      final keys = [key, ...?children[key]];
      if (on) {
        _selected.addAll(keys);
      } else {
        _selected.removeAll(keys);
        for (final e in children.entries) {
          if (e.value.contains(key)) _selected.remove(e.key);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(reportFilterOptionsProvider);
    return Scaffold(
      body: Column(
        children: [
          PrimaryHeader(
            title: widget.title,
            showBack: true,
            compact: true,
            actions: [
              IconButton(
                tooltip: l10n.commonOk,
                onPressed: () => Navigator.pop(
                  context,
                  KeySetFilter(
                      mode: _mode, values: {..._selected}, includeNone: _none),
                ),
                icon: Icon(Icons.check, color: BeeTokens.textPrimary(context)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<FilterMode>(
              segments: [
                ButtonSegment(
                    value: FilterMode.include,
                    label: Text(l10n.reportFilterInclude)),
                ButtonSegment(
                    value: FilterMode.exclude,
                    label: Text(l10n.reportFilterExclude)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: l10n.commonSearch,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('${l10n.commonError}: $e')),
              data: (opts) {
                final all = widget.options(opts);
                final children = widget.children?.call(opts) ?? const {};
                String labelOf(ReportFilterOption o) => widget.translateCategory
                    ? CategoryUtils.getDisplayName(o.label, context)
                    : o.label;
                final shown = _query.isEmpty
                    ? all
                    : all
                        .where((o) => labelOf(o).toLowerCase().contains(_query))
                        .toList();
                // 已選但選項清單裡找不到的(實體已刪除),照樣列出讓使用者能取消。
                final known = {for (final o in all) o.key};
                final orphans =
                    _selected.where((k) => !known.contains(k)).toList();
                final rows = <Widget>[];
                String? lastSection;
                for (final o in shown) {
                  if (o.section != null && o.section != lastSection) {
                    lastSection = o.section;
                    rows.add(Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        o.section == 'income'
                            ? l10n.homeIncome
                            : l10n.homeExpense,
                        style: BeeTextTokens.label(context),
                      ),
                    ));
                  }
                  rows.add(CheckboxListTile(
                    dense: true,
                    contentPadding:
                        EdgeInsets.only(left: 16.0 + o.indent * 24, right: 16),
                    value: _selected.contains(o.key),
                    title: Text(labelOf(o)),
                    onChanged: (v) => _toggle(o.key, v ?? false, children),
                  ));
                }
                return ListView(
                  padding: EdgeInsets.only(
                      bottom: 24 + MediaQuery.of(context).viewPadding.bottom),
                  children: [
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => setState(
                              () => _selected.addAll(shown.map((o) => o.key))),
                          child: Text(l10n.reportFilterSelectAll),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _selected.clear();
                            _none = false;
                          }),
                          child: Text(l10n.reportFilterSelectNone),
                        ),
                      ],
                    ),
                    CheckboxListTile(
                      dense: true,
                      value: _none,
                      title: Text(l10n.reportNone),
                      onChanged: (v) => setState(() => _none = v ?? false),
                    ),
                    if (all.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                            child: Text(l10n.reportFilterEmptyOptions,
                                style: TextStyle(
                                    color: BeeTokens.textTertiary(context)))),
                      ),
                    ...rows,
                    for (final k in orphans)
                      CheckboxListTile(
                        dense: true,
                        value: true,
                        title: Text(l10n.reportDeletedEntity),
                        onChanged: (_) => setState(() => _selected.remove(k)),
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
}
