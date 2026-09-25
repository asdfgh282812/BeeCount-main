import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/report/report_dataset.dart';
import '../../models/report/report_definition.dart';
import '../../models/report/report_period.dart';
import '../../providers.dart';
import '../../services/export/share_poster_service.dart';
import '../../services/report/report_aggregator.dart';
import '../../services/report/report_period_resolver.dart';
import '../../styles/tokens.dart';
import '../../utils/month_range.dart';
import '../../widgets/statistics/foreign_currency_stats_banner.dart';
import '../../widgets/ui/ui.dart';
import 'report_edit_page.dart';
import 'report_filter_page.dart';
import 'report_labels.dart';
import 'report_view.dart';
import 'tabs/category_tab.dart';
import 'tabs/details_tab.dart';
import 'tabs/dimension_tab.dart';
import 'tabs/overview_tab.dart';
import 'tabs/ranking_tab.dart';

/// 單份統計報表(對齊 doc.moze.app/analysis/statistics-report):頁首切換
/// 期間,下方 10 個分頁共用同一份資料集。
class StatisticsReportPage extends ConsumerStatefulWidget {
  final String reportId;
  const StatisticsReportPage({super.key, required this.reportId});

  @override
  ConsumerState<StatisticsReportPage> createState() =>
      _StatisticsReportPageState();
}

