import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/repositories/stock_trade_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/investment_settings.dart';
import '../../providers.dart';
import '../../services/currency/rate_math.dart';
import '../../services/investment/dividend_estimate.dart';
import '../../services/investment/markets.dart';
import '../../services/investment/stock_trade_tx_mapper.dart';
import '../../services/investment/stock_trade_types.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/account_card_picker.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';
import 'investment_ui.dart';
import 'opening_holdings_batch_page.dart';
import 'recurring_stock_rule_editor_page.dart';
import 'security_search_sheet.dart';

/// 新增/編輯一筆股票交易(docs/changes/2026-09-28-stock-holdings.md)。
///
/// 買進/賣出會連帶建立一筆轉帳(交割帳戶 ⇄ 這個投資理財帳戶),由
/// [StockTradeRepository.createStockTrade] 一起寫入;期初持股/配股沒有金流。
/// 現金股利/股利再投入(Phase 2 手動補記)建一筆「股利」收入:現金股利入
/// 「入帳帳戶」,再投入入這個投資理財帳戶本身。
/// 手續費/交易稅依帳戶費用設定([InvestmentSettings])自動試算,使用者改過
/// 欄位後就不再自動覆蓋。交易類型/帳戶/標的建立後不可改(同 Cloud)。
class StockTradeEditorPage extends ConsumerStatefulWidget {
  final Account account;
  final StockTrade? trade;
  final String? initialTradeType;
  final String? initialMarket;
  final String? initialSymbol;
  final String? initialName;
  // 轉帳表單偵測到轉入/轉出帳戶是投資理財帳戶、導來這裡買進/賣出時,把
  // 使用者已經選好的另一側帳戶帶過來當交割帳戶,略過 [_loadDefaultSettlement]。
  final Account? initialSettlement;

  const StockTradeEditorPage({
    super.key,
    required this.account,
    this.trade,
    this.initialTradeType,
    this.initialMarket,
    this.initialSymbol,
    this.initialName,
    this.initialSettlement,
  });

  @override
  ConsumerState<StockTradeEditorPage> createState() =>
      _StockTradeEditorPageState();
}

class _StockTradeEditorPageState extends ConsumerState<StockTradeEditorPage> {
  static const _creatableTypes = [
    kStockTradeBuy,
    kStockTradeSell,
    kStockTradeOpening,
    kStockTradeStockDividend,
    kStockTradeSplit,
    kStockTradeCashDividend,
    kStockTradeReinvest,
  ];

  final _symbolCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _sharesCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _settlementAmountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  late String _tradeType;
  late String _market;
  late String _securityCurrency;
  late DateTime _tradeDate;
  Account? _settlement;
  bool _feeEdited = false;
  bool _taxEdited = false;
  bool _saving = false;

  /// 選/輸入代號後自動帶入的現價(顯示「已帶入現價」提示用);使用者自己改
  /// 價格後清掉。
  SecurityQuote? _prefilledQuote;
  bool _priceEdited = false;
  Timer? _symbolDebounce;
  final _symbolFocus = FocusNode();
  // 上一次自動帶入的名稱:代號改了、名稱還是舊的自動值才覆蓋(手打的名稱不動)。
  String? _autoName;
  late final InvestmentSettings _settings =
      InvestmentSettings.parse(widget.account.investmentSettingsJson);

  bool get _isEditing => widget.trade != null;

  /// 需要選交割/入帳帳戶的類型(reinvest 入投資理財帳戶本身,不用選)。
  bool get _isCash =>
      kStockTradeCashTypes.contains(_tradeType) ||
      _tradeType == kStockTradeCashDividend;
  bool get _isDividend => _tradeType == kStockTradeCashDividend;

  /// 股票分割:shares 欄位存「分割比例」,沒有價格/手續費/交割帳戶。
  bool get _isSplit => _tradeType == kStockTradeSplit;

  /// 只有股數(或比例)欄位、沒有價格/費用/金額的類型。
  bool get _sharesOnly => _tradeType == kStockTradeStockDividend || _isSplit;

  /// 交易日期一律存當地中午:換成 UTC 或其它市場時區都還是同一天(Cloud 判斷
  /// 除息日前持股時會換成市場當地日期比)。
  static DateTime _noon(DateTime d) => DateTime(d.year, d.month, d.day, 12);

