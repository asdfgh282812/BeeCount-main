import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/report/report_definition.dart';
import '../../models/report/report_filter.dart';
import '../../models/report/report_period.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../widgets/ui/capsule_switcher.dart';
import '../../widgets/ui/ui.dart';
import 'report_filter_page.dart';
import 'report_labels.dart';

enum _Kind { recurring, untilToday, fixed }

/// 新增/編輯統計報表:名稱、期間(三種類型)、篩選條件。[initial] 為 null
/// = 新增;新增成功後 pop 回傳新報表 id,讓清單頁直接開啟它。
class ReportEditPage extends ConsumerStatefulWidget {
  final ReportDefinition? initial;
  const ReportEditPage({super.key, this.initial});

  @override
  ConsumerState<ReportEditPage> createState() => _ReportEditPageState();
}

class _ReportEditPageState extends ConsumerState<ReportEditPage> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late ReportFilter _filter = widget.initial?.filter ?? ReportFilter.none;

  late _Kind _kind;
  // 重複循環
  ReportPeriodUnit _recUnit = ReportPeriodUnit.month;
  int _recSpan = 1;
  // 截至今天
  UntilTodayMode _utMode = UntilTodayMode.lastN;
  ReportPeriodUnit _utUnit = ReportPeriodUnit.day;
  int _utCount = 30;
  DateTime? _utSince;
  // 單一區間
  late DateTime _fixStart;
  late DateTime _fixEnd;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fixStart = DateTime(now.year, now.month, 1);
    _fixEnd = DateTime(now.year, now.month, now.day);
    final p = widget.initial?.period ??
        const RecurringPeriod(unit: ReportPeriodUnit.month);
    switch (p) {
      case RecurringPeriod(:final unit, :final span):
        _kind = _Kind.recurring;
        _recUnit = unit;
        _recSpan = span;
      case UntilTodayPeriod(
          :final mode,
          :final unit,
          :final count,
          :final since
        ):
        _kind = _Kind.untilToday;
        _utMode = mode;
        _utUnit = unit;
        _utCount = count;
        _utSince = since;
      case FixedRangePeriod(:final start, :final endInclusive):
        _kind = _Kind.fixed;
        _fixStart = start;
        _fixEnd = endInclusive;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  ReportPeriod get _period {
    switch (_kind) {
      case _Kind.recurring:
        return RecurringPeriod(unit: _recUnit, span: _recSpan);
      case _Kind.untilToday:
        return UntilTodayPeriod(
          mode: _utMode,
          unit: _utUnit,
          count: _utCount,
          since: _utMode == UntilTodayMode.since ? _utSince : null,
        );
      case _Kind.fixed:
        return FixedRangePeriod(start: _fixStart, endInclusive: _fixEnd);
    }
  }

  Future<void> _save() async {
    final store = ref.read(reportStoreProvider.notifier);
    final name = _name.text.trim();
    final init = widget.initial;
    if (init == null) {
      final def = ReportDefinition(
        id: ReportStoreNotifier.newId(),
        name: name.isEmpty ? null : name,
        period: _period,
        filter: _filter,
      );
      await store.add(def);
      if (mounted) Navigator.pop(context, def.id);
      return;
    }
    final periodChanged = init.period != _period;
    await store.update(init.copyWith(
      name: () => name.isEmpty ? null : name,
      period: _period,
      filter: _filter,
    ));
    if (periodChanged) {
      ref.read(reportOffsetProvider.notifier).set(init.id, 0);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<DateTime?> _pickDate(DateTime initial) => showWheelDatePicker(context,
      initial: initial, mode: WheelDatePickerMode.ymd);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final init = widget.initial;
    final nameHint = init != null && init.builtInKey != null
        ? reportDisplayName(l10n, init.copyWith(name: () => null))
        : l10n.reportNameHint;

    return Scaffold(
      body: Column(
        children: [
          PrimaryHeader(
            title: init == null ? l10n.reportNew : l10n.reportEdit,
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
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, 24 + MediaQuery.of(context).viewPadding.bottom),
              children: [
                Text(l10n.reportName, style: BeeTextTokens.label(context)),
                const SizedBox(height: 6),
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    hintText: nameHint,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                Text(l10n.reportPeriod, style: BeeTextTokens.label(context)),
                const SizedBox(height: 6),
                CapsuleSwitcher<_Kind>(
                  selectedValue: _kind,
                  height: 36,
                  options: [
                    CapsuleOption(
                        value: _Kind.recurring,
                        label: l10n.reportPeriodRecurring),
                    CapsuleOption(
                        value: _Kind.untilToday,
                        label: l10n.reportPeriodUntilToday),
                    CapsuleOption(
                        value: _Kind.fixed, label: l10n.reportPeriodFixed),
                  ],
                  onChanged: (k) => setState(() => _kind = k),
                ),
                const SizedBox(height: 16),
                ..._periodFields(l10n),
                const SizedBox(height: 24),
                Divider(color: BeeTokens.divider(context)),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.reportFilter),
                  subtitle: _filter.isActive
                      ? Text(l10n.reportFilterApplied(_filter.activeCount),
                          style: TextStyle(color: BeeTokens.primary(context)))
                      : null,
                  trailing: Icon(Icons.chevron_right,
                      color: BeeTokens.iconTertiary(context)),
                  onTap: () async {
                    final result =
                        await Navigator.of(context).push<ReportFilter>(
                      MaterialPageRoute(
                          builder: (_) => ReportFilterPage(initial: _filter)),
                    );
                    if (result != null) setState(() => _filter = result);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _unitChips(
      ReportPeriodUnit selected, ValueChanged<ReportPeriodUnit> onPick) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      children: [
        for (final u in ReportPeriodUnit.values)
          ChoiceChip(
            label: Text(reportUnitLabel(l10n, u)),
            selected: u == selected,
            onSelected: (_) => onPick(u),
          ),
      ],
    );
  }

  Widget _stepper(
      String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Row(
      children: [
        Text(label, style: BeeTextTokens.label(context)),
        const Spacer(),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 44,
          child: Text('$value',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  Widget _dateRow(String label, DateTime? value, String emptyText,
      ValueChanged<DateTime> onPicked) {
    final text =
        value == null ? emptyText : '${value.year}/${value.month}/${value.day}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(text,
          style: TextStyle(
              color: BeeTokens.primary(context), fontWeight: FontWeight.w600)),
      onTap: () async {
        final d = await _pickDate(value ?? DateTime.now());
        if (d != null) onPicked(DateTime(d.year, d.month, d.day));
      },
    );
  }

  List<Widget> _periodFields(AppLocalizations l10n) {
    switch (_kind) {
      case _Kind.recurring:
        return [
          Text(l10n.reportUnit, style: BeeTextTokens.label(context)),
          const SizedBox(height: 6),
          _unitChips(_recUnit, (u) => setState(() => _recUnit = u)),
          const SizedBox(height: 8),
          _stepper(l10n.reportSpan, _recSpan, 1, 12,
              (v) => setState(() => _recSpan = v)),
          Text(l10n.reportEveryN(_recSpan, reportUnitLabel(l10n, _recUnit)),
              style: TextStyle(
                  fontSize: 12, color: BeeTokens.textTertiary(context))),
        ];
      case _Kind.untilToday:
        return [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(l10n.reportUntilTodayLastN),
                selected: _utMode == UntilTodayMode.lastN,
                onSelected: (_) =>
                    setState(() => _utMode = UntilTodayMode.lastN),
              ),
              ChoiceChip(
                label: Text(l10n.reportUntilTodaySince),
                selected: _utMode == UntilTodayMode.since,
                onSelected: (_) =>
                    setState(() => _utMode = UntilTodayMode.since),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_utMode == UntilTodayMode.lastN) ...[
            Text(l10n.reportUnit, style: BeeTextTokens.label(context)),
            const SizedBox(height: 6),
            _unitChips(_utUnit, (u) => setState(() => _utUnit = u)),
            const SizedBox(height: 8),
            _stepper(l10n.reportCount, _utCount, 1, 999,
                (v) => setState(() => _utCount = v)),
            Text(l10n.reportLastN(_utCount, reportUnitPlural(l10n, _utUnit)),
                style: TextStyle(
                    fontSize: 12, color: BeeTokens.textTertiary(context))),
          ] else ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.reportSinceAll),
              value: _utSince == null,
              onChanged: (all) => setState(() {
                _utSince = all ? null : DateTime(DateTime.now().year, 1, 1);
              }),
            ),
            if (_utSince != null)
              _dateRow(l10n.reportSinceDate, _utSince, '',
                  (d) => setState(() => _utSince = d)),
          ],
        ];
      case _Kind.fixed:
        return [
          _dateRow(l10n.reportStartDate, _fixStart, '',
              (d) => setState(() => _fixStart = d)),
          _dateRow(l10n.reportEndDate, _fixEnd, '',
              (d) => setState(() => _fixEnd = d)),
        ];
    }
  }
}
