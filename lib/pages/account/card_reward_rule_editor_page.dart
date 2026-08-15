import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/repositories/local/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../styles/tokens.dart';
import '../../widgets/biz/account_card_picker.dart';
import '../../widgets/biz/card_reward_rule_actions.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';

/// 信用卡紅利回饋規則的新增/編輯頁。
///
/// 欄位對照 BeeCount Cloud 確認過的 schema(見
/// docs/changes/2026-08-16-card-reward-rules.md)。`locked` 語意——規則已有
/// 交易/入帳紀錄掛著時計算類欄位不可再編輯——server 端只在 web 專用 REST
/// read endpoint 才會計算回傳,generic sync pull 拿不到,這裡用本地代理判斷
/// (本地是否有交易的 rewardRuleIds 命中這條規則),見 [_checkLocked]。
class CardRewardRuleEditorPage extends ConsumerStatefulWidget {
  /// 綁定的信用卡帳戶(本地 int id)。新增模式下由入口帶入、不給改;
  /// 編輯模式下取自 [rule].accountId,傳入值僅供保險起見一致性校驗。
  final int accountId;
  final String accountName;

  /// 要編輯的規則,為空表示新增。
  final CardRewardRule? rule;

  const CardRewardRuleEditorPage({
    super.key,
    required this.accountId,
    required this.accountName,
    this.rule,
  });

  @override
  ConsumerState<CardRewardRuleEditorPage> createState() =>
      _CardRewardRuleEditorPageState();
}

