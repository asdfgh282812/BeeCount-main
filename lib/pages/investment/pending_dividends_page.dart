import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../models/investment_settings.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/account_card_picker.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';
import 'investment_ui.dart';

/// 待確認股利(股票持股 Phase 2,docs/changes/2026-09-28-stock-dividends.md)。
///
/// BeeCount Cloud 在除息日後依「除息日前一天」的持股替每個投資理財帳戶建一筆
/// 待確認股利並發通知;這裡讓使用者確認實收金額(或選擇再投入)——確認由
/// server 建 income 交易 + 明細,App 之後 sync pull 拿回(使用者確認的決策:
/// 股利入帳統一由 server 處理,App/Web 行為一致)。Web 對應
/// `PendingDividendsPanel.tsx`。

/// 帳戶頁投資市值卡、持股分頁上方的「N 筆股利待確認」入口。沒有待確認時
/// 不顯示。[accountId] 給了就只算這個投資理財帳戶的。
class PendingDividendsBanner extends ConsumerWidget {
  final int? accountId;
  final bool inCard;

  const PendingDividendsBanner(
      {super.key, this.accountId, this.inCard = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = accountId == null
        ? ref.watch(pendingDividendsProvider.select((s) => s.items))
        : ref.watch(accountPendingDividendsProvider(accountId!));
    if (items.isEmpty) return const SizedBox.shrink();
    final primary = ref.watch(primaryColorProvider);
    final row = InkWell(
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PendingDividendsPage())),
      child: Padding(
        padding: EdgeInsets.symmetric(
            vertical: inCard ? 6 : 12, horizontal: inCard ? 0 : 4),
        child: Row(
          children: [
            Icon(Icons.payments_outlined, size: 18, color: primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.stockPendingDividendsBanner(items.length),
                style: TextStyle(color: primary, fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: primary),
          ],
        ),
      ),
    );
    if (inCard) return row;
    return SectionCard(
        margin: EdgeInsets.only(bottom: 12.0.scaled(context, ref)), child: row);
  }
}

class PendingDividendsPage extends ConsumerStatefulWidget {
  const PendingDividendsPage({super.key});

  @override
  ConsumerState<PendingDividendsPage> createState() =>
      _PendingDividendsPageState();
}

