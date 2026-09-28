import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/investment/markets.dart';
import '../../styles/tokens.dart';
import 'investment_ui.dart';

class SecurityPick {
  final String market;
  final String symbol;
  final String? name;
  final String currency;
  const SecurityPick(
      {required this.market,
      required this.symbol,
      this.name,
      required this.currency});
}

/// 證券搜尋(BeeCount Cloud `/read/securities/search`:台股走官方清單,可以打
/// 中文名稱;其它市場走 Yahoo)。沒登入 Cloud 或搜不到時,第一列永遠是「直接
/// 使用輸入的代號」,不會卡住非 Cloud 使用者。
class SecuritySearchSheet extends ConsumerStatefulWidget {
  final String market;
  final String initialQuery;

  const SecuritySearchSheet(
      {super.key, required this.market, this.initialQuery = ''});

  static Future<SecurityPick?> show(BuildContext context,
      {required String market, String initialQuery = ''}) {
    return showModalBottomSheet<SecurityPick>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BeeTokens.surfaceSheet(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) =>
          SecuritySearchSheet(market: market, initialQuery: initialQuery),
    );
  }

  @override
  ConsumerState<SecuritySearchSheet> createState() =>
      _SecuritySearchSheetState();
}

class _SecuritySearchSheetState extends ConsumerState<SecuritySearchSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  bool _loading = false;
  List<Map<String, dynamic>> _results = const [];
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) _search(widget.initialQuery);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
    setState(() {});
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    final seq = ++_seq;
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    final cloud = await ref.read(beecountCloudProviderInstance.future);
    if (cloud == null) return;
    setState(() => _loading = true);
    try {
      // 台股兩個市場一起搜(使用者常分不清上市/上櫃);其它市場只搜指定市場。
      final isTaiwan = widget.market == 'TW' || widget.market == 'TWO';
      final rows = await cloud.searchSecurities(
          query: q, market: isTaiwan ? null : widget.market);
      if (!mounted || seq != _seq) return;
      final filtered = isTaiwan
          ? [
              ...rows.where((r) => r['market'] == 'TW' || r['market'] == 'TWO'),
              ...rows.where((r) => r['market'] != 'TW' && r['market'] != 'TWO'),
            ]
          : rows;
      setState(() {
        _results = filtered;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = const [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final typed = _ctrl.text.trim();
    final market = stockMarketByCode(widget.market);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  onSubmitted: _search,
                  style: TextStyle(color: BeeTokens.textPrimary(context)),
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search,
                        color: BeeTokens.iconSecondary(context)),
                    hintText: l10n.stockSymbolSearchHint,
                    hintStyle:
                        TextStyle(color: BeeTokens.textTertiary(context)),
                    filled: true,
                    fillColor: BeeTokens.surfaceInput(context),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: ListView(
                  children: [
                    if (typed.isNotEmpty)
                      ListTile(
                        leading: Icon(Icons.edit_outlined,
                            color: BeeTokens.iconSecondary(context)),
                        title: Text(
                          typed.toUpperCase(),
                          style: TextStyle(
                              color: BeeTokens.textPrimary(context),
                              fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          stockMarketLabel(l10n, widget.market),
                          style: TextStyle(
                              color: BeeTokens.textSecondary(context)),
                        ),
                        onTap: () => Navigator.of(context).pop(SecurityPick(
                          market: widget.market,
                          symbol: typed.toUpperCase(),
                          currency: market?.currency ?? 'USD',
                        )),
                      ),
                    for (final r in _results)
                      ListTile(
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: BeeTokens.surfaceChip(context),
                          child: Text(
                            (r['market'] as String? ?? '').substring(
                                0,
                                (r['market'] as String? ?? '')
                                    .length
                                    .clamp(0, 2)),
                            style: TextStyle(
                                fontSize: 11,
                                color: BeeTokens.textSecondary(context)),
                          ),
                        ),
                        title: Text(
                          '${r['symbol']}  ${r['name'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: BeeTokens.textPrimary(context)),
                        ),
                        subtitle: Text(
                          '${stockMarketLabel(l10n, r['market'] as String? ?? '')} · ${r['currency'] ?? ''}',
                          style: TextStyle(
                              color: BeeTokens.textSecondary(context)),
                        ),
                        onTap: () => Navigator.of(context).pop(SecurityPick(
                          market: (r['market'] as String).toUpperCase(),
                          symbol: (r['symbol'] as String).toUpperCase(),
                          name: r['name'] as String?,
                          currency: (r['currency'] as String?) ??
                              market?.currency ??
                              'USD',
                        )),
                      ),
                    if (!_loading && typed.isNotEmpty && _results.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          l10n.stockSearchNoResult,
                          style:
                              TextStyle(color: BeeTokens.textTertiary(context)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
