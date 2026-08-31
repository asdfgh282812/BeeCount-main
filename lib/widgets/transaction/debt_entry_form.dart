import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/repositories/debt_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../styles/tokens.dart';
import '../../utils/amount_calculator.dart';
import '../../utils/currencies.dart';
import '../../widgets/biz/account_card_picker.dart';
import '../../widgets/biz/amount_calculator_keypad.dart';
import '../../widgets/biz/category_selector_dialog.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/biz/shared_entry_fields.dart';
import '../ui/ui.dart';

/// 記帳表單第 4 分頁「欠款」——新增欠款 + 起點交易(帳戶餘額立即變動)。
/// 對齐 `DebtEditorPage` 新增模式的欄位,唯一差異是這裡多了帳戶(必填)。
///
/// 本金金額輸入跟支出/收入分頁用同一套自訂計算小鍵盤(`AmountCalculatorKeypad`
/// + `_amountStr`/`_acc`/`_op` 狀態),不是系統小鍵盤——對齐
/// `TransactionEntryFormState`/`TransferFormState` 的既有寫法。
class DebtEntryForm extends ConsumerStatefulWidget {
  final VoidCallback onDebtCreated;

  const DebtEntryForm({super.key, required this.onDebtCreated});

  @override
  ConsumerState<DebtEntryForm> createState() => DebtEntryFormState();
}

class DebtEntryFormState extends ConsumerState<DebtEntryForm> {
  final _counterpartyController = TextEditingController();
  final _noteController = TextEditingController();
  final _counterpartyFocus = FocusNode();
  final _noteFocus = FocusNode();
  String _direction = kDebtDirectionPayable;
  int? _accountId;
  Account? _account;
  int? _categoryId;
  Category? _category;
  DateTime? _dueAt;
  bool _excludedFromTotal = false;
  bool _isSubmitting = false;

  // ===== 金額表達式(跟支出/收入分頁同一套) =====
  String _amountStr = '0';
  double _acc = 0;
  String? _op;
  // 底部小算盤只在使用者點金額欄位時才顯示,不再預設開啟——見
  // `_onTextFieldFocusChange` 旁的說明。
  bool _amountFocused = false;

  /// 起點交易的 type 跟隨 direction(payable → income,receivable →
  /// expense),分類選擇要用同一個 type 才能對得上實際入帳方向。
  String get _originTxType =>
      _direction == kDebtDirectionPayable ? 'income' : 'expense';

  bool get _textFieldFocused =>
      _counterpartyFocus.hasFocus || _noteFocus.hasFocus;

  @override
  void initState() {
    super.initState();
    _counterpartyFocus.addListener(_onTextFieldFocusChange);
    _noteFocus.addListener(_onTextFieldFocusChange);
  }

  @override
  void dispose() {
    _counterpartyFocus.removeListener(_onTextFieldFocusChange);
    _noteFocus.removeListener(_onTextFieldFocusChange);
    _counterpartyController.dispose();
    _noteController.dispose();
    _counterpartyFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  /// 對象/備註欄位聚焦時收起底部小算盤(改用系統鍵盤,可輸入中文),並清掉
  /// `_amountFocused`——小算盤只能靠點金額欄位重新叫出來,不會因為文字欄位
  /// 失焦就自己跳回來。
  void _onTextFieldFocusChange() {
    if (!mounted) return;
    if (_textFieldFocused) {
      setState(() => _amountFocused = false);
    } else {
      setState(() {});
    }
  }

  /// 供 `transaction_editor_page.dart` 切 tab 時讀出目前已輸入的共用欄位。
  SharedEntryFields exportSharedFields() => (
        amountStr: _amountStr,
        amountAcc: _acc,
        amountOp: _op,
        date: DateTime.now(),
        note: _noteController.text,
        merchant: _counterpartyController.text,
        tagIds: const <int>[],
        accountId: _accountId,
        // 欠款分頁沒有專案概念(design doc §6 只涵蓋支出/收入),恆傳 null。
        projectSyncId: null,
      );

  /// 把另一個分頁匯出的共用欄位套用到這裡——無條件覆蓋,跟
  /// `TransactionEntryFormState`/`TransferFormState` 的既有語意一致。「商家」
  /// 欄位映射到這裡的「對象」,語意最接近,也是使用者從支出/收入分頁切過來
  /// 最常見的情境。這個表單沒有交易日期/標籤欄位,`f.date`/`f.tagIds` 忽略。
  void applySharedFields(SharedEntryFields f) {
    if (!mounted) return;
    setState(() {
      _amountStr = f.amountStr;
      _acc = f.amountAcc;
      _op = f.amountOp;
      _noteController.text = f.note;
      _counterpartyController.text = f.merchant;
    });
    if (f.accountId != null && f.accountId != _accountId) {
      setState(() => _accountId = f.accountId);
      _loadAccount(f.accountId!);
    }
  }

  double _parsedAmount() => double.tryParse(_amountStr) ?? 0.0;

  String _fmtAbs(double v) {
    final s = v.abs().toStringAsFixed(2);
    final r1 = s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '') : s;
    return r1.endsWith('.') ? r1.substring(0, r1.length - 1) : r1;
  }