class _StatisticsReportPageState extends ConsumerState<StatisticsReportPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 10, vsync: this);

  /// 換期/改篩選時先沿用上一份資料,避免整頁閃成 loading。
  ReportDataset? _lastDataset;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  int get _offset => ref.read(reportOffsetProvider)[widget.reportId] ?? 0;

  void _setOffset(int o) =>
      ref.read(reportOffsetProvider.notifier).set(widget.reportId, o);

  /// 期間選單上限(防呆:第一筆交易很久以前、又是週報表時不至於列上千期)。
  static const _maxPickerEntries = 520;

  Future<void> _pickRecurring(
      ReportDefinition def, int sd, bool weekMon, DateTime? firstTx) async {
    final l10n = AppLocalizations.of(context);
    final current = _offset;
    // 從當期往前列到第一筆交易所在的那一期;沒有交易就只列當期。目前停在
    // 更早的期間(例如第一筆交易被刪了)也照樣列出,打勾才對得上。
    final entries = <({int offset, String label})>[];
    for (var o = 0; o > -_maxPickerEntries; o--) {
      final r = resolveReportPeriod(def.period,
          offset: o, monthStartDay: sd, weekStartsOnMonday: weekMon);
      final beforeFirst = firstTx == null || !r.nominalEnd.isAfter(firstTx);
      if (o < current && beforeFirst) {
        break;
      }
      entries.add((
        offset: o,
        label: reportPeriodLabel(l10n, def.period, r, monthStartDay: sd),
      ));
    }
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: BeeTokens.surfaceElevated(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in entries)
                ListTile(
                  title: Text(e.label,
                      style: TextStyle(
                        color: e.offset == current
                            ? BeeTokens.primary(ctx)
                            : BeeTokens.textPrimary(ctx),
                        fontWeight: e.offset == current
                            ? FontWeight.w600
                            : FontWeight.normal,
                      )),
                  trailing: e.offset == current
                      ? Icon(Icons.check, color: BeeTokens.primary(ctx))
                      : null,
                  onTap: () => Navigator.pop(ctx, e.offset),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) _setOffset(picked);
  }

  void _openEdit(ReportDefinition def) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => ReportEditPage(initial: def)));

  void _openFilter(ReportDefinition def) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReportFilterPage(reportId: def.id)));

  Future<void> _share(ReportDefinition def, ResolvedPeriod r, int sd) async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    final l10n = AppLocalizations.of(context);
    if (ledgerId == 0) {
      showToast(context, l10n.sharePosterNoLedger);
      return;
    }
    final unit = (def.period as RecurringPeriod).unit;
    final label = labelForDate(r.start, sd);
    try {
      await SharePosterService.showDynamicPosterPreview(
        context,
        ref,
        type: unit == ReportPeriodUnit.month ? 'month' : 'year',
        ledgerId: ledgerId,
        year: label.year,
        month: unit == ReportPeriodUnit.month ? label.month : null,
      );
    } catch (e) {
      if (mounted) showToast(context, '${l10n.commonError}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final store = ref.watch(reportStoreProvider);
    final def = store.byId(widget.reportId);
    if (def == null) {
      return Scaffold(
        body: Column(
          children: [
            PrimaryHeader(title: '', showBack: true, compact: true),
            Expanded(
              child: Center(
                child: store.loaded
                    ? Text(l10n.reportNotFound)
                    : const CircularProgressIndicator(),
              ),
            ),
          ],
        ),
      );
    }

    final sd = ref.watch(currentMonthStartDayProvider);
    final weekMon = ref.watch(weekStartsOnMondayProvider);
    final offset = ref.watch(reportOffsetProvider)[def.id] ?? 0;
    final resolved = resolveReportPeriod(def.period,
        offset: offset, monthStartDay: sd, weekStartsOnMonday: weekMon);
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final query = ReportQuery(
      ledgerId: ledgerId,
      start: resolved.start,
      end: resolved.end,
      filter: def.filter,
    );
    final async = ref.watch(reportDatasetProvider(query));
    final ds = async.valueOrNull;
    if (ds != null) _lastDataset = ds;
    final shown = ds ?? _lastDataset;
    final periodLabel =
        reportPeriodLabel(l10n, def.period, resolved, monthStartDay: sd);
    final isRecurring = def.period is RecurringPeriod;
    // 上一期停在第一筆交易那一期;還在查第一筆交易時先不擋
    final firstTxAsync = ref.watch(reportFirstTxDateProvider(ledgerId));
    final firstTx = firstTxAsync.valueOrNull;
    final hasEarlier = !firstTxAsync.hasValue ||
        (firstTx != null && firstTx.isBefore(resolved.start));
    final onPrev =
        resolved.canPrev && hasEarlier ? () => _setOffset(offset - 1) : null;
    final onNext = resolved.canNext ? () => _setOffset(offset + 1) : null;
    final canShare = def.period is RecurringPeriod &&
        (def.period as RecurringPeriod).span == 1 &&
        ((def.period as RecurringPeriod).unit == ReportPeriodUnit.month ||
            (def.period as RecurringPeriod).unit == ReportPeriodUnit.year) &&
        !def.filter.isActive;
    final filterCount = def.filter.activeCount;

    return Scaffold(
      body: Column(
        children: [
          PrimaryHeader(
            title: reportDisplayName(l10n, def),
            showBack: true,
            compact: true,
            actions: [
              IconButton(
                tooltip: l10n.reportFilter,
                onPressed: () => _openFilter(def),
                icon: Badge(
                  isLabelVisible: filterCount > 0,
                  label: Text('$filterCount'),
                  child: Icon(Icons.filter_alt_outlined,
                      color: BeeTokens.textPrimary(context)),
                ),
              ),
              IconButton(
                tooltip: l10n.reportEdit,
                onPressed: () => _openEdit(def),
                icon: Icon(Icons.tune, color: BeeTokens.textPrimary(context)),
              ),
              if (canShare)
                IconButton(
                  onPressed: () => _share(def, resolved, sd),
                  icon:
                      Icon(Icons.share, color: BeeTokens.textPrimary(context)),
                ),
            ],
            bottom: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: isRecurring
                  ? PeriodRangeSelector(
                      label: periodLabel,
                      onPrev: onPrev,
                      onNext: onNext,
                      onTapLabel: () =>
                          _pickRecurring(def, sd, weekMon, firstTx),
                    )
                  : TextButton(
                      onPressed: () => _openEdit(def),
                      child: Text(periodLabel,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: BeeTokens.textPrimary(context))),
                    ),
            ),
          ),
          const ForeignCurrencyRecalcBanner(),
          const ConvertedStatsFootnote(),
          if (filterCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.filter_alt,
                      size: 14, color: BeeTokens.primary(context)),
                  const SizedBox(width: 4),
                  Text(l10n.reportFilterApplied(filterCount),
                      style: TextStyle(
                          fontSize: 12, color: BeeTokens.primary(context))),
                ],
              ),
            ),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: BeeTokens.textPrimary(context),
            unselectedLabelColor: BeeTokens.textTertiary(context),
            indicatorColor: BeeTokens.primary(context),
            dividerColor: BeeTokens.divider(context),
            labelStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 14),
            tabs: [
              Tab(text: l10n.reportTabOverview),
              Tab(text: l10n.reportTabDetails),
              Tab(text: l10n.reportTabCategory),
              Tab(text: l10n.reportTabRanking),
              Tab(text: l10n.reportTabAccount),
              Tab(text: l10n.reportTabProject),
              Tab(text: l10n.reportTabAccountGroup),
              Tab(text: l10n.reportTabName),
              Tab(text: l10n.reportTabMerchant),
              Tab(text: l10n.reportTabTagCounterparty),
            ],
          ),
          if (async.isLoading && shown != null)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: shown == null
                ? (async.hasError
                    ? Center(child: Text('${l10n.commonError}: ${async.error}'))
                    : const Center(child: CircularProgressIndicator()))
                : _buildTabs(
                    ReportView(
                      def: def,
                      period: resolved,
                      query: query,
                      ds: shown,
                      agg: ReportAggregator(shown),
                      periodLabel: periodLabel,
                      monthStartDay: sd,
                      onPrev: onPrev,
                      onNext: onNext,
                    ),
                    l10n,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(ReportView v, AppLocalizations l10n) {
    return TabBarView(
      controller: _tabs,
      // 分頁只靠點上方 TabBar 切換(同 MOZE):趨勢圖的左右滑留給「上/下一期」。
      physics: const NeverScrollableScrollPhysics(),
      children: [
        ReportOverviewTab(view: v),
        ReportDetailsTab(view: v),
        ReportCategoryTab(view: v),
        ReportRankingTab(view: v),
        ReportDimensionTab(
            view: v, dimensions: const [ReportDimension.account]),
        ReportDimensionTab(
            view: v, dimensions: const [ReportDimension.project]),
        ReportDimensionTab(
            view: v, dimensions: const [ReportDimension.accountGroup]),
        ReportDimensionTab(view: v, dimensions: const [ReportDimension.name]),
        ReportDimensionTab(
            view: v, dimensions: const [ReportDimension.merchant]),
        ReportDimensionTab(
          view: v,
          dimensions: const [
            ReportDimension.tag,
            ReportDimension.counterparty,
          ],
          sectionTitles: [
            l10n.reportSectionTags,
            l10n.reportSectionCounterparties,
          ],
          footnote: l10n.reportTagFootnote,
        ),
      ],
    );
  }
}
