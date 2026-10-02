import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/investment/markets.dart';
import '../../services/investment/opening_holdings_import.dart';
import '../../services/investment/stock_trade_types.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';
import 'investment_ui.dart';

/// 一次輸入/貼上多檔期初持股(docs/changes/2026-09-30-dca-sync-opening-holdings.md)。
///
/// 開始用 BeeCount 前就買過很多次的股票,不用逐筆補記:照券商「庫存」頁每一
/// 檔填股數 + 平均成本(或總成本),每檔存成一筆 `opening` 明細(沒有金流)。
/// 也可以從 Excel/Google 試算表複製「代號 股數 成本」貼上,解析規則見
/// [parseOpeningHoldingsText]。入口:股票交易頁選「期初持股」→「一次新增多檔
/// 期初持股」。
class OpeningHoldingsBatchPage extends ConsumerStatefulWidget {
  final Account account;
  final String? initialMarket;

  const OpeningHoldingsBatchPage(
      {super.key, required this.account, this.initialMarket});

  @override
  ConsumerState<OpeningHoldingsBatchPage> createState() =>
      _OpeningHoldingsBatchPageState();
}

class _HoldingRow {
  final symbol = TextEditingController();
  final name = TextEditingController();
  final shares = TextEditingController();
  final cost = TextEditingController();
  final symbolFocus = FocusNode();
  Timer? debounce;
  // 上一次自動帶入的名稱:代號改了、名稱還是舊的自動值才覆蓋。
  String? autoName;

  bool get isBlank =>
      symbol.text.trim().isEmpty &&
      name.text.trim().isEmpty &&
      shares.text.trim().isEmpty &&
      cost.text.trim().isEmpty;

  double? get sharesValue => double.tryParse(shares.text.trim());
  double? get costValue => double.tryParse(cost.text.trim());

  void dispose() {
    debounce?.cancel();
    for (final c in [symbol, name, shares, cost]) {
      c.dispose();
    }
    symbolFocus.dispose();
  }
}