  void _appendDigit(String s) {
    setState(() {
      if (s == '.') {
        if (_amountStr.contains('.')) return;
      }
      if (_amountStr.contains('.')) {
        final dot = _amountStr.indexOf('.');
        final decimals = _amountStr.length - dot - 1;
        if (s != '.' && decimals >= 2) return;
      }
      if (_amountStr == '0' && s != '.') {
        _amountStr = s;
      } else {
        _amountStr += s;
      }
    });
  }

  void _backspace() {
    setState(() {
      if (_amountStr.isEmpty) return;
      _amountStr = _amountStr.substring(0, _amountStr.length - 1);
      if (_amountStr.isEmpty) _amountStr = '0';
    });
  }

  void _clearAll() {
    setState(() {
      _amountStr = '0';
      _acc = 0;
      _op = null;
    });
  }

  void _applyOp(String op) {
    final cur = _parsedAmount();
    setState(() {
      if (_op == null) {
        _acc = cur;
      } else {
        _acc = computeAmountOp(_acc, _op!, cur);
      }
      _op = op;
      _amountStr = '0';
    });
  }

  void _applyEquals() {
    if (_op == null) return;
    final cur = _parsedAmount();
    final total = computeAmountOp(_acc, _op!, cur);
    setState(() {
      final s = total.abs().toStringAsFixed(2);
      final trimmed = s.contains('.')
          ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
          : s;
      _amountStr = trimmed.isEmpty ? '0' : trimmed;
      _acc = 0;
      _op = null;
    });
  }

  Future<void> _loadAccount(int id) async {
    final repo = ref.read(repositoryProvider);
    final account = await repo.getAccount(id);
    if (!mounted) return;
    setState(() {
      _accountId = id;
      _account = account;
    });
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
    await _loadAccount(id);
  }

