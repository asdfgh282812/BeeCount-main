import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../models/investment_settings.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../services/investment/markets.dart';
import '../../services/investment/stock_dca.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/account_card_picker.dart';
import '../../widgets/biz/recurring_rule_advanced_sheet.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';
import 'investment_ui.dart';
import 'security_search_sheet.dart';

/// 新增/編輯「股票定期定額」規則(`RecurringTransactions.kind == 'stock_dca'`,
/// docs/changes/2026-09-28-stock-dca-recurring.md)。
///
/// 跟一般週期性收支規則共用同一張表跟同一套「查看已生成交易/終止未來週期/
/// 啟停」管理入口([RecurringRuleListPage]),只是新增/編輯走這個專屬頁面
/// (欄位集合不同:投資帳戶/市場/代號/每期投入金額/手續費覆寫,沒有分類/
/// 商家/標籤/信用卡回饋規則)。到期生成時價格未知,規則本身**不**預生成
/// occurrence,交給 [RecurringRuleRepository.materializeDueStockRules] 到期
/// 當下抓報價、算股數/手續費、呼叫 [StockTradeRepository.createStockTrade]
/// 生成——所以這裡存檔後看不到任何已生成的交易,要等下次啟動生成引擎跑完
/// (或報價/餘額備妥)才會出現。
///
/// [account] 是投資理財帳戶(新建時必填,鎖定不可換——同 [StockTradeEditorPage]
/// 的「帳戶/標的建立後不可改」慣例);[rule] 非 null 時是編輯既有規則,市場/
/// 代號/證券名稱鎖死不可改,只能改金額/手續費覆寫/週期/下次執行/結束時間/
/// 備註。
class RecurringStockRuleEditorPage extends ConsumerStatefulWidget {
  final Account account;
  final RecurringTransaction? rule;
  // 從股票交易頁的「定期定額」入口過來時,帶入使用者已經輸入的標的(新建才用)。
  final String? initialMarket;
  final String? initialSymbol;
  final String? initialName;

  const RecurringStockRuleEditorPage({
    super.key,
    required this.account,
    this.rule,
    this.initialMarket,
    this.initialSymbol,
    this.initialName,
  });

  @override
  ConsumerState<RecurringStockRuleEditorPage> createState() =>
      _RecurringStockRuleEditorPageState();
}

