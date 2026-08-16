import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';

/// 交易表单「日期/時間」欄位專用的一對選擇器——取代舊版
/// `wheel_date_picker.dart` 裡合併日期+時間的 wheel 兩步流程。日期/時間在
/// 表單上已拆成兩個獨立欄位,各自喚起這裡的其中一個 sheet。
///
/// 兩者共用同一套 chrome:左上角鍵盤圖示(展開/收起 MMdd 或 HHmm 快速跳轉
/// 輸入框)、置中標題、右上角快速操作(日期是「今天」,時間是「現在」),
/// 下方是月曆網格/時分 wheel,再下方是取消/確定兩個 pill 按鈕。
///
/// 這裡刻意不動 `wheel_date_picker.dart` 裡既有的 `showWheelDatePicker` /
/// `showWheelDateTimePicker`——那些仍給行事曆表頭年月跳轉等其它入口用。

/// 月曆網格日期選擇器。預設不限制上界(可選未來日期),下界固定
/// 2000-01-01,與 App 內其它日期選擇器的慣例一致。
Future<DateTime?> showTransactionDatePicker(
  BuildContext context, {
  required DateTime initial,
  DateTime? minDate,
  DateTime? maxDate,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: BeeTokens.surfaceElevated(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    isScrollControlled: true,
    builder: (_) => _TransactionDatePickerSheet(
      initial: initial,
      minDate: minDate ?? DateTime(2000, 1, 1),
      maxDate: maxDate ?? DateTime(2100, 12, 31),
    ),
  );
}

/// 時分選擇器(HH:mm,不含秒)。右上角「現在」一鍵填入當下時間。
Future<TimeOfDay?> showTransactionTimePicker(
  BuildContext context, {
  required TimeOfDay initial,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: BeeTokens.surfaceElevated(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    isScrollControlled: true,
    builder: (_) => _TransactionTimePickerSheet(initial: initial),
  );
}

/// 兩個 sheet 共用的頂部欄:鍵盤圖示 + 置中標題 + 右側快速操作文字按鈕。
class _PickerTopBar extends StatelessWidget {
  final bool jumpOpen;
  final VoidCallback onToggleJump;
  final String title;
  final String quickActionLabel;
  final VoidCallback onQuickAction;

  const _PickerTopBar({
    required this.jumpOpen,
    required this.onToggleJump,
    required this.title,
    required this.quickActionLabel,
    required this.onQuickAction,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          IconButton(
            onPressed: onToggleJump,
            icon: Icon(
              jumpOpen ? Icons.keyboard_hide_outlined : Icons.keyboard_outlined,
              color: jumpOpen
                  ? Theme.of(context).primaryColor
                  : BeeTokens.textSecondary(context),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: BeeTokens.textPrimary(context),
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: onQuickAction,
            child: Text(
              quickActionLabel,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// MMdd / HHmm 快速跳轉輸入框:純 4 位數字,湊滿即時套用。
class _JumpInputField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onChanged;

  const _JumpInputField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 4,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        style: TextStyle(
          fontSize: 20,
          letterSpacing: 4,
          color: BeeTokens.textPrimary(context),
        ),
        decoration: InputDecoration(
          counterText: '',
          hintText: hint,
          hintStyle: TextStyle(
              color: BeeTokens.textTertiary(context), letterSpacing: 4),
          filled: true,
          fillColor: BeeTokens.surfaceInput(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// 底部取消/確定 pill 按鈕列。
class _PickerBottomActions extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const _PickerBottomActions({
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onCancel,
              child: Text(l10n.commonCancel),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: onConfirm,
              child: Text(l10n.commonOk),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionDatePickerSheet extends StatefulWidget {
  final DateTime initial;
  final DateTime minDate;
  final DateTime maxDate;

  const _TransactionDatePickerSheet({
    required this.initial,
    required this.minDate,
    required this.maxDate,
  });

  @override
  State<_TransactionDatePickerSheet> createState() =>
      _TransactionDatePickerSheetState();
}

class _TransactionDatePickerSheetState
    extends State<_TransactionDatePickerSheet> {
  late DateTime _focusedMonth;
  late DateTime _selectedDay;
  bool _jumpOpen = false;
  final _jumpCtrl = TextEditingController();
  final _jumpFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final clamped = _clamp(widget.initial);
    _selectedDay = DateTime(clamped.year, clamped.month, clamped.day);
    _focusedMonth = _monthStart(clamped);
  }

  @override
  void dispose() {
    _jumpCtrl.dispose();
    _jumpFocus.dispose();
    super.dispose();
  }

  DateTime _clamp(DateTime d) {
    if (d.isBefore(widget.minDate)) return widget.minDate;
    if (d.isAfter(widget.maxDate)) return widget.maxDate;
    return d;
  }

  /// 該日期所在月份的「1 號」,再夾回 [minDate, maxDate]——`minDate` 不見得
  /// 剛好是月初(例如週期規則「截止日期」的下限是 anchorDate,可能是月中任一
  /// 天),直接回傳月初會落在 `firstDay`(=minDate)之前,傳給 `TableCalendar`
  /// 的 `focusedDay` 觸發它內部 `isSameDay(focusedDay, firstDay) ||
  /// focusedDay.isAfter(firstDay)` 斷言失敗、紅屏崩潰。
  DateTime _monthStart(DateTime d) => _clamp(DateTime(d.year, d.month, 1));

  void _toggleJump() {
    final opening = !_jumpOpen;
    setState(() => _jumpOpen = opening);
    if (opening) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpFocus.requestFocus();
      });
    } else {
      _jumpCtrl.clear();
      _jumpFocus.unfocus();
    }
  }

  void _applyJump(String value) {
    if (value.length != 4) return;
    final month = int.tryParse(value.substring(0, 2));
    final day = int.tryParse(value.substring(2, 4));
    if (month == null || day == null || month < 1 || month > 12 || day < 1) {
      return;
    }
    // 年份跟随目前聚焦的月份;日期超出該月天數時鉗到月底,而不是靜默忽略。
    final year = _focusedMonth.year;
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    final clampedDay = day > lastDayOfMonth ? lastDayOfMonth : day;
    final target = _clamp(DateTime(year, month, clampedDay));
    setState(() {
      _selectedDay = target;
      _focusedMonth = _monthStart(target);
    });
  }

  void _jumpToToday() {
    final today = _clamp(DateTime.now());
    setState(() {
      _selectedDay = DateTime(today.year, today.month, today.day);
      _focusedMonth = _monthStart(today);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final primary = Theme.of(context).primaryColor;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _PickerTopBar(
              jumpOpen: _jumpOpen,
              onToggleJump: _toggleJump,
              title: _jumpOpen ? 'MMdd' : l10n.homeSelectDate,
              quickActionLabel: l10n.calendarToday,
              onQuickAction: _jumpToToday,
            ),
          ),
          if (_jumpOpen)
            _JumpInputField(
              controller: _jumpCtrl,
              focusNode: _jumpFocus,
              hint: 'MMdd',
              onChanged: _applyJump,
            ),
          TableCalendar(
            locale: locale,
            firstDay: widget.minDate,
            lastDay: widget.maxDate,
            focusedDay: _focusedMonth,
            selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
            onDaySelected: (selected, focused) {
              setState(() {
                _selectedDay =
                    DateTime(selected.year, selected.month, selected.day);
                _focusedMonth = _monthStart(focused);
              });
            },
            onPageChanged: (focused) {
              setState(() => _focusedMonth = _monthStart(focused));
            },
            calendarFormat: CalendarFormat.month,
            availableCalendarFormats: const {CalendarFormat.month: ''},
            startingDayOfWeek: StartingDayOfWeek.monday,
            availableGestures: AvailableGestures.horizontalSwipe,
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              leftChevronIcon: Icon(Icons.chevron_left, color: primary),
              rightChevronIcon: Icon(Icons.chevron_right, color: primary),
              titleTextStyle: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: BeeTokens.textPrimary(context),
              ),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: TextStyle(
                  color: BeeTokens.textSecondary(context), fontSize: 12),
              weekendStyle: TextStyle(
                  color: BeeTokens.textSecondary(context), fontSize: 12),
            ),
            calendarStyle: CalendarStyle(
              outsideDaysVisible: true,
              todayDecoration: BoxDecoration(
                color: primary.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              todayTextStyle:
                  TextStyle(color: primary, fontWeight: FontWeight.bold),
              selectedDecoration:
                  BoxDecoration(color: primary, shape: BoxShape.circle),
              selectedTextStyle: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
              defaultTextStyle:
                  TextStyle(color: BeeTokens.textPrimary(context)),
              weekendTextStyle:
                  TextStyle(color: BeeTokens.textPrimary(context)),
              outsideTextStyle: TextStyle(
                  color:
                      BeeTokens.textTertiary(context).withValues(alpha: 0.4)),
            ),
          ),
          _PickerBottomActions(
            onCancel: () => Navigator.pop(context),
            onConfirm: () => Navigator.pop(context, _selectedDay),
          ),
        ],
      ),
    );
  }
}

class _TransactionTimePickerSheet extends StatefulWidget {
  final TimeOfDay initial;

  const _TransactionTimePickerSheet({required this.initial});

  @override
  State<_TransactionTimePickerSheet> createState() =>
      _TransactionTimePickerSheetState();
}

class _TransactionTimePickerSheetState
    extends State<_TransactionTimePickerSheet> {
  late int hour;
  late int minute;
  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minuteCtrl;
  bool _jumpOpen = false;
  final _jumpCtrl = TextEditingController();
  final _jumpFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    hour = widget.initial.hour;
    minute = widget.initial.minute;
    _hourCtrl = FixedExtentScrollController(initialItem: hour);
    _minuteCtrl = FixedExtentScrollController(initialItem: minute);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    _jumpCtrl.dispose();
    _jumpFocus.dispose();
    super.dispose();
  }

  void _toggleJump() {
    final opening = !_jumpOpen;
    setState(() => _jumpOpen = opening);
    if (opening) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpFocus.requestFocus();
      });
    } else {
      _jumpCtrl.clear();
      _jumpFocus.unfocus();
    }
  }

  void _applyJump(String value) {
    if (value.length != 4) return;
    final h = int.tryParse(value.substring(0, 2));
    final m = int.tryParse(value.substring(2, 4));
    if (h == null || m == null || h > 23 || m > 59) return;
    setState(() {
      hour = h;
      minute = m;
    });
    _hourCtrl.jumpToItem(h);
    _minuteCtrl.jumpToItem(m);
  }

  void _setNow() {
    final now = TimeOfDay.now();
    setState(() {
      hour = now.hour;
      minute = now.minute;
    });
    _hourCtrl.jumpToItem(hour);
    _minuteCtrl.jumpToItem(minute);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _PickerTopBar(
              jumpOpen: _jumpOpen,
              onToggleJump: _toggleJump,
              title: _jumpOpen ? 'HHmm' : l10n.commonSelectTime,
              quickActionLabel: l10n.commonNow,
              onQuickAction: _setNow,
            ),
          ),
          if (_jumpOpen)
            _JumpInputField(
              controller: _jumpCtrl,
              focusNode: _jumpFocus,
              hint: 'HHmm',
              onChanged: _applyJump,
            ),
          SizedBox(
            height: 180,
            child: Row(
              children: [
                Expanded(
                  child: CupertinoPicker(
                    scrollController: _hourCtrl,
                    itemExtent: 40,
                    onSelectedItemChanged: (i) => setState(() => hour = i),
                    children: List.generate(
                      24,
                      (i) => Center(
                        child: Text(
                          i.toString().padLeft(2, '0'),
                          style: TextStyle(
                              fontSize: 20,
                              color: BeeTokens.textPrimary(context)),
                        ),
                      ),
                    ),
                  ),
                ),
                Text(':',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: BeeTokens.textPrimary(context))),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: _minuteCtrl,
                    itemExtent: 40,
                    onSelectedItemChanged: (i) => setState(() => minute = i),
                    children: List.generate(
                      60,
                      (i) => Center(
                        child: Text(
                          i.toString().padLeft(2, '0'),
                          style: TextStyle(
                              fontSize: 20,
                              color: BeeTokens.textPrimary(context)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _PickerBottomActions(
            onCancel: () => Navigator.pop(context),
            onConfirm: () =>
                Navigator.pop(context, TimeOfDay(hour: hour, minute: minute)),
          ),
        ],
      ),
    );
  }
}
