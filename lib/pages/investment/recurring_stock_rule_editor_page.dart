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

  const RecurringStockRuleEditorPage({
    super.key,
    required this.account,
    this.rule,
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

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

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
      _nextRunAt = r.nextRunAt;
      _draft = RecurringRuleDraft(
        frequency: r.frequency,
        interval: r.interval,
        advancedRule: _decodeAdvancedRule(r.advancedRuleJson),
        endAt: r.endAt,
      );
      _customFee = r.stockFeeRate != null || r.stockFeeMin != null;
      if (_customFee) {
        _feeRatePercentCtrl.text =
            _num((r.stockFeeRate ?? _accountSettings.feeRate ?? 0) * 100);
        _feeMinCtrl.text = _num(r.stockFeeMin ?? _accountSettings.feeMin ?? 0);
      }
      if (r.fromAccountId != null) _loadSettlementFor(r.fromAccountId!);
    } else {
      _market = _accountSettings.market ??
          _defaultMarketFor(widget.account.currency);
      _nextRunAt = DateTime.now();
      _loadDefaultSettlement();
    }
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
    if (mounted && acc != null) setState(() => _settlement = acc);
  }

  Future<void> _loadSettlementFor(int accountId) async {
    final repo = ref.read(repositoryProvider);
    final acc = await repo.getAccount(accountId);
    if (mounted && acc != null) setState(() => _settlement = acc);
  }

  @override
  void dispose() {
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
    setState(() => _market = picked);
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
      allowAllCurrencies: true,
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
    final res = await showAppDatePicker(context, initial: _nextRunAt);
    if (res != null) setState(() => _nextRunAt = res);
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
      ref.invalidate(countsForLedgerProvider(ledgerId));
      ref.read(statsRefreshProvider.notifier).state++;
      PostProcessor.sync(ref, ledgerId: ledgerId);
      if (!mounted) return;
      showToast(context, l10n.commonSaved);
      Navigator.of(context).pop(true);
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
                                _feeRatePercentCtrl.text = _num(
                                    (_accountSettings.feeRate ?? 0) * 100);
                                _feeMinCtrl.text =
                                    _num(_accountSettings.feeMin ?? 0);
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
  }) {
    return TextField(
      controller: controller,
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
