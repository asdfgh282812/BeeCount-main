import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';
import '../../utils/card_reward_period.dart';
import '../../utils/month_range.dart';

/// 期間切換元件(design doc 2026-09-06 §4.1):左右箭頭 + 可點擊的期間文字。
/// 樣式抄 `account_detail_page.dart` 的信用卡帳單週期 chevron(置中 Row +
/// 兩個 compact IconButton),抽成共用元件而非再複製一份。
class PeriodRangeSelector extends StatelessWidget {
  final String label;

  /// null = 停用(例如已到專案建立前——本元件不設下限,呼叫端若要停用請傳
  /// null)。
  final VoidCallback? onPrev;

  /// null = 停用(已是當期,不能切到未來)。
  final VoidCallback? onNext;

  final VoidCallback onTapLabel;

  const PeriodRangeSelector({
    super.key,
    required this.label,
    required this.onPrev,
    required this.onNext,
    required this.onTapLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.chevron_left,
              size: 20,
              color: onPrev == null
                  ? BeeTokens.iconTertiary(context)
                  : BeeTokens.iconSecondary(context)),
          onPressed: onPrev,
        ),
        InkWell(
          onTap: onTapLabel,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: BeeTokens.textPrimary(context),
              ),
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.chevron_right,
              size: 20,
              color: onNext == null
                  ? BeeTokens.iconTertiary(context)
                  : BeeTokens.iconSecondary(context)),
          onPressed: onNext,
        ),
      ],
    );
  }
}

/// 「選擇區間」清單彈窗(design doc §4.2)。[periodType] 只接受
/// 'monthly'/'yearly'('fixed' 專案只有單一區間,呼叫端不應調用本函式,見
/// [PeriodRangeSelector] 的用法)。[currentOffset] 是目前選中的 offset,
/// [monthStartDay] 供 monthly 模式算標籤用。往回列 12 期(超過 12 期需求極低,
/// 之後如有反饋再加分頁載入)。回傳使用者按下「確定」時選中的 offset;取消
/// 或關閉回傳 null。
Future<int?> showPeriodRangeListPicker(
  BuildContext context, {
  required String periodType,
  required int currentOffset,
  required int monthStartDay,
}) {
  final l10n = AppLocalizations.of(context);
  final now = DateTime.now();

  final entries = <({int offset, String label})>[];
  if (periodType == 'yearly') {
    for (var offset = 0; offset < 12; offset++) {
      final year = now.year - offset;
      entries.add((offset: offset, label: l10n.projectPeriodYearlyLabel(year)));
    }
  } else {
    final currentLabel = labelForDate(now, monthStartDay);
    for (var offset = 0; offset < 12; offset++) {
      final target =
          DateTime(currentLabel.year, currentLabel.month - offset, 1);
      final range = periodForLabel(target.year, target.month, monthStartDay);
      final endInclusive =
          DateTime(range.end.year, range.end.month, range.end.day - 1);
      entries.add((
        offset: offset,
        label: '${_formatDate(range.start)}~${_formatDate(endInclusive)}',
      ));
    }
  }

  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: BeeTokens.surfaceElevated(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    isScrollControlled: true,
    builder: (_) => _PeriodRangeListPickerSheet(
      entries: entries,
      initialOffset: currentOffset,
    ),
  );
}

/// 信用卡「選擇區間」清單彈窗:跟 [showPeriodRangeListPicker] 是同一個彈窗
/// UI,只是週期改用 [billingCyclePeriod](帳單結帳日週期)算,而不是自然月/
/// 年——帳戶頁的信用卡帳單彙總卡片用這個,見
/// `account_detail_page.dart::_buildBillingSummaryCard`。
///
/// [oldestOffset] 是清單要往回列到哪一期(含),呼叫端應該用該帳戶(含合併
/// 帳單子卡)最早一筆交易反推——沒有資料的更舊帳期不列出來,避免使用者選到
/// 空清單(2026-09-06 使用者回報)。[currentOffset] 必須 <= 0(0 = 涵蓋今天、
/// 尚未結束的本期,呼叫端的右箭頭本來就不允許切到未來);若呼叫端傳入的
/// [oldestOffset] 比目前選中的 [currentOffset] 還新(例如使用者先手動點箭頭
/// 翻到比最早交易還舊的帳期),仍會把 [currentOffset] 納入清單,確保目前選取
/// 一定在列表裡可以被勾選到。
Future<int?> showBillingCyclePeriodListPicker(
  BuildContext context, {
  required int? billingDay,
  required int currentOffset,
  required int oldestOffset,
}) {
  final effectiveOldestOffset =
      oldestOffset < currentOffset ? oldestOffset : currentOffset;
  final entries = <({int offset, String label})>[];
  for (var offset = 0; offset >= effectiveOldestOffset; offset--) {
    final period = billingCyclePeriod(billingDay, offset);
    entries.add((
      offset: offset,
      label: '${_formatDate(period.start.subtract(const Duration(days: 1)))} – '
          '${_formatDate(period.end)}',
    ));
  }

  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: BeeTokens.surfaceElevated(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    isScrollControlled: true,
    builder: (_) => _PeriodRangeListPickerSheet(
      entries: entries,
      initialOffset: currentOffset,
    ),
  );
}

String _formatDate(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

class _PeriodRangeListPickerSheet extends StatefulWidget {
  final List<({int offset, String label})> entries;
  final int initialOffset;

  const _PeriodRangeListPickerSheet({
    required this.entries,
    required this.initialOffset,
  });

  @override
  State<_PeriodRangeListPickerSheet> createState() =>
      _PeriodRangeListPickerSheetState();
}

class _PeriodRangeListPickerSheetState
    extends State<_PeriodRangeListPickerSheet> {
  late int _selected = widget.initialOffset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              l10n.projectPeriodPickerTitle,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: BeeTokens.textPrimary(context),
              ),
            ),
          ),
          Divider(height: 1, color: BeeTokens.divider(context)),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final entry in widget.entries)
                  ListTile(
                    title: Text(
                      entry.label,
                      style: TextStyle(
                        color: entry.offset == _selected
                            ? BeeTokens.primary(context)
                            : BeeTokens.textPrimary(context),
                        fontWeight: entry.offset == _selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: entry.offset == _selected
                        ? Icon(Icons.check, color: BeeTokens.primary(context))
                        : null,
                    onTap: () => setState(() => _selected = entry.offset),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: BeeTokens.divider(context)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.commonCancel,
                        style:
                            TextStyle(color: BeeTokens.textTertiary(context))),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: Text(l10n.commonOk,
                        style: TextStyle(
                            color: BeeTokens.primary(context),
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
