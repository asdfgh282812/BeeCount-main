import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../styles/tokens.dart';
import '../../utils/currencies.dart';
import '../../widgets/biz/account_card_picker.dart';
import '../../widgets/biz/card_reward_rule_selector.dart';
import '../../widgets/biz/category_selector_dialog.dart';
import '../../widgets/biz/section_card.dart';
import '../tag/widgets/tag_selector.dart';
import '../../widgets/ui/ui.dart';

/// 週期性規則的完整編輯頁——對齊 Web 端規則編輯 Modal 的欄位集合(類型/金額/
/// 分類/帳戶/商家/標籤/紅利回饋規則/頻率/間隔/下次執行時間/結束時間)。
///
/// 存檔時一律走 [RecurringRuleRepository.updateRuleAndFuture]:更新規則本身
/// + 批次套用到「未來、未被單獨編輯過」的既有 occurrence 交易——這是刻意跟
/// Web 不同的新行為(Web 的規則編輯 Modal 只改規則本身,不回頭套用到已生成
/// 的交易),使用者已確認要這個行為,見 docs/changes 說明。
///
/// [anchorTransactionId] 決定批次更新的起點:
/// - null:從規則列表頁「編輯」直接進來,起點 = 現在。
/// - 非 null:從某一筆 occurrence 的「連同以後」進來,起點 = 那一筆的
///   `happenedAt`。除了起點不同,其餘欄位/流程完全一致,所以共用同一頁。
///
/// 進階規則(星期幾/每月第幾天)刻意不開放編輯——已生成的 occurrence 日期不
/// 會回頭搬動,重新配置星期/日期模式對既有規則沒有實際意義,跟 Web 編輯
/// Modal 隱藏進階規則區塊的理由一致(見 `RecurringRulesPanel.tsx` 對應註解)。
class RecurringRuleEditorPage extends ConsumerStatefulWidget {
  final RecurringTransaction rule;
  final int? anchorTransactionId;

  const RecurringRuleEditorPage({
    super.key,
    required this.rule,
    this.anchorTransactionId,
  });

  @override
  ConsumerState<RecurringRuleEditorPage> createState() =>
      _RecurringRuleEditorPageState();
}