class _CardRewardRuleEditorPageState
    extends ConsumerState<CardRewardRuleEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelCtrl;
  late final TextEditingController _rateValueCtrl;
  late final TextEditingController _minSpendThresholdCtrl;
  late final TextEditingController _minTxAmountCtrl;
  late final TextEditingController _capAmountCtrl;
  late final TextEditingController _capSharedKeyCtrl;
  late final TextEditingController _settlementDaysCtrl;
  late final TextEditingController _settlementMonthOffsetCtrl;
  late final TextEditingController _settlementDayOfMonthCtrl;
  late final TextEditingController _noteCtrl;

  late String _rateType;
  late String _rounding;
  late String _totalRounding;
  late String _calcBasis;
  late String _interval;
  late String _settlementType;
  late bool _enabled;
  DateTime? _startsAt;
  DateTime? _endsAt;
  int? _rewardAccountId;
  String? _rewardAccountName;

  bool _isSubmitting = false;
  bool _locked = false;
  bool _lockedChecked = false;

  bool get _isEditing => widget.rule != null;

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    _labelCtrl = TextEditingController(text: r?.label ?? '');
    _rateValueCtrl =
        TextEditingController(text: r != null ? _trimZeros(r.rateValue) : '');
    _minSpendThresholdCtrl = TextEditingController(
        text: r?.minSpendThreshold != null
            ? _trimZeros(r!.minSpendThreshold!)
            : '');
    _minTxAmountCtrl = TextEditingController(
        text: r?.minTxAmount != null ? _trimZeros(r!.minTxAmount!) : '');
    _capAmountCtrl = TextEditingController(
        text: r?.capAmount != null ? _trimZeros(r!.capAmount!) : '');
    _capSharedKeyCtrl = TextEditingController(text: r?.capSharedKey ?? '');
    _settlementDaysCtrl =
        TextEditingController(text: r?.settlementDays?.toString() ?? '');
    _settlementMonthOffsetCtrl =
        TextEditingController(text: r?.settlementMonthOffset?.toString() ?? '');
    _settlementDayOfMonthCtrl =
        TextEditingController(text: r?.settlementDayOfMonth?.toString() ?? '');
    _noteCtrl = TextEditingController(text: r?.note ?? '');

    _rateType = r?.rateType ?? 'percentage';
    _rounding = r?.rounding ?? 'round';
    _totalRounding = r?.totalRounding ?? 'round';
    _calcBasis = r?.calcBasis ?? 'transaction_date';
    _interval = r?.interval ?? 'billing_cycle';
    _settlementType = r?.settlementType ?? 'manual';
    _enabled = r?.enabled ?? true;
    _startsAt = r?.startsAt;
    _endsAt = r?.endsAt;
    _rewardAccountId = r?.rewardAccountId;

    if (_rewardAccountId != null) {
      _loadRewardAccountName(_rewardAccountId!);
    }
    if (r?.syncId != null) {
      _checkLocked(r!.syncId!);
    } else {
      _lockedChecked = true;
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _rateValueCtrl.dispose();
    _minSpendThresholdCtrl.dispose();
    _minTxAmountCtrl.dispose();
    _capAmountCtrl.dispose();
    _capSharedKeyCtrl.dispose();
    _settlementDaysCtrl.dispose();
    _settlementMonthOffsetCtrl.dispose();
    _settlementDayOfMonthCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String _trimZeros(double v) {
    final s = v.toStringAsFixed(4);
    return s.contains('.')
        ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : s;
  }

  Future<void> _loadRewardAccountName(int id) async {
    final repo = ref.read(repositoryProvider);
    final acc = repo is LocalRepository
        ? await (repo.db.select(repo.db.accounts)
              ..where((a) => a.id.equals(id)))
            .getSingleOrNull()
        : null;
    if (mounted && acc != null) {
      setState(() => _rewardAccountName = acc.name);
    }
  }

  /// 本地代理判斷「是否已有交易/入帳紀錄掛著這條規則」——本地能看到的只有
  /// 交易的 rewardRuleIds 引用,看不到 server 端的自動入帳紀錄。見本檔案
  /// class doc 的說明,這是已知的不完整近似。
  Future<void> _checkLocked(String syncId) async {
    final repo = ref.read(repositoryProvider);
    if (repo is! LocalRepository) {
      if (mounted) setState(() => _lockedChecked = true);
      return;
    }
    final needle = '"$syncId"';
    final hit = await (repo.db.select(repo.db.transactions)
          ..where((t) => t.rewardRuleIdsJson.like('%$needle%'))
          ..limit(1))
        .getSingleOrNull();
    if (mounted) {
      setState(() {
        _locked = hit != null;
        _lockedChecked = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: _isEditing
                ? l10n.cardRewardRuleEditorTitleEdit
                : l10n.cardRewardRuleEditorTitleNew,
            showBack: true,
            actions: [
              if (_isEditing)
                BeePopupMenu(
                  tooltip: l10n.commonMore,
                  items: [
                    BeeMenuItem.action(
                      value: 'copy',
                      icon: Icons.copy_outlined,
                      label: l10n.cardRewardRuleCopy,
                    ),
                    BeeMenuItem.action(
                      value: 'delete',
                      icon: Icons.delete_outline,
                      label: l10n.cardRewardRuleDelete,
                      isDanger: true,
                    ),
                  ],
                  onSelected: _onMenuSelected,
                ),
              TextButton(
                onPressed: _isSubmitting || !_lockedChecked ? null : _submit,
                child: Text(
                  l10n.commonSave,
                  style: TextStyle(
                    color: _isSubmitting
                        ? BeeTokens.textTertiary(context)
                        : BeeTokens.textPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  if (_locked) _buildLockedBanner(l10n),
                  _buildBasicSection(l10n),
                  const SizedBox(height: 16),
                  _buildRateSection(l10n),
                  const SizedBox(height: 16),
                  _buildMechanismSection(l10n),
                  const SizedBox(height: 16),
                  _buildThresholdSection(l10n),
                  const SizedBox(height: 16),
                  _buildRoundingSection(l10n),
                  const SizedBox(height: 16),
                  _buildCapSection(l10n),
                  const SizedBox(height: 16),
                  _buildOtherSection(l10n),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedBanner(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: BeeTokens.warning(context).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline,
                size: 18, color: BeeTokens.warning(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.cardRewardRuleLockedHint,
                style: TextStyle(
                    fontSize: 12.5, color: BeeTokens.warning(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: BeeTokens.textSecondary(context),
          ),
        ),
      );

  InputDecoration _dec({String? hint, String? suffixText}) => InputDecoration(
        hintText: hint,
        suffixText: suffixText,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );

  Widget _buildBasicSection(AppLocalizations l10n) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(l10n.cardRewardRuleLabelField),
          TextFormField(
            controller: _labelCtrl,
            decoration: _dec(hint: l10n.cardRewardRuleLabelHint),
            maxLength: 255,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? l10n.cardRewardRuleLabelHint
                : null,
          ),
          const SizedBox(height: 8),
          _sectionLabel(l10n.cardRewardRuleAccountField),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: BeeTokens.surfaceInput(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(widget.accountName,
                style: TextStyle(color: BeeTokens.textPrimary(context))),
          ),
        ],
      ),
    );
  }

  Widget _buildRateSection(AppLocalizations l10n) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(l10n.cardRewardRuleRateTypeField),
          DropdownButtonFormField<String>(
            initialValue: _rateType,
            decoration: _dec(),
            items: [
              DropdownMenuItem(
                  value: 'percentage',
                  child: Text(l10n.cardRewardRuleRateTypePercentage)),
              DropdownMenuItem(
                  value: 'fixed_amount',
                  child: Text(l10n.cardRewardRuleRateTypeFixedAmount)),
            ],
            onChanged: _locked
                ? null
                : (v) => setState(() => _rateType = v ?? 'percentage'),
          ),
          const SizedBox(height: 8),
          _sectionLabel(_rateType == 'percentage'
              ? l10n.cardRewardRuleRateValuePercentField
              : l10n.cardRewardRuleRateValueFixedField),
          TextFormField(
            controller: _rateValueCtrl,
            enabled: !_locked,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:
                _dec(suffixText: _rateType == 'percentage' ? '%' : null),
            validator: (v) {
              final parsed = double.tryParse(v?.trim() ?? '');
              if (parsed == null || parsed <= 0) return l10n.commonError;
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMechanismSection(AppLocalizations l10n) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(l10n.cardRewardRuleMechanismSection),
          _sectionLabel(l10n.cardRewardRuleIntervalField),
          DropdownButtonFormField<String>(
            initialValue: _interval,
            decoration: _dec(),
            items: [
              DropdownMenuItem(
                  value: 'billing_cycle',
                  child: Text(l10n.cardRewardRuleIntervalBillingCycle)),
              DropdownMenuItem(
                  value: 'calendar_month',
                  child: Text(l10n.cardRewardRuleIntervalCalendarMonth)),
            ],
            onChanged: _locked
                ? null
                : (v) => setState(() => _interval = v ?? 'billing_cycle'),
          ),
          const SizedBox(height: 12),
          _sectionLabel(l10n.cardRewardRuleCalcBasisField),
          DropdownButtonFormField<String>(
            initialValue: _calcBasis,
            decoration: _dec(),
            items: [
              DropdownMenuItem(
                  value: 'transaction_date',
                  child: Text(l10n.cardRewardRuleCalcBasisTransactionDate)),
              DropdownMenuItem(
                  value: 'settlement_date',
                  child: Text(l10n.cardRewardRuleCalcBasisSettlementDate)),
            ],
            onChanged: _locked
                ? null
                : (v) => setState(() => _calcBasis = v ?? 'transaction_date'),
          ),
          const SizedBox(height: 12),
          _sectionLabel(l10n.cardRewardRuleSettlementTypeField),
          DropdownButtonFormField<String>(
            initialValue: _settlementType,
            decoration: _dec(),
            items: [
              DropdownMenuItem(
                  value: 'immediate_after_tx',
                  child: Text(l10n.cardRewardRuleSettlementImmediate)),
              DropdownMenuItem(
                  value: 'after_posting_date',
                  child: Text(l10n.cardRewardRuleSettlementAfterPostingDate)),
              DropdownMenuItem(
                  value: 'period_end',
                  child: Text(l10n.cardRewardRuleSettlementPeriodEnd)),
              DropdownMenuItem(
                  value: 'manual',
                  child: Text(l10n.cardRewardRuleSettlementManual)),
            ],
            onChanged: _locked
                ? null
                : (v) => setState(() => _settlementType = v ?? 'manual'),
          ),
          if (_settlementType == 'after_posting_date') ...[
            const SizedBox(height: 12),
            _sectionLabel(l10n.cardRewardRuleSettlementDayOfMonthField),
            TextFormField(
              controller: _settlementDaysCtrl,
              enabled: !_locked,
              keyboardType: TextInputType.number,
              decoration: _dec(),
            ),
          ],
          if (_settlementType == 'period_end') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel(
                          l10n.cardRewardRuleSettlementMonthOffsetField),
                      TextFormField(
                        controller: _settlementMonthOffsetCtrl,
                        enabled: !_locked,
                        keyboardType: TextInputType.number,
                        decoration: _dec(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel(
                          l10n.cardRewardRuleSettlementDayOfMonthField),
                      TextFormField(
                        controller: _settlementDayOfMonthCtrl,
                        enabled: !_locked,
                        keyboardType: TextInputType.number,
                        decoration: _dec(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildThresholdSection(AppLocalizations l10n) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(l10n.cardRewardRuleThresholdSection),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(l10n.cardRewardRuleMinSpendThresholdField),
                    TextFormField(
                      controller: _minSpendThresholdCtrl,
                      enabled: !_locked,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: _dec(hint: l10n.cardRewardRuleNoThreshold),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(l10n.cardRewardRuleMinTxAmountField),
                    TextFormField(
                      controller: _minTxAmountCtrl,
                      enabled: !_locked,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: _dec(hint: l10n.cardRewardRuleNoThreshold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roundingDropdown({
    required String value,
    required ValueChanged<String?> onChanged,
    required AppLocalizations l10n,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: _dec(),
      items: [
        DropdownMenuItem(
            value: 'floor', child: Text(l10n.cardRewardRuleRoundingFloor)),
        DropdownMenuItem(
            value: 'round', child: Text(l10n.cardRewardRuleRoundingRound)),
        DropdownMenuItem(
            value: 'ceil', child: Text(l10n.cardRewardRuleRoundingCeil)),
        DropdownMenuItem(
            value: 'keep', child: Text(l10n.cardRewardRuleRoundingKeep)),
      ],
      onChanged: _locked ? null : onChanged,
    );
  }

  Widget _buildRoundingSection(AppLocalizations l10n) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(l10n.cardRewardRuleCalcSection),
          _sectionLabel(l10n.cardRewardRuleRoundingField),
          _roundingDropdown(
            value: _rounding,
            onChanged: (v) => setState(() => _rounding = v ?? 'round'),
            l10n: l10n,
          ),
          const SizedBox(height: 12),
          _sectionLabel(l10n.cardRewardRuleTotalRoundingField),
          _roundingDropdown(
            value: _totalRounding,
            onChanged: (v) => setState(() => _totalRounding = v ?? 'round'),
            l10n: l10n,
          ),
        ],
      ),
    );
  }

  Widget _buildCapSection(AppLocalizations l10n) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(l10n.cardRewardRuleCapSection),
          _sectionLabel(l10n.cardRewardRuleCapTotalField),
          TextFormField(
            controller: _capAmountCtrl,
            enabled: !_locked,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _dec(hint: l10n.cardRewardRuleCapNoLimit),
          ),
          const SizedBox(height: 12),
          _sectionLabel(l10n.cardRewardRuleCapSharedKeyField),
          TextFormField(
            controller: _capSharedKeyCtrl,
            enabled: !_locked,
            decoration: _dec(hint: l10n.cardRewardRuleCapSharedKeyHint),
          ),
        ],
      ),
    );
  }

  Widget _buildOtherSection(AppLocalizations l10n) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(l10n.cardRewardRuleOtherSection),
          _sectionLabel(l10n.cardRewardRuleRewardAccountField),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _locked ? null : _pickRewardAccount,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: BeeTokens.surfaceInput(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _rewardAccountName ?? l10n.cardRewardRuleNoRewardAccount,
                      style: TextStyle(color: BeeTokens.textPrimary(context)),
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 18, color: BeeTokens.iconSecondary(context)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(l10n.cardRewardRuleStartsAtField),
                    _dateField(_startsAt, (d) {
                      setState(() => _startsAt = d);
                    }),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(l10n.cardRewardRuleEndsAtField),
                    _dateField(_endsAt, (d) {
                      setState(() => _endsAt = d);
                    }, clearable: true),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              l10n.enabled,
              style: TextStyle(
                  fontSize: 14, color: BeeTokens.textPrimary(context)),
            ),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          const SizedBox(height: 8),
          _sectionLabel(l10n.cardRewardRuleNoteField),
          TextFormField(
            controller: _noteCtrl,
            enabled: !_locked,
            maxLines: 4,
            minLines: 2,
            decoration: _dec(hint: l10n.cardRewardRuleNotePlaceholder),
          ),
        ],
      ),
    );
  }

  Widget _dateField(DateTime? value, ValueChanged<DateTime?> onPicked,
      {bool clearable = false}) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: BeeTokens.surfaceInput(context),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value != null
                    ? '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}'
                    : AppLocalizations.of(context).cardRewardRuleNoEndDate,
                style: TextStyle(
                    fontSize: 13, color: BeeTokens.textPrimary(context)),
              ),
            ),
            if (clearable && value != null)
              GestureDetector(
                onTap: () => onPicked(null),
                child: Icon(Icons.close,
                    size: 16, color: BeeTokens.iconTertiary(context)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRewardAccount() async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    final result = await AccountCardPicker.show(
      context,
      ledgerId: ledgerId,
      selectedAccountId: _rewardAccountId,
      allowNull: true,
    );
    if (result == null) return;
    setState(() {
      _rewardAccountId = result.accountId;
      _rewardAccountName = null;
    });
    if (result.accountId != null) {
      await _loadRewardAccountName(result.accountId!);
    }
  }

  Future<void> _onMenuSelected(String value) async {
    final rule = widget.rule;
    if (rule == null) return;
    if (value == 'copy') {
      await duplicateCardRewardRule(context, ref, rule);
      if (mounted) Navigator.of(context).pop();
    } else if (value == 'delete') {
      final deleted = await confirmAndDeleteCardRewardRule(context, ref, rule);
      if (deleted && mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(repositoryProvider);
      final rateValue = double.parse(_rateValueCtrl.text.trim());
      final minSpendThreshold =
          double.tryParse(_minSpendThresholdCtrl.text.trim());
      final minTxAmount = double.tryParse(_minTxAmountCtrl.text.trim());
      final capAmount = double.tryParse(_capAmountCtrl.text.trim());
      final capSharedKey = _capSharedKeyCtrl.text.trim().isEmpty
          ? null
          : _capSharedKeyCtrl.text.trim();
      final settlementDays = int.tryParse(_settlementDaysCtrl.text.trim());
      final settlementMonthOffset =
          int.tryParse(_settlementMonthOffsetCtrl.text.trim());
      final settlementDayOfMonth =
          int.tryParse(_settlementDayOfMonthCtrl.text.trim());
      final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
      final label = _labelCtrl.text.trim();

      if (_isEditing) {
        await repo.updateCardRewardRule(
          widget.rule!.id,
          CardRewardRulesCompanion(
            label: Value(label),
            rateType: Value(_rateType),
            rateValue: Value(rateValue),
            rounding: Value(_rounding),
            totalRounding: Value(_totalRounding),
            calcBasis: Value(_calcBasis),
            interval: Value(_interval),
            minSpendThreshold: Value(minSpendThreshold),
            minTxAmount: Value(minTxAmount),
            capAmount: Value(capAmount),
            capSharedKey: Value(capSharedKey),
            startsAt: Value(_startsAt),
            endsAt: Value(_endsAt),
            settlementType: Value(_settlementType),
            settlementDays: Value(settlementDays),
            settlementMonthOffset: Value(settlementMonthOffset),
            settlementDayOfMonth: Value(settlementDayOfMonth),
            rewardAccountId: Value(_rewardAccountId),
            note: Value(note),
            enabled: Value(_enabled),
          ),
        );
      } else {
        await repo.createCardRewardRule(
          accountId: widget.accountId,
          label: label,
          rateType: _rateType,
          rateValue: rateValue,
          rounding: _rounding,
          totalRounding: _totalRounding,
          calcBasis: _calcBasis,
          interval: _interval,
          minSpendThreshold: minSpendThreshold,
          minTxAmount: minTxAmount,
          capAmount: capAmount,
          capSharedKey: capSharedKey,
          startsAt: _startsAt,
          endsAt: _endsAt,
          settlementType: _settlementType,
          settlementDays: settlementDays,
          settlementMonthOffset: settlementMonthOffset,
          settlementDayOfMonth: settlementDayOfMonth,
          rewardAccountId: _rewardAccountId,
          note: note,
          enabled: _enabled,
        );
      }

      final activeLedgerId = ref.read(currentLedgerIdProvider);
      if (activeLedgerId > 0) {
        unawaited(PostProcessor.sync(ref, ledgerId: activeLedgerId));
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.cardRewardRuleSaveFailed(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
