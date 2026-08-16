import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/data/recurring_rule_schedule.dart' as recurring_schedule;
import '../../styles/tokens.dart';
import '../ui/entry_date_time_picker.dart';

/// 「進階設定」彈窗的結果——單次(null)或一組週期規則草稿。
///
/// 只覆蓋 App 範圍決策(2026-08-17)內的欄位:不含 `project`/手續費/折扣。
/// `frequency`/`interval`/`advancedRule` 對齐
/// `lib/services/data/recurring_rule_schedule.dart` 的演算法輸入,直接可以
/// 傳給 `RecurringRuleRepository.createRule`。
class RecurringRuleDraft {
  final String frequency; // daily / weekly / monthly / yearly
  final int interval;
  final Map<String, dynamic>? advancedRule;
  final DateTime? endAt; // null = 無限期

  const RecurringRuleDraft({
    required this.frequency,
    required this.interval,
    this.advancedRule,
    this.endAt,
  });

  /// 摘要文字,給交易表單的「週期」欄位 + 規則列表頁共用。
  /// 例如「每月 · 10 號 · 無限期」「每 2 週 · 一、三、五 · 至 2026/12/01」。
  String summary(AppLocalizations l10n) {
    final parts = <String>[];
    final rule = advancedRule;
    if (rule != null && rule['type'] == 'weekly_days') {
      // List.of(...) 而不是 .cast()..sort():来源可能是不可变 list(例如呼叫端
      // 传 const list),就地 sort() 会抛 Unsupported operation。
      final days = List<int>.of((rule['days'] as List).cast<int>())..sort();
      final labels = days.map((d) => _weekdayLabel(l10n, d)).join('、');
      parts.add('${l10n.recurringUnitWeek} · $labels');
    } else if (rule != null && rule['type'] == 'monthly_day') {
      final day = rule['day'] as int;
      parts.add(
          '${l10n.recurringEveryPrefix}${interval > 1 ? interval : ''}${l10n.recurringUnitMonth} · ${l10n.recurringSummaryMonthDay(day)}');
    } else {
      parts.add(
          '${l10n.recurringEveryPrefix}${interval > 1 ? interval : ''}${_unitLabel(l10n, frequency)}');
    }
    parts.add(endAt == null
        ? l10n.recurringSummaryUnlimited
        : l10n.recurringSummaryUntil(_fmtDate(endAt!)));
    return parts.join(' · ');
  }

  static String _fmtDate(DateTime d) => '${d.year}/${d.month}/${d.day}';

  static String _unitLabel(AppLocalizations l10n, String frequency) {
    switch (frequency) {
      case 'daily':
        return l10n.recurringUnitDay;
      case 'weekly':
        return l10n.recurringUnitWeek;
      case 'yearly':
        return l10n.recurringUnitYear;
      default:
        return l10n.recurringUnitMonth;
    }
  }

  static String _weekdayLabel(AppLocalizations l10n, int zeroBasedMonday) {
    const labels = [
      'recurringWeekdayMon',
      'recurringWeekdayTue',
      'recurringWeekdayWed',
      'recurringWeekdayThu',
      'recurringWeekdayFri',
      'recurringWeekdaySat',
      'recurringWeekdaySun',
    ];
    switch (labels[zeroBasedMonday % 7]) {
      case 'recurringWeekdayMon':
        return l10n.recurringWeekdayMon;
      case 'recurringWeekdayTue':
        return l10n.recurringWeekdayTue;
      case 'recurringWeekdayWed':
        return l10n.recurringWeekdayWed;
      case 'recurringWeekdayThu':
        return l10n.recurringWeekdayThu;
      case 'recurringWeekdayFri':
        return l10n.recurringWeekdayFri;
      case 'recurringWeekdaySat':
        return l10n.recurringWeekdaySat;
      default:
        return l10n.recurringWeekdaySun;
    }
  }
}