class _PendingDividendsPageState extends ConsumerState<PendingDividendsPage> {
  List<PendingDividend>? _dismissed;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        ref.read(pendingDividendsProvider.notifier).refresh(force: true);
    });
  }

  Future<void> _loadDismissed() async {
    try {
      final rows =
          await ref.read(pendingDividendsProvider.notifier).fetchDismissed();
      if (mounted) setState(() => _dismissed = rows);
    } catch (e) {
      if (mounted)
        showToast(context, '${AppLocalizations.of(context).commonError}: $e');
    }
  }

  Future<void> _setDismissed(PendingDividend item, bool dismissed) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busyId = item.id);
    try {
      await ref
          .read(pendingDividendsProvider.notifier)
          .setDismissed(item, dismissed);
      if (_dismissed != null) await _loadDismissed();
      if (mounted && dismissed)
        showToast(context, l10n.stockDividendDismissedToast);
    } catch (e) {
      if (mounted) showToast(context, '${l10n.commonError}: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _confirm(PendingDividend item) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ConfirmDividendPage(item: item)),
    );
    if (done == true && mounted) {
      showToast(
          context, AppLocalizations.of(context).stockDividendConfirmedToast);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(pendingDividendsProvider);
    final items = state.items;
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
              title: l10n.stockPendingDividendsTitle,
              showBack: true,
              compact: true),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref
                  .read(pendingDividendsProvider.notifier)
                  .refresh(force: true),
              child: ListView(
                padding: EdgeInsets.symmetric(
                    horizontal: 12.0.scaled(context, ref),
                    vertical: 8.0.scaled(context, ref)),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                    child: Text(
                      l10n.stockPendingDividendsDesc,
                      style: TextStyle(
                          fontSize: 12, color: BeeTokens.textTertiary(context)),
                    ),
                  ),
                  if (items.isEmpty && !state.loading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Icon(Icons.payments_outlined,
                              size: 48, color: BeeTokens.iconTertiary(context)),
                          const SizedBox(height: 12),
                          Text(l10n.stockPendingDividendsEmpty,
                              style: TextStyle(
                                  color: BeeTokens.textSecondary(context))),
                        ],
                      ),
                    ),
                  for (final item in items)
                    _DividendCard(
                      item: item,
                      busy: _busyId == item.id,
                      actions: [
                        TextButton(
                          onPressed: _busyId == item.id
                              ? null
                              : () => _setDismissed(item, true),
                          child: Text(l10n.stockDividendDismiss,
                              style: TextStyle(
                                  color: BeeTokens.textSecondary(context))),
                        ),
                        const SizedBox(width: 4),
                        FilledButton(
                          onPressed:
                              _busyId == item.id ? null : () => _confirm(item),
                          child: Text(l10n.stockDividendConfirm),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => _dismissed == null
                          ? _loadDismissed()
                          : setState(() => _dismissed = null),
                      child: Text(
                        _dismissed == null
                            ? l10n.stockDividendShowDismissed
                            : l10n.stockDividendHideDismissed,
                        style:
                            TextStyle(color: BeeTokens.textSecondary(context)),
                      ),
                    ),
                  ),
                  if (_dismissed != null) ...[
                    if (_dismissed!.isEmpty)
                      Center(
                          child: Text('—',
                              style: TextStyle(
                                  color: BeeTokens.textTertiary(context)))),
                    for (final item in _dismissed!)
                      Opacity(
                        opacity: 0.7,
                        child: _DividendCard(
                          item: item,
                          busy: _busyId == item.id,
                          actions: [
                            TextButton(
                              onPressed: _busyId == item.id
                                  ? null
                                  : () => _setDismissed(item, false),
                              child: Text(l10n.stockDividendRestore),
                            ),
                          ],
                        ),
                      ),
                  ],
                  SizedBox(height: 24.0.scaled(context, ref)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DividendCard extends ConsumerWidget {
  final PendingDividend item;
  final bool busy;
  final List<Widget> actions;

  const _DividendCard(
      {required this.item, required this.busy, required this.actions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    final details = [
      l10n.stockDividendExDate(formatTradeDate(item.exDate)),
      if (item.payDate != null)
        l10n.stockDividendPayDate(formatTradeDate(item.payDate!)),
      l10n.stockDividendRecordShares(formatShares(item.shares)),
      if (item.cashPerShare > 0)
        l10n.stockDividendPerShareValue(formatPrice(item.cashPerShare)),
      if (item.estStockShares > 0)
        l10n.stockDividendStockShares(formatShares(item.estStockShares)),
    ];
    return SectionCard(
      margin: EdgeInsets.only(bottom: 10.0.scaled(context, ref)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: item.symbol,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: BeeTokens.textPrimary(context)),
                    ),
                    if ((item.securityName ?? '').isNotEmpty)
                      TextSpan(
                        text: '  ${item.securityName}',
                        style:
                            TextStyle(color: BeeTokens.textSecondary(context)),
                      ),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (item.estNet > 0)
                Text(
                  hide ? '****' : formatStockMoney(item.estNet, item.currency),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: BeeTokens.incomeColor(context, ref),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if ((item.accountName ?? '').isNotEmpty) item.accountName!,
              ...details
            ].join(' · '),
            style: TextStyle(
                fontSize: 12, color: BeeTokens.textSecondary(context)),
          ),
          if (item.estNet > 0)
            Text(
              l10n.stockDividendEstimateLine(
                hide ? '****' : formatStockMoney(item.estGross, item.currency),
                hide
                    ? '****'
                    : formatStockMoney(
                        item.estFee + item.estTax, item.currency),
              ),
              style: TextStyle(
                  fontSize: 12, color: BeeTokens.textTertiary(context)),
            ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (busy)
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ...actions,
            ],
          ),
        ],
      ),
    );
  }
}

