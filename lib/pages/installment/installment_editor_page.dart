import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../styles/tokens.dart';
import '../../utils/currencies.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/account_card_picker.dart';
import '../../widgets/biz/category_selector_dialog.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';

/// 分期付款新增表單(子專案 1:只有建立,沒有編輯——建立後 totalAmount/
/// periods/firstPeriodAt 都不可改,見 `InstallmentPlans` 表註解;子專案 2
/// 才會加「連同未來重算」等狀態變更操作)。
///
/// 子專案 4(帳單分期沖銷):[initialAccountId]/[initialOffsetExistingBalance]
/// 給 `account_detail_page.dart` 信用卡帳戶詳情頁的「轉為分期」按鈕用——帶
/// 入當下這張卡的 accountId,並直接勾選「沖銷現有欠款」進來,省去使用者
/// 自己再選一次帳戶。一般從分期列表頁 FAB 進入時兩者都是預設值(null/
/// false),行為跟子專案 1~3 完全一樣。
class InstallmentEditorPage extends ConsumerStatefulWidget {
  const InstallmentEditorPage({
    super.key,
    this.initialAccountId,
    this.initialOffsetExistingBalance = false,
  });

  final int? initialAccountId;
  final bool initialOffsetExistingBalance;

  @override
  ConsumerState<InstallmentEditorPage> createState() =>
      _InstallmentEditorPageState();
}

class _InstallmentEditorPageState extends ConsumerState<InstallmentEditorPage> {
  final _totalAmountController = TextEditingController();
  final _periodsController = TextEditingController(text: '12');
  final _interestRateController = TextEditingController(text: '0');
  final _graceController = TextEditingController(text: '0');
  final _noteController = TextEditingController();

  DateTime _firstPeriodAt = DateTime.now();
  String _repaymentMethod = 'equal_principal';
  String _interestPeriod = 'monthly';
  bool _roundAmounts = true;
  String _remainderPosition = 'last';
  bool _advancedExpanded = false;

  int? _accountId;
  Account? _account;
  int? _categoryId;
  Category? _category;
  bool _isLoading = false;

  // 子專案 4:帳單分期沖銷。_offsetableDue 是「這張卡目前還能沖銷多少」的
  // 權威值(跟 repository 建立時的驗證用同一個方法算出來,不會跟實際校驗
  // 對不上),null = 還沒查到(或不適用)。
  bool _offsetExistingBalance = false;
  double? _offsetableDue;
  bool _offsetLoading = false;

  @override
  void initState() {
    super.initState();
    _totalAmountController.addListener(_clampToOffsetableDue);
    final initialAccountId = widget.initialAccountId;
    if (initialAccountId != null) {
      // 用 microtask 而不是直接在 initState 同步呼叫 async 方法——避免第一次
      // build 之前就觸發 setState 的既有寫法疑慮,跟本頁其餘 async 回呼
      // (_pickAccount 等)的風格一致。
      scheduleMicrotask(() => _loadInitialAccount(initialAccountId));
    }
  }

  Future<void> _loadInitialAccount(int accountId) async {
    final repo = ref.read(repositoryProvider);
    final account = await repo.getAccount(accountId);
    if (!mounted || account == null) return;
    setState(() {
      _accountId = accountId;
      _account = account;
    });
    if (widget.initialOffsetExistingBalance) {
      await _setOffsetExistingBalance(true);
    }
  }