class _OpeningHoldingsBatchPageState
    extends ConsumerState<OpeningHoldingsBatchPage> {
  late String _market;
  late DateTime _date;
  bool _costIsTotal = false;
  bool _saving = false;
  final List<_HoldingRow> _rows = [];

  String get _currency =>
      (stockMarketByCode(_market)?.currency ?? widget.account.currency)
          .toUpperCase();

  static DateTime _noon(DateTime d) => DateTime(d.year, d.month, d.day, 12);

  @override
  void initState() {
    super.initState();
    _market = widget.initialMarket ?? _defaultMarketFor(widget.account.currency);
    _date = _noon(DateTime.now());
    _addRow();
  }

  static String _defaultMarketFor(String currency) {
    for (final m in kStockMarkets) {
      if (m.currency == currency.toUpperCase()) return m.code;
    }
    return 'TW';
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  _HoldingRow _addRow() {
    final row = _HoldingRow();
    row.symbolFocus.addListener(() {
      if (!row.symbolFocus.hasFocus) _lookupRow(row);
    });
    _rows.add(row);
    return row;
  }

  void _removeRow(_HoldingRow row) {
    setState(() {
      _rows.remove(row);
      row.dispose();
      if (_rows.isEmpty) _addRow();
    });
  }

  void _onSymbolChanged(_HoldingRow row) {
    row.debounce?.cancel();
    row.debounce =
        Timer(const Duration(milliseconds: 700), () => _lookupRow(row));
    setState(() {});
  }

  void _applyName(_HoldingRow row, String? name) {
    final current = row.name.text.trim();
    if (current.isNotEmpty && current != row.autoName) return;
    final n = name?.trim() ?? '';
    row.name.text = n;
    row.autoName = n.isEmpty ? null : n;
  }

  /// 單列:代號打完(停頓或離開欄位)查報價帶名稱,同 [StockTradeEditorPage]。
  Future<void> _lookupRow(_HoldingRow row) async {
    row.debounce?.cancel();
    final symbol = row.symbol.text.trim().toUpperCase();
    if (symbol.isEmpty || !_rows.contains(row)) return;
    final market = _market;
    final quote =
        await ref.read(quoteRefreshProvider.notifier).quoteFor(market, symbol);
    if (!mounted ||
        !_rows.contains(row) ||
        market != _market ||
        symbol != row.symbol.text.trim().toUpperCase()) return;
    setState(() => _applyName(row, quote?.name));
  }

  /// 多列(貼上/換市場後):一次抓完報價再帶名稱。報價 refresh 正在跑時會
  /// 直接略過,所以不能每列各自呼叫 [QuoteRefreshNotifier.quoteFor]。
  Future<void> _lookupAll() async {
    final market = _market;
    final keys = {
      for (final r in _rows)
        if (r.symbol.text.trim().isNotEmpty)
          securityKey(market, r.symbol.text.trim()),
    }.toList();
    if (keys.isEmpty) return;
    await ref
        .read(quoteRefreshProvider.notifier)
        .refresh(force: true, extraKeys: keys);
    final quotes = await ref.read(repositoryProvider).getSecurityQuotes();
    if (!mounted || market != _market) return;
    final byKey = {for (final q in quotes) securityKey(q.market, q.symbol): q};
    setState(() {
      for (final r in _rows) {
        final symbol = r.symbol.text.trim();
        if (symbol.isEmpty) continue;
        final q = byKey[securityKey(market, symbol)];
        if (q?.name != null && q!.name!.trim().isNotEmpty) {
          _applyName(r, q.name);
        }
      }
    });
  }

  Future<void> _paste() async {
    final l10n = AppLocalizations.of(context);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final result = parseOpeningHoldingsText(data?.text ?? '');
    if (!mounted) return;
    if (result.lines.isEmpty) {
      showToast(context, l10n.stockOpeningPasteEmpty);
      return;
    }
    setState(() {
      // 只有一列空白列(剛打開頁面)時直接換掉。
      final blanks = _rows.where((r) => r.isBlank).toList();
      for (final r in blanks) {
        _rows.remove(r);
        r.dispose();
      }
      for (final line in result.lines) {
        final row = _addRow();
        row.symbol.text = line.symbol;
        if (line.name != null) row.name.text = line.name!;
        row.shares.text = _num(line.shares);
        row.cost.text = _num(line.cost);
      }
    });
    showToast(context, l10n.stockOpeningPasted(result.lines.length, result.skipped));
    _lookupAll();
  }

  Future<void> _pickMarket() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: BeeTokens.surfaceSheet(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final m in kStockMarkets)
              ListTile(
                title: Text(stockMarketLabel(l10n, m.code),
                    style: TextStyle(color: BeeTokens.textPrimary(ctx))),
                subtitle: Text(m.currency,
                    style: TextStyle(color: BeeTokens.textSecondary(ctx))),
                trailing: m.code == _market
                    ? Icon(Icons.check, color: BeeTokens.primary(ctx))
                    : null,
                onTap: () => Navigator.of(ctx).pop(m.code),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == _market) return;
    setState(() => _market = picked);
    _lookupAll();
  }

  Future<void> _pickDate() async {
    final picked = await showAppDatePicker(
      context,
      initial: _date,
      minDate: DateTime(1990),
      maxDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = _noon(picked));
  }

  double _rowTotal(_HoldingRow row) {
    final shares = row.sharesValue;
    final cost = row.costValue;
    if (shares == null || cost == null || shares <= 0 || cost <= 0) return 0;
    return openingTotalCost(
        shares: shares,
        cost: cost,
        costIsTotal: _costIsTotal,
        currency: _currency);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final filled = _rows.where((r) => !r.isBlank).toList();
    if (filled.isEmpty) {
      showToast(context, l10n.stockOpeningNothing);
      return;
    }
    for (var i = 0; i < filled.length; i++) {
      final r = filled[i];
      final shares = r.sharesValue;
      final cost = r.costValue;
      if (r.symbol.text.trim().isEmpty ||
          shares == null ||
          shares <= 0 ||
          cost == null ||
          cost <= 0) {
        showToast(context, l10n.stockOpeningRowInvalid(_rows.indexOf(r) + 1));
        return;
      }
    }

    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    var saved = 0;
    try {
      final isFirstTrade =
          (await repo.getStockTradesForAccount(widget.account.id)).isEmpty;
      final keys = <String>[];
      for (final r in filled) {
        final symbol = r.symbol.text.trim().toUpperCase();
        final shares = r.sharesValue!;
        final t = openingTradeFromCost(
            shares: shares,
            cost: r.costValue!,
            costIsTotal: _costIsTotal,
            currency: _currency);
        final name = r.name.text.trim();
        await repo.createStockTrade(
          ledgerId: ref.read(currentLedgerIdProvider),
          accountId: widget.account.id,
          tradeType: kStockTradeOpening,
          market: _market,
          symbol: symbol,
          securityName: name.isEmpty ? null : name,
          shares: shares,
          price: t.price,
          fee: t.fee,
          currency: _currency,
          tradeDate: _date,
        );
        saved++;
        keys.add(securityKey(_market, symbol));
      }
      ref.read(statsRefreshProvider.notifier).state++;
      ref
          .read(quoteRefreshProvider.notifier)
          .refresh(force: true, extraKeys: keys);
      if (!mounted) return;
      showToast(context, l10n.stockOpeningSaved(saved));
      if (isFirstTrade && widget.account.includeInTotal) {
        final yes = await AppDialog.confirm<bool>(
          context,
          title: l10n.stockExcludeFromTotalTitle,
          message: l10n.stockExcludeFromTotalDesc,
          okLabel: l10n.stockExcludeFromTotalYes,
          cancelLabel: l10n.stockExcludeFromTotalNo,
        );
        if (yes == true) {
          await repo.updateAccount(widget.account.id, includeInTotal: false);
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      // 前面已存的幾檔保留,把它們從清單拿掉免得重按儲存又存一次。
      setState(() {
        final done = filled.take(saved).toList();
        for (final r in done) {
          _rows.remove(r);
          r.dispose();
        }
        if (_rows.isEmpty) _addRow();
      });
      showToast(context, '${l10n.commonError}: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gap = SizedBox(height: 12.0.scaled(context, ref));
    final primary = ref.watch(primaryColorProvider);
    final held = <String, double>{
      for (final h in ref.watch(accountHoldingsProvider(widget.account.id)) ??
          const [])
        if (h.holding.shares > 0)
          securityKey(h.holding.market, h.holding.symbol): h.holding.shares,
    };
    final filled = _rows.where((r) => _rowTotal(r) > 0).toList();
    final grandTotal = filled.fold<double>(0, (s, r) => s + _rowTotal(r));

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.stockOpeningBatchTitle,
            subtitle: widget.account.name,
            showBack: true,
            compact: true,
            actions: [
              TextButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  l10n.commonSave,
                  style: TextStyle(
                      color: BeeTokens.textPrimary(context),
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                  horizontal: 12.0.scaled(context, ref),
                  vertical: 8.0.scaled(context, ref)),
              children: [
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.stockOpeningBatchIntro,
                        style: TextStyle(
                            fontSize: 12,
                            color: BeeTokens.textSecondary(context)),
                      ),
                      const SizedBox(height: 4),
                      _row(context,
                          label: l10n.stockMarket,
                          value:
                              '${stockMarketLabel(l10n, _market)} · $_currency',
                          onTap: _pickMarket),
                      _divider(context),
                      _row(context,
                          label: l10n.stockOpeningAsOfDate,
                          value: formatTradeDate(_date),
                          onTap: _pickDate),
                      _divider(context),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Text(l10n.stockOpeningCostMode,
                                style: TextStyle(
                                    color: BeeTokens.textSecondary(context))),
                            const Spacer(),
                            for (final total in [false, true]) ...[
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: Text(total
                                    ? l10n.stockOpeningCostTotal
                                    : l10n.stockAvgCost),
                                selected: _costIsTotal == total,
                                selectedColor: primary.withValues(alpha: 0.15),
                                backgroundColor: BeeTokens.surfaceChip(context),
                                labelStyle: TextStyle(
                                  color: _costIsTotal == total
                                      ? primary
                                      : BeeTokens.textSecondary(context),
                                ),
                                onSelected: (_) =>
                                    setState(() => _costIsTotal = total),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                gap,
                for (var i = 0; i < _rows.length; i++) ...[
                  _holdingCard(context, l10n, i, _rows[i], held),
                  SizedBox(height: 8.0.scaled(context, ref)),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(_addRow),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(l10n.stockOpeningAddRow,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _paste,
                        icon: const Icon(Icons.content_paste, size: 18),
                        label: Text(l10n.stockOpeningPaste,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.stockOpeningPasteHint,
                  style: TextStyle(
                      fontSize: 12, color: BeeTokens.textTertiary(context)),
                ),
                if (filled.isNotEmpty) ...[
                  gap,
                  Text(
                    l10n.stockOpeningSummary(filled.length,
                        formatStockMoney(grandTotal, _currency)),
                    style: TextStyle(
                        color: BeeTokens.textPrimary(context),
                        fontWeight: FontWeight.w600),
                  ),
                ],
                SizedBox(height: 24.0.scaled(context, ref)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _holdingCard(BuildContext context, AppLocalizations l10n, int index,
      _HoldingRow row, Map<String, double> held) {
    final total = _rowTotal(row);
    final symbol = row.symbol.text.trim();
    final heldShares =
        symbol.isEmpty ? null : held[securityKey(_market, symbol)];
    final hints = <String>[
      if (total > 0)
        l10n.stockOpeningRowTotal(formatStockMoney(total, _currency)),
      if (heldShares != null) l10n.stockOpeningRowHeld(formatShares(heldShares)),
    ];
    return SectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _field(
                  context,
                  controller: row.symbol,
                  label: '${index + 1}. ${l10n.stockSymbol}',
                  focusNode: row.symbolFocus,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => _onSymbolChanged(row),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: _field(context,
                    controller: row.name, label: l10n.stockSecurityName),
              ),
              IconButton(
                tooltip: l10n.commonDelete,
                icon: Icon(Icons.close,
                    size: 18, color: BeeTokens.iconTertiary(context)),
                onPressed: () => _removeRow(row),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _field(context,
                    controller: row.shares,
                    label: l10n.stockShares,
                    numeric: true,
                    onChanged: (_) => setState(() {})),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _field(context,
                    controller: row.cost,
                    label:
                        '${_costIsTotal ? l10n.stockOpeningCostTotal : l10n.stockAvgCost} ($_currency)',
                    numeric: true,
                    onChanged: (_) => setState(() {})),
              ),
            ],
          ),
          if (hints.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                hints.join(' · '),
                style: TextStyle(
                    fontSize: 12, color: BeeTokens.textTertiary(context)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) =>
      Divider(height: 1, color: BeeTokens.divider(context));

  Widget _row(BuildContext context,
      {required String label, required String value, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(color: BeeTokens.textSecondary(context))),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: BeeTokens.textPrimary(context),
                    fontWeight: FontWeight.w500),
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right,
                  size: 18, color: BeeTokens.iconTertiary(context)),
          ],
        ),
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    bool numeric = false,
    TextCapitalization textCapitalization = TextCapitalization.none,
    FocusNode? focusNode,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      textCapitalization: textCapitalization,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,6}'))]
          : null,
      style: TextStyle(fontSize: 16, color: BeeTokens.textPrimary(context)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: BeeTokens.textSecondary(context)),
        border: InputBorder.none,
      ),
    );
  }
}