/// 確認一筆待確認股利:現金入帳(選入帳帳戶、可改手續費/稅)或再投入(填買進
/// 價格/股數),有配股時另外確認配股股數。送出後由 server 建交易。
class ConfirmDividendPage extends ConsumerStatefulWidget {
  final PendingDividend item;

  const ConfirmDividendPage({super.key, required this.item});

  @override
  ConsumerState<ConfirmDividendPage> createState() =>
      _ConfirmDividendPageState();
}

class _ConfirmDividendPageState extends ConsumerState<ConfirmDividendPage> {
  late final _perShareCtrl =
      TextEditingController(text: _num(widget.item.cashPerShare));
  late final _feeCtrl = TextEditingController(text: _num(widget.item.estFee));
  late final _taxCtrl = TextEditingController(text: _num(widget.item.estTax));
  final _receivedCtrl = TextEditingController();
  late final _reinvestPriceCtrl = TextEditingController(
      text:
          widget.item.quotePrice == null ? '' : _num(widget.item.quotePrice!));
  final _reinvestSharesCtrl = TextEditingController();
  final _reinvestFeeCtrl = TextEditingController();
  late final _stockSharesCtrl =
      TextEditingController(text: _num(widget.item.estStockShares));
  final _noteCtrl = TextEditingController();

  late bool _reinvest = widget.item.reinvestDefault;
  late DateTime _date = _noon(widget.item.payDate ?? widget.item.exDate);
  Account? _receiving;
  Account? _investment;
  bool _reinvestSharesEdited = false;
  bool _saving = false;

  PendingDividend get _item => widget.item;
  bool get _hasCash => _item.cashPerShare > 0;
  bool get _hasStock => _item.stockPerShare > 0;

  static DateTime _noon(DateTime d) => DateTime(d.year, d.month, d.day, 12);
  static String _num(double v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : double.parse(v.toStringAsFixed(6)).toString();
  static double _parse(TextEditingController c) => double.tryParse(c.text) ?? 0;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
    _recomputeReinvestShares();
  }

  Future<void> _loadAccounts() async {
    final repo = ref.read(repositoryProvider);
    final investment = await repo.getAccountBySyncId(_item.accountSyncId);
    final receiving = _item.settlementAccountSyncId == null
        ? null
        : await repo.getAccountBySyncId(_item.settlementAccountSyncId!);
    if (!mounted) return;
    setState(() {
      _investment = investment;
      _receiving = receiving;
    });
  }