  @override
  void dispose() {
    _totalAmountController.removeListener(_clampToOffsetableDue);
    _totalAmountController.dispose();
    _periodsController.dispose();
    _interestRateController.dispose();
    _graceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// 「勾選『沖銷現有欠款』時鎖定 totalAmount 上限為目前欠款金額」
  /// (設計文件 §5.4)——使用者打字超過 [_offsetableDue] 時即時夾回上限,
  /// 不是等存檔才報錯。[_offsetableDue] 本身還沒查到(還在 loading)時不夾。
  void _clampToOffsetableDue() {
    if (!_offsetExistingBalance || _offsetableDue == null) return;
    final due = _offsetableDue!;
    final current = double.tryParse(_totalAmountController.text.trim());
    if (current != null && current > due) {
      final clamped = due.toStringAsFixed(2);
      if (_totalAmountController.text == clamped) return;
      _totalAmountController.value = TextEditingValue(
        text: clamped,
        selection: TextSelection.collapsed(offset: clamped.length),
      );
    }
  }

  /// 切換「沖銷現有欠款」:開啟時去查 [_accountId] 目前可沖銷的應繳餘額
  /// (跟 repository 建立時驗證用同一個方法),沒有欠款可沖銷時直接跳回
  /// 關閉狀態並提示。關閉時清掉查到的值,totalAmount 欄位解除上限。
  Future<void> _setOffsetExistingBalance(bool value) async {
    if (!value) {
      setState(() {
        _offsetExistingBalance = false;
        _offsetableDue = null;
      });
      return;
    }
    final accountId = _accountId;
    final l10n = AppLocalizations.of(context);
    if (accountId == null || _account == null) return;
    if (_account!.type == 'account_group') {
      showToast(context, l10n.installmentOffsetGroupUnsupportedError);
      return;
    }
    setState(() {
      _offsetExistingBalance = true;
      _offsetLoading = true;
      _offsetableDue = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      final due = await repo.getCreditCardOffsetableBalance(accountId);
      if (!mounted) return;
      if (due <= 0.005) {
        setState(() {
          _offsetExistingBalance = false;
          _offsetLoading = false;
          _offsetableDue = null;
        });
        showToast(context, l10n.installmentOffsetNoBalanceError);
        return;
      }
      setState(() {
        _offsetLoading = false;
        _offsetableDue = due;
      });
      _clampToOffsetableDue();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _offsetExistingBalance = false;
        _offsetLoading = false;
        _offsetableDue = null;
      });
      showToast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currencyCode =
        ref.watch(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    final currencySymbol = getCurrencySymbol(currencyCode);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.installmentAddTitle,
            showBack: true,
            compact: true,
            actions: [
              TextButton(
                onPressed: _isLoading ? null : _save,
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
              padding: EdgeInsets.symmetric(
                horizontal: 12.0.scaled(context, ref),
                vertical: 8.0.scaled(context, ref),
              ),
              children: [
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.installmentTotalAmountLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                      SizedBox(height: 12.0.scaled(context, ref)),
                      TextField(
                        controller: _totalAmountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d+\.?\d{0,2}')),
                        ],
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: BeeTokens.textPrimary(context),
                        ),
                        decoration: InputDecoration(
                          prefixText: '$currencySymbol ',
                          prefixStyle: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: BeeTokens.textPrimary(context),
                          ),
                          hintText: l10n.installmentTotalAmountHint,
                          hintStyle: TextStyle(
                              fontSize: 24,
                              color: BeeTokens.textTertiary(context)),
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.0.scaled(context, ref)),
                SectionCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.installmentPeriodsLabel,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: BeeTokens.textSecondary(context),
                              ),
                            ),
                            SizedBox(height: 12.0.scaled(context, ref)),
                            TextField(
                              controller: _periodsController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              style: TextStyle(
                                  fontSize: 16,
                                  color: BeeTokens.textPrimary(context)),
                              decoration: const InputDecoration(
                                  border: InputBorder.none),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.0.scaled(context, ref)),
                SectionCard(
                  child: InkWell(
                    onTap: _pickFirstPeriodDate,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.installmentFirstPeriodAtLabel,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: BeeTokens.textSecondary(context),
                                ),
                              ),
                              SizedBox(height: 6.0.scaled(context, ref)),
                              Text(
                                _formatDate(_firstPeriodAt),
                                style: TextStyle(
                                    fontSize: 16,
                                    color: BeeTokens.textPrimary(context)),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            color: BeeTokens.iconTertiary(context)),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 12.0.scaled(context, ref)),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.installmentRepaymentMethodLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                      SizedBox(height: 12.0.scaled(context, ref)),
                      _buildSegmented(
                        context,
                        options: {
                          'equal_principal':
                              l10n.installmentMethodEqualPrincipal,
                          'equal_installment':
                              l10n.installmentMethodEqualInstallment,
                          'fixed_interest': l10n.installmentMethodFixedInterest,
                        },
                        value: _repaymentMethod,
                        onChanged: (v) => setState(() => _repaymentMethod = v),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.0.scaled(context, ref)),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.installmentInterestRateLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                      SizedBox(height: 12.0.scaled(context, ref)),
                      TextField(
                        controller: _interestRateController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}')),
                        ],
                        decoration: InputDecoration(
                          suffixText: '%',
                          helperText: l10n.installmentInterestRateHint,
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.0.scaled(context, ref)),
                InkWell(
                  onTap: () =>
                      setState(() => _advancedExpanded = !_advancedExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          _advancedExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: BeeTokens.iconSecondary(context),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          l10n.installmentAdvancedSectionLabel,
                          style: TextStyle(
                              fontSize: 14,
                              color: BeeTokens.textSecondary(context)),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_advancedExpanded) ...[
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.installmentInterestPeriodLabel,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: BeeTokens.textSecondary(context)),
                        ),
                        SizedBox(height: 12.0.scaled(context, ref)),
                        _buildSegmented(
                          context,
                          options: {
                            'monthly': l10n.installmentInterestPeriodMonthly,
                            'daily': l10n.installmentInterestPeriodDaily,
                          },
                          value: _interestPeriod,
                          onChanged: (v) => setState(() => _interestPeriod = v),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12.0.scaled(context, ref)),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.installmentGracePeriodLabel,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: BeeTokens.textSecondary(context)),
                        ),
                        SizedBox(height: 12.0.scaled(context, ref)),
                        TextField(
                          controller: _graceController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration:
                              const InputDecoration(border: InputBorder.none),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12.0.scaled(context, ref)),
                  SectionCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.installmentRoundAmountsLabel,
                            style: TextStyle(
                                color: BeeTokens.textPrimary(context)),
                          ),
                        ),
                        Switch(
                          value: _roundAmounts,
                          onChanged: (v) => setState(() => _roundAmounts = v),
                        ),
                      ],
                    ),
                  ),
                  if (_roundAmounts) ...[
                    SizedBox(height: 12.0.scaled(context, ref)),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.installmentRemainderPositionLabel,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: BeeTokens.textSecondary(context)),
                          ),
                          SizedBox(height: 12.0.scaled(context, ref)),
                          _buildSegmented(
                            context,
                            options: {
                              'first': l10n.installmentRemainderPositionFirst,
                              'last': l10n.installmentRemainderPositionLast,
                            },
                            value: _remainderPosition,
                            onChanged: (v) =>
                                setState(() => _remainderPosition = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                SizedBox(height: 12.0.scaled(context, ref)),
                SectionCard(
                  child: InkWell(
                    onTap: _pickCategory,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.installmentCategoryLabel,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: BeeTokens.textSecondary(context),
                                ),
                              ),
                              SizedBox(height: 6.0.scaled(context, ref)),
                              Text(
                                _category?.name ?? l10n.installmentCategoryNone,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _category != null
                                      ? BeeTokens.textPrimary(context)
                                      : BeeTokens.textTertiary(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            color: BeeTokens.iconTertiary(context)),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 12.0.scaled(context, ref)),
                SectionCard(
                  child: InkWell(
                    onTap: _pickAccount,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.installmentAccountLabel,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: BeeTokens.textSecondary(context),
                                ),
                              ),
                              SizedBox(height: 6.0.scaled(context, ref)),
                              Text(
                                _account?.name ?? l10n.installmentAccountNone,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _account != null
                                      ? BeeTokens.textPrimary(context)
                                      : BeeTokens.textTertiary(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_account != null)
                          IconButton(
                            onPressed: () => setState(() {
                              _accountId = null;
                              _account = null;
                              _offsetExistingBalance = false;
                              _offsetableDue = null;
                            }),
                            icon: Icon(Icons.close,
                                color: BeeTokens.iconTertiary(context)),
                          )
                        else
                          Icon(Icons.chevron_right,
                              color: BeeTokens.iconTertiary(context)),
                      ],
                    ),
                  ),
                ),
                // 子專案 4:帳單分期沖銷,只在選了一張獨立信用卡(非
                // account_group)時才顯示這張卡——沒有帳戶或帳戶不是信用卡
                // 時「沖銷現有欠款」沒有意義,不顯示一個永遠用不到的控制項。
                if (_account != null && _account!.type == 'credit_card') ...[
                  SizedBox(height: 12.0.scaled(context, ref)),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.installmentOffsetToggleLabel,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: BeeTokens.textPrimary(context),
                                ),
                              ),
                            ),
                            if (_offsetLoading)
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: BeeTokens.textTertiary(context),
                                ),
                              )
                            else
                              Switch(
                                value: _offsetExistingBalance,
                                onChanged: (v) => _setOffsetExistingBalance(v),
                              ),
                          ],
                        ),
                        SizedBox(height: 6.0.scaled(context, ref)),
                        Text(
                          l10n.installmentOffsetToggleSubtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: BeeTokens.textTertiary(context),
                          ),
                        ),
                        if (_offsetExistingBalance &&
                            _offsetableDue != null) ...[
                          SizedBox(height: 8.0.scaled(context, ref)),
                          Text(
                            l10n.installmentOffsetDueLabel(
                              '$currencySymbol${_offsetableDue!.toStringAsFixed(2)}',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: BeeTokens.textSecondary(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                SizedBox(height: 12.0.scaled(context, ref)),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.installmentNoteLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                      SizedBox(height: 12.0.scaled(context, ref)),
                      TextField(
                        controller: _noteController,
                        maxLines: 3,
                        style: TextStyle(
                            fontSize: 15,
                            color: BeeTokens.textPrimary(context)),
                        decoration: InputDecoration(
                          hintText: l10n.commonNoteHint,
                          hintStyle:
                              TextStyle(color: BeeTokens.textTertiary(context)),
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmented(
    BuildContext context, {
    required Map<String, String> options,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in options.entries)
          ChoiceChip(
            label: Text(entry.value),
            selected: value == entry.key,
            onSelected: (_) => onChanged(entry.key),
            selectedColor: primary.withValues(alpha: 0.15),
            labelStyle: TextStyle(
              color: value == entry.key
                  ? primary
                  : BeeTokens.textSecondary(context),
              fontWeight:
                  value == entry.key ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
      ],
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickFirstPeriodDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _firstPeriodAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _firstPeriodAt = picked);
    }
  }

  Future<void> _pickAccount() async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    final currencyCode =
        ref.read(currentLedgerProvider).asData?.value?.currency;
    final result = await AccountCardPicker.show(
      context,
      ledgerId: ledgerId,
      selectedAccountId: _accountId,
      filterCurrency: currencyCode,
    );
    if (result == null || !mounted) return;
    final id = result.accountId;
    if (id == null) return;
    final repo = ref.read(repositoryProvider);
    final account = await repo.getAccount(id);
    if (!mounted) return;
    setState(() {
      _accountId = id;
      _account = account;
      // 換了帳戶,之前查到的沖銷上限就不適用了——不要留著舊帳戶的數字誤導
      // 使用者,關掉沖銷開關,使用者可以再重新勾選觸發新帳戶的查詢。
      _offsetExistingBalance = false;
      _offsetableDue = null;
    });
  }

  Future<void> _pickCategory() async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    final picked = await showCategorySelector(
      context,
      type: 'expense',
      currentCategoryId: _categoryId,
      ledgerId: ledgerId,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _categoryId = picked.id;
      _category = picked;
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final totalAmount = double.tryParse(_totalAmountController.text.trim());
    if (totalAmount == null || totalAmount <= 0) {
      showToast(context, l10n.installmentTotalAmountHint);
      return;
    }
    final periods = int.tryParse(_periodsController.text.trim());
    if (periods == null || periods < 1 || periods > 600) {
      showToast(context, l10n.installmentPeriodsRangeError);
      return;
    }
    final grace = int.tryParse(_graceController.text.trim()) ?? 0;
    if (grace < 0 || grace >= periods) {
      showToast(context, l10n.installmentGracePeriodRangeError);
      return;
    }
    if (_categoryId == null) {
      showToast(context, l10n.installmentCategoryRequired);
      return;
    }
    // 子專案 4:再校驗一次「總額不能超過沖銷上限」——_clampToOffsetableDue
    // 已經即時夾住打字輸入,這裡是防禦性的第二層(例如 _offsetableDue 還在
    // loading 途中使用者就按了存檔),repository 端還會再做一次權威校驗。
    if (_offsetExistingBalance &&
        _offsetableDue != null &&
        totalAmount > _offsetableDue! + 0.01) {
      showToast(
        context,
        l10n.installmentOffsetExceedsBalanceError(
            _offsetableDue!.toStringAsFixed(2)),
      );
      return;
    }
    final ratePercent =
        double.tryParse(_interestRateController.text.trim()) ?? 0.0;
    // 內部存小數,對齐 Cloud interestRateToPercentDisplay/
    // percentDisplayToInterestRate 換算慣例。用 toStringAsFixed 再轉回 double
    // 避免二進位浮點誤差殘留。
    final interestRate = double.parse((ratePercent / 100).toStringAsFixed(6));

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(repositoryProvider);
      final ledgerId = ref.read(currentLedgerIdProvider);
      final note = _noteController.text.trim();

      await repo.createInstallmentPlan(
        ledgerId: ledgerId,
        totalAmount: totalAmount,
        periods: periods,
        firstPeriodAt: _firstPeriodAt,
        accountId: _accountId,
        categoryId: _categoryId!,
        note: note.isEmpty ? null : note,
        repaymentMethod: _repaymentMethod,
        interestPeriod: _interestPeriod,
        interestRate: interestRate,
        roundAmounts: _roundAmounts,
        remainderPosition: _remainderPosition,
        gracePeriodMonths: grace,
        offsetExistingBalance: _offsetExistingBalance,
      );

      ref.read(installmentsRefreshProvider.notifier).state++;
      unawaited(PostProcessor.sync(ref, ledgerId: ledgerId));

      if (mounted) {
        showToast(context, l10n.installmentSaveSuccess);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
