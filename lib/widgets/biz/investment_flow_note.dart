import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../pages/investment/investment_market_value_card.dart';
import '../../pages/investment/investment_ui.dart';
import '../../providers.dart';
import '../../services/investment/investment_flow.dart';
import '../../styles/tokens.dart';

/// 把 [InvestmentFlowConverted] 組成要顯示的文字(報表小字、年度報告卡共用)。
///
/// 文案原則(docs/changes/2026-10-03-stock-report-consistency.md):
/// - 淨投入那行明講「未計入收入與支出」,讓使用者知道買股票的錢沒有消失、也不是支出;
/// - 手續費與證交稅是投資成本,不計入支出,在這裡可查;
/// - 股利收入「已計入收入」,這行只是標示來源,避免使用者以為要再加一次。
class InvestmentFlowLines {
  /// 主行(例:「投資淨投入 +NT$20,000」);沒有買賣只有股利時為 null。
  final String? title;

  /// 說明行(買進/賣出明細、手續費稅、股利、缺匯率)。
  final List<String> details;

  /// 缺匯率那行(用警示色)在 [details] 裡的索引,沒有為 null。
  final int? warningIndex;

  const InvestmentFlowLines(this.title, this.details, this.warningIndex);

  static InvestmentFlowLines build(
      AppLocalizations l10n, InvestmentFlowConverted conv,
      {bool hide = false}) {
    final t = conv.total;
    final cur = conv.currency;
    String money(double v, {bool signed = false}) =>
        hide ? '****' : formatStockMoney(v, cur, signed: signed);
    final hasTrades = t.buyCount > 0 || t.sellCount > 0;
    final details = <String>[];
    String? title;
    if (hasTrades) {
      title = '${l10n.stockFlowNetInvested} ${money(t.netInvested, signed: true)}';
      details.add(
          '${l10n.stockFlowBuySell(money(t.buy), money(t.sell))} · ${l10n.stockFlowNotCounted}');
      if (t.feesAndTax > 1e-9) {
        details.add(l10n.stockFlowFees(money(t.feesAndTax)));
      }
    }
    if (t.dividends.abs() > 1e-9) {
      details.add(l10n.stockFlowDividends(money(t.dividends)));
    }
    int? warn;
    if (conv.missingCurrencies.isNotEmpty) {
      warn = details.length;
      details.add(l10n.stockMissingRates(conv.missingCurrencies.join(', ')));
    }
    return InvestmentFlowLines(title, details, warn);
  }
}

/// 報表/日曆下方的「投資補充資訊」小字:這段期間股票的淨投入、手續費稅、股利。
///
/// 收入/支出統計刻意不計轉帳(買股票是轉帳到投資理財帳戶),所以只看收支會覺得
/// 錢少了——這個元件補上「錢去哪了」。期間內沒有股票買賣/股利時完全不佔空間。
/// 點擊進投資總覽。
class InvestmentFlowNote extends ConsumerWidget {
  /// 半開區間 [start, end)。
  final DateTime start;
  final DateTime end;
  final int? ledgerId;

  /// 精簡模式(日曆頁空間吃緊):只顯示主行 + 第一行說明,手續費/股利進投資頁再看。
  final bool compact;
  final EdgeInsetsGeometry padding;

  const InvestmentFlowNote({
    super.key,
    required this.start,
    required this.end,
    this.ledgerId,
    this.compact = false,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 0),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(currentLedgerProvider).valueOrNull;
    final conv = ref.watch(investmentFlowProvider((
      ledgerId: ledgerId,
      start: start,
      end: end,
      currency: ledger?.currency,
    )));
    if (conv == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    final lines = InvestmentFlowLines.build(l10n, conv, hide: hide);
    if (lines.title == null && lines.details.isEmpty) {
      return const SizedBox.shrink();
    }
    final tertiary = BeeTokens.textTertiary(context);
    return Padding(
      padding: padding,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const InvestmentsOverviewPage())),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.candlestick_chart_outlined,
                    size: 14, color: BeeTokens.iconTertiary(context)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (lines.title != null)
                      Text(lines.title!,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: BeeTokens.textSecondary(context))),
                    for (final (i, line) in lines.details
                        .take(compact ? 1 : lines.details.length)
                        .indexed)
                      Text(line,
                          style: TextStyle(
                              fontSize: 11,
                              color: i == lines.warningIndex
                                  ? BeeTokens.warning(context)
                                  : tertiary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: tertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 帳戶頁淨資產卡 / 淨資產走勢頁的補充說明:淨資產不含投資理財帳戶,買進股票時
/// 淨資產會減少(是轉帳不是支出);有持股時另外標出投資市值,點擊進投資總覽。
/// 使用者從來沒記過股票交易時不顯示。
class StockNetWorthNote extends ConsumerWidget {
  /// 走勢頁用較短的說明(不重複市值)。
  final bool trend;

  /// 置中(帳戶頁淨資產卡內容是置中的)。
  final bool centered;
  final EdgeInsetsGeometry padding;

  const StockNetWorthNote({
    super.key,
    this.trend = false,
    this.centered = false,
    this.padding = const EdgeInsets.fromLTRB(4, 10, 4, 0),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTrades =
        ref.watch(stockTradesProvider.select((s) => s.valueOrNull?.isNotEmpty ?? false));
    if (!hasTrades) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final tertiary = BeeTokens.textTertiary(context);

    if (trend) {
      return Padding(
        padding: padding,
        child: Text(l10n.stockNetWorthTrendNote,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: TextStyle(fontSize: 11, color: tertiary)),
      );
    }

    final summary = ref.watch(investmentSummaryProvider);
    final hide = ref.watch(hideAmountsProvider);
    // 有持股但全部缺報價時市值是 0,不要寫成「約 $0」誤導,退回只說明不含投資帳戶。
    final text = (summary == null || summary.marketValue <= 0)
        ? l10n.stockNetWorthNoteExcluded
        : l10n.stockNetWorthNoteWithValue(hide
            ? '****'
            : formatStockMoney(summary.marketValue, summary.baseCurrency));

    // 有持股的投資理財帳戶若還計入淨資產(舊帳戶、使用者選了保持計入),淨資產裡
    // 已經有一份「成本」,再看投資市值會重複算。
    final accounts =
        ref.watch(allAccountsStreamProvider).valueOrNull ?? const [];
    final stockAccountIds = {
      for (final t in ref.watch(stockTradesProvider).valueOrNull ?? const [])
        if (t.accountId != null) t.accountId!
    };
    final includedCount = accounts
        .where((a) =>
            a.type == 'investment' &&
            a.includeInTotal &&
            stockAccountIds.contains(a.id))
        .length;

    return Padding(
      padding: padding,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const InvestmentsOverviewPage())),
        child: Column(
          crossAxisAlignment:
              centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Text(text,
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: TextStyle(fontSize: 11, color: tertiary)),
            if (includedCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(l10n.stockNetWorthIncludedWarning(includedCount),
                    textAlign: centered ? TextAlign.center : TextAlign.start,
                    style: TextStyle(
                        fontSize: 11, color: BeeTokens.warning(context))),
              ),
          ],
        ),
      ),
    );
  }
}