/// MOZE 對標「進階設定」彈窗:單次/週期/分期(佔位,不可點) tab,週期 tab
/// 內含區間 picker、星期/日期選擇、次數(無限期/指定次數)、入帳方式(v1 只有
/// 「立即入帳」一種,純展示)。
///
/// [show] 回傳:
/// - `null`:使用者選「單次」或取消 —— 呼叫端應把週期關掉。
/// - [RecurringRuleDraft]:使用者選「週期」並確認。
class RecurringRuleAdvancedSheet {
  static Future<RecurringRuleDraft?> show(
    BuildContext context, {
    required DateTime anchorDate,
    RecurringRuleDraft? initialDraft,
  }) {
    return showModalBottomSheet<RecurringRuleDraft?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BeeTokens.surfaceSheet(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _RecurringRuleAdvancedSheetBody(
        anchorDate: anchorDate,
        initialDraft: initialDraft,
      ),
    );
  }
}

class _RecurringRuleAdvancedSheetBody extends StatefulWidget {
  final DateTime anchorDate;
  final RecurringRuleDraft? initialDraft;

  const _RecurringRuleAdvancedSheetBody({
    required this.anchorDate,
    this.initialDraft,
  });

  @override
  State<_RecurringRuleAdvancedSheetBody> createState() =>
      _RecurringRuleAdvancedSheetBodyState();
}

enum _Mode { once, recurring }

// 「截止日期」是新增的第三種結束方式,跟「指定次數」互斥——擇一決定
// _endAt 怎麼算。RecurringRuleDraft 只存最終算出的 endAt,不記錄是哪種
// 模式選出來的,所以重新打開彈窗(initialDraft 帶入舊 endAt)時沒法還原
// 「當初是選次數還是選日期」,一律當「截止日期」模式回顯——這是既有設計
// (RecurringRuleDraft 的欄位範圍)的既知限制,不是這次改動引入的新問題。
enum _EndMode { unlimited, count, date }