class _RecurringRuleEditorPageState
    extends ConsumerState<RecurringRuleEditorPage> {
  late final TextEditingController _amountController;
  late final TextEditingController _merchantController;
  late final String _type;

  int? _categoryId;
  String? _categoryName;

  int? _accountId;
  String? _accountName;
  String? _accountType;

  int? _fromAccountId;
  String? _fromAccountName;
  int? _toAccountId;
  String? _toAccountName;

  List<int> _selectedTagIds = [];
  List<Tag> _allTags = const [];
  List<String> _selectedRewardRuleSyncIds = [];

  late String _frequency;
  late int _interval;
  late DateTime _nextRunAt;
  DateTime? _endAt;

  bool _isLoading = true;
  bool _isSaving = false;

  bool get _isTransfer => _type == 'transfer';
  bool get _rewardRuleSelectionEnabled =>
      !_isTransfer && _accountType == 'credit_card';

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    _type = r.type;
    _amountController = TextEditingController(text: _formatAmount(r.amount));
    _merchantController = TextEditingController(text: r.merchant ?? '');
    _categoryId = r.categoryId;
    _accountId = r.accountId;
    _fromAccountId = r.fromAccountId;
    _toAccountId = r.toAccountId;
    _selectedRewardRuleSyncIds = List.of(r.rewardRuleIds);
    _frequency = r.frequency;
    _interval = r.interval;
    _nextRunAt = r.nextRunAt;
    _endAt = r.endAt;
    _loadDisplayData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    super.dispose();
  }

  String _formatAmount(double amount) {
    return amount == amount.truncateToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }

  Future<void> _loadDisplayData() async {
    final repo = ref.read(repositoryProvider);
    final r = widget.rule;
    if (r.categoryId != null) {
      final cat = await repo.getCategoryById(r.categoryId!);
      if (cat != null) _categoryName = cat.name;
    }
    if (r.accountId != null) {
      final acc = await repo.getAccount(r.accountId!);
      if (acc != null) {
        _accountName = acc.name;
        _accountType = acc.type;
      }
    }
    if (r.fromAccountId != null) {
      final acc = await repo.getAccount(r.fromAccountId!);
      if (acc != null) _fromAccountName = acc.name;
    }
    if (r.toAccountId != null) {
      final acc = await repo.getAccount(r.toAccountId!);
      if (acc != null) _toAccountName = acc.name;
    }
    _allTags = await repo.getAllTags();
    if (r.tagSyncIds.isNotEmpty) {
      final bySync = {
        for (final t in _allTags)
          if (t.syncId != null) t.syncId!: t.id,
      };
      _selectedTagIds =
          r.tagSyncIds.map((s) => bySync[s]).whereType<int>().toList();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_isLoading) {
      return Scaffold(
        backgroundColor: BeeTokens.scaffoldBackground(context),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.recurringRuleEditTitle,
            showBack: true,
            compact: true,
            actions: [
              TextButton(
                onPressed: _isSaving ? null : _save,
                child: Text(
                  l10n.commonSave,
                  style: TextStyle(
                    color: BeeTokens.textPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildLabeledCard(
                  context,
                  label: l10n.recurringFieldType,
                  child: Text(
                    _typeLabel(l10n),
                    style: TextStyle(
                      fontSize: 16,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildLabeledCard(
                  context,
                  label: l10n.budgetAmountLabel,
                  child: _buildAmountField(context),
                ),
                const SizedBox(height: 12),
                if (!_isTransfer) ...[
                  _buildLabeledCard(
                    context,
                    label: l10n.budgetCategoryLabel,
                    child: _buildTapRow(
                      context,
                      value: _categoryName,
                      hint: l10n.budgetCategoryHint,
                      onTap: _selectCategory,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildLabeledCard(
                    context,
                    label: l10n.recurringFieldAccount,
                    child: _buildTapRow(
                      context,
                      value: _accountName,
                      hint: l10n.transferSelectAccount,
                      onTap: () => _selectAccount(isFrom: true),
                    ),
                  ),
                ] else ...[
                  _buildLabeledCard(
                    context,
                    label: l10n.transferFromAccount,
                    child: _buildTapRow(
                      context,
                      value: _fromAccountName,
                      hint: l10n.transferSelectAccount,
                      onTap: () => _selectAccount(isFrom: true),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildLabeledCard(
                    context,
                    label: l10n.transferToAccount,
                    child: _buildTapRow(
                      context,
                      value: _toAccountName,
                      hint: l10n.transferSelectAccount,
                      onTap: () => _selectAccount(isFrom: false),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _buildLabeledCard(
                  context,
                  label: l10n.recurringFieldMerchant,
                  child: TextField(
                    key: const Key('recurringEditorMerchantField'),
                    controller: _merchantController,
                    style: TextStyle(
                        fontSize: 16, color: BeeTokens.textPrimary(context)),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildLabeledCard(
                  context,
                  label: l10n.recurringFieldTags,
                  child: _buildTagRow(context, l10n),
                ),
                if (_rewardRuleSelectionEnabled) ...[
                  const SizedBox(height: 12),
                  _buildLabeledCard(
                    context,
                    label: l10n.cardRewardRuleEntryLabel,
                    child: _buildRewardRuleRow(context, l10n),
                  ),
                ],
                const SizedBox(height: 12),
                _buildLabeledCard(
                  context,
                  label: l10n.recurringFieldFrequency,
                  child: _buildFrequencyRow(context, l10n),
                ),
                const SizedBox(height: 12),
                _buildLabeledCard(
                  context,
                  label: l10n.recurringFieldNextRunAt,
                  child: _buildTapRow(
                    context,
                    value: _fmtDateTime(_nextRunAt),
                    hint: '',
                    onTap: _pickNextRunAt,
                  ),
                ),
                const SizedBox(height: 12),
                _buildLabeledCard(
                  context,
                  label: l10n.recurringFieldEndAtOptional,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTapRow(
                          context,
                          value: _endAt == null ? null : _fmtDateTime(_endAt!),
                          hint: l10n.recurringSummaryUnlimited,
                          onTap: _pickEndAt,
                        ),
                      ),
                      if (_endAt != null)
                        IconButton(
                          icon: Icon(Icons.clear,
                              color: BeeTokens.iconTertiary(context)),
                          onPressed: () => setState(() => _endAt = null),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabeledCard(BuildContext context,
      {required String label, required Widget child}) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: BeeTokens.textSecondary(context),
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildTapRow(
    BuildContext context, {
    required String? value,
    required String hint,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: BeeTokens.surface(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: BeeTokens.border(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? hint,
                style: TextStyle(
                  fontSize: 16,
                  color: value == null
                      ? BeeTokens.textTertiary(context)
                      : BeeTokens.textPrimary(context),
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: BeeTokens.iconTertiary(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountField(BuildContext context) {
    final currencyCode =
        ref.watch(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    return TextField(
      key: const Key('recurringEditorAmountField'),
      controller: _amountController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
      ],
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: BeeTokens.textPrimary(context),
      ),
      decoration: InputDecoration(
        prefixText: '${getCurrencySymbol(currencyCode)} ',
        border: InputBorder.none,
        isDense: true,
      ),
    );
  }

  Widget _buildTagRow(BuildContext context, AppLocalizations l10n) {
    final selected =
        _allTags.where((t) => _selectedTagIds.contains(t.id)).toList();
    return InkWell(
      onTap: _selectTags,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: BeeTokens.surface(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: BeeTokens.border(context)),
        ),
        child: selected.isEmpty
            ? Text(l10n.recurringFieldTagsEmpty,
                style: TextStyle(
                    fontSize: 16, color: BeeTokens.textTertiary(context)))
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: selected
                    .map((t) => Chip(
                          label: Text(t.name),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
      ),
    );
  }

  Widget _buildRewardRuleRow(BuildContext context, AppLocalizations l10n) {
    return InkWell(
      onTap: _selectRewardRules,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: BeeTokens.surface(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: BeeTokens.border(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selectedRewardRuleSyncIds.isEmpty
                    ? l10n.cardRewardRuleNoRewardAccount
                    : l10n.cardRewardRuleSelectedCount(
                        _selectedRewardRuleSyncIds.length),
                style: TextStyle(
                  fontSize: 16,
                  color: _selectedRewardRuleSyncIds.isEmpty
                      ? BeeTokens.textTertiary(context)
                      : BeeTokens.textPrimary(context),
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: BeeTokens.iconTertiary(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildFrequencyRow(BuildContext context, AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            initialValue: _frequency,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
            ),
            items: [
              DropdownMenuItem(
                  value: 'daily', child: Text(l10n.recurringUnitDay)),
              DropdownMenuItem(
                  value: 'weekly', child: Text(l10n.recurringUnitWeek)),
              DropdownMenuItem(
                  value: 'monthly', child: Text(l10n.recurringUnitMonth)),
              DropdownMenuItem(
                  value: 'yearly', child: Text(l10n.recurringUnitYear)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _frequency = v);
            },
          ),
        ),
        const SizedBox(width: 12),
        Text(l10n.recurringFieldInterval,
            style: TextStyle(
                fontSize: 13, color: BeeTokens.textSecondary(context))),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: _interval > 1
              ? () => setState(() => _interval -= 1)
              : null,
        ),
        Text('$_interval',
            style: TextStyle(
                fontSize: 16, color: BeeTokens.textPrimary(context))),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => setState(() => _interval += 1),
        ),
      ],
    );
  }

  String _typeLabel(AppLocalizations l10n) {
    switch (_type) {
      case 'income':
        return l10n.categoryIncome;
      case 'transfer':
        return l10n.transferTitle;
      default:
        return l10n.categoryExpense;
    }
  }

  String _fmtDateTime(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} $h:$m';
  }

  Future<void> _selectCategory() async {
    final selected = await showCategorySelector(
      context,
      type: _type,
      currentCategoryId: _categoryId,
    );
    if (selected != null) {
      setState(() {
        _categoryId = selected.id;
        _categoryName = selected.name;
      });
    }
  }

  Future<void> _selectAccount({required bool isFrom}) async {
    final ledgerId = widget.rule.ledgerId;
    final result = await AccountCardPicker.show(
      context,
      ledgerId: ledgerId,
      selectedAccountId: _isTransfer
          ? (isFrom ? _fromAccountId : _toAccountId)
          : _accountId,
      excludeAccountId: _isTransfer
          ? (isFrom ? _toAccountId : _fromAccountId)
          : null,
    );
    if (result == null || !mounted) return;
    final id = result.accountId;
    if (id == null) return;
    final repo = ref.read(repositoryProvider);
    final acc = await repo.getAccount(id);
    if (!mounted) return;
    setState(() {
      if (_isTransfer) {
        if (isFrom) {
          _fromAccountId = id;
          _fromAccountName = acc?.name;
        } else {
          _toAccountId = id;
          _toAccountName = acc?.name;
        }
      } else {
        _accountId = id;
        _accountName = acc?.name;
        _accountType = acc?.type;
        // 換帳戶時清掉舊選的回饋規則——規則綁定特定信用卡帳戶,換帳戶後舊選
        // 擇不再有意義,寫入也會被 server 校驗擋掉。
        _selectedRewardRuleSyncIds = [];
      }
    });
  }

  Future<void> _selectTags() async {
    final result = await TagSelector.show(context, selectedTagIds: _selectedTagIds);
    if (result != null) setState(() => _selectedTagIds = result);
  }

  Future<void> _selectRewardRules() async {
    if (_accountId == null) return;
    final result = await CardRewardRuleSelector.show(
      context,
      accountId: _accountId!,
      selectedSyncIds: _selectedRewardRuleSyncIds,
    );
    if (result != null) setState(() => _selectedRewardRuleSyncIds = result);
  }

  Future<void> _pickNextRunAt() async {
    final res =
        await showTransactionDatePicker(context, initial: _nextRunAt);
    if (res != null) setState(() => _nextRunAt = res);
  }

  Future<void> _pickEndAt() async {
    final res = await showTransactionDatePicker(
      context,
      initial: _endAt ?? _nextRunAt,
      minDate: _nextRunAt,
    );
    if (res != null) setState(() => _endAt = res);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      showToast(context, l10n.budgetAmountHint);
      return;
    }
    if (!_isTransfer && _categoryId == null) {
      showToast(context, l10n.budgetCategoryHint);
      return;
    }
    if (_isTransfer && (_fromAccountId == null || _toAccountId == null)) {
      showToast(context, l10n.transferSelectAccount);
      return;
    }
    if (!_isTransfer && _accountId == null) {
      showToast(context, l10n.transferSelectAccount);
      return;
    }

    final confirmed = await AppDialog.confirm<bool>(
          context,
          title: l10n.recurringApplyFutureConfirmTitle,
          message: l10n.recurringApplyFutureConfirmMessage,
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(repositoryProvider);
      final tagSyncIds = _allTags
          .where((t) => _selectedTagIds.contains(t.id))
          .map((t) => t.syncId)
          .whereType<String>()
          .toList();
      final hadEndAt = widget.rule.endAt != null;
      final clearEndAt = hadEndAt && _endAt == null;

      await repo.updateRuleAndFuture(
        ruleId: widget.rule.id,
        anchorTransactionId: widget.anchorTransactionId,
        amount: amount,
        categoryId: _isTransfer ? null : _categoryId,
        accountId: _isTransfer ? null : _accountId,
        fromAccountId: _isTransfer ? _fromAccountId : null,
        toAccountId: _isTransfer ? _toAccountId : null,
        merchant: _merchantController.text.trim().isEmpty
            ? null
            : _merchantController.text.trim(),
        tagSyncIds: tagSyncIds,
        rewardRuleSyncIds: _selectedRewardRuleSyncIds,
        frequency: _frequency,
        interval: _interval,
        nextRunAt: _nextRunAt,
        endAt: _endAt,
        clearEndAt: clearEndAt,
      );

      final ledgerId = widget.rule.ledgerId;
      ref.invalidate(countsForLedgerProvider(ledgerId));
      ref.read(statsRefreshProvider.notifier).state++;
      PostProcessor.sync(ref, ledgerId: ledgerId);

      if (!mounted) return;
      showToast(context, l10n.commonSaved);
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