  @override
  void dispose() {
    for (final c in [
      _perShareCtrl,
      _feeCtrl,
      _taxCtrl,
      _receivedCtrl,
      _reinvestPriceCtrl,
      _reinvestSharesCtrl,
      _reinvestFeeCtrl,
      _stockSharesCtrl,
      _noteCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _gross {
    final raw = _item.shares * _parse(_perShareCtrl);
    return InvestmentSettings.currencyDecimals(_item.currency) == 0
        ? (raw + 1e-9).floorToDouble()
        : (raw * 100).roundToDouble() / 100;
  }

  double get _net {
    final v = _gross - _parse(_feeCtrl) - _parse(_taxCtrl);
    return v < 0 ? 0 : v;
  }

  Account? get _target => _reinvest ? _investment : _receiving;

  bool get _crossCurrency =>
      _hasCash &&
      _target != null &&
      _target!.currency.toUpperCase() != (_item.currency ?? '').toUpperCase();

  /// 再投入股數預設 = 實收 ÷ 價格(台股捨去到整股,其它到 6 位小數)。
  void _recomputeReinvestShares() {
    if (_reinvestSharesEdited) return;
    final price = _parse(_reinvestPriceCtrl);
    if (price <= 0 || _net <= 0) {
      _reinvestSharesCtrl.text = '';
      return;
    }
    final raw = _net / price;
    final isTw = _item.market == 'TW' || _item.market == 'TWO';
    _reinvestSharesCtrl.text =
        _num(isTw ? raw.floorToDouble() : (raw * 1e6).floorToDouble() / 1e6);
  }

  Future<void> _pickReceiving() async {
    final result = await AccountCardPicker.show(
      context,
      ledgerId: ref.read(currentLedgerIdProvider),
      selectedAccountId: _receiving?.id,
      allowAllCurrencies: true,
    );
    if (result?.accountId == null) return;
    final acc =
        await ref.read(repositoryProvider).getAccount(result!.accountId!);
    if (mounted && acc != null) setState(() => _receiving = acc);
  }

  Future<void> _pickDate() async {
    final picked = await showAppDatePicker(
      context,
      initial: _date,
      minDate: DateTime(1990),
      maxDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = _noon(picked));
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (_hasCash && !_reinvest && _receiving?.syncId == null) {
      return showToast(context, l10n.stockReceivingAccountRequired);
    }
    if (_hasCash &&
        _reinvest &&
        (_parse(_reinvestSharesCtrl) <= 0 || _parse(_reinvestPriceCtrl) <= 0)) {
      return showToast(context, l10n.stockDividendReinvestRequired);
    }
    double? received;
    if (_crossCurrency) {
      received = double.tryParse(_receivedCtrl.text);
      if (received == null || received <= 0)
        return showToast(context, l10n.stockSettlementAmountRequired);
    }
    final note = _noteCtrl.text.trim();
    final body = <String, dynamic>{
      'mode': _reinvest ? 'reinvest' : 'cash',
      'cash_per_share': _parse(_perShareCtrl),
      'fee': _parse(_feeCtrl),
      'tax': _parse(_taxCtrl),
      if (!_reinvest && _receiving?.syncId != null)
        'settlement_account_id': _receiving!.syncId,
      if (received != null) 'settlement_amount': received,
      if (_reinvest) 'reinvest_shares': _parse(_reinvestSharesCtrl),
      if (_reinvest) 'reinvest_price': _parse(_reinvestPriceCtrl),
      if (_reinvest) 'reinvest_fee': _parse(_reinvestFeeCtrl),
      'stock_shares': _hasStock ? _parse(_stockSharesCtrl) : 0,
      'trade_date': _date.toUtc().toIso8601String(),
      if (note.isNotEmpty) 'note': note,
    };
    setState(() => _saving = true);
    try {
      await ref.read(pendingDividendsProvider.notifier).confirm(_item, body);
      ref.read(statsRefreshProvider.notifier).state++;
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showToast(context, '${l10n.commonError}: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gap = SizedBox(height: 12.0.scaled(context, ref));
    final ccy = _item.currency ?? '';
    final primary = ref.watch(primaryColorProvider);
    final reinvestCost =
        _parse(_reinvestSharesCtrl) * _parse(_reinvestPriceCtrl) +
            _parse(_reinvestFeeCtrl);

    Widget modeChip(bool reinvest, String label) {
      final on = _reinvest == reinvest;
      return ChoiceChip(
        label: Text(label),
        selected: on,
        selectedColor: primary.withValues(alpha: 0.15),
        backgroundColor: BeeTokens.surfaceChip(context),
        labelStyle: TextStyle(
          color: on ? primary : BeeTokens.textSecondary(context),
          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
        ),
        onSelected: (_) => setState(() => _reinvest = reinvest),
      );
    }

    void onAmountChanged(String _) => setState(_recomputeReinvestShares);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.stockDividendConfirmTitle,
            subtitle: '${_item.symbol} ${_item.securityName ?? ''}'.trim(),
            showBack: true,
            compact: true,
            actions: [
              TextButton(
                onPressed: _saving ? null : _submit,
                child: Text(
                  l10n.stockDividendConfirm,
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
                  child: Text(
                    [
                      if ((_item.accountName ?? '').isNotEmpty)
                        _item.accountName!,
                      l10n.stockDividendExDate(formatTradeDate(_item.exDate)),
                      l10n.stockDividendRecordShares(
                          formatShares(_item.shares)),
                    ].join(' · '),
                    style: TextStyle(color: BeeTokens.textSecondary(context)),
                  ),
                ),
                gap,
                if (_hasCash) ...[
                  SectionCard(
                    margin: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(spacing: 8, children: [
                          modeChip(false, l10n.stockDividendModeCash),
                          modeChip(true, l10n.stockDividendModeReinvest),
                        ]),
                        _field(context, _perShareCtrl,
                            '${l10n.stockDividendPerShare} ($ccy)',
                            onChanged: onAmountChanged),
                        _divider(context),
                        _field(context, _feeCtrl, l10n.stockFee,
                            onChanged: onAmountChanged),
                        _divider(context),
                        _field(context, _taxCtrl, l10n.stockDividendTax,
                            onChanged: onAmountChanged),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              '${l10n.stockDividendGross} ${formatStockMoney(_gross, ccy)}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: BeeTokens.textTertiary(context)),
                            ),
                            const Spacer(),
                            Text(l10n.stockDividendNet,
                                style: TextStyle(
                                    color: BeeTokens.textSecondary(context))),
                            const SizedBox(width: 8),
                            Text(
                              formatStockMoney(_net, ccy),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: BeeTokens.textPrimary(context),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  gap,
                  SectionCard(
                    margin: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!_reinvest)
                          _row(
                            context,
                            label: l10n.stockReceivingAccount,
                            value: _receiving == null
                                ? l10n.stockReceivingAccountRequired
                                : '${_receiving!.name} · ${_receiving!.currency}',
                            onTap: _pickReceiving,
                          )
                        else ...[
                          _field(context, _reinvestPriceCtrl,
                              '${l10n.stockDividendReinvestPrice} ($ccy)',
                              onChanged: onAmountChanged),
                          _divider(context),
                          _field(context, _reinvestSharesCtrl,
                              l10n.stockDividendReinvestShares,
                              onChanged: (_) =>
                                  setState(() => _reinvestSharesEdited = true)),
                          _divider(context),
                          _field(context, _reinvestFeeCtrl, l10n.stockFee,
                              onChanged: (_) => setState(() {})),
                          const SizedBox(height: 6),
                          Text(
                            l10n.stockDividendReinvestHint(
                                formatStockMoney(reinvestCost, ccy)),
                            style: TextStyle(
                                fontSize: 12,
                                color: BeeTokens.textTertiary(context)),
                          ),
                        ],
                        if (_crossCurrency) ...[
                          _divider(context),
                          _field(
                              context,
                              _receivedCtrl,
                              l10n.stockDividendReceivedAmount(
                                  _target!.currency)),
                        ],
                      ],
                    ),
                  ),
                  gap,
                ],
                if (_hasStock) ...[
                  SectionCard(
                    margin: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _field(context, _stockSharesCtrl,
                            l10n.stockDividendStockSharesField),
                        Text(
                          l10n.stockDividendStockSharesHint(
                              _num(_item.stockPerShare)),
                          style: TextStyle(
                              fontSize: 12,
                              color: BeeTokens.textTertiary(context)),
                        ),
                      ],
                    ),
                  ),
                  gap,
                ],
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _row(context,
                          label: l10n.stockDividendDate,
                          value: formatTradeDate(_date),
                          onTap: _pickDate),
                      _divider(context),
                      TextField(
                        controller: _noteCtrl,
                        style: TextStyle(
                            fontSize: 16,
                            color: BeeTokens.textPrimary(context)),
                        decoration: InputDecoration(
                          labelText: l10n.stockNote,
                          labelStyle: TextStyle(
                              color: BeeTokens.textSecondary(context)),
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16.0.scaled(context, ref)),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l10n.stockDividendConfirm),
                ),
                SizedBox(height: 24.0.scaled(context, ref)),
              ],
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
      BuildContext context, TextEditingController controller, String label,
      {ValueChanged<String>? onChanged}) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,6}'))
      ],
      style: TextStyle(fontSize: 16, color: BeeTokens.textPrimary(context)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: BeeTokens.textSecondary(context)),
        border: InputBorder.none,
      ),
    );
  }
}
