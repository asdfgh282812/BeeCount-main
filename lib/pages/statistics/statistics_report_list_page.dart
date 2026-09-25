import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/report/report_dataset.dart';
import '../../models/report/report_definition.dart';
import '../../providers.dart';
import '../../services/report/report_aggregator.dart';
import '../../services/report/report_period_resolver.dart';
import '../../styles/tokens.dart';
import '../../widgets/biz/biz.dart';
import '../../widgets/statistics/report_colors.dart';
import '../../widgets/ui/ui.dart';
import 'report_edit_page.dart';
import 'report_labels.dart';
import 'statistics_report_page.dart';

/// 底部導覽第 4 個分頁「報表」的根頁面:已儲存的統計報表清單(對齊 MOZE
/// 報表列表)。點卡片開報表;右上 + 新增;卡片右側按鈕開編輯/複製/刪除;
/// 長按拖曳排序。
class StatisticsReportListPage extends ConsumerWidget {
  const StatisticsReportListPage({super.key});

  Future<void> _create(BuildContext context) async {
    final id = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const ReportEditPage()));
    if (id != null && context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => StatisticsReportPage(reportId: id)));
    }
  }

  Future<void> _actions(
      BuildContext context, WidgetRef ref, ReportDefinition def) async {
    final l10n = AppLocalizations.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: BeeTokens.surfaceElevated(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.commonEdit),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(l10n.reportDuplicate),
              onTap: () => Navigator.pop(ctx, 'duplicate'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: BeeTokens.error(ctx)),
              title: Text(l10n.commonDelete,
                  style: TextStyle(color: BeeTokens.error(ctx))),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    final store = ref.read(reportStoreProvider.notifier);
    final name = reportDisplayName(l10n, def);
    switch (action) {
      case 'edit':
        await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ReportEditPage(initial: def)));
      case 'duplicate':
        await store.duplicate(def.id, l10n.reportCopyName(name));
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (dctx) => AlertDialog(
            content: Text(l10n.reportDeleteConfirm(name)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dctx, false),
                  child: Text(l10n.commonCancel)),
              TextButton(
                  onPressed: () => Navigator.pop(dctx, true),
                  child: Text(l10n.commonDelete,
                      style: TextStyle(color: BeeTokens.error(dctx)))),
            ],
          ),
        );
        if (ok == true) await store.delete(def.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final store = ref.watch(reportStoreProvider);
    // 懸浮 Tab 欄高度(56) + 浮動間距(12) + 安全區 + 額外間距
    final bottom = 56 + 12 + MediaQuery.of(context).viewPadding.bottom + 16;

    return Scaffold(
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.reportListTitle,
            leadingIcon: Icons.bar_chart_outlined,
            compact: true,
            actions: [
              IconButton(
                tooltip: l10n.reportRestoreDefaults,
                onPressed: () async {
                  await ref
                      .read(reportStoreProvider.notifier)
                      .restoreBuiltIns();
                  if (context.mounted) {
                    showToast(context, l10n.reportRestoreDefaultsDone);
                  }
                },
                icon: Icon(Icons.settings_backup_restore,
                    color: BeeTokens.textPrimary(context)),
              ),
              IconButton(
                tooltip: l10n.reportNew,
                onPressed: () => _create(context),
                icon: Icon(Icons.add, color: BeeTokens.textPrimary(context)),
              ),
            ],
          ),
          Expanded(
            child: !store.loaded
                ? const Center(child: CircularProgressIndicator())
                : store.reports.isEmpty
                    ? AppEmpty(text: l10n.reportEmptyList)
                    : ReorderableListView.builder(
                        padding: EdgeInsets.fromLTRB(12, 12, 12, bottom),
                        itemCount: store.reports.length,
                        onReorderItem: (a, b) => ref
                            .read(reportStoreProvider.notifier)
                            .reorder(a, b),
                        footer: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Center(
                            child: Text(l10n.reportReorderHint,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: BeeTokens.textTertiary(context))),
                          ),
                        ),
                        itemBuilder: (ctx, i) {
                          final def = store.reports[i];
                          return _ReportCard(
                            key: ValueKey(def.id),
                            def: def,
                            onOpen: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => StatisticsReportPage(
                                        reportId: def.id))),
                            onMore: () => _actions(context, ref, def),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends ConsumerWidget {
  final ReportDefinition def;
  final VoidCallback onOpen;
  final VoidCallback onMore;

  const _ReportCard({
    super.key,
    required this.def,
    required this.onOpen,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sd = ref.watch(currentMonthStartDayProvider);
    final weekMon = ref.watch(weekStartsOnMondayProvider);
    final resolved = resolveReportPeriod(def.period,
        monthStartDay: sd, weekStartsOnMonday: weekMon);
    final query = ReportQuery(
      ledgerId: ref.watch(currentLedgerIdProvider),
      start: resolved.start,
      end: resolved.end,
      filter: def.filter,
    );
    final ds = ref.watch(reportDatasetProvider(query)).valueOrNull;
    final s = ds == null ? null : ReportAggregator(ds).summary();

    Widget amount(String label, double? v, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12, color: BeeTokens.textTertiary(context))),
              const SizedBox(height: 2),
              v == null
                  ? const Text('—')
                  : AmountText(
                      value: v,
                      signed: false,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: color)),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: BeeTokens.surface(context),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(reportDisplayName(l10n, def),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: BeeTextTokens.title(context)),
                              ),
                              if (def.filter.isActive) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.filter_alt,
                                    size: 14,
                                    color: BeeTokens.primary(context)),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${reportPeriodLabel(l10n, def.period, resolved, monthStartDay: sd)}'
                            ' · ${reportPeriodKindLabel(l10n, def.period)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color: BeeTokens.textSecondary(context)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onMore,
                      icon: Icon(Icons.more_horiz,
                          color: BeeTokens.iconSecondary(context)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    amount(l10n.homeExpense, s?.expense,
                        reportFlowColor(context, ref, ReportFlow.expense)),
                    amount(l10n.homeIncome, s?.income,
                        reportFlowColor(context, ref, ReportFlow.income)),
                    amount(l10n.homeBalance, s?.balance,
                        reportBalanceColor(context, ref, s?.balance ?? 0)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
