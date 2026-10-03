import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/investment/stock_annual_report.dart';
import '../../styles/tokens.dart';
import '../investment/investment_ui.dart';
import 'annual_report_labels.dart';
import 'annual_report_page.dart';

/// 年度報告新增的頁面(股票總覽 / 股票亮點 / 年度稱號 / 跟去年比 / 消費習慣)。
///
/// 全部畫在主題色背景上,沿用既有頁面的視覺:白字 + 半透明白卡片,需要顏色
/// 語意的數字放進實心 [BeeTokens.surface] 卡片(深色模式也看得清楚)。
/// 每一頁都只在「資料條件成立」時才會被 [AnnualReportPage] 加進 PageView。

// ---------------------------------------------------------------------------
// 共用小元件
// ---------------------------------------------------------------------------

Color _onPrimary(BuildContext c) => BeeTokens.textOnHeader(c);
Color _onPrimaryDim(BuildContext c, [double alpha = 0.7]) =>
    BeeTokens.textOnHeader(c).withValues(alpha: alpha);
Color _glass(BuildContext c) =>
    BeeTokens.textOnHeader(c).withValues(alpha: 0.15);

/// 股票漲跌色(跟投資頁 [pnlColor] 同一套規則:依「股票漲跌顏色」設定,
/// 與收支配色互相獨立)。
Color _stockPnlColor(BuildContext c, bool upIsRed, double v) {
  if (v.abs() < 1e-9) return BeeTokens.textSecondary(c);
  final up = upIsRed ? BeeTokens.error(c) : BeeTokens.success(c);
  final down = upIsRed ? BeeTokens.success(c) : BeeTokens.error(c);
  return v > 0 ? up : down;
}

/// 進場動畫:淡入 + 上滑,[delayMs] 讓同一頁的區塊依序登場。
class _Reveal extends StatelessWidget {
  final int delayMs;
  final Widget child;
  const _Reveal({this.delayMs = 0, required this.child});

  @override
  Widget build(BuildContext context) {
    final total = 480 + delayMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: BeeMotion.durationOf(context, Duration(milliseconds: total)),
      curve: Interval(delayMs / total, 1, curve: BeeMotion.standard),
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child:
            Transform.translate(offset: Offset(0, 18 * (1 - v)), child: child),
      ),
      child: child,
    );
  }
}

class _PageFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  const _PageFrame(
      {required this.title, required this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: _onPrimary(context),
                  fontSize: 32,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(
                  color: BeeTokens.textOnHeaderSecondary(context),
                  fontSize: 16)),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _GlassCard(
      {required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: _glass(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );
}

class _SolidCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _SolidCard(
      {required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: BeeTokens.surface(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );
}

/// 數字從 0 滾到 [value]。
class _CountUp extends StatelessWidget {
  final double value;
  final String Function(double) format;
  final TextStyle style;
  const _CountUp(
      {required this.value, required this.format, required this.style});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration:
          BeeMotion.durationOf(context, const Duration(milliseconds: 900)),
      curve: BeeMotion.standard,
      builder: (context, v, _) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(format(v), style: style),
      ),
    );
  }
}

/// 多幣別時的切換 chip;只有一個幣別時不佔空間。
class _CurrencyChips extends StatelessWidget {
  final List<StockCurrencyAnnual> currencies;
  final ValueNotifier<int> selected;
  const _CurrencyChips({required this.currencies, required this.selected});

