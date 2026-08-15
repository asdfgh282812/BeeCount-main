import 'dart:io';

import 'package:drift/drift.dart' as d;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/repositories/local/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../pages/attachment/attachment_preview_page.dart';
import '../../pages/tag/widgets/tag_selector.dart';
import '../../providers.dart';
import '../../services/attachment_service.dart';
import '../../services/billing/post_processor.dart';
import '../../services/custom_icon_service.dart';
import '../../services/data/tx_author_service.dart';
import '../../styles/tokens.dart';
import '../../utils/account_type_utils.dart';
import '../../utils/amount_calculator.dart';
import '../../utils/shared_ledger_picker_filter.dart';
import '../biz/account_card_picker.dart';
import '../biz/amount_calculator_keypad.dart';
import '../biz/amount_text.dart';
import '../biz/tag_chip.dart';
import '../currency/currency_flag.dart';
import '../ui/ui.dart';

/// 轉帳表單(v2:單頁式,比照參考圖 + 這次新版 `TransactionEntryForm` 的
/// 單頁模式)。帳戶卡片並排 + 交換方向鍵、金額、名稱、商家、標籤/附件、
/// 日期、底部固定小算盤一次呈現,拿掉了舊版「先選帳戶方格 grid → 再彈
/// `AmountEditorSheet` modal 填金額」的兩步流程(`AmountEditorSheet` 已刪除,
/// 唯一呼叫方就是這裡)。
///
/// 帳戶反查/synthetic id 解析、幣別守衛、存檔 orchestration 沿用舊版邏輯
/// 搬過來,行為不變;鍵盤固定貼底 + 跟系統鍵盤互斥顯示的寫法跟
/// `transaction_entry_form.dart` 一致,兩邊各自實作、不抽共用 base class。
class TransferForm extends ConsumerStatefulWidget {
  final VoidCallback onTransferComplete;
  final int? initialFromAccountId;
  final int? initialToAccountId;
  final int? editingTransactionId;
  final double? initialAmount;
  final String? initialNote;
  final String? initialMerchant;
  final DateTime? initialDate;
  final List<int>? initialTagIds;

  const TransferForm({
    super.key,
    required this.onTransferComplete,
    this.initialFromAccountId,
    this.initialToAccountId,
    this.editingTransactionId,
    this.initialAmount,
    this.initialNote,
    this.initialMerchant,
    this.initialDate,
    this.initialTagIds,
  });