class _RecurringStockRuleEditorPageState
    extends ConsumerState<RecurringStockRuleEditorPage> {
  final _symbolCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _feeRatePercentCtrl = TextEditingController();
  final _feeMinCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _symbolFocus = FocusNode();
  Timer? _symbolDebounce;
  // 上一次自動帶入的名稱:代號改了、名稱還是舊的自動值才覆蓋(手打的名稱不動)。
  String? _autoName;

  late String _market;
  Account? _settlement;
  bool _customFee = false;
  RecurringRuleDraft _draft = const RecurringRuleDraft(
      frequency: 'monthly', interval: 1, endAt: null);
  late DateTime _nextRunAt;
  bool _saving = false;

  bool get _isEditing => widget.rule != null;

  late final InvestmentSettings _accountSettings =
      InvestmentSettings.parse(widget.account.investmentSettingsJson);

  String get _securityCurrency =>
      (stockMarketByCode(_market)?.currency ?? widget.account.currency)
          .toUpperCase();

  static String _defaultMarketFor(String currency) {
    for (final m in kStockMarkets) {
      if (m.currency == currency.toUpperCase()) return m.code;
    }
    return 'TW';
  }

  // 四捨五入到 6 位小數再去尾零:0.001425 * 100 = 0.14250000000000002 直接
  // toString 會顯示浮點雜訊,輸入框的格式限制又會把它截壞。
  static String _num(double v) {
    final fixed = v.toStringAsFixed(6);
    final trimmed = fixed.replaceFirst(RegExp(r'0+$'), '');
    return trimmed.endsWith('.') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  /// 帳戶目前生效的費率(使用者沒自訂時是市場預設),開自訂手續費時的預填值。
  /// 以前讀原始設定的 `feeRate ?? 0`,沒自訂過帳戶費率的話會預填 0% / 最低 0,
  /// 使用者不打字直接存檔就變成每期都不收手續費。
  InvestmentSettings get _effectiveAccountFees =>
      _accountSettings.resolvedFor(_market);

  /// 規則實際會用的費用設定(自訂覆寫或帳戶預設),同
  /// `LocalRepository._materializeStockRule`。
  InvestmentSettings get _ruleFeeSettings {
    final base = _effectiveAccountFees;
    if (!_customFee) return base;
    final ratePercent = double.tryParse(_feeRatePercentCtrl.text.trim());
    final min = double.tryParse(_feeMinCtrl.text.trim());
    return InvestmentSettings(
      feeRate: ratePercent != null ? ratePercent / 100 : base.feeRate,
      feeDiscount: base.feeDiscount,
      feeMin: min ?? base.feeMin,
    );
  }

  /// 金額欄下方:整數股/碎股說明 + 以快取報價試算這一期(台股只買整數股、
  /// 金額含手續費、零頭不扣,見 [stockDcaOrder])。
  Widget _dcaPreview(BuildContext context, AppLocalizations l10n) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [_amountCtrl, _symbolCtrl, _feeRatePercentCtrl, _feeMinCtrl]),
      builder: (context, _) {
        final whole = stockDcaWholeShares(_market);
        final lines = <String>[
          whole
              ? l10n.recurringStockWholeShareHint
              : l10n.recurringStockFractionalHint,
        ];
        final amount = double.tryParse(_amountCtrl.text.trim());
        final symbol = _symbolCtrl.text.trim().toUpperCase();
        final quotes = ref.watch(securityQuotesProvider).valueOrNull;
        final price = symbol.isEmpty
            ? null
            : quotes?[securityKey(_market, symbol)]?.price;
        if (amount != null && amount > 0 && price != null && price > 0) {
          final currency = _securityCurrency;
          final order = stockDcaOrder(
            amount: amount,
            price: price,
            market: _market,
            currency: currency,
            feeSettings: _ruleFeeSettings,
          );
          if (order == null) {
            lines.add(l10n.recurringStockPreviewTooSmall(formatPrice(price)));
          } else if (whole) {
            lines.add(l10n.recurringStockPreviewWhole(
              formatPrice(price),
              formatShares(order.shares),
              formatStockMoney(order.total, currency),
              formatStockMoney(order.fee, currency),
              formatStockMoney(
                  (amount - order.total).clamp(0, double.infinity), currency),
            ));
          } else {
            lines.add(l10n.recurringStockPreviewFractional(
              formatPrice(price),
              formatShares(order.shares),
              formatStockMoney(order.total, currency),
              formatStockMoney(order.fee, currency),
            ));
          }
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              lines.join('\n'),
              style: TextStyle(
                  fontSize: 12, color: BeeTokens.textTertiary(context)),
            ),
          ),
        );
      },
    );
  }

  /// 編輯時「下次執行」不能早於已經生成的最後一期(會重生成已生成過的期數);
  /// 新建時不能早於今天(到期只讀得到當下報價,回溯的期數會全用今天的價格買)。
  DateTime get _minNextRunAt {
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final generated = widget.rule?.generatedUntilAt;
    if (generated == null) return startOfToday;
    final nextDay = DateTime(generated.year, generated.month, generated.day)
        .add(const Duration(days: 1));
    return nextDay.isAfter(startOfToday) ? nextDay : startOfToday;
  }

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    if (r != null) {
      _market = r.market ?? _defaultMarketFor(widget.account.currency);
      _symbolCtrl.text = r.symbol ?? '';
      _nameCtrl.text = r.securityName ?? '';
      _amountCtrl.text = _num(r.amount);
      _noteCtrl.text = r.note ?? '';
      _draft = RecurringRuleDraft(
        frequency: r.frequency,
        interval: r.interval,
        advancedRule: _decodeAdvancedRule(r.advancedRuleJson),
        endAt: r.endAt,
      );
      // 規則的 nextRunAt 在第一期之後就不再變,顯示真正的下一期;改了之後
      // updateRuleAndFuture 會從新時間重新起算。
      _nextRunAt = nextPendingOccurrence(
            nextRunAt: r.nextRunAt,
            generatedUntilAt: r.generatedUntilAt,
            frequency: r.frequency,
            interval: r.interval,
            advancedRule: _draft.advancedRule,
          ) ??
          r.nextRunAt;
      _customFee = r.stockFeeRate != null || r.stockFeeMin != null;
      if (_customFee) {
        final fees = _effectiveAccountFees;
        _feeRatePercentCtrl.text = _num((r.stockFeeRate ?? fees.feeRate ?? 0) * 100);
        _feeMinCtrl.text = _num(r.stockFeeMin ?? fees.feeMin ?? 0);
      }
      if (r.fromAccountId != null) _loadSettlementFor(r.fromAccountId!);
    } else {
      _market = widget.initialMarket ??
          _accountSettings.market ??
          _defaultMarketFor(widget.account.currency);
      _symbolCtrl.text = widget.initialSymbol ?? '';
      _nameCtrl.text = widget.initialName ?? '';
      // 預設明天 09:00(同 Web)。選今天的話下次開 App / Cloud 排程就會執行。
      final now = DateTime.now();
      _nextRunAt = DateTime(now.year, now.month, now.day + 1, 9);
      _loadDefaultSettlement();
      if (_symbolCtrl.text.trim().isNotEmpty && _nameCtrl.text.trim().isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _lookupSymbol());
      }
    }
    _symbolFocus.addListener(() {
      if (!_symbolFocus.hasFocus) _lookupSymbol();
    });
  }

  void _onSymbolChanged(String _) {
    _symbolDebounce?.cancel();
    _symbolDebounce =
        Timer(const Duration(milliseconds: 700), _lookupSymbol);
  }

  /// 代號打完(停頓 0.7 秒或離開輸入框)就查報價,精準命中時帶入名稱,同
  /// [StockTradeEditorPage]。報價也會寫進快取,金額下方的試算跟著出現。
  Future<void> _lookupSymbol() async {
    _symbolDebounce?.cancel();
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
    final current = _nameCtrl.text.trim();
    if (current.isNotEmpty && current != _autoName) return;
    if (name.isEmpty) {
      // 查不到這個代號:清掉上一檔自動帶入的名稱,免得名稱跟代號對不上。
      if (current.isNotEmpty) setState(() => _nameCtrl.clear());
      return;
    }
    setState(() {
      _nameCtrl.text = name;
      _autoName = name;
    });
  }

  Map<String, dynamic>? _decodeAdvancedRule(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // 忽略格式錯誤的舊資料,當作沒有進階規則。
    }
    return null;
  }

  Future<void> _loadDefaultSettlement() async {
    final repo = ref.read(repositoryProvider);
    Account? acc;
    final syncId = _accountSettings.settlementAccountId;
    if (syncId != null) acc = await repo.getAccountBySyncId(syncId);
    // 預設交割戶必須跟證券同幣別(v1 不支援跨幣別定期定額),也不能是投資帳戶本身。
    if (acc != null &&
        (acc.id == widget.account.id ||
            acc.currency.toUpperCase() != _securityCurrency)) {
      acc = null;
    }
    if (mounted && acc != null) setState(() => _settlement = acc);
  }

  Future<void> _loadSettlementFor(int accountId) async {
    final repo = ref.read(repositoryProvider);
    final acc = await repo.getAccount(accountId);
    if (mounted && acc != null) setState(() => _settlement = acc);
  }

  @override
  void dispose() {
    _symbolDebounce?.cancel();
    _symbolFocus.dispose();
    _symbolCtrl.dispose();
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _feeRatePercentCtrl.dispose();
    _feeMinCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _lookupSymbol());
    setState(() {
      _market = picked;
      // 換市場 = 換幣別,原本的交割戶可能不再同幣別。
      if (_settlement != null &&
          _settlement!.currency.toUpperCase() != _securityCurrency) {
        _settlement = null;
      }
    });
  }

  Future<void> _searchSecurity() async {
    final pick = await SecuritySearchSheet.show(context,
        market: _market, initialQuery: _symbolCtrl.text);
    if (pick == null) return;
    setState(() {
      _market = pick.market;
      _symbolCtrl.text = pick.symbol;
      if (pick.name != null && pick.name!.isNotEmpty) {
        _nameCtrl.text = pick.name!;
        _autoName = pick.name;
      }
      if (_settlement != null &&
          _settlement!.currency.toUpperCase() != _securityCurrency) {
        _settlement = null;
      }
    });
  }

  Future<void> _pickSettlement() async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    final result = await AccountCardPicker.show(
      context,
      ledgerId: ledgerId,
      selectedAccountId: _settlement?.id,
      excludeAccountId: widget.account.id,
      // v1 不支援跨幣別定期定額:到期生成的轉帳金額以證券幣別計、直接從交割戶
      // 扣,幣別不同會扣錯(Cloud 也會擋)。以前允許選任何幣別,結果每次啟動
      // createStockTrade 都丟 StockTradeSettlementAmountRequired。
      filterCurrency: _securityCurrency,
    );
    if (result?.accountId == null) return;
    final acc =
        await ref.read(repositoryProvider).getAccount(result!.accountId!);
    if (!mounted || acc == null) return;
    setState(() => _settlement = acc);
  }

  Future<void> _pickSchedule() async {
    final result = await RecurringRuleAdvancedSheet.show(
      context,
      anchorDate: _nextRunAt,
      initialDraft: _draft,
    );
    if (result == null || result.recurring == null || !mounted) return;
    setState(() => _draft = result.recurring!);
  }

  Future<void> _pickNextRunAt() async {
    final min = _minNextRunAt;
    final res = await showAppDatePicker(context,
        initial: _nextRunAt.isBefore(min) ? min : _nextRunAt, minDate: min);
    if (res == null) return;
    setState(() {
      // 只選日期,時間固定 09:00(同新建預設);選今天且已過 9 點 = 下次生成就執行。
      _nextRunAt = DateTime(res.year, res.month, res.day, 9);
      // 進階規則「每月 N 號」是用打開週期設定當下的日期當錨點,改了下次執行日要
      // 跟著改,不然第一期用新日期、之後又跳回舊的 N 號。
      final adv = _draft.advancedRule;
      if (adv != null && adv['type'] == 'monthly_day') {
        _draft = RecurringRuleDraft(
          frequency: _draft.frequency,
          interval: _draft.interval,
          advancedRule: {...adv, 'day': res.day},
          endAt: _draft.endAt,
        );
      }
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final symbol = _symbolCtrl.text.trim().toUpperCase();
    if (!_isEditing && symbol.isEmpty) {
      return showToast(context, l10n.recurringStockSecurityRequired);
    }
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      return showToast(context, l10n.recurringStockAmountRequired);
    }
    if (_settlement == null) {
      return showToast(context, l10n.stockSettlementRequired);
    }
    if (_settlement!.currency.toUpperCase() != _securityCurrency) {
      return showToast(context, l10n.recurringStockSettlementCurrencyMismatch);
    }

    double? feeRate;
    double? feeMin;
    if (_customFee) {
      final ratePercent = double.tryParse(_feeRatePercentCtrl.text.trim());
      feeRate = ratePercent == null ? null : ratePercent / 100;
      feeMin = double.tryParse(_feeMinCtrl.text.trim());
    }

    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    setState(() => _saving = true);
    try {
      final repo = ref.read(repositoryProvider);
      if (_isEditing) {
        final rule = widget.rule!;
        final hadEndAt = rule.endAt != null;
        await repo.updateRuleAndFuture(
          ruleId: rule.id,
          amount: amount,
          fromAccountId: _settlement!.id,
          note: note,
          frequency: _draft.frequency,
          interval: _draft.interval,
          advancedRule: _draft.advancedRule,
          nextRunAt: _nextRunAt,
          endAt: _draft.endAt,
          clearEndAt: hadEndAt && _draft.endAt == null,
          stockFeeRate: feeRate,
          clearStockFeeRate: !_customFee,
          stockFeeMin: feeMin,
          clearStockFeeMin: !_customFee,
        );
      } else {
        await repo.createRule(
          ledgerId: ref.read(currentLedgerIdProvider),
          type: 'transfer',
          amount: amount,
          fromAccountId: _settlement!.id,
          toAccountId: widget.account.id,
          note: note,
          frequency: _draft.frequency,
          interval: _draft.interval,
          advancedRule: _draft.advancedRule,
          nextRunAt: _nextRunAt,
          endAt: _draft.endAt,
          kind: 'stock_dca',
          market: _market,
          symbol: symbol,
          securityName:
              _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
          stockFeeRate: feeRate,
          stockFeeMin: feeMin,
        );
      }
      final int ledgerId =
          widget.rule != null ? widget.rule!.ledgerId : ref.read(currentLedgerIdProvider);
      // 已經到期的(例如選今天)不用等下次開 App:存檔後立刻補抓報價並生成一次。
      var generated = 0;
      if (!_nextRunAt.isAfter(DateTime.now())) {
        try {
          await ref
              .read(quoteRefreshProvider.notifier)
              .refreshForStockDcaRules()
              .timeout(const Duration(seconds: 8));
        } catch (_) {
          // 抓不到報價就用快取,那期會照舊在下次啟動時重試。
        }
        generated = (await repo.materializeDueStockRules()).materialized;
      }
      ref.invalidate(countsForLedgerProvider(ledgerId));
      ref.read(statsRefreshProvider.notifier).state++;
      PostProcessor.sync(ref, ledgerId: ledgerId);
      if (!mounted) return;
      showToast(
          context,
          generated > 0
              ? l10n.recurringStockGeneratedNow(generated)
              : l10n.commonSaved);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showToast(context, '${l10n.commonFailed}: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialog.confirm<bool>(
          context,
          title: l10n.recurringRuleDeleteConfirmTitle,
          message: l10n.recurringRuleDeleteConfirmMessage,
        ) ??
        false;
    if (!confirmed || !mounted) return;
    final repo = ref.read(repositoryProvider);
    final rule = widget.rule!;
    await repo.deleteRule(rule.id, deleteFutureOccurrences: true);
    ref.invalidate(countsForLedgerProvider(rule.ledgerId));
    ref.read(statsRefreshProvider.notifier).state++;
    PostProcessor.sync(ref, ledgerId: rule.ledgerId);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gap = SizedBox(height: 12.0.scaled(context, ref));
    final cloudAvailable =
        ref.watch(securitiesCloudAvailableProvider).valueOrNull ?? false;

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: _isEditing
                ? l10n.recurringStockEditTitle
                : l10n.recurringStockAddTitle,
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
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: _row(context,
                      label: l10n.recurringStockInvestmentAccountLabel,
                      value: '${widget.account.name} · ${widget.account.currency}'),
                ),
                gap,
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
                              onChanged: _onSymbolChanged,
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
                          controller: _nameCtrl,
                          label: l10n.stockSecurityName,
                          enabled: !_isEditing),
                    ],
                  ),
                ),
                gap,
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _field(
                        context,
                        controller: _amountCtrl,
                        label:
                            '${l10n.recurringStockInvestAmountLabel} ($_securityCurrency)',
                        numeric: true,
                      ),
                      _dcaPreview(context, l10n),
                      _divider(context),
                      _row(
                        context,
                        label: l10n.stockSettlementAccount,
                        value: _settlement == null
                            ? l10n.stockSettlementRequired
                            : '${_settlement!.name} · ${_settlement!.currency}',
                        onTap: _pickSettlement,
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(l10n.recurringStockCustomFeeLabel,
                                style: TextStyle(
                                    color: BeeTokens.textPrimary(context))),
                          ),
                          Switch(
                            value: _customFee,
                            onChanged: (v) => setState(() {
                              _customFee = v;
                              if (v &&
                                  _feeRatePercentCtrl.text.trim().isEmpty) {
                                final fees = _effectiveAccountFees;
                                _feeRatePercentCtrl.text =
                                    _num((fees.feeRate ?? 0) * 100);
                                _feeMinCtrl.text = _num(fees.feeMin ?? 0);
                              }
                            }),
                          ),
                        ],
                      ),
                      Text(l10n.recurringStockCustomFeeHint,
                          style: TextStyle(
                              fontSize: 12,
                              color: BeeTokens.textTertiary(context))),
                      if (_customFee) ...[
                        const SizedBox(height: 8),
                        _divider(context),
                        _field(
                          context,
                          controller: _feeRatePercentCtrl,
                          label: '${l10n.recurringStockFeeRateLabel} (%)',
                          numeric: true,
                        ),
                        _divider(context),
                        _field(
                          context,
                          controller: _feeMinCtrl,
                          label:
                              '${l10n.recurringStockFeeMinLabel} ($_securityCurrency)',
                          numeric: true,
                        ),
                      ],
                    ],
                  ),
                ),
                gap,
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _row(context,
                          label: l10n.recurringFieldFrequency,
                          value: _draft.summary(l10n),
                          onTap: _pickSchedule),
                      _divider(context),
                      _row(context,
                          label: l10n.recurringFieldNextRunAt,
                          value: _fmtDate(_nextRunAt),
                          onTap: _pickNextRunAt),
                    ],
                  ),
                ),
                gap,
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: _field(context,
                      controller: _noteCtrl, label: l10n.stockNote),
                ),
                SizedBox(height: 24.0.scaled(context, ref)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

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
    bool enabled = true,
    TextCapitalization textCapitalization = TextCapitalization.none,
    FocusNode? focusNode,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      enabled: enabled,
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
        border: InputBorder.none,
      ),
    );
  }
}
