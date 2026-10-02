import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/investment/markets.dart';
import '../../services/investment/realized_pnl_report.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';
import 'investment_ui.dart';

/// 已實現損益報表(股票持股 Phase 3)。
///
/// 全部由本機 stock_trade 即時算([RealizedPnlReport]),不呼叫 Cloud API。
/// 可依年度/帳戶/標的篩選;頂部各幣別分開彙總已實現損益與累計股利,下方
/// 依標的分組、可展開看每筆賣出。損益顏色沿用 [pnlColor](紅漲綠跌設定)。
class RealizedPnlPage extends ConsumerStatefulWidget {
  const RealizedPnlPage({super.key});

  @override
  ConsumerState<RealizedPnlPage> createState() => _RealizedPnlPageState();
}

class _RealizedPnlPageState extends ConsumerState<RealizedPnlPage> {
  int? _year;
  String? _accountKey;
  String? _symbolKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    final trades = ref.watch(stockTradesProvider).valueOrNull;
    final accounts =
        ref.watch(allAccountsStreamProvider).valueOrNull ?? const <Account>[];
    final accountNames = {for (final a in accounts) a.id.toString(): a.name};

    Widget body;
    if (trades == null) {
      body = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else {
      final holdingTrades = trades.map(holdingTradeOf).toList();
      final years = RealizedPnlReport.availableYears(holdingTrades);
      // 篩選條件指向已不存在的選項(例如資料被刪光)時當作「全部」。
      final year = years.contains(_year) ? _year : null;
      final accountKeys = <String>{
        for (final t in holdingTrades)
          if (t.accountKey != null) t.accountKey!,
      };
      final accountKey = accountKeys.contains(_accountKey) ? _accountKey : null;
      final symbolOptions = <String, String>{};
      for (final t in holdingTrades) {
        final k = securityKey(t.market, t.symbol);
        final name = t.securityName;
        final label = (name == null || name.isEmpty) ? t.symbol : '${t.symbol} $name';
        if (!symbolOptions.containsKey(k) || (name != null && name.isNotEmpty)) {
          symbolOptions[k] = label;
        }
      }
      final symbolKey = symbolOptions.containsKey(_symbolKey) ? _symbolKey : null;
      final report = RealizedPnlReport.build(
        holdingTrades,
        filter: RealizedFilter(
            year: year, accountKey: accountKey, symbolKey: symbolKey),
      );
      String money(double v, String ccy, {bool signed = false}) =>
          hide ? '****' : formatStockMoney(v, ccy, signed: signed);

      body = ListView(
        padding: EdgeInsets.symmetric(
            horizontal: 12.0.scaled(context, ref),
            vertical: 8.0.scaled(context, ref)),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _FilterChip<int>(
                label: year == null ? l10n.stockRealizedAllYears : '$year',
                active: year != null,
                options: [for (final y in years) MapEntry(y, '$y')],
                allLabel: l10n.stockRealizedAllYears,
                onSelected: (v) => setState(() => _year = v),
              ),
              _FilterChip<String>(
                label: accountKey == null
                    ? l10n.stockRealizedAllAccounts
                    : (accountNames[accountKey] ?? accountKey),
                active: accountKey != null,
                options: [
                  for (final k in accountKeys)
                    MapEntry(k, accountNames[k] ?? k),
                ],
                allLabel: l10n.stockRealizedAllAccounts,
                onSelected: (v) => setState(() => _accountKey = v),
              ),
              _FilterChip<String>(
                label: symbolKey == null
                    ? l10n.stockRealizedAllSymbols
                    : (symbolOptions[symbolKey] ?? symbolKey),
                active: symbolKey != null,
                options: symbolOptions.entries.toList()
                  ..sort((a, b) => a.key.compareTo(b.key)),
                allLabel: l10n.stockRealizedAllSymbols,
                onSelected: (v) => setState(() => _symbolKey = v),
              ),
            ],
          ),
          SizedBox(height: 8.0.scaled(context, ref)),
          SectionCard(
            margin: EdgeInsets.zero,
            child: report.totals.isEmpty
                ? Text(l10n.stockRealizedEmpty,
                    style: TextStyle(color: BeeTokens.textSecondary(context)))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in report.totals.entries) ...[
                        Text(
                          e.key.isEmpty ? l10n.stockRealizedPnl : e.key,
                          style: TextStyle(
                              fontSize: 12,
                              color: BeeTokens.textSecondary(context)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${l10n.stockRealizedPnl} ${money(e.value.pnl, e.key, signed: true)}',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: pnlColor(context, ref, e.value.pnl)),
                        ),
                        Text(
                          '${l10n.stockDividends} ${money(e.value.dividends, e.key)}',
                          style: TextStyle(
                              fontSize: 13,
                              color: BeeTokens.textSecondary(context)),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Text(l10n.stockRealizedCurrencyNote,
                          style: TextStyle(
                              fontSize: 11,
                              color: BeeTokens.textTertiary(context))),
                    ],
                  ),
          ),
          SizedBox(height: 12.0.scaled(context, ref)),
          for (final g in report.groups) ...[
            SectionCard(
              margin: EdgeInsets.zero,
              padding: EdgeInsets.zero,
              child: _GroupTile(
                group: g,
                hide: hide,
                accountNames: accountNames,
              ),
            ),
            SizedBox(height: 8.0.scaled(context, ref)),
          ],
          SizedBox(height: 24.0.scaled(context, ref)),
        ],
      );
    }

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
              title: l10n.stockRealizedReportTitle,
              showBack: true,
              compact: true),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _FilterChip<T> extends StatelessWidget {
  final String label;
  final bool active;
  final String allLabel;
  final List<MapEntry<T, String>> options;
  final ValueChanged<T?> onSelected;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.allLabel,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: label,
      onSelected: (i) => onSelected(i < 0 ? null : options[i].key),
      itemBuilder: (_) => [
        PopupMenuItem<int>(value: -1, child: Text(allLabel)),
        for (var i = 0; i < options.length; i++)
          PopupMenuItem<int>(value: i, child: Text(options[i].value)),
      ],
      child: Chip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: active
                          ? BeeTokens.textPrimary(context)
                          : BeeTokens.textSecondary(context),
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
            ),
            Icon(Icons.arrow_drop_down,
                size: 18, color: BeeTokens.iconSecondary(context)),
          ],
        ),
        backgroundColor: BeeTokens.surfaceChip(context),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _GroupTile extends ConsumerWidget {
  final RealizedSymbolGroup group;
  final bool hide;
  final Map<String, String> accountNames;

  const _GroupTile(
      {required this.group, required this.hide, required this.accountNames});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final g = group;
    String money(double v, {bool signed = false}) =>
        hide ? '****' : formatStockMoney(v, g.currency, signed: signed);
    final name = g.securityName;
    final title =
        (name == null || name.isEmpty) ? g.symbol : '${g.symbol} $name';
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: EdgeInsets.zero,
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: BeeTokens.textPrimary(context))),
        subtitle: Text(
          [
            stockMarketLabel(l10n, g.market),
            if (g.events.isNotEmpty) l10n.stockRealizedSellCount(g.events.length),
            if (g.dividends > 0) '${l10n.stockDividends} ${money(g.dividends)}',
          ].join(' · '),
          style: TextStyle(
              fontSize: 12, color: BeeTokens.textSecondary(context)),
        ),
        trailing: Text(
          money(g.pnl, signed: true),
          style: TextStyle(
              fontWeight: FontWeight.w700, color: pnlColor(context, ref, g.pnl)),
        ),
        children: [
          for (final e in g.events)
            ListTile(
              dense: true,
              title: Text(
                '${e.date} · ${l10n.stockSharesCount(formatShares(e.shares))}',
                style: TextStyle(color: BeeTokens.textPrimary(context)),
              ),
              subtitle: Text(
                [
                  '${l10n.stockRealizedProceeds} ${money(e.proceeds)}',
                  '${l10n.stockRealizedCostBasis} ${money(e.costBasis)}',
                  if (accountNames[e.accountKey] != null)
                    accountNames[e.accountKey]!,
                ].join(' · '),
                style: TextStyle(color: BeeTokens.textSecondary(context)),
              ),
              trailing: Text(
                money(e.pnl, signed: true),
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: pnlColor(context, ref, e.pnl)),
              ),
            ),
        ],
      ),
    );
  }
}