  @override
  ConsumerState<TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends ConsumerState<TransferForm> {
  int? _fromAccountId;
  int? _toAccountId;
  Account? _fromAccount;
  Account? _toAccount;

  late String _amountStr;
  double _acc = 0;
  String? _op;
  late DateTime _date;

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _merchantCtrl = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _merchantFocus = FocusNode();

  late List<int> _selectedTagIds;
  List<File> _pendingAttachments = [];

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(_onTextFieldFocusChange);
    _merchantFocus.addListener(_onTextFieldFocusChange);
    _fromAccountId = widget.initialFromAccountId;
    _toAccountId = widget.initialToAccountId;
    _date = widget.initialDate ?? DateTime.now();
    _nameCtrl.text = widget.initialNote ?? '';
    _merchantCtrl.text = widget.initialMerchant ?? '';
    _selectedTagIds = List.from(widget.initialTagIds ?? []);

    final initAmount = widget.initialAmount ?? 0;
    final s = initAmount.toStringAsFixed(2);
    final trimmed = s.contains('.')
        ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : s;
    _amountStr = trimmed.isEmpty ? '0' : trimmed;

    if (_fromAccountId != null) _loadAccount(_fromAccountId!, isFrom: true);
    if (_toAccountId != null) _loadAccount(_toAccountId!, isFrom: false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _merchantCtrl.dispose();
    _nameFocus.dispose();
    _merchantFocus.dispose();
    super.dispose();
  }

  /// 名稱/商家欄位聚焦時收起底部小算盤(改用 iOS 原生鍵盤);兩者都失焦時
  /// 小算盤才重新出現,跟 `transaction_entry_form.dart` 同款寫法。
  void _onTextFieldFocusChange() {
    if (mounted) setState(() {});
  }

  bool get _textFieldFocused => _nameFocus.hasFocus || _merchantFocus.hasFocus;

  /// 反查账户:正数 id → 主表 accounts;负数 synthetic id → 扫
  /// SharedLedgerAccounts 找 syntheticIdForSyncId 命中(共享账本 Editor
  /// 视角下 picker 给出的是 Owner 的 synthetic 账户)。
  Future<Account?> _lookupAccount(int accountId) async {
    final repo = ref.read(repositoryProvider);
    if (accountId >= 0) return repo.getAccount(accountId);
    if (repo is! LocalRepository) return null;
    return repo.db.findAccountBySyntheticId(accountId);
  }

  Future<void> _loadAccount(int accountId, {required bool isFrom}) async {
    final acc = await _lookupAccount(accountId);
    if (!mounted) return;
    setState(() {
      if (isFrom) {
        _fromAccount = acc;
      } else {
        _toAccount = acc;
      }
    });
  }

  /// 把 synthetic accountId(负数)反查回 Owner 的 syncId(正数 id 时返 null)。
  /// 用 ledger.syncId 限定 SharedLedgerAccounts 的查询范围。
  Future<String?> _resolveSyncIdByAccountId(int accountId, int ledgerId) async {
    if (accountId >= 0) return null;
    final repo = ref.read(repositoryProvider);
    if (repo is! LocalRepository) return null;
    final ledger = await (repo.db.select(repo.db.ledgers)
          ..where((l) => l.id.equals(ledgerId)))
        .getSingleOrNull();
    if (ledger?.syncId == null) return null;
    final rows = await (repo.db.select(repo.db.sharedLedgerAccounts)
          ..where((t) => t.ledgerSyncId.equals(ledger!.syncId!)))
        .get();
    for (final r in rows) {
      if (syntheticIdForSyncId(r.syncId) == accountId) return r.syncId;
    }
    return null;
  }

  Future<void> _pickAccount({required bool isFrom}) async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    final currency = ref.read(currentLedgerCurrencyProvider);
    final result = await AccountCardPicker.show(
      context,
      ledgerId: ledgerId,
      selectedAccountId: isFrom ? _fromAccountId : _toAccountId,
      filterCurrency: currency,
      pinnedAccountId:
          isFrom ? widget.initialFromAccountId : widget.initialToAccountId,
      allowNull: false,
      excludeAccountId: isFrom ? _toAccountId : _fromAccountId,
    );
    if (result == null || !mounted) return;
    final id = result.accountId;
    if (id == null) return; // allowNull:false 理论上拿不到 null,防御
    setState(() {
      if (isFrom) {
        _fromAccountId = id;
      } else {
        _toAccountId = id;
      }
    });
    await _loadAccount(id, isFrom: isFrom);
  }

  void _swapAccounts() {
    setState(() {
      final tmpId = _fromAccountId;
      _fromAccountId = _toAccountId;
      _toAccountId = tmpId;
      final tmpAcc = _fromAccount;
      _fromAccount = _toAccount;
      _toAccount = tmpAcc;
    });
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

  double _parsedAmount() => double.tryParse(_amountStr) ?? 0.0;

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

  void _pickDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    final showTime = ref.read(showTransactionTimeProvider);
    if (showTime) {
      final res = await showWheelDateTimePicker(context,
          initial: _date, maxDate: DateTime.now());
      if (res != null) setState(() => _date = res);
    } else {
      final res = await showWheelDatePicker(
        context,
        initial: _date,
        mode: WheelDatePickerMode.ymd,
        maxDate: DateTime.now(),
      );
      if (res != null) setState(() => _date = res);
    }
  }

