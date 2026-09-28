import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../models/investment_settings.dart';
import '../../providers.dart';
import '../../services/investment/markets.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/account_card_picker.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';
import 'investment_ui.dart';

/// 投資理財帳戶的費用設定(使用者確認的需求:手續費不寫死,由使用者自訂)。
///
/// 欄位留空 = 沿用市場預設值([InvestmentSettings.defaultsFor]),預設值顯示在
/// 欄位下方。比率類欄位畫面上用百分比(0.1425),存的是小數(0.001425),
/// 跟 Cloud 端 `investmentSettings` 同形。
class InvestmentSettingsPage extends ConsumerStatefulWidget {
  final Account account;

  const InvestmentSettingsPage({super.key, required this.account});

  @override
  ConsumerState<InvestmentSettingsPage> createState() =>
      _InvestmentSettingsPageState();
}

class _InvestmentSettingsPageState
    extends ConsumerState<InvestmentSettingsPage> {
  late InvestmentSettings _initial;
  late String? _market;
  late bool _reinvest;
  late bool _pnlAfterSellCosts;
  Account? _settlement;
  bool _saving = false;

  final _feeRate = TextEditingController();
  final _feeDiscount = TextEditingController();
  final _feeMin = TextEditingController();
  final _sellTax = TextEditingController();
  final _etfSellTax = TextEditingController();
  final _bondEtfSellTax = TextEditingController();
  final _divFeeFixed = TextEditingController();
  final _divFeeRate = TextEditingController();
  final _withholding = TextEditingController();
  final _nhiRate = TextEditingController();
  final _nhiThreshold = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initial = InvestmentSettings.parse(widget.account.investmentSettingsJson);
    _market = _initial.market;
    _reinvest = _initial.reinvestDividends ?? false;
    _pnlAfterSellCosts = _initial.pnlAfterSellCosts ?? true;
    _setPct(_feeRate, _initial.feeRate);
    _setPct(_feeDiscount, _initial.feeDiscount);
    _setNum(_feeMin, _initial.feeMin);
    _setPct(_sellTax, _initial.sellTaxRate);
    _setPct(_etfSellTax, _initial.etfSellTaxRate);
    _setPct(_bondEtfSellTax, _initial.bondEtfSellTaxRate);
    _setNum(_divFeeFixed, _initial.dividendFeeFixed);
    _setPct(_divFeeRate, _initial.dividendFeeRate);
    _setPct(_withholding, _initial.dividendWithholdingRate);
    _setPct(_nhiRate, _initial.nhiSupplementRate);
    _setNum(_nhiThreshold, _initial.nhiThreshold);
    _loadSettlement();
  }

  Future<void> _loadSettlement() async {
    final id = _initial.settlementAccountId;
    if (id == null) return;
    final acc = await ref.read(repositoryProvider).getAccountBySyncId(id);
    if (mounted) setState(() => _settlement = acc);
  }

  @override
  void dispose() {
    for (final c in [
      _feeRate,
      _feeDiscount,
      _feeMin,
      _sellTax,
      _etfSellTax,
      _bondEtfSellTax,
      _divFeeFixed,
      _divFeeRate,
      _withholding,
      _nhiRate,
      _nhiThreshold
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _trim(double v) {
    var t = v.toStringAsFixed(6);
    t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return t;
  }

  static void _setPct(TextEditingController c, double? v) =>
      c.text = v == null ? '' : _trim(v * 100);
  static void _setNum(TextEditingController c, double? v) =>
      c.text = v == null ? '' : _trim(v);
  static double? _pct(TextEditingController c) {
    final v = double.tryParse(c.text.trim());
    return v == null ? null : v / 100;
  }

  static double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim());

  String get _effectiveMarket =>
      _market ??
      (() {
        for (final m in kStockMarkets) {
          if (m.currency == widget.account.currency.toUpperCase())
            return m.code;
        }
        return 'TW';
      })();

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
                trailing: m.code == _effectiveMarket
                    ? Icon(Icons.check, color: BeeTokens.primary(ctx))
                    : null,
                onTap: () => Navigator.of(ctx).pop(m.code),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _market = picked);
  }

  Future<void> _pickSettlement() async {
    final result = await AccountCardPicker.show(
      context,
      ledgerId: ref.read(currentLedgerIdProvider),
      selectedAccountId: _settlement?.id,
      excludeAccountId: widget.account.id,
      allowAllCurrencies: true,
    );
    if (result?.accountId == null) return;
    final acc =
        await ref.read(repositoryProvider).getAccount(result!.accountId!);
    if (mounted) setState(() => _settlement = acc);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final settings = InvestmentSettings(
      market: _market,
      feeRate: _pct(_feeRate),
      feeDiscount: _pct(_feeDiscount),
      feeMin: _num(_feeMin),
      sellTaxRate: _pct(_sellTax),
      etfSellTaxRate: _pct(_etfSellTax),
      bondEtfSellTaxRate: _pct(_bondEtfSellTax),
      // 預設就是開,關掉才存(同 reinvestDividends 只存非預設值)。
      pnlAfterSellCosts: _pnlAfterSellCosts ? null : false,
      dividendFeeFixed: _num(_divFeeFixed),
      dividendFeeRate: _pct(_divFeeRate),
      dividendWithholdingRate: _pct(_withholding),
      nhiSupplementRate: _pct(_nhiRate),
      nhiThreshold: _num(_nhiThreshold),
      reinvestDividends: _reinvest ? true : null,
      settlementAccountId: _settlement?.syncId,
    );
    setState(() => _saving = true);
    try {
      await ref
          .read(repositoryProvider)
          .updateAccountInvestmentSettings(widget.account.id, settings);
      if (!mounted) return;
      showToast(context, l10n.stockFeeSettingsSaved);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showToast(context, '${l10n.commonError}: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final d = InvestmentSettings.defaultsFor(_effectiveMarket);
    final isTw = _effectiveMarket == 'TW' || _effectiveMarket == 'TWO';
    String pct(double? v) => v == null ? '—' : '${_trim(v * 100)}%';
    String num(double? v) => v == null ? '—' : _trim(v);
    final gap = SizedBox(height: 12.0.scaled(context, ref));

    Widget field(TextEditingController c, String label, String defaultText) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,6}'))
            ],
            style: TextStyle(color: BeeTokens.textPrimary(context)),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(color: BeeTokens.textSecondary(context)),
              helperText: l10n.stockMarketDefault(defaultText),
              helperStyle: TextStyle(color: BeeTokens.textTertiary(context)),
              border: InputBorder.none,
            ),
          ),
        );

    Widget tapRow(String label, String value, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Text(label,
                    style: TextStyle(color: BeeTokens.textSecondary(context))),
                const Spacer(),
                Text(value,
                    style: TextStyle(
                        color: BeeTokens.textPrimary(context),
                        fontWeight: FontWeight.w500)),
                Icon(Icons.chevron_right,
                    size: 18, color: BeeTokens.iconTertiary(context)),
              ],
            ),
          ),
        );

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.stockFeeSettings,
            subtitle: widget.account.name,
            showBack: true,
            compact: true,
            actions: [
              TextButton(
                onPressed: _saving ? null : _save,
                child: Text(l10n.commonSave,
                    style: TextStyle(
                        color: BeeTokens.textPrimary(context),
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                  horizontal: 12.0.scaled(context, ref),
                  vertical: 8.0.scaled(context, ref)),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(l10n.stockFeeSettingsDesc,
                      style: TextStyle(
                          fontSize: 13,
                          color: BeeTokens.textSecondary(context))),
                ),
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      tapRow(
                          l10n.stockDefaultMarket,
                          stockMarketLabel(l10n, _effectiveMarket),
                          _pickMarket),
                      Divider(height: 1, color: BeeTokens.divider(context)),
                      tapRow(l10n.stockSettlementAccount,
                          _settlement?.name ?? '—', _pickSettlement),
                    ],
                  ),
                ),
                gap,
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      field(_feeRate, l10n.stockFeeRate, pct(d.feeRate)),
                      field(_feeDiscount, l10n.stockFeeDiscount,
                          pct(d.feeDiscount)),
                      field(_feeMin, l10n.stockFeeMin, num(d.feeMin)),
                      field(
                          _sellTax,
                          isTw
                              ? l10n.stockSellTaxRateStock
                              : l10n.stockSellTaxRate,
                          pct(d.sellTaxRate)),
                      // 台股證交稅依標的類型不同(普通股 0.3%、ETF 0.1%、債券
                      // ETF 停徵),依代號自動判斷,見 securityKindOf。
                      if (isTw) ...[
                        field(_etfSellTax, l10n.stockEtfSellTaxRate,
                            pct(d.etfSellTaxRate)),
                        field(_bondEtfSellTax, l10n.stockBondEtfSellTaxRate,
                            pct(d.bondEtfSellTaxRate)),
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 8),
                          child: Text(l10n.stockSellTaxKindHint,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: BeeTokens.textTertiary(context))),
                        ),
                      ],
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _pnlAfterSellCosts,
                        onChanged: (v) =>
                            setState(() => _pnlAfterSellCosts = v),
                        title: Text(l10n.stockPnlAfterSellCosts,
                            style: TextStyle(
                                color: BeeTokens.textPrimary(context))),
                        subtitle: Text(l10n.stockPnlAfterSellCostsDesc,
                            style: TextStyle(
                                fontSize: 12,
                                color: BeeTokens.textTertiary(context))),
                      ),
                    ],
                  ),
                ),
                gap,
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(l10n.stockDividendSection,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: BeeTokens.textPrimary(context))),
                ),
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      field(_divFeeFixed, l10n.stockDividendFeeFixed,
                          num(d.dividendFeeFixed)),
                      field(_divFeeRate, l10n.stockDividendFeeRate,
                          pct(d.dividendFeeRate)),
                      field(_withholding, l10n.stockDividendWithholding,
                          pct(d.dividendWithholdingRate)),
                      field(_nhiRate, l10n.stockNhiRate,
                          pct(d.nhiSupplementRate)),
                      field(_nhiThreshold, l10n.stockNhiThreshold,
                          num(d.nhiThreshold)),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _reinvest,
                        onChanged: (v) => setState(() => _reinvest = v),
                        title: Text(l10n.stockReinvestDividends,
                            style: TextStyle(
                                color: BeeTokens.textPrimary(context))),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24.0.scaled(context, ref)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