  Future<void> _pickCategory() async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    final picked = await showCategorySelector(
      context,
      type: _originTxType,
      currentCategoryId: _categoryId,
      ledgerId: ledgerId,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _categoryId = picked.id;
      _category = picked;
    });
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dueAt = picked);
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final l10n = AppLocalizations.of(context);
    final counterpartyName = _counterpartyController.text.trim();
    if (counterpartyName.isEmpty) {
      showToast(context, l10n.debtCounterpartyHint);
      return;
    }
    final principalAmount = _parsedAmount();
    if (principalAmount <= 0) {
      showToast(context, l10n.debtPrincipalAmountHint);
      return;
    }
    if (_accountId == null) {
      showToast(context, l10n.debtRepaymentAccountRequired);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(repositoryProvider);
      final ledgerId = ref.read(currentLedgerIdProvider);
      final note = _noteController.text.trim();

      await repo.createDebtWithOriginTransaction(
        ledgerId: ledgerId,
        direction: _direction,
        counterpartyName: counterpartyName,
        principalAmount: principalAmount,
        accountId: _accountId!,
        dueAt: _dueAt,
        note: note.isEmpty ? null : note,
        categoryId: _categoryId,
        excludedFromTotal: _excludedFromTotal,
      );

      ref.read(debtsRefreshProvider.notifier).state++;
      ref.read(statsRefreshProvider.notifier).state++;
      unawaited(PostProcessor.sync(ref, ledgerId: ledgerId));

      HapticFeedback.lightImpact();
      SystemSound.play(SystemSoundType.click);
      if (mounted) showToast(context, l10n.debtSaveSuccess);
      widget.onDebtCreated();
    } catch (e) {
      if (mounted) showToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _buildDirectionOption(
    BuildContext context,
    String label,
    String direction,
    IconData icon,
  ) {
    final isSelected = _direction == direction;
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: () => setState(() {
        if (_direction != direction) {
          // 換方向會改變起點交易的 type(income/expense),已選的分類可能
          // 不再屬於新 type,清掉避免帶著錯誤 type 的分類送出。
          _categoryId = null;
          _category = null;
        }
        _direction = direction;
      }),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? primary.withValues(alpha: 0.1) : BeeTokens.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? primary : BeeTokens.border(context),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: isSelected ? primary : BeeTokens.iconSecondary(context)),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? primary : BeeTokens.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currencyCode =
        ref.watch(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    final currencySymbol = getCurrencySymbol(currencyCode);
    final text = Theme.of(context).textTheme;
    final primary = Theme.of(context).colorScheme.primary;

    final cur = _parsedAmount();
    final total = _op == null ? cur : computeAmountOp(_acc, _op!, cur);
    final isInCalcMode = _op != null;
    final canSubmit = _accountId != null && (isInCalcMode || total.abs() > 0);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.debtDirectionLabel,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BeeTokens.textSecondary(context))),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                              child: _buildDirectionOption(context, l10n.debtDirectionPayableLabel,
                                  kDebtDirectionPayable, Icons.arrow_upward)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _buildDirectionOption(context, l10n.debtDirectionReceivableLabel,
                                  kDebtDirectionReceivable, Icons.arrow_downward)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.debtCounterpartyLabel,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BeeTokens.textSecondary(context))),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _counterpartyController,
                        focusNode: _counterpartyFocus,
                        style: TextStyle(fontSize: 16, color: BeeTokens.textPrimary(context)),
                        decoration: InputDecoration(
                          hintText: l10n.debtCounterpartyHint,
                          hintStyle: TextStyle(color: BeeTokens.textTertiary(context)),
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  child: GestureDetector(
                    key: const Key('amountDisplayTap'),
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      setState(() => _amountFocused = true);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.debtPrincipalAmountLabel,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BeeTokens.textSecondary(context))),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_op != null) ...[
                              Text(
                                _fmtAbs(_acc),
                                style: text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: BeeTokens.textSecondary(context),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  amountOpGlyph(_op!),
                                  style: text.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600, color: primary),
                                ),
                              ),
                            ],
                            Text(
                              '$currencySymbol ',
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: BeeTokens.textPrimary(context)),
                            ),
                            Text(
                              _amountStr,
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: BeeTokens.textPrimary(context)),
                            ),
                          ],
                        ),
                        if (_op != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('= ',
                                  style: text.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w500, color: BeeTokens.textTertiary(context))),
                              Text(_fmtAbs(total),
                                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: primary)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.debtRepaymentAccountLabel,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BeeTokens.textSecondary(context))),
                      const SizedBox(height: 12),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _pickAccount,
                        child: Container(
                          width: double.infinity,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: BeeTokens.surfaceInput(context),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.credit_card,
                                  size: 18, color: BeeTokens.iconSecondary(context)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _account?.name ?? l10n.debtRepaymentAccountLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: BeeTokens.textPrimary(context),
                                      fontSize: 14),
                                ),
                              ),
                              Icon(Icons.chevron_right,
                                  size: 18, color: BeeTokens.iconTertiary(context)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  child: InkWell(
                    onTap: _pickDueDate,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n.debtDueDateLabel,
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BeeTokens.textSecondary(context))),
                              const SizedBox(height: 6),
                              Text(
                                _dueAt != null ? _formatDate(_dueAt!) : l10n.debtDueDateNone,
                                style: TextStyle(
                                    fontSize: 16,
                                    color: _dueAt != null ? BeeTokens.textPrimary(context) : BeeTokens.textTertiary(context)),
                              ),
                            ],
                          ),
                        ),
                        if (_dueAt != null)
                          IconButton(
                            onPressed: () => setState(() => _dueAt = null),
                            icon: Icon(Icons.close, color: BeeTokens.iconTertiary(context)),
                            tooltip: l10n.debtDueDateClear,
                          )
                        else
                          Icon(Icons.chevron_right, color: BeeTokens.iconTertiary(context)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  child: InkWell(
                    onTap: _pickCategory,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n.debtCategoryLabel,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: BeeTokens.textSecondary(context))),
                              const SizedBox(height: 6),
                              Text(
                                _category?.name ?? l10n.debtCategoryNone,
                                style: TextStyle(
                                    fontSize: 16,
                                    color: _category != null
                                        ? BeeTokens.textPrimary(context)
                                        : BeeTokens.textTertiary(context)),
                              ),
                            ],
                          ),
                        ),
                        if (_category != null)
                          IconButton(
                            onPressed: () => setState(() {
                              _categoryId = null;
                              _category = null;
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
                const SizedBox(height: 12),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.debtNoteLabel,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BeeTokens.textSecondary(context))),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _noteController,
                        focusNode: _noteFocus,
                        maxLines: 3,
                        style: TextStyle(fontSize: 15, color: BeeTokens.textPrimary(context)),
                        decoration: InputDecoration(
                          hintText: l10n.commonNoteHint,
                          hintStyle: TextStyle(color: BeeTokens.textTertiary(context)),
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.debtExcludedFromTotalLabel,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BeeTokens.textPrimary(context)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.debtExcludedFromTotalHint,
                              style: TextStyle(fontSize: 12, color: BeeTokens.textTertiary(context)),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _excludedFromTotal,
                        onChanged: (v) => setState(() => _excludedFromTotal = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
        // 小算盤只在使用者點過金額欄位後才顯示;對象/備註欄位聚焦時讓位給
        // 系統鍵盤,跟支出/收入分頁同一套規則(見 TransactionEntryFormState)。
        if (_amountFocused && !_textFieldFocused)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: AmountCalculatorKeypad(
              onDigit: _appendDigit,
              onOp: _applyOp,
              onBackspace: _backspace,
              onClear: _clearAll,
              onEquals: _applyEquals,
              onSave: _submit,
              isInCalcMode: isInCalcMode,
              canSubmit: canSubmit,
              isSubmitting: _isSubmitting,
            ),
          ),
      ],
    );
  }
}