  Future<void> _submit() async {
    if (_fromAccountId == null || _toAccountId == null || _isSubmitting) {
      return;
    }
    final total = _op == null
        ? _parsedAmount()
        : computeAmountOp(_acc, _op!, _parsedAmount());
    if (total.abs() <= 0) return;

    final l10n = AppLocalizations.of(context);

    // 跨币种转账守卫(.docs/multi-currency-ledger 01 §4.4):存量数据放行
    // (2026-07-12 细则)——编辑模式且账户对未改动(老数据在守卫上线前就是
    // 跨币种)才放行,让用户能改备注/日期等,不强迫重选账户。
    final fromCurrency = _fromAccount?.currency;
    final toCurrency = _toAccount?.currency;
    final sameCurrency = fromCurrency != null && fromCurrency == toCurrency;
    if (!sameCurrency) {
      final isOriginalPair = widget.editingTransactionId != null &&
          _fromAccountId == widget.initialFromAccountId &&
          _toAccountId == widget.initialToAccountId;
      if (!isOriginalPair) {
        showToast(context, l10n.transferDifferentCurrencyError);
        return;
      }
    }

    setState(() => _isSubmitting = true);

    final repo = ref.read(repositoryProvider);
    final ledgerId = ref.read(currentLedgerIdProvider);
    final attachmentService = ref.read(attachmentServiceProvider);
    final transferCategory = await ref.read(transferCategoryProvider.future);
    final transferCategoryId = transferCategory.id;

    // §7 共享账本:Editor picker 给的是 synthetic Account(负数 id)。写本地
    // Drift 时 accountId / toAccountId 留 null,override 字段走 Owner 的
    // syncId;push 序列化时按 override 输出 payload。
    final isSyntheticFrom = _fromAccountId! < 0;
    final isSyntheticTo = _toAccountId! < 0;
    final fromAccountForAdd = isSyntheticFrom ? null : _fromAccountId;
    final toAccountForAdd = isSyntheticTo ? null : _toAccountId;
    final fromOverride = isSyntheticFrom
        ? await _resolveSyncIdByAccountId(_fromAccountId!, ledgerId)
        : null;
    final toOverride = isSyntheticTo
        ? await _resolveSyncIdByAccountId(_toAccountId!, ledgerId)
        : null;

    final note = _nameCtrl.text.isEmpty ? null : _nameCtrl.text;
    final merchant = _merchantCtrl.text.isEmpty ? null : _merchantCtrl.text;

    try {
      int transactionId;
      if (widget.editingTransactionId != null) {
        transactionId = widget.editingTransactionId!;
        await repo.updateTransaction(
          id: transactionId,
          type: 'transfer',
          amount: total.abs(),
          categoryId: transferCategoryId,
          note: note,
          merchant: merchant,
          happenedAt: _date,
          accountId: d.Value<int?>(fromAccountForAdd),
          accountSyncIdOverride: fromOverride,
        );
        // 更新 toAccountId(同时写 toAccountSyncIdOverride,共享账本场景)
        await repo.updateTransactionFields(
          id: transactionId,
          toAccountId: d.Value<int?>(toAccountForAdd),
          toAccountSyncIdOverride: toOverride,
          writeToAccountSyncIdOverride: true,
        );
        // 共享账本:回填编辑人,UI 头像组立即展示
        await TxAuthorService.markEdited(ref, transactionId);

        if (_selectedTagIds.isNotEmpty) {
          await repo.updateTransactionTags(
            transactionId: transactionId,
            tagIds: _selectedTagIds,
          );
          ref.read(tagListRefreshProvider.notifier).state++;
        } else {
          // 编辑模式没选标签 → 清掉旧关联
          await repo.removeAllTagsFromTransaction(transactionId);
          ref.read(tagListRefreshProvider.notifier).state++;
        }

        if (_pendingAttachments.isNotEmpty) {
          await attachmentService.saveAttachments(
            transactionId: transactionId,
            sourceFiles: _pendingAttachments,
            startIndex: 0,
          );
          ref.read(attachmentListRefreshProvider.notifier).state++;
        }

        await PostProcessor.sync(ref, ledgerId: ledgerId);
        ref.invalidate(countsForLedgerProvider(ledgerId));
        ref.read(statsRefreshProvider.notifier).state++;

        if (!mounted) return;
        showToast(context, l10n.transferUpdateSuccess);
      } else {
        transactionId = await repo.addTransaction(
          ledgerId: ledgerId,
          type: 'transfer',
          amount: total.abs(),
          categoryId: transferCategoryId,
          accountId: fromAccountForAdd,
          toAccountId: toAccountForAdd,
          accountSyncIdOverride: fromOverride,
          toAccountSyncIdOverride: toOverride,
          note: note,
          merchant: merchant,
          happenedAt: _date,
        );
        // 共享账本:本地立即标记创建人 + 编辑人(同一个 user)
        await TxAuthorService.markCreated(ref, transactionId);

        if (_selectedTagIds.isNotEmpty) {
          await repo.updateTransactionTags(
            transactionId: transactionId,
            tagIds: _selectedTagIds,
          );
          ref.read(tagListRefreshProvider.notifier).state++;
        }

        if (_pendingAttachments.isNotEmpty) {
          await attachmentService.saveAttachments(
            transactionId: transactionId,
            sourceFiles: _pendingAttachments,
            startIndex: 0,
          );
          ref.read(attachmentListRefreshProvider.notifier).state++;
        }

        await PostProcessor.sync(ref, ledgerId: ledgerId);
        ref.invalidate(countsForLedgerProvider(ledgerId));
        ref.read(statsRefreshProvider.notifier).state++;

        if (!mounted) return;
        showToast(context, l10n.transferCreateSuccess);
      }

      HapticFeedback.lightImpact();
      SystemSound.play(SystemSoundType.click);
      widget.onTransferComplete();
      // 成功路径不重置 _isSubmitting:onTransferComplete 通常会关闭页面。
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        showToast(context, '${l10n.commonError}: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final primary = Theme.of(context).colorScheme.primary;
    final cur = _parsedAmount();
    final total = _op == null ? cur : computeAmountOp(_acc, _op!, cur);
    final isInCalcMode = _op != null;
    final canSubmit = _fromAccountId != null &&
        _toAccountId != null &&
        (isInCalcMode ? true : total.abs() > 0);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAccountCardsRow(context),
                const SizedBox(height: 14),
                // 金额表达式行——外面包 GestureDetector,点一下主动收起
                // 名稱/商家欄位的系統鍵盤,讓底部小算盤重新出現。
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          _buildCurrencyBadge(context),
                          const Spacer(),
                          if (_op != null) ...[
                            Text(
                              _fmtAbs(_acc),
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: BeeTokens.textSecondary(context),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                amountOpGlyph(_op!),
                                style: text.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: primary),
                              ),
                            ),
                          ],
                          Text(
                            _amountStr,
                            style: text.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.0,
                              color: BeeTokens.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                      if (_op != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '= ',
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: BeeTokens.textTertiary(context),
                              ),
                            ),
                            Text(
                              _fmtAbs(total),
                              style: text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600, color: primary),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameCtrl,
                  focusNode: _nameFocus,
                  style: TextStyle(color: BeeTokens.textPrimary(context)),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context).transactionNameHint,
                    hintStyle:
                        TextStyle(color: BeeTokens.textTertiary(context)),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: BeeTokens.surfaceInput(context),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(height: 8),
                // 商家欄(v33 新增,獨立於名稱/備註的自由文本欄位)
                TextField(
                  controller: _merchantCtrl,
                  focusNode: _merchantFocus,
                  style: TextStyle(color: BeeTokens.textPrimary(context)),
                  decoration: InputDecoration(
                    hintText:
                        AppLocalizations.of(context).transactionMerchantHint,
                    hintStyle:
                        TextStyle(color: BeeTokens.textTertiary(context)),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: BeeTokens.surfaceInput(context),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    prefixIcon: Icon(Icons.storefront_outlined,
                        color: BeeTokens.iconSecondary(context), size: 18),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 40, minHeight: 20),
                  ),
                ),
                const SizedBox(height: 8),
                _buildTagAndAttachmentRow(),
                const SizedBox(height: 8),
                _buildDateRow(context),
              ],
            ),
          ),
        ),
        // 小算盤固定貼底,名稱/商家欄位聚焦時讓位給系統鍵盤,道理跟
        // `transaction_entry_form.dart` 一致。
        if (!_textFieldFocused)
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

  String _fmtAbs(double v) {
    final s = v.abs().toStringAsFixed(2);
    final r1 = s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '') : s;
    return r1.endsWith('.') ? r1.substring(0, r1.length - 1) : r1;
  }

  Widget _buildCurrencyBadge(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final fromCurrency = _fromAccount?.currency;
    final String currency = (fromCurrency != null && fromCurrency.isNotEmpty)
        ? fromCurrency.toUpperCase()
        : ref.watch(currentLedgerCurrencyProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: BeeTokens.surfaceKeySecondary(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          currencyFlag(context, currency, width: 19, height: 14, radius: 4),
          const SizedBox(width: 5),
          Text(
            currency,
            style: text.bodySmall?.copyWith(
              color: BeeTokens.textSecondary(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCardsRow(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _AccountCardSlot(
            account: _fromAccount,
            label: l10n.transferFromAccount,
            onTap: () => _pickAccount(isFrom: true),
          ),
        ),
        SizedBox(
          width: 40,
          child: IconButton(
            onPressed: (_fromAccountId != null || _toAccountId != null)
                ? _swapAccounts
                : null,
            icon:
                Icon(Icons.swap_horiz, color: BeeTokens.iconSecondary(context)),
          ),
        ),
        Expanded(
          child: _AccountCardSlot(
            account: _toAccount,
            label: l10n.transferToAccount,
            onTap: () => _pickAccount(isFrom: false),
          ),
        ),
      ],
    );
  }

  Widget _buildTagAndAttachmentRow() {
    final allTagsAsync = ref.watch(tagsForCurrentLedgerProvider);
    final allTags = allTagsAsync.valueOrNull ?? [];
    final selectedTags =
        allTags.where((t) => _selectedTagIds.contains(t.id)).toList();

    List<TransactionAttachment> savedAttachments = [];
    int attachmentCount = _pendingAttachments.length;
    if (widget.editingTransactionId != null) {
      final attachmentsAsync = ref
          .watch(transactionAttachmentsProvider(widget.editingTransactionId!));
      savedAttachments = attachmentsAsync.valueOrNull ?? [];
      attachmentCount = savedAttachments.length + _pendingAttachments.length;
    }
    final l10n = AppLocalizations.of(context);
    final hasAttachments = attachmentCount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: BeeTokens.surfaceInput(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final result = await TagSelector.show(context,
                    selectedTagIds: _selectedTagIds);
                if (result != null) setState(() => _selectedTagIds = result);
              },
              behavior: HitTestBehavior.opaque,
              child: selectedTags.isEmpty
                  ? Text(
                      l10n.tagSelectTitle,
                      style: TextStyle(
                          color: BeeTokens.textTertiary(context), fontSize: 14),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: selectedTags
                            .map((tag) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: TagChip(
                                      name: tag.name,
                                      color: tag.color,
                                      size: TagChipSize.small),
                                ))
                            .toList(),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () => _handleAttachmentTap(savedAttachments),
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasAttachments ? Icons.image : Icons.image_outlined,
                  size: 18,
                  color: hasAttachments
                      ? Theme.of(context).colorScheme.primary
                      : BeeTokens.iconSecondary(context),
                ),
                if (hasAttachments) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$attachmentCount',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAttachmentTap(
      List<TransactionAttachment> savedAttachments) async {
    final totalCount = savedAttachments.length + _pendingAttachments.length;

    if (totalCount == 0) {
      await _showAddAttachmentOptions();
    } else {
      final result = await Navigator.push<List<File>?>(
        context,
        MaterialPageRoute(
          builder: (_) => AttachmentPreviewPage(
            attachments: savedAttachments,
            initialIndex: 0,
            allowDelete: true,
            allowAdd: true,
            pendingFiles: _pendingAttachments,
            transactionId: widget.editingTransactionId,
          ),
        ),
      );
      if (result != null) {
        setState(() => _pendingAttachments = result);
      }
    }
  }

  Future<void> _showAddAttachmentOptions() async {
    final l10n = AppLocalizations.of(context);
    final service = ref.read(attachmentServiceProvider);

    await showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(l10n.attachmentTakePhoto),
              onTap: () async {
                Navigator.pop(context);
                final file = await service.takePhoto();
                if (file != null && mounted) {
                  if (widget.editingTransactionId != null) {
                    await service.saveAttachment(
                      transactionId: widget.editingTransactionId!,
                      sourceFile: file,
                      index: 0,
                    );
                    ref.read(attachmentListRefreshProvider.notifier).state++;
                  } else {
                    setState(() =>
                        _pendingAttachments = [..._pendingAttachments, file]);
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(l10n.attachmentChooseFromGallery),
              onTap: () async {
                Navigator.pop(context);
                final files = await service.pickFromGallery(
                    maxCount: 9 - _pendingAttachments.length);
                if (files.isNotEmpty && mounted) {
                  if (widget.editingTransactionId != null) {
                    await service.saveAttachments(
                      transactionId: widget.editingTransactionId!,
                      sourceFiles: files,
                      startIndex: 0,
                    );
                    ref.read(attachmentListRefreshProvider.notifier).state++;
                  } else {
                    setState(() => _pendingAttachments = [
                          ..._pendingAttachments,
                          ...files
                        ]);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRow(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final showTime = ref.watch(showTransactionTimeProvider);
    String fmtDate(DateTime d) => '${d.year}/${d.month}/${d.day}';
    String fmtTime(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        SystemSound.play(SystemSoundType.click);
        _pickDate();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: BeeTokens.surfaceInput(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 16, color: BeeTokens.iconSecondary(context)),
            const SizedBox(width: 8),
            Text(
              showTime
                  ? '${fmtDate(_date)}  ${fmtTime(_date)}'
                  : fmtDate(_date),
              style: text.bodyMedium?.copyWith(
                  color: BeeTokens.textPrimary(context),
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// 帳戶卡片(轉出/轉入槽位)。未選帳戶時顯示「點擊選擇」佔位;已選時顯示
/// 頭像(有自訂頭像走 avatarPath,否則退回 AccountTypeIcon)、名稱、即時
/// 餘額。
class _AccountCardSlot extends ConsumerWidget {
  final Account? account;
  final String label;
  final VoidCallback onTap;

  const _AccountCardSlot({
    required this.account,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primaryColor = ref.watch(primaryColorProvider);
    final acc = account;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BeeTokens.surfaceElevated(context),
                border:
                    Border.all(color: BeeTokens.cardOuterBorderColor(context)),
              ),
              clipBehavior: Clip.antiAlias,
              child: acc == null
                  ? Icon(Icons.add,
                      color: BeeTokens.iconSecondary(context), size: 28)
                  : (acc.avatarPath != null
                      ? _AccountAvatarImage(
                          avatarPath: acc.avatarPath!,
                          size: 64,
                          fallback: AccountTypeIcon(
                              type: acc.type,
                              size: 28,
                              color: getColorForAccountType(
                                  acc.type, primaryColor)),
                        )
                      : Center(
                          child: AccountTypeIcon(
                              type: acc.type,
                              size: 28,
                              color: getColorForAccountType(
                                  acc.type, primaryColor)),
                        )),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 账户隐藏(#240)E1 钉住:acc.hidden 只可能在编辑历史转账、
                // 该账户被 AccountCardPicker 补回候选时为 true,借该字段
                // 直接打灰标(跟 account_card_picker.dart 的 _AccountRow 同款)。
                if (acc?.hidden == true) ...[
                  Icon(Icons.visibility_off,
                      size: 10, color: BeeTokens.textTertiary(context)),
                  const SizedBox(width: 2),
                ],
                Flexible(
                  child: Text(
                    acc?.name ?? label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: acc == null
                          ? BeeTokens.textTertiary(context)
                          : BeeTokens.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
            if (acc != null) ...[
              const SizedBox(height: 2),
              Consumer(builder: (context, ref, _) {
                final statsAsync = ref.watch(allAccountStatsProvider);
                final balance = statsAsync.valueOrNull?[acc.id]?.balance ?? 0;
                return AmountText(
                  value: balance,
                  signed: false,
                  showCurrency: false,
                  currencyCode: acc.currency,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: BeeTokens.textSecondary(context)),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

/// 账户头像图片——跟 `accounts_page.dart` 的 `_AccountAvatarImage` 同款
/// 複製(private class 不能跨檔案 import,本專案慣例是各自複製一份小
/// widget,見 `account_card_picker.dart` 開頭註解的做法)。
class _AccountAvatarImage extends StatelessWidget {
  final String avatarPath;
  final double size;
  final Widget fallback;

  const _AccountAvatarImage({
    required this.avatarPath,
    required this.size,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: CustomIconService().resolveIconPath(avatarPath),
      builder: (context, snapshot) {
        final abs = snapshot.data;
        if (abs == null) return Center(child: fallback);
        final file = File(abs);
        if (!file.existsSync()) return Center(child: fallback);
        return Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Center(child: fallback),
        );
      },
    );
  }
}