  @override
  Widget build(BuildContext context) {
    if (currencies.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ValueListenableBuilder<int>(
        valueListenable: selected,
        builder: (context, index, _) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < currencies.length; i++)
              GestureDetector(
                onTap: () => selected.value = i,
                child: AnimatedContainer(
                  duration: BeeMotion.durationOf(context, BeeMotion.fast),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: i == index
                        ? _onPrimary(context)
                        : _onPrimary(context).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    currencies[i].currency.isEmpty
                        ? '—'
                        : currencies[i].currency,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: i == index
                          ? BeeTokens.surfaceHeader(context)
                          : _onPrimary(context),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 股票年度總覽
// ---------------------------------------------------------------------------

class AnnualStockOverviewPage extends ConsumerWidget {
  final StockAnnualBundle stock;
  final ValueNotifier<int> selected;
  const AnnualStockOverviewPage(
      {super.key, required this.stock, required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final upIsRed = ref.watch(stockUpIsRedProvider);
    final hide = ref.watch(hideAmountsProvider);
    return _PageFrame(
      title: l10n.annualStockOverviewTitle,
      subtitle: l10n.annualStockOverviewSubtitle,
      children: [
        if (stock.firstBuyThisYear)
          _Reveal(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _GlassCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Icon(Icons.auto_awesome_rounded,
                      color: _onPrimary(context), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(l10n.annualStockFirstBuy,
                        style: TextStyle(
                            color: _onPrimary(context),
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ),
          ),
        _CurrencyChips(currencies: stock.currencies, selected: selected),
        ValueListenableBuilder<int>(
          valueListenable: selected,
          builder: (context, index, _) {
            final c =
                stock.currencies[index.clamp(0, stock.currencies.length - 1)];
            return _OverviewBody(c: c, upIsRed: upIsRed, hide: hide);
          },
        ),
      ],
    );
  }
}

class _OverviewBody extends StatelessWidget {
  final StockCurrencyAnnual c;
  final bool upIsRed;
  final bool hide;
  const _OverviewBody(
      {required this.c, required this.upIsRed, required this.hide});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String money(double v, {bool signed = false}) =>
        hide ? '****' : formatStockMoney(v, c.currency, signed: signed);
    final pnlColor = _stockPnlColor(context, upIsRed, c.realizedPnl);

    final cheer = !c.hasSells
        ? l10n.annualStockNoSell
        : (c.realizedPnl > 1e-9
            ? l10n.annualStockCheerUp
            : (c.realizedPnl < -1e-9
                ? l10n.annualStockCheerDown
                : l10n.annualStockCheerFlat));

    final tiles = <Widget>[
      _StatTile(
        icon: Icons.swap_horiz_rounded,
        label: l10n.annualStockTrades,
        value: '${c.tradeCount}',
        sub: l10n.annualStockBuySellCount(c.buyCount, c.sellCount),
      ),
      if (c.buyCount > 0)
        _StatTile(
          icon: Icons.south_west_rounded,
          label: l10n.annualStockBuyAmount,
          value: money(c.buyAmount),
        ),
      if (c.sellCount > 0)
        _StatTile(
          icon: Icons.north_east_rounded,
          label: l10n.annualStockSellAmount,
          value: money(c.sellAmount),
        ),
      if (c.dividendCount > 0)
        _StatTile(
          icon: Icons.paid_rounded,
          label: l10n.annualStockDividendIncome,
          value: money(c.dividends),
          sub: l10n.annualStockDividendCount(c.dividendCount),
        ),
      if (c.fees + c.taxes > 1e-9)
        _StatTile(
          icon: Icons.receipt_long_rounded,
          label: l10n.annualStockFeesTax,
          value: money(c.fees + c.taxes),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Reveal(
          delayMs: 80,
          child: _SolidCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: pnlColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                        c.realizedPnl >= 0
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        color: pnlColor,
                        size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(l10n.annualStockRealizedPnl,
                        style: TextStyle(
                            color: BeeTokens.textSecondary(context),
                            fontSize: 14)),
                  ),
                ]),
                if (c.hasSells) ...[
                  const SizedBox(height: 14),
                  hide
                      ? Text('****',
                          style: TextStyle(
                              color: pnlColor,
                              fontSize: 40,
                              fontWeight: FontWeight.bold))
                      : _CountUp(
                          value: c.realizedPnl,
                          format: (v) =>
                              formatStockMoney(v, c.currency, signed: true),
                          style: TextStyle(
                              color: pnlColor,
                              fontSize: 40,
                              fontWeight: FontWeight.bold),
                        ),
                ],
                const SizedBox(height: 10),
                Text(cheer,
                    style: TextStyle(
                        color: BeeTokens.textSecondary(context),
                        fontSize: 13,
                        height: 1.4)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, box) {
          final w = (box.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < tiles.length; i++)
                _Reveal(
                    delayMs: 160 + i * 70,
                    child: SizedBox(width: w, child: tiles[i])),
            ],
          );
        }),
        const SizedBox(height: 16),
        Text(l10n.annualStockSymbolCount(c.symbolCount),
            style: TextStyle(
                color: _onPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(l10n.annualStockFootnote,
            style: TextStyle(color: _onPrimaryDim(context, 0.6), fontSize: 11)),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  const _StatTile(
      {required this.icon, required this.label, required this.value, this.sub});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _onPrimary(context), size: 20),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    color: _onPrimary(context),
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(color: _onPrimaryDim(context), fontSize: 12)),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!,
                style: TextStyle(
                    color: _onPrimaryDim(context, 0.55), fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 股票亮點
// ---------------------------------------------------------------------------

class AnnualStockHighlightsPage extends ConsumerWidget {
  final StockAnnualBundle stock;
  final ValueNotifier<int> selected;
  const AnnualStockHighlightsPage(
      {super.key, required this.stock, required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final upIsRed = ref.watch(stockUpIsRedProvider);
    final hide = ref.watch(hideAmountsProvider);
    return _PageFrame(
      title: l10n.annualStockHighlightsTitle,
      subtitle: l10n.annualStockHighlightsSubtitle,
      children: [
        _CurrencyChips(currencies: stock.currencies, selected: selected),
        ValueListenableBuilder<int>(
          valueListenable: selected,
          builder: (context, index, _) {
            final c =
                stock.currencies[index.clamp(0, stock.currencies.length - 1)];
            return _HighlightsBody(c: c, upIsRed: upIsRed, hide: hide);
          },
        ),
      ],
    );
  }
}

class _HighlightsBody extends StatelessWidget {
  final StockCurrencyAnnual c;
  final bool upIsRed;
  final bool hide;
  const _HighlightsBody(
      {required this.c, required this.upIsRed, required this.hide});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String money(double v, {bool signed = false}) =>
        hide ? '****' : formatStockMoney(v, c.currency, signed: signed);

    final best =
        (c.bestSell != null && c.bestSell!.pnl > 1e-9) ? c.bestSell : null;
    final worst =
        (c.worstSell != null && c.worstSell!.pnl < -1e-9) ? c.worstSell : null;
    final hasMonthly = c.monthlyRealizedPnl.any((v) => v.abs() > 1e-9);

    var step = 0;
    int nextDelay() => 80 + (step++) * 90;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 投資風格
        _Reveal(
          delayMs: nextDelay(),
          child: _GlassCard(
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _onPrimary(context).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(stockStyleIcon(c.styleTag),
                      color: _onPrimary(context), size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.annualStockStyleLabel,
                          style: TextStyle(
                              color: _onPrimaryDim(context), fontSize: 12)),
                      const SizedBox(height: 2),
                      Text(stockStyleLabel(l10n, c.styleTag),
                          style: TextStyle(
                              color: _onPrimary(context),
                              fontSize: 22,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(stockStyleDesc(l10n, c.styleTag),
                          style: TextStyle(
                              color: _onPrimaryDim(context, 0.85),
                              fontSize: 13,
                              height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // 最賺 / 最賠
        if (best != null || worst != null) ...[
          const SizedBox(height: 12),
          _Reveal(
            delayMs: nextDelay(),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (best != null)
                    Expanded(
                        child: _SellCard(
                            label: l10n.annualStockBestSell,
                            h: best,
                            color: _stockPnlColor(context, upIsRed, best.pnl),
                            moneyText: money(best.pnl, signed: true),
                            hide: hide)),
                  if (best != null && worst != null) const SizedBox(width: 12),
                  if (worst != null)
                    Expanded(
                        child: _SellCard(
                            label: l10n.annualStockWorstSell,
                            h: worst,
                            color: _stockPnlColor(context, upIsRed, worst.pnl),
                            moneyText: money(worst.pnl, signed: true),
                            hide: hide)),
                ],
              ),
            ),
          ),
        ],
        // 勝率環
        if (c.decidedCount > 0) ...[
          const SizedBox(height: 12),
          _Reveal(
            delayMs: nextDelay(),
            child: _GlassCard(
              child: Row(
                children: [
                  _WinRing(rate: c.winRate),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.annualStockWinRate,
                            style: TextStyle(
                                color: _onPrimaryDim(context), fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(l10n.annualStockWinLoss(c.winCount, c.lossCount),
                            style: TextStyle(
                                color: _onPrimary(context),
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        // 領息王 / 最常交易
        if (c.topDividendSymbol != null) ...[
          const SizedBox(height: 12),
          _Reveal(
            delayMs: nextDelay(),
            child: _SymbolRow(
              icon: Icons.emoji_events_rounded,
              label: l10n.annualStockDividendKing,
              name: c.topDividendSymbol!.displayName,
              value: money(c.topDividendSymbol!.value),
            ),
          ),
        ],
        if (c.topSymbolByTrades != null) ...[
          const SizedBox(height: 12),
          _Reveal(
            delayMs: nextDelay(),
            child: _SymbolRow(
              icon: Icons.local_fire_department_rounded,
              label: l10n.annualStockMostTraded,
              name: c.topSymbolByTrades!.displayName,
              value: l10n.annualStockTimes(c.topSymbolByTrades!.value.round()),
            ),
          ),
        ],
        // 每月已實現損益
        if (hasMonthly) ...[
          const SizedBox(height: 12),
          _Reveal(
            delayMs: nextDelay(),
            child: _SolidCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.annualStockMonthlyPnl,
                      style: TextStyle(
                          color: BeeTokens.textSecondary(context),
                          fontSize: 13)),
                  const SizedBox(height: 14),
                  _MonthlyPnlBars(
                      values: c.monthlyRealizedPnl, upIsRed: upIsRed),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SellCard extends StatelessWidget {
  final String label;
  final StockSellHighlight h;
  final Color color;
  final String moneyText;
  final bool hide;
  const _SellCard(
      {required this.label,
      required this.h,
      required this.color,
      required this.moneyText,
      required this.hide});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rate = h.returnRate;
    final parts = h.date.split('-');
    final dateText = parts.length == 3 ? '${parts[1]}/${parts[2]}' : h.date;
    return _SolidCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: BeeTokens.textSecondary(context), fontSize: 12)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(moneyText,
                style: TextStyle(
                    color: color, fontSize: 22, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 6),
          Text(h.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: BeeTokens.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            rate == null || hide
                ? dateText
                : '$dateText · ${l10n.annualStockReturnRate(formatPercent(rate * 100))}',
            style:
                TextStyle(color: BeeTokens.textTertiary(context), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _SymbolRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String name;
  final String value;
  const _SymbolRow(
      {required this.icon,
      required this.label,
      required this.name,
      required this.value});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _onPrimary(context).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _onPrimary(context), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        TextStyle(color: _onPrimaryDim(context), fontSize: 12)),
                const SizedBox(height: 2),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: _onPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                  color: _onPrimary(context),
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _WinRing extends StatelessWidget {
  final double rate;
  const _WinRing({required this.rate});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: rate.clamp(0.0, 1.0)),
      duration:
          BeeMotion.durationOf(context, const Duration(milliseconds: 1000)),
      curve: BeeMotion.standard,
      builder: (context, v, _) => SizedBox(
        width: 104,
        height: 104,
        child: CustomPaint(
          painter: _RingPainter(
            progress: v,
            track: _onPrimary(context).withValues(alpha: 0.2),
            color: _onPrimary(context),
          ),
          child: Center(
            child: Text('${(v * 100).round()}%',
                style: TextStyle(
                    color: _onPrimary(context),
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color track;
  final Color color;
  const _RingPainter(
      {required this.progress, required this.track, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, 0, math.pi * 2, false, base..color = track);
    if (progress > 0) {
      canvas.drawArc(arc, -math.pi / 2, math.pi * 2 * progress, false,
          base..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

class _MonthlyPnlBars extends StatelessWidget {
  final List<double> values;
  final bool upIsRed;
  const _MonthlyPnlBars({required this.values, required this.upIsRed});

  @override
  Widget build(BuildContext context) {
    final maxPos = values.fold<double>(0, (a, v) => v > a ? v : a);
    final maxNeg = values.fold<double>(0, (a, v) => -v > a ? -v : a);
    final topFlex = math.max(1, (maxPos * 1000).round());
    final bottomFlex = math.max(1, (maxNeg * 1000).round());
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration:
          BeeMotion.durationOf(context, const Duration(milliseconds: 800)),
      curve: BeeMotion.standard,
      builder: (context, t, _) => SizedBox(
        height: 150,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < 12; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            if (maxPos > 0)
                              Expanded(
                                flex: topFlex,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor: values[i] > 0
                                        ? (values[i] / maxPos) * t
                                        : 0,
                                    child: _bar(context, values[i], true),
                                  ),
                                ),
                              ),
                            if (maxNeg > 0)
                              Expanded(
                                flex: bottomFlex,
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: FractionallySizedBox(
                                    heightFactor: values[i] < 0
                                        ? (-values[i] / maxNeg) * t
                                        : 0,
                                    child: _bar(context, values[i], false),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('${i + 1}',
                          style: TextStyle(
                              color: BeeTokens.textTertiary(context),
                              fontSize: 10)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bar(BuildContext context, double v, bool up) => Container(
        decoration: BoxDecoration(
          color: _stockPnlColor(context, upIsRed, v),
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(up ? 4 : 0),
              bottom: Radius.circular(up ? 0 : 4)),
        ),
      );
}

// ---------------------------------------------------------------------------
// 年度稱號
// ---------------------------------------------------------------------------

class AnnualPersonaPage extends ConsumerWidget {
  final AnnualReportData data;
  const AnnualPersonaPage({super.key, required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    final persona = data.persona;
    return _PageFrame(
      title: l10n.annualPersonaTitle,
      subtitle: l10n.annualPersonaSubtitle,
      children: [
        _Reveal(
          delayMs: 100,
          child: _GlassCard(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: _onPrimary(context),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(personaIcon(persona.type),
                      color: BeeTokens.surfaceHeader(context), size: 52),
                ),
                const SizedBox(height: 20),
                Text(personaName(l10n, persona.type),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _onPrimary(context),
                        fontSize: 30,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text(personaDesc(l10n, persona.type),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _onPrimaryDim(context, 0.85),
                        fontSize: 15,
                        height: 1.5)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _Reveal(
          delayMs: 300,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final r in persona.reasons)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _onPrimary(context).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(personaReasonIcon(r.kind),
                          color: _onPrimary(context), size: 16),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(personaReasonText(l10n, r, hide: hide),
                            style: TextStyle(
                                color: _onPrimary(context),
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 跟去年比
// ---------------------------------------------------------------------------

class AnnualYoYPage extends StatelessWidget {
  final AnnualReportData data;
  const AnnualYoYPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prevIncome = data.previousYearIncome ?? 0;
    final prevExpense = data.previousYearExpense ?? 0;
    final prevNet = prevIncome - prevExpense;

    double? pct(double cur, double prev) =>
        prev.abs() < 1e-9 ? null : (cur - prev) / prev.abs() * 100;
    final incomePct = pct(data.totalIncome, prevIncome);
    final expensePct = pct(data.totalExpense, prevExpense);

    final verdicts = <String>[];
    if (expensePct != null) {
      if (expensePct <= -1) {
        verdicts.add(
            l10n.annualYoYExpenseDown(expensePct.abs().toStringAsFixed(0)));
      } else if (expensePct >= 1) {
        verdicts.add(l10n.annualYoYExpenseUp(expensePct.toStringAsFixed(0)));
      } else {
        verdicts.add(l10n.annualYoYExpenseFlat);
      }
    }
    if (incomePct != null && incomePct >= 1) {
      verdicts.add(l10n.annualYoYIncomeUp(incomePct.toStringAsFixed(0)));
    }

    return _PageFrame(
      title: l10n.annualYoYTitle,
      subtitle: l10n.annualYoYSubtitle('${data.year - 1}'),
      children: [
        _Reveal(
          delayMs: 80,
          child: _YoYRow(
            label: l10n.annualReportTotalIncome,
            year: data.year,
            current: data.totalIncome,
            previous: prevIncome,
            pct: incomePct,
            higherIsBetter: true,
          ),
        ),
        const SizedBox(height: 12),
        _Reveal(
          delayMs: 180,
          child: _YoYRow(
            label: l10n.annualReportTotalExpense,
            year: data.year,
            current: data.totalExpense,
            previous: prevExpense,
            pct: expensePct,
            higherIsBetter: false,
          ),
        ),
        const SizedBox(height: 12),
        _Reveal(
          delayMs: 280,
          child: _YoYRow(
            label: l10n.annualReportNetSavings,
            year: data.year,
            current: data.netSavings,
            previous: prevNet,
            pct: pct(data.netSavings, prevNet),
            higherIsBetter: true,
            signed: true,
          ),
        ),
        if (verdicts.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Reveal(
            delayMs: 380,
            child: _GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < verdicts.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            color: _onPrimary(context), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(verdicts[i],
                              style: TextStyle(
                                  color: _onPrimary(context),
                                  fontSize: 14,
                                  height: 1.4)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _YoYRow extends StatelessWidget {
  final String label;
  final int year;
  final double current;
  final double previous;
  final double? pct;
  final bool higherIsBetter;
  final bool signed;
  const _YoYRow({
    required this.label,
    required this.year,
    required this.current,
    required this.previous,
    required this.pct,
    required this.higherIsBetter,
    this.signed = false,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'zh_TW');
    String money(double v) =>
        '${signed && v > 0 ? '+' : ''}${v < 0 ? '-' : ''}${fmt.format(v.abs())}';
    final p = pct;
    final up = p != null && p > 0;
    final flat = p == null || p.abs() < 0.5;
    final good = up == higherIsBetter;
    final chipColor = flat
        ? BeeTokens.textSecondary(context)
        : (good ? BeeTokens.success(context) : BeeTokens.error(context));
    return _SolidCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: BeeTokens.textSecondary(context), fontSize: 13)),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(money(current),
                      style: TextStyle(
                          color: BeeTokens.textPrimary(context),
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 2),
                Text('${year - 1}  ${money(previous)}',
                    style: TextStyle(
                        color: BeeTokens.textTertiary(context), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: chipColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                    flat
                        ? Icons.drag_handle_rounded
                        : (up
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded),
                    color: chipColor,
                    size: 16),
                if (p != null) ...[
                  const SizedBox(width: 2),
                  Text('${p.abs().toStringAsFixed(p.abs() >= 100 ? 0 : 1)}%',
                      style: TextStyle(
                          color: chipColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 消費習慣(時段分布 + 平日 vs 週末)
// ---------------------------------------------------------------------------

class AnnualHabitsPage extends StatelessWidget {
  final AnnualReportData data;
  const AnnualHabitsPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = [
      l10n.annualHabitsNight,
      l10n.annualHabitsMorning,
      l10n.annualHabitsNoon,
      l10n.annualHabitsAfternoon,
      l10n.annualHabitsEvening,
    ];
    final buckets = data.expenseHourBuckets;
    final maxCount = buckets.fold<int>(0, math.max);
    final peak = buckets.indexOf(maxCount);

    final wdDaily =
        data.weekdayDays > 0 ? data.weekdayExpense / data.weekdayDays : 0.0;
    final weDaily =
        data.weekendDays > 0 ? data.weekendExpense / data.weekendDays : 0.0;
    final maxDaily = math.max(wdDaily, weDaily);
    final ratio = data.weekendWeekdayRatio;
    final fmt = NumberFormat('#,##0', 'zh_TW');

    String weekVerdict() {
      if (ratio == null || (ratio > 0.8 && ratio < 1.25)) {
        return l10n.annualHabitsBalanced;
      }
      return ratio >= 1.25
          ? l10n.annualHabitsWeekendHigh
          : l10n.annualHabitsWeekdayHigh;
    }

    return _PageFrame(
      title: l10n.annualHabitsTitle,
      subtitle: l10n.annualHabitsSubtitle,
      children: [
        _Reveal(
          delayMs: 80,
          child: _GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.annualHabitsHoursTitle,
                    style: TextStyle(
                        color: _onPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: BeeMotion.durationOf(
                      context, const Duration(milliseconds: 700)),
                  curve: BeeMotion.standard,
                  builder: (context, t, _) => SizedBox(
                    height: 150,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < buckets.length; i++)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text('${buckets[i]}',
                                      style: TextStyle(
                                          color: _onPrimaryDim(context),
                                          fontSize: 11)),
                                  const SizedBox(height: 4),
                                  Container(
                                    height: maxCount > 0
                                        ? 90 * (buckets[i] / maxCount) * t
                                        : 0,
                                    decoration: BoxDecoration(
                                      color: i == peak
                                          ? _onPrimary(context)
                                          : _onPrimary(context)
                                              .withValues(alpha: 0.45),
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(6)),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(labels[i],
                                      style: TextStyle(
                                          color: _onPrimaryDim(context),
                                          fontSize: 11)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (maxCount > 0) ...[
                  const SizedBox(height: 14),
                  Text(l10n.annualHabitsPeak(labels[peak]),
                      style: TextStyle(
                          color: _onPrimary(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ),
        if (ratio != null) ...[
          const SizedBox(height: 12),
          _Reveal(
            delayMs: 200,
            child: _GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.annualHabitsWeekTitle,
                      style: TextStyle(
                          color: _onPrimary(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  _DailyBar(
                      label: l10n.annualHabitsWeekday,
                      text: l10n.annualHabitsDailyAvg(fmt.format(wdDaily)),
                      fraction: maxDaily > 0 ? wdDaily / maxDaily : 0,
                      highlight: wdDaily >= weDaily),
                  const SizedBox(height: 12),
                  _DailyBar(
                      label: l10n.annualHabitsWeekend,
                      text: l10n.annualHabitsDailyAvg(fmt.format(weDaily)),
                      fraction: maxDaily > 0 ? weDaily / maxDaily : 0,
                      highlight: weDaily > wdDaily),
                  const SizedBox(height: 14),
                  Text(weekVerdict(),
                      style: TextStyle(
                          color: _onPrimary(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
        if (data.maxConsecutiveDays >= 2) ...[
          const SizedBox(height: 12),
          _Reveal(
            delayMs: 320,
            child: _GlassCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.local_fire_department_rounded,
                      color: _onPrimary(context), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(l10n.annualHabitsStreak,
                        style: TextStyle(
                            color: _onPrimaryDim(context, 0.85), fontSize: 14)),
                  ),
                  Text(l10n.annualHabitsStreakDays(data.maxConsecutiveDays),
                      style: TextStyle(
                          color: _onPrimary(context),
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DailyBar extends StatelessWidget {
  final String label;
  final String text;
  final double fraction;
  final bool highlight;
  const _DailyBar(
      {required this.label,
      required this.text,
      required this.fraction,
      required this.highlight});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label,
              style: TextStyle(color: _onPrimaryDim(context), fontSize: 12)),
          const Spacer(),
          Text(text,
              style: TextStyle(
                  color: _onPrimary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
          duration:
              BeeMotion.durationOf(context, const Duration(milliseconds: 700)),
          curve: BeeMotion.standard,
          builder: (context, v, _) => Stack(
            children: [
              Container(
                height: 14,
                decoration: BoxDecoration(
                  color: _onPrimary(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              FractionallySizedBox(
                widthFactor: v,
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: highlight
                        ? _onPrimary(context)
                        : _onPrimary(context).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