  @override
  void initState() {
    super.initState();
    final t = widget.trade;
    if (t != null) {
      _tradeType = t.tradeType;
      _market = t.market;
      _securityCurrency = (t.currency ??
              stockMarketByCode(t.market)?.currency ??
              widget.account.currency)
          .toUpperCase();
      _symbolCtrl.text = t.symbol;
      _nameCtrl.text = t.securityName ?? '';
      _sharesCtrl.text = _num(t.shares);
      _priceCtrl.text = t.price == null ? '' : _num(t.price!);
      _feeCtrl.text = _num(t.fee);
      _taxCtrl.text = _num(t.tax);
      _noteCtrl.text = t.note ?? '';
      _tradeDate = t.tradeDate;
      _feeEdited = true;
      _taxEdited = true;
      _priceEdited = true;
      _loadLinkedTx(t);
    } else {
      _tradeType = widget.initialTradeType ?? kStockTradeBuy;
      _market = widget.initialMarket ??
          _settings.market ??
          _defaultMarketFor(widget.account.currency);
      _securityCurrency =
          stockMarketByCode(_market)?.currency ?? widget.account.currency;
      _symbolCtrl.text = widget.initialSymbol ?? '';
      _nameCtrl.text = widget.initialName ?? '';
      _tradeDate = _noon(DateTime.now());
      if (widget.initialSettlement != null) {
        _settlement = widget.initialSettlement;
      } else {
        _loadDefaultSettlement();
      }
      // 從持股明細頁「買進/賣出」進來時代號已經帶好,直接帶現價。
      if (_symbolCtrl.text.trim().isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _prefillPrice());
      }
      // 離開代號欄時馬上查(不用等 0.7 秒 debounce)。
      _symbolFocus.addListener(() {
        if (!_symbolFocus.hasFocus) {
          _symbolDebounce?.cancel();
          _prefillPrice();
        }
      });
    }
  }

  static String _defaultMarketFor(String currency) {
    for (final m in kStockMarkets) {
      if (m.currency == currency.toUpperCase()) return m.code;
    }
    return 'TW';
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// 預帶交割帳戶:優先用費用設定裡指定的;沒設定時沿用這個帳戶上一筆
  /// 買進/賣出用的交割帳戶(多數人固定用同一個交割戶)。
  Future<void> _loadDefaultSettlement() async {
    final repo = ref.read(repositoryProvider);
    Account? acc;
    final syncId = _settings.settlementAccountId;
    if (syncId != null) {
      acc = await repo.getAccountBySyncId(syncId);
    } else {
      final trades = await repo.getStockTradesForAccount(widget.account.id);
      for (final t in trades.reversed) {
        if (t.txSyncId == null || !kStockTradeCashTypes.contains(t.tradeType))
          continue;
        final tx = await repo.getTransactionBySyncId(t.txSyncId!);
        final id = tx == null
            ? null
            : (t.tradeType == kStockTradeBuy ? tx.accountId : tx.toAccountId);
        if (id != null) acc = await repo.getAccount(id);
        break;
      }
    }
    if (mounted && acc != null && acc.id != widget.account.id)
      setState(() => _settlement = acc);
  }

  Future<void> _loadLinkedTx(StockTrade t) async {
    if (t.txSyncId == null) return;
    final repo = ref.read(repositoryProvider);
    final tx = await repo.getTransactionBySyncId(t.txSyncId!);
    if (tx == null) return;
    final isIncome = kStockTradeIncomeTypes.contains(t.tradeType);
    final settlementId = t.tradeType == kStockTradeBuy || isIncome
        ? tx.accountId
        : tx.toAccountId;
    if (settlementId == null) return;
    final acc = await repo.getAccount(settlementId);
    if (!mounted || acc == null) return;
    setState(() {
      if (t.tradeType != kStockTradeReinvest) _settlement = acc;
      if (acc.currency.toUpperCase() != _securityCurrency) {
        final v = t.tradeType == kStockTradeSell ? tx.toAmount : tx.amount;
        if (v != null) _settlementAmountCtrl.text = _num(v);
      }
    });
  }

  @override
  void dispose() {
    _symbolDebounce?.cancel();
    _symbolFocus.dispose();
    for (final c in [
      _symbolCtrl,
      _nameCtrl,
      _sharesCtrl,
      _priceCtrl,
      _feeCtrl,
      _taxCtrl,
      _settlementAmountCtrl,
      _noteCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _shares => double.tryParse(_sharesCtrl.text) ?? 0;
  double get _price => double.tryParse(_priceCtrl.text) ?? 0;
  double get _fee => double.tryParse(_feeCtrl.text) ?? 0;
  double get _tax => double.tryParse(_taxCtrl.text) ?? 0;
  double get _gross =>
      InvestmentSettings.gross(_shares, _price, _securityCurrency);

  /// 會用「現價」當成交價預帶的類型(期初持股填的是成本,股利填的是每股
  /// 股利,都不帶)。
  bool get _usesMarketPrice =>
      _tradeType == kStockTradeBuy ||
      _tradeType == kStockTradeSell ||
      _tradeType == kStockTradeReinvest;

  /// 代號打完(停頓 0.7 秒或離開輸入框)查報價:精準命中就帶入名稱(所有交易
  /// 類型,含期初持股/股利);價格欄還空著(或還是上次自動帶入的值)且是買賣類
  /// 才帶入現價。
  Future<void> _prefillPrice() async {
    if (_isEditing) return;
    final symbol = _symbolCtrl.text.trim().toUpperCase();
    if (symbol.isEmpty) return;
    final market = _market;
    final quote =
        await ref.read(quoteRefreshProvider.notifier).quoteFor(market, symbol);
    if (!mounted ||
        market != _market ||
        symbol != _symbolCtrl.text.trim().toUpperCase()) return;
    final name = quote?.name?.trim() ?? '';
    final currentName = _nameCtrl.text.trim();
    final nameReplaceable = currentName.isEmpty || currentName == _autoName;
    final fillPrice = quote?.price != null && _usesMarketPrice && !_priceEdited;
    if (!fillPrice && !nameReplaceable) return;
    setState(() {
      if (nameReplaceable) {
        // 查不到代號時清掉上一檔自動帶入的名稱,免得名稱跟代號對不上。
        _nameCtrl.text = name;
        _autoName = name.isEmpty ? null : name;
      }
      if (fillPrice) {
        _priceCtrl.text = _num(quote!.price!);
        _prefilledQuote = quote;
      }
      _recomputeSuggestions();
    });
  }

  /// 代號/市場真的換了才清掉上一檔帶入的價格(搜尋結果點同一檔時保留)。
  void _clearPrefilledPriceIfSymbolChanged() {
    final q = _prefilledQuote;
    if (q == null || _priceEdited) return;
    if (q.market.toUpperCase() == _market.toUpperCase() &&
        q.symbol.toUpperCase() == _symbolCtrl.text.trim().toUpperCase()) {
      return;
    }
    _priceCtrl.clear();
    _prefilledQuote = null;
  }

  void _onSymbolChanged(String _) {
    setState(() {
      // 代號換了,上一檔帶入的價格不能沿用。
      _clearPrefilledPriceIfSymbolChanged();
      _recomputeSuggestions();
    });
    _symbolDebounce?.cancel();
    _symbolDebounce = Timer(const Duration(milliseconds: 700), () {
      _prefillPrice();
      _prefillHeldShares();
    });
  }

  /// 實際收/付款的帳戶:reinvest 是投資理財帳戶本身,其它是選的交割/入帳帳戶。
  Account? get _receiving => _tradeType == kStockTradeReinvest
      ? widget.account
      : (_isCash ? _settlement : null);

  bool get _crossCurrency =>
      _receiving != null &&
      _receiving!.currency.toUpperCase() != _securityCurrency.toUpperCase();

  /// 成交金額變了就重算建議手續費/稅(使用者手動改過的欄位不動)。
  void _recomputeSuggestions() {
    if (_sharesOnly) return;
    if (_isDividend) {
      // 現金股利:手續費 = 股利手續費,稅 = 預扣稅 + 二代健保(同 Cloud 估算)。
      final est = estimateDividend(
        market: _market,
        currency: _securityCurrency,
        shares: _shares,
        cashPerShare: _price,
        settings: _settings,
      );
      if (!_feeEdited) _feeCtrl.text = est.fee > 0 ? _num(est.fee) : '';
      if (!_taxEdited) _taxCtrl.text = est.tax > 0 ? _num(est.tax) : '';
      return;
    }
    if (!_feeEdited) {
      // 期初持股填的是券商庫存的平均成本,通常已經含手續費,不再另外估。
      final fee = _tradeType == kStockTradeOpening
          ? 0.0
          : _settings.suggestFee(_gross,
              market: _market, currency: _securityCurrency, shares: _shares);
      _feeCtrl.text = _gross > 0 && fee > 0 ? _num(fee) : '';
    }
    if (!_taxEdited) {
      final tax = _tradeType == kStockTradeSell
          ? _settings.suggestSellTax(_gross,
              market: _market,
              symbol: _symbolCtrl.text.trim(),
              currency: _securityCurrency,
              shares: _shares)
          : 0.0;
      _taxCtrl.text = _gross > 0 && tax > 0 ? _num(tax) : '';
    }
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
    setState(() {
      _market = picked;
      _securityCurrency =
          stockMarketByCode(picked)?.currency ?? _securityCurrency;
      _recomputeSuggestions();
    });
  }

  Future<void> _searchSecurity() async {
    final pick = await SecuritySearchSheet.show(context,
        market: _market, initialQuery: _symbolCtrl.text);
    if (pick == null) return;
    setState(() {
      _market = pick.market;
      _securityCurrency = pick.currency.toUpperCase();
      _symbolCtrl.text = pick.symbol;
      if (pick.name != null && pick.name!.isNotEmpty) {
        _nameCtrl.text = pick.name!;
        _autoName = pick.name;
      }
      _clearPrefilledPriceIfSymbolChanged();
      _recomputeSuggestions();
    });
    _prefillPrice();
    _prefillHeldShares();
  }

  /// 現金股利預填持有股數(使用者還沒填的時候)。
  Future<void> _prefillHeldShares() async {
    if (!_isDividend || _isEditing || _sharesCtrl.text.trim().isNotEmpty)
      return;
    final symbol = _symbolCtrl.text.trim().toUpperCase();
    if (symbol.isEmpty) return;
    final held = await ref.read(repositoryProvider).getHeldShares(
          accountId: widget.account.id,
          market: _market,
          symbol: symbol,
        );
    if (!mounted || held <= 0 || _sharesCtrl.text.trim().isNotEmpty) return;
    setState(() {
      _sharesCtrl.text = _num(held);
      _recomputeSuggestions();
    });
  }

  Future<void> _pickSettlement() async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    final result = await AccountCardPicker.show(
      context,
      ledgerId: ledgerId,
      selectedAccountId: _settlement?.id,
      // 股利可以直接入投資理財帳戶本身(例:券商交割戶就是這個帳戶)。
      excludeAccountId: _isDividend ? null : widget.account.id,
      allowAllCurrencies: true,
    );
    if (result?.accountId == null) return;
    final acc =
        await ref.read(repositoryProvider).getAccount(result!.accountId!);
    if (!mounted || acc == null) return;
    setState(() => _settlement = acc);
  }

  Future<void> _pickDate() async {
    final picked = await showAppDatePicker(
      context,
      initial: _tradeDate,
      minDate: DateTime(1990),
      maxDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _tradeDate = _noon(picked));
  }

  /// 跨幣別時,用使用者主幣別匯率幫忙估一個交割金額當提示(實際金額以券商
  /// 對帳單為準,所以只放 hint 不自動填)。
  String? _estimatedSettlementHint() {
    if (!_crossCurrency || _gross <= 0) return null;
    final rates = ref.watch(effectiveRatesProvider).valueOrNull ??
        const <String, EffectiveRate>{};
    final base = ref.watch(baseCurrencyProvider);
    double? toBase(String c) {
      if (c.toUpperCase() == base.toUpperCase()) return 1;
      return double.tryParse(rates[c.toUpperCase()]?.rate ?? '');
    }

    final a = toBase(_securityCurrency);
    final b = toBase(_receiving!.currency);
    if (a == null || b == null || b == 0) return null;
    final secAmount = stockTradeAmount(
        tradeType: _tradeType,
        shares: _shares,
        price: _price,
        fee: _fee,
        tax: _tax,
        currency: _securityCurrency);
    return '≈ ${formatStockMoney(secAmount * a / b, _receiving!.currency)}';
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(repositoryProvider);
    final symbol = _symbolCtrl.text.trim().toUpperCase();
    if (symbol.isEmpty) return showToast(context, l10n.stockSymbolRequired);
    if (_isSplit) {
      if (_shares <= 0) return showToast(context, l10n.stockSplitRatioInvalid);
    } else if (_shares <= 0) {
      return showToast(context, l10n.stockSharesRequired);
    }
    if (!_sharesOnly && _priceCtrl.text.trim().isEmpty) {
      return showToast(context, l10n.stockPriceRequired);
    }
    double? settlementAmount;
    if (_isCash && _settlement == null) {
      return showToast(
          context,
          _isDividend
              ? l10n.stockReceivingAccountRequired
              : l10n.stockSettlementRequired);
    }
    if (_crossCurrency) {
      settlementAmount = double.tryParse(_settlementAmountCtrl.text);
      if (settlementAmount == null || settlementAmount <= 0) {
        return showToast(context, l10n.stockSettlementAmountRequired);
      }
    }
    if (_tradeType == kStockTradeSell) {
      final held = await repo.getHeldShares(
        accountId: widget.account.id,
        market: _market,
        symbol: symbol,
        excludeTradeId: widget.trade?.id,
      );
      if (_shares > held + 1e-6) {
        if (mounted)
          showToast(context, l10n.stockOversellError(formatShares(held)));
        return;
      }
    }

    final name = _nameCtrl.text.trim();
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    final sharesText = formatShares(_shares);
    final txNote = note ??
        (switch (_tradeType) {
          kStockTradeSell =>
            l10n.stockDefaultTxNoteSell(symbol, name, sharesText),
          kStockTradeCashDividend =>
            l10n.stockDefaultTxNoteDividend(symbol, name, sharesText),
          kStockTradeReinvest =>
            l10n.stockDefaultTxNoteReinvest(symbol, name, sharesText),
          // 分割不建交易,txNote 不會被用到。
          kStockTradeSplit => '',
          _ => l10n.stockDefaultTxNoteBuy(symbol, name, sharesText),
        })
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

    setState(() => _saving = true);
    try {
      final isFirstTrade = !_isEditing &&
          (await repo.getStockTradesForAccount(widget.account.id)).isEmpty;
      if (_isEditing) {
        await repo.updateStockTrade(
          widget.trade!.id,
          shares: _shares,
          price: _isSplit ? null : _price,
          fee: _fee,
          tax: _tax,
          tradeDate: _tradeDate,
          securityName: name.isEmpty ? null : name,
          note: note,
          settlementAccountId: _settlement?.id,
          settlementAmount: settlementAmount,
          txNote: txNote,
        );
      } else {
        await repo.createStockTrade(
          ledgerId: ref.read(currentLedgerIdProvider),
          accountId: widget.account.id,
          tradeType: _tradeType,
          market: _market,
          symbol: symbol,
          securityName: name.isEmpty ? null : name,
          shares: _shares,
          price: _isSplit ? null : _price,
          fee: _fee,
          tax: _tax,
          currency: _securityCurrency,
          tradeDate: _tradeDate,
          settlementAccountId: _isCash ? _settlement?.id : null,
          settlementAmount: settlementAmount,
          note: note,
          txNote: txNote,
        );
      }
      ref.read(statsRefreshProvider.notifier).state++;
      // 報價:新標的立刻抓一次(沒登入 Cloud 時 no-op)。
      ref
          .read(quoteRefreshProvider.notifier)
          .refresh(force: true, extraKeys: [securityKey(_market, symbol)]);
      if (!mounted) return;
      if (isFirstTrade && widget.account.includeInTotal) {
        await _suggestExcludeFromTotal();
      }
      if (mounted) Navigator.of(context).pop(true);
    } on StockTradeOversellException catch (e) {
      if (mounted)
        showToast(context, l10n.stockOversellError(formatShares(e.held)));
    } on StockTradeSettlementAmountRequired {
      if (mounted) showToast(context, l10n.stockSettlementAmountRequired);
    } on StockTradeAccountException catch (e) {
      if (mounted) showToast(context, '${l10n.commonError}: $e');
    } catch (e) {
      if (mounted) showToast(context, '${l10n.commonError}: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 在「仍計入淨資產」的既有投資理財帳戶第一次記股票時,建議排除(使用者
  /// 確認的決策:股票不屬於馬上可以花的錢)。
  Future<void> _suggestExcludeFromTotal() async {
    final l10n = AppLocalizations.of(context);
    final yes = await AppDialog.confirm<bool>(
      context,
      title: l10n.stockExcludeFromTotalTitle,
      message: l10n.stockExcludeFromTotalDesc,
      okLabel: l10n.stockExcludeFromTotalYes,
      cancelLabel: l10n.stockExcludeFromTotalNo,
    );
    if (yes == true) {
      await ref
          .read(repositoryProvider)
          .updateAccount(widget.account.id, includeInTotal: false);
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final ok = await AppDialog.confirm<bool>(
      context,
      title: l10n.commonDelete,
      message: l10n.stockDeleteTradeConfirm,
      okLabel: l10n.commonDelete,
    );
    if (ok != true) return;
    await ref.read(repositoryProvider).deleteStockTrade(widget.trade!.id);
    ref.read(statsRefreshProvider.notifier).state++;
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gap = SizedBox(height: 12.0.scaled(context, ref));
    final cloudAvailable =
        ref.watch(securitiesCloudAvailableProvider).valueOrNull ?? false;
    final secAmount = switch (_tradeType) {
      kStockTradeBuy ||
      kStockTradeOpening ||
      kStockTradeReinvest =>
        stockTradeAmount(
            tradeType: _tradeType,
            shares: _shares,
            price: _price,
            fee: _fee,
            tax: 0,
            currency: _securityCurrency),
      kStockTradeSell || kStockTradeCashDividend => stockTradeAmount(
          tradeType: _tradeType,
          shares: _shares,
          price: _price,
          fee: _fee,
          tax: _tax,
          currency: _securityCurrency),
      _ => 0.0,
    };
    final typeHint = switch (_tradeType) {
      kStockTradeOpening => l10n.stockTradeTypeOpeningHint,
      kStockTradeStockDividend => l10n.stockTradeTypeStockDividendHint,
      kStockTradeSplit => l10n.stockTradeTypeSplitHint,
      kStockTradeCashDividend => l10n.stockTradeTypeCashDividendHint,
      kStockTradeReinvest => l10n.stockTradeTypeReinvestHint,
      _ => null,
    };

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: _isEditing ? l10n.stockEditTrade : l10n.stockAddTrade,
            subtitle: widget.account.name,
            showBack: true,
            compact: true,
            actions: [
              if (_isEditing)
                IconButton(
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(Icons.delete_outline)),
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
                // 交易類型
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final type
                              in _isEditing ? [_tradeType] : _creatableTypes)
                            ChoiceChip(
                              label: Text(stockTradeTypeLabel(l10n, type)),
                              selected: _tradeType == type,
                              selectedColor: ref
                                  .watch(primaryColorProvider)
                                  .withValues(alpha: 0.15),
                              backgroundColor: BeeTokens.surfaceChip(context),
                              labelStyle: TextStyle(
                                color: _tradeType == type
                                    ? ref.watch(primaryColorProvider)
                                    : BeeTokens.textSecondary(context),
                                fontWeight: _tradeType == type
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              onSelected: _isEditing
                                  ? null
                                  : (_) => setState(() {
                                        _tradeType = type;
                                        if (type == kStockTradeStockDividend ||
                                            type == kStockTradeSplit) {
                                          _feeCtrl.clear();
                                          _taxCtrl.clear();
                                        }
                                        if (!_usesMarketPrice &&
                                            _prefilledQuote != null &&
                                            !_priceEdited) {
                                          _priceCtrl.clear();
                                          _prefilledQuote = null;
                                        }
                                        _recomputeSuggestions();
                                        _prefillHeldShares();
                                        _prefillPrice();
                                      }),
                            ),
                          // 2026-09-29:在股票交易裡也能直接開始定期定額(帶入已輸入的標的)。
                          if (!_isEditing)
                            ActionChip(
                              avatar: Icon(Icons.repeat,
                                  size: 16,
                                  color: BeeTokens.iconSecondary(context)),
                              label: Text(l10n.recurringStockAddButton),
                              backgroundColor: BeeTokens.surfaceChip(context),
                              labelStyle: TextStyle(
                                  color: BeeTokens.textSecondary(context)),
                              onPressed: () {
                                final symbol =
                                    _symbolCtrl.text.trim().toUpperCase();
                                Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            RecurringStockRuleEditorPage(
                                              account: widget.account,
                                              initialMarket: _market,
                                              initialSymbol: symbol.isEmpty
                                                  ? null
                                                  : symbol,
                                              initialName:
                                                  _nameCtrl.text.trim().isEmpty
                                                      ? null
                                                      : _nameCtrl.text.trim(),
                                            )));
                              },
                            ),
                        ],
                      ),
                      if (typeHint != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          typeHint,
                          style: TextStyle(
                              fontSize: 12,
                              color: BeeTokens.textTertiary(context)),
                        ),
                      ],
                      // 2026-09-30:期初持股一檔一筆就好(填平均成本),很多檔時
                      // 改用批次頁一次輸入/貼上。
                      if (!_isEditing && _tradeType == kStockTradeOpening)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact),
                            icon: Icon(Icons.playlist_add,
                                size: 18,
                                color: ref.watch(primaryColorProvider)),
                            label: Text(l10n.stockOpeningBatchEntry,
                                style: TextStyle(
                                    color: ref.watch(primaryColorProvider))),
                            onPressed: () => Navigator.of(context)
                                .pushReplacement(MaterialPageRoute(
                                    builder: (_) => OpeningHoldingsBatchPage(
                                          account: widget.account,
                                          initialMarket: _market,
                                        ))),
                          ),
                        ),
                    ],
                  ),
                ),
                gap,
                // 標的
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _row(
                        context,
                        label: l10n.stockMarket,
                        value:
                            '${stockMarketLabel(l10n, _market)} · $_securityCurrency',
                        onTap: _isEditing ? null : _pickMarket,
                      ),
                      _divider(context),
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              context,
                              controller: _symbolCtrl,
                              label: l10n.stockSymbol,
                              enabled: !_isEditing,
                              textCapitalization: TextCapitalization.characters,
                              focusNode: _symbolFocus,
                              onChanged: _isEditing ? null : _onSymbolChanged,
                            ),
                          ),
                          if (!_isEditing && cloudAvailable)
                            IconButton(
                              tooltip: l10n.stockSymbolSearchHint,
                              icon: Icon(Icons.search,
                                  color: BeeTokens.iconSecondary(context)),
                              onPressed: _searchSecurity,
                            ),
                        ],
                      ),
                      _divider(context),
                      _field(context,
                          controller: _nameCtrl, label: l10n.stockSecurityName),
                    ],
                  ),
                ),
                gap,
                // 數量/價格/費用
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _field(
                        context,
                        controller: _sharesCtrl,
                        label:
                            _isSplit ? l10n.stockSplitRatio : l10n.stockShares,
                        numeric: true,
                        onChanged: (_) => setState(_recomputeSuggestions),
                      ),
                      if (!_sharesOnly) ...[
                        _divider(context),
                        _field(
                          context,
                          controller: _priceCtrl,
                          label:
                              '${_isDividend ? l10n.stockDividendPerShare : _tradeType == kStockTradeOpening ? l10n.stockAvgCost : l10n.stockPrice} ($_securityCurrency)',
                          numeric: true,
                          onChanged: (_) => setState(() {
                            _priceEdited = true;
                            _prefilledQuote = null;
                            _recomputeSuggestions();
                          }),
                        ),
                        if (_prefilledQuote != null) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                _prefilledQuoteHint(l10n, _prefilledQuote!),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: BeeTokens.textTertiary(context)),
                              ),
                            ),
                          ),
                        ],
                        _divider(context),
                        _field(
                          context,
                          controller: _feeCtrl,
                          label: l10n.stockFee,
                          numeric: true,
                          onChanged: (_) => setState(() => _feeEdited = true),
                        ),
                      ],
                      if (_tradeType == kStockTradeSell || _isDividend) ...[
                        _divider(context),
                        _field(
                          context,
                          controller: _taxCtrl,
                          label: _isDividend
                              ? l10n.stockDividendTax
                              : l10n.stockTax,
                          numeric: true,
                          onChanged: (_) => setState(() => _taxEdited = true),
                        ),
                        if (_tradeType == kStockTradeSell)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                _sellTaxRateHint(l10n),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: BeeTokens.textTertiary(context)),
                              ),
                            ),
                          ),
                      ],
                      if (!_sharesOnly) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            l10n.stockAutoFeeHint,
                            style: TextStyle(
                                fontSize: 12,
                                color: BeeTokens.textTertiary(context)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              _isDividend
                                  ? l10n.stockDividendNet
                                  : _tradeType == kStockTradeSell
                                      ? l10n.stockNetProceeds
                                      : l10n.stockTotalCost,
                              style: TextStyle(
                                  color: BeeTokens.textSecondary(context)),
                            ),
                            const Spacer(),
                            Text(
                              formatStockMoney(secAmount, _securityCurrency),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: BeeTokens.textPrimary(context),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                gap,
                if (_isCash || _crossCurrency) ...[
                  SectionCard(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        if (_isCash)
                          _row(
                            context,
                            label: _isDividend
                                ? l10n.stockReceivingAccount
                                : l10n.stockSettlementAccount,
                            value: _settlement == null
                                ? (_isDividend
                                    ? l10n.stockReceivingAccountRequired
                                    : l10n.stockSettlementRequired)
                                : '${_settlement!.name} · ${_settlement!.currency}',
                            onTap: _pickSettlement,
                          ),
                        if (_crossCurrency) ...[
                          if (_isCash) _divider(context),
                          _field(
                            context,
                            controller: _settlementAmountCtrl,
                            label: l10n
                                .stockSettlementAmount(_receiving!.currency),
                            numeric: true,
                            hint: _estimatedSettlementHint(),
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              l10n.stockSettlementAmountHint,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: BeeTokens.textTertiary(context)),
                            ),
                          ),
                        ],
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
                          label: l10n.stockTradeDate,
                          value: formatTradeDate(_tradeDate),
                          onTap: _pickDate),
                      _divider(context),
                      _field(context,
                          controller: _noteCtrl, label: l10n.stockNote),
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

  String _prefilledQuoteHint(AppLocalizations l10n, SecurityQuote q) {
    final when = q.quoteTime ?? q.fetchedAt;
    final session = quoteSessionLabel(l10n, q.session);
    return l10n.stockPricePrefilled(
        '${session.isEmpty ? '' : '$session '}${formatQuoteTime(when)}');
  }

  /// 「證交稅率 0.1%(ETF)」:台股依代號判斷普通股/ETF/債券 ETF,其它市場
  /// 只顯示稅率。
  String _sellTaxRateHint(AppLocalizations l10n) {
    final symbol = _symbolCtrl.text.trim();
    final rate =
        _settings.sellTaxRateFor(market: _market, symbol: symbol) * 100;
    var text = rate.toStringAsFixed(4);
    text =
        text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    final upper = _market.toUpperCase();
    if (upper != 'TW' && upper != 'TWO') {
      return l10n.stockSellTaxRateHint('$text%');
    }
    final kind = switch (securityKindOf(_market, symbol)) {
      SecurityKind.etf => l10n.stockSecurityKindEtf,
      SecurityKind.bondEtf => l10n.stockSecurityKindBondEtf,
      SecurityKind.stock => l10n.stockSecurityKindStock,
    };
    return l10n.stockSellTaxRateHintWithKind('$text%', kind);
  }

  Widget _field(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    bool numeric = false,
    bool enabled = true,
    String? hint,
    TextCapitalization textCapitalization = TextCapitalization.none,
    ValueChanged<String>? onChanged,
    FocusNode? focusNode,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      onChanged: onChanged,
      textCapitalization: textCapitalization,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,6}'))]
          : null,
      style: TextStyle(
        fontSize: 16,
        color: enabled
            ? BeeTokens.textPrimary(context)
            : BeeTokens.textTertiary(context),
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: BeeTokens.textSecondary(context)),
        hintText: hint,
        hintStyle: TextStyle(color: BeeTokens.textTertiary(context)),
        border: InputBorder.none,
      ),
    );
  }
}