class _RecurringRuleAdvancedSheetBodyState
    extends State<_RecurringRuleAdvancedSheetBody> {
  late _Mode _mode;
  late String _frequency; // daily/weekly/monthly/yearly
  late int _interval;
  late Set<int> _weekdays; // 0=Monday..6=Sunday
  late int _monthDay;
  late _EndMode _endMode;
  late int _fixedCount;
  late DateTime _specificEndDate;

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    _mode = draft == null ? _Mode.once : _Mode.recurring;
    _frequency = draft?.frequency ?? 'monthly';
    _interval = draft?.interval ?? 1;
    final rule = draft?.advancedRule;
    _weekdays = rule != null && rule['type'] == 'weekly_days'
        ? (rule['days'] as List).cast<int>().toSet()
        : {recurring_schedule.weekdayZeroBased(widget.anchorDate)};
    _monthDay = rule != null && rule['type'] == 'monthly_day'
        ? rule['day'] as int
        : widget.anchorDate.day;
    _endMode = draft?.endAt == null ? _EndMode.unlimited : _EndMode.date;
    _fixedCount = 12;
    _specificEndDate = draft?.endAt ?? widget.anchorDate;
  }

  Map<String, dynamic>? get _advancedRule {
    if (_frequency == 'weekly') {
      return {'type': 'weekly_days', 'days': _weekdays.toList()..sort()};
    }
    if (_frequency == 'monthly') {
      return {'type': 'monthly_day', 'day': _monthDay};
    }
    return null;
  }

  DateTime? get _endAt {
    switch (_endMode) {
      case _EndMode.unlimited:
        return null;
      case _EndMode.date:
        return _specificEndDate;
      case _EndMode.count:
        final occurrences = recurring_schedule.enumerateOccurrences(
          start: widget.anchorDate,
          end: null,
          frequency: _frequency,
          interval: _interval,
          advancedRule: _advancedRule,
          maxCount: _fixedCount < 1 ? 1 : _fixedCount,
        );
        return occurrences.isNotEmpty ? occurrences.last : widget.anchorDate;
    }
  }

  void _confirm() {
    if (_mode == _Mode.once) {
      Navigator.pop(context, null);
      return;
    }
    Navigator.pop(
      context,
      RecurringRuleDraft(
        frequency: _frequency,
        interval: _interval,
        advancedRule: _advancedRule,
        endAt: _endAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: BeeTokens.divider(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  l10n.recurringSheetTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 14),
                _buildModeTabs(context, l10n),
                const SizedBox(height: 16),
                if (_mode == _Mode.recurring) ...[
                  _buildIntervalRow(context, l10n),
                  const SizedBox(height: 14),
                  if (_frequency == 'weekly')
                    _buildWeekdayPicker(context, l10n),
                  if (_frequency == 'monthly')
                    _buildMonthDayPicker(context, l10n),
                  const SizedBox(height: 14),
                  _buildCountSection(context, l10n),
                  const SizedBox(height: 14),
                  _buildPostingModeRow(context, l10n),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(l10n.commonCancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _confirm,
                        child: Text(l10n.commonConfirm),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeTabs(BuildContext context, AppLocalizations l10n) {
    Widget tab(String label, _Mode? mode, {bool disabled = false}) {
      final selected = mode != null && mode == _mode;
      return Expanded(
        child: GestureDetector(
          onTap: disabled || mode == null
              ? null
              : () => setState(() => _mode = mode),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.12)
                  : BeeTokens.surfaceInput(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: disabled
                        ? BeeTokens.textTertiary(context)
                        : selected
                            ? Theme.of(context).colorScheme.primary
                            : BeeTokens.textSecondary(context),
                  ),
                ),
                if (disabled)
                  Text(
                    l10n.recurringTabInstallmentComingSoon,
                    style: TextStyle(
                      fontSize: 10,
                      color: BeeTokens.textTertiary(context),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab(l10n.recurringTabOnce, _Mode.once),
        const SizedBox(width: 8),
        tab(l10n.recurringTabRecurring, _Mode.recurring),
        const SizedBox(width: 8),
        tab(l10n.recurringTabInstallment, null, disabled: true),
      ],
    );
  }

  Widget _buildIntervalRow(BuildContext context, AppLocalizations l10n) {
    final units = <(String, String)>[
      ('daily', l10n.recurringUnitDay),
      ('weekly', l10n.recurringUnitWeek),
      ('monthly', l10n.recurringUnitMonth),
      ('yearly', l10n.recurringUnitYear),
    ];
    return Row(
      children: [
        Text(l10n.recurringEveryPrefix,
            style: TextStyle(color: BeeTokens.textPrimary(context))),
        const SizedBox(width: 8),
        if (_frequency != 'weekly') ...[
          _stepperButton(context, Icons.remove, () {
            if (_interval > 1) setState(() => _interval--);
          }),
          SizedBox(
            width: 32,
            child: Text(
              '$_interval',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: BeeTokens.textPrimary(context)),
            ),
          ),
          _stepperButton(context, Icons.add, () {
            setState(() => _interval++);
          }),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Wrap(
            spacing: 6,
            children: units.map((u) {
              final selected = _frequency == u.$1;
              return ChoiceChip(
                label: Text(u.$2),
                selected: selected,
                onSelected: (_) => setState(() {
                  _frequency = u.$1;
                  if (u.$1 == 'weekly') _interval = 1;
                }),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _stepperButton(
      BuildContext context, IconData icon, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: BeeTokens.surfaceInput(context),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: BeeTokens.textPrimary(context)),
      ),
    );
  }

  Widget _buildWeekdayPicker(BuildContext context, AppLocalizations l10n) {
    final labels = [
      l10n.recurringWeekdayMon,
      l10n.recurringWeekdayTue,
      l10n.recurringWeekdayWed,
      l10n.recurringWeekdayThu,
      l10n.recurringWeekdayFri,
      l10n.recurringWeekdaySat,
      l10n.recurringWeekdaySun,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.recurringWeekdaysLabel,
            style: TextStyle(
                fontSize: 12, color: BeeTokens.textSecondary(context))),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(7, (i) {
            final selected = _weekdays.contains(i);
            return ChoiceChip(
              label: Text(labels[i]),
              selected: selected,
              onSelected: (val) {
                setState(() {
                  if (val) {
                    _weekdays.add(i);
                  } else if (_weekdays.length > 1) {
                    // 至少保留一天,避免 weekly_days.days 传空 list 触发
                    // enumerateOccurrences 的 ArgumentError。
                    _weekdays.remove(i);
                  }
                });
              },
            );
          }),
        ),
      ],
    );
  }

  Widget _buildMonthDayPicker(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.recurringMonthDayLabel,
            style: TextStyle(
                fontSize: 12, color: BeeTokens.textSecondary(context))),
        const SizedBox(height: 6),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 31,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final day = i + 1;
              final selected = _monthDay == day;
              return ChoiceChip(
                label: Text('$day'),
                selected: selected,
                onSelected: (_) => setState(() => _monthDay = day),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCountSection(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.recurringCountLabel,
            style: TextStyle(
                fontSize: 12, color: BeeTokens.textSecondary(context))),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(l10n.recurringCountUnlimited),
              selected: _endMode == _EndMode.unlimited,
              onSelected: (_) =>
                  setState(() => _endMode = _EndMode.unlimited),
            ),
            ChoiceChip(
              label: Text(l10n.recurringCountFixed),
              selected: _endMode == _EndMode.count,
              onSelected: (_) => setState(() => _endMode = _EndMode.count),
            ),
            ChoiceChip(
              label: Text(l10n.recurringCountDate),
              selected: _endMode == _EndMode.date,
              onSelected: (_) => setState(() => _endMode = _EndMode.date),
            ),
          ],
        ),
        if (_endMode == _EndMode.count) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              _stepperButton(context, Icons.remove, () {
                if (_fixedCount > 1) setState(() => _fixedCount--);
              }),
              InkWell(
                key: const Key('recurringFixedCountValue'),
                borderRadius: BorderRadius.circular(8),
                onTap: _editFixedCount,
                child: SizedBox(
                  width: 40,
                  child: Text(
                    '$_fixedCount',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: BeeTokens.textPrimary(context)),
                  ),
                ),
              ),
              _stepperButton(context, Icons.add, () {
                setState(() => _fixedCount++);
              }),
              const SizedBox(width: 8),
              Text(l10n.recurringCountUnit,
                  style: TextStyle(color: BeeTokens.textSecondary(context))),
            ],
          ),
        ],
        if (_endMode == _EndMode.date) ...[
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _pickSpecificEndDate,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: BeeTokens.surfaceInput(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_outlined,
                      size: 16, color: BeeTokens.iconSecondary(context)),
                  const SizedBox(width: 6),
                  Text(
                    RecurringRuleDraft._fmtDate(_specificEndDate),
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: BeeTokens.textPrimary(context)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _editFixedCount() async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController(text: '$_fixedCount');
    final entered = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(l10n.recurringCountEditTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(suffixText: l10n.recurringCountUnit),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (entered == null || !mounted) return;
    final v = int.tryParse(entered);
    if (v == null || v < 1) return;
    setState(() => _fixedCount = v);
  }

  Future<void> _pickSpecificEndDate() async {
    final res = await showTransactionDatePicker(
      context,
      initial: _specificEndDate,
      minDate: widget.anchorDate,
    );
    if (res == null || !mounted) return;
    setState(() => _specificEndDate = res);
  }

  Widget _buildPostingModeRow(BuildContext context, AppLocalizations l10n) {
    // v1 只支持「立即入帳」,純展示(對齐計畫 §3.1:先把 UI 選項做出來,語意
    // 上先只接這一種,不做額外邏輯)。
    return Row(
      children: [
        Text(l10n.recurringPostingModeLabel,
            style: TextStyle(
                fontSize: 12, color: BeeTokens.textSecondary(context))),
        const SizedBox(width: 10),
        Chip(label: Text(l10n.recurringPostingModeImmediate)),
      ],
    );
  }
}
