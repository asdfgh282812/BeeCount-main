import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beecount/widgets/ui/entry_date_time_picker.dart';
import '../../data/db.dart';
import '../../data/repositories/local/local_repository.dart';
import '../../providers/shared_ledger_providers.dart';
import '../../styles/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/data/note_history_service.dart';
import '../../models/note_history.dart';
import '../../services/attachment_service.dart';
import '../../providers.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../utils/amount_calculator.dart';
import '../../utils/card_reward_calc.dart';
import '../../utils/currencies.dart' show getCurrencySymbol;
import '../../utils/shared_ledger_picker_filter.dart';
import '../../pages/tag/widgets/tag_selector.dart';
import 'card_reward_rule_selector.dart';
import '../category/category_selector.dart';
import 'category_selector_dialog.dart';
import '../category_icon.dart';
import 'account_card_picker.dart';
import 'amount_calculator_keypad.dart';
import 'note_picker_dialog.dart';
import '../currency/currency_picker_sheet.dart';
import '../currency/currency_flag.dart';
import '../ui/toast.dart';
import 'tag_chip.dart';
import '../../pages/attachment/attachment_preview_page.dart';
import 'recurring_rule_advanced_sheet.dart';
import 'shared_entry_fields.dart';

/// 表單提交結果——原本定義在 `amount_editor_sheet.dart`(該檔案已刪除,
/// `AmountEditorSheet` modal 的唯一呼叫方 `transfer_form.dart` 已改成單頁式
/// 自行提交,不再需要那個 widget;這個型別仍是 `TransactionEntryForm` 跟上層
/// `transaction_editor_page.dart` 之間唯一還在用的共用形狀,搬來這裡)。
/// v38 拆帳:表單提交時單筆拆分明細的結果,交給上層(transaction_editor_page.dart)
/// 轉成 `TransactionSplitInput` 寫入 repo。`categoryId`/`categorySyncId` 跟
/// `_handleSubmit` 對單一分類欄位的 synthetic(id<0)處理同一套規則——
/// synthetic 分類只帶 syncId,categoryId 留 null。
class SplitLineResult {
  final int? categoryId;
  final String? categorySyncId;
  final double amount;
  final String? note;

  const SplitLineResult({
    this.categoryId,
    this.categorySyncId,
    required this.amount,
    this.note,
  });
}

typedef AmountEditorResult = ({
  double amount,
  String? note,
  String? merchant,
  DateTime date,
  int? accountId,
  List<int> tagIds,
  List<File> pendingAttachments,
  bool excludeFromStats,
  bool excludeFromBudget,
  // v30 交易级多币种:交易币种(有账户=账户币种;无账户=手选,默认本位币)
  // 与折本位币快照(同币种 == amount;外币 = amount × 汇率,缺汇率已在提交前阻断)。
  String? currencyCode,
  double? nativeAmount,
  // v35:信用卡紅利回饋——使用者勾選的回饋規則 syncId 列表(空 list = 沒勾)。
  List<String> rewardRuleIds,
  // v36:週期性收支——非 null 時上層改呼叫 createRule 而不是 addTransaction。
  // 只在新增模式(editingTransactionId == null)才可能非 null,見表單內
  // `_buildRecurringRow` 只在新增模式渲染的註解。
  RecurringRuleDraft? recurringDraft,
  // v38 拆帳:三態語義比照 TransactionRepository.updateTransaction 的
  // splits 參數——null=沒碰過拆帳(維持原本單分類流程,上層走
  // categoryId/categorySyncIdOverride);[]=編輯時使用者把原本的拆帳交易
  // 「還原」成單一分類(上層需顯式清空);非空=目前是拆帳交易,整組覆蓋。
  List<SplitLineResult>? splits,
});

/// v36:`onSubmit` 回傳 `Future<void>`(原本是 `void`)——編輯「週期規則
/// occurrence」時上層要先跳「此記錄/連同未來週期」選擇彈窗,使用者取消時整
/// 個存檔動作會中止且不會 pop 頁面,表單需要知道「等它做完」才能解除
/// `_isSubmitting`,不然存檔鍵會卡在禁用狀態。正常存檔成功的路徑上層仍會
/// `Navigator.pop`,`_submit()` 的 `whenComplete` 在那之後才跑,`mounted`
/// 已经是 false,`if (mounted)` 保護下自然是 no-op,行為不變。
typedef TransactionSubmitCallback = Future<void> Function(
    Category category, AmountEditorResult result);

/// 支出/收入新增交易的單頁式表單(比照 Moze 參考圖):類別、金額、名稱、
/// 商家、帳戶、標籤/附件/旗標、日期一次呈現,不再是「先選類別 → 再彈金額
/// 輸入 modal」的兩步流程。
///
/// 業務邏輯(多幣別 chip/匯率、標籤、附件、旗標、備註歷史、decimal 安全
/// 計算、鍵盤固定於底部+跟系統鍵盤互斥顯示)`transfer_form.dart` 的單頁式
/// 轉帳表單是以這份為底稿複製改寫——刻意不抽共用 base class,避免兩邊互相
/// 耦合。存檔那段 orchestration 不在這裡,回呼給上層
/// `transaction_editor_page.dart`(同一個 `AmountEditorResult` 型別)。
class TransactionEntryForm extends ConsumerStatefulWidget {
  final String kind; // 'expense' / 'income'
  final int? initialCategoryId;
  final DateTime initialDate;
  final double? initialAmount;
  final String? initialNote;
  final String? initialMerchant;
  final int? initialAccountId;
  final List<int>? initialTagIds;
  final int ledgerId;
  final int? editingTransactionId;
  final bool initialExcludeFromStats;
  final bool initialExcludeFromBudget;
  final String? initialCurrencyCode;
  final double? initialNativeAmount;
  // v35:編輯模式回填已勾選的信用卡紅利回饋規則(syncId 列表)。
  final List<String>? initialRewardRuleIds;
  // v38 拆帳:false 時完全不提供拆帳入口(目前只有「從退款入口新增」這個
  // 場景會傳 false——退款單不能同時是拆帳交易,見
  // transaction_editor_page.dart 的 initialRefundOfSyncId)。
  final bool allowSplit;
  final TransactionSubmitCallback onSubmit;

  const TransactionEntryForm({
    super.key,
    required this.kind,
    this.initialCategoryId,
    required this.initialDate,
    this.initialAmount,
    this.initialNote,
    this.initialMerchant,
    this.initialAccountId,
    this.initialTagIds,
    required this.ledgerId,
    this.editingTransactionId,
    this.initialExcludeFromStats = false,
    this.initialExcludeFromBudget = false,
    this.initialCurrencyCode,
    this.initialNativeAmount,
    this.initialRewardRuleIds,
    this.allowSplit = true,
    required this.onSubmit,
  });

  @override
  ConsumerState<TransactionEntryForm> createState() =>
      TransactionEntryFormState();
}

/// v38 拆帳:表單內部編輯中的一筆拆分明細(可變,金鑰盤直接改 amount)。
/// 跟 [SplitLineResult] 的差異——這個是編輯態(持有完整 [Category] 物件供
/// UI 畫圖示/名稱),送出時才轉成 [SplitLineResult] 那個純資料形狀。
class _SplitLine {
  Category category;
  double amount;
  String? note;

  _SplitLine({required this.category, required this.amount, this.note});
}

/// 公開(非底線開頭)是刻意的——`transaction_editor_page.dart` 需要透過
/// `GlobalKey<TransactionEntryFormState>` 呼叫 [exportSharedFields] /
/// [applySharedFields] 在切 tab 時同步共用欄位,見該檔案 `_syncSharedFieldsOnTabChange`。
class TransactionEntryFormState extends ConsumerState<TransactionEntryForm>
    with AutomaticKeepAliveClientMixin<TransactionEntryForm> {
  // v36:支出/收入兩個 tab 各自是一個長駐的 TransactionEntryForm 實例,包在
  // 同一個 TabBarView 裡。TabBarView 底層的 PageView 用 SliverChildListDelegate
  // 管理 children,預設會依 cacheExtent 把捲出畫面範圍的分頁 State 整個丟棄
  // 重建——不加這個 mixin 的話,切到別的 tab 再切回來,使用者已輸入的金額/
  // 名稱/商家/帳戶/標籤等欄位會被清空回到 initState 的初始值(等於重置)。
  // wantKeepAlive=true 強制這個 State 全程留在樹上,不受捲動快取範圍影響。
  @override
  bool get wantKeepAlive => true;

  // ===== 類別選擇 =====
  Category? _selectedCategory;
  bool _categoryGridExpanded = true; // 未選類別時預設展開

  // ===== v38 拆帳(split into multiple categories) =====
  // 不變式:_splits.isNotEmpty(拆帳模式中)時,_activeSplitIndex 恆為
  // _splits 的合法索引——每個結構性操作(新增/移除/切換/初始回填)都會
  // 一併設好它,讓底部金鑰盤/上方金額顯示永遠對應到「目前正在編輯哪一筆」,
  // 不會出現「拆帳中但沒有任何一筆在編輯」的曖昧態。
  final List<_SplitLine> _splits = [];
  int? _activeSplitIndex;
  // 編輯模式下,原本這筆交易「一開始」是否為拆帳交易——用來在使用者於編輯
  // 中把拆帳「還原」成單一分類時,區分「[]=顯式清空」跟「null=從未碰過
  // 拆帳」這兩種對 repo 語義不同的情況(見 AmountEditorResult.splits 註解)。
  bool _wasInitiallySplit = false;

  // ===== 金額表達式 =====
  late String _amountStr;
  late DateTime _date;
  int? _selectedAccountId;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _merchantCtrl = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _merchantFocus = FocusNode();
  double _acc = 0;
  String? _op;

  List<NoteHistoryEntry> _frequentNotes = [];
  List<double> _recentAmounts = [];

  bool _isSubmitting = false;

  late List<int> _selectedTagIds;
  late List<String> _selectedRewardRuleIds;
  List<File> _pendingAttachments = [];
  // v36:週期性收支——只在新增模式提供入口(見 _buildRecurringRow),編輯既有
  // 交易一律走原本的單筆更新流程,不支援回填/再次調整規則(範圍決策,詳見
  // docs/changes)。
  RecurringRuleDraft? _recurringDraft;

  bool _excludeFromStats = false;
  bool _excludeFromBudget = false;

  // v30 交易级多币种(跟 amount_editor_sheet.dart 同一套逻辑)
  String? _pickedCurrency;
  String? _selectedAccountCurrency;
  String? _selectedAccountName;
  // v35:信用卡紅利回饋——只有選中帳戶是 credit_card 時才啟用回饋選單。
  String? _selectedAccountType;
  String? _rateStr;
  bool _rateManuallySet = false;
  bool _fetchingRate = false;
  String? _rateFetchAttemptedFor;

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(_onTextFieldFocusChange);
    _merchantFocus.addListener(_onTextFieldFocusChange);
    _date = widget.initialDate;
    _excludeFromStats = widget.initialExcludeFromStats;
    _excludeFromBudget = widget.initialExcludeFromBudget;
    _selectedAccountId = widget.initialAccountId;
    _selectedTagIds = List.from(widget.initialTagIds ?? []);
    _selectedRewardRuleIds = List.from(widget.initialRewardRuleIds ?? []);
    _pickedCurrency = widget.initialCurrencyCode?.toUpperCase();

    final initAmount = widget.initialAmount ?? 0;
    final initNative = widget.initialNativeAmount;
    if (initNative != null && initAmount > 0 && initNative != initAmount) {
      _rateStr = (initNative / initAmount).toStringAsPrecision(6);
      _rateManuallySet = true;
    }
    if (widget.initialAccountId != null) {
      _loadSelectedAccount(widget.initialAccountId!);
    }

    final s = initAmount.toStringAsFixed(2);
    final trimmed = s.contains('.')
        ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : s;
    _amountStr = trimmed.isEmpty ? '0' : trimmed;
    _nameCtrl.text = widget.initialNote ?? '';
    _merchantCtrl.text = widget.initialMerchant ?? '';

    _resolveInitialCategory();
    _resolveInitialSplits();
    if (widget.editingTransactionId == null &&
        widget.initialAccountId == null) {
      _loadDefaultAccount();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _merchantCtrl.dispose();
    _nameFocus.dispose();
    _merchantFocus.dispose();
    super.dispose();
  }

  /// 名稱/商家欄位聚焦時收起底部小算盤(改用 iOS 原生鍵盤,可輸入中文);
  /// 兩者都失焦時小算盤才重新出現。點金額顯示區會主動 unfocus 觸發這裡。
  void _onTextFieldFocusChange() {
    if (mounted) setState(() {});
  }

  bool get _textFieldFocused => _nameFocus.hasFocus || _merchantFocus.hasFocus;

  /// 供 `transaction_editor_page.dart` 切 tab 時讀出目前已輸入的共用欄位。
  SharedEntryFields exportSharedFields() => (
        amountStr: _amountStr,
        amountAcc: _acc,
        amountOp: _op,
        date: _date,
        note: _nameCtrl.text,
        merchant: _merchantCtrl.text,
        tagIds: List.of(_selectedTagIds),
        accountId: _selectedAccountId,
      );

  /// 把另一個分頁匯出的共用欄位套用到這裡——切 tab 時讓支出/收入/轉帳「看起
  /// 來像同一份草稿」,取代原本各分頁獨立 `AutomaticKeepAliveClientMixin`
  /// 只保留「自己那份」輸入、切過去仍是空白的體驗。`accountId` 為 null 代表
  /// 來源分頁沒選帳戶,維持這裡原本的選擇不動;非 null 且跟目前不同才觸發
  /// 帳戶詳情重新載入(幣種/名稱/類型),避免不必要的請求跟回饋規則被誤清空。
  void applySharedFields(SharedEntryFields f) {
    if (!mounted) return;
    setState(() {
      _amountStr = f.amountStr;
      _acc = f.amountAcc;
      _op = f.amountOp;
      _date = f.date;
      _nameCtrl.text = f.note;
      _merchantCtrl.text = f.merchant;
      _selectedTagIds = List.of(f.tagIds);
    });
    if (f.accountId != null && f.accountId != _selectedAccountId) {
      final accountChanged = _selectedAccountId != null;
      setState(() {
        _selectedAccountId = f.accountId;
        _selectedAccountCurrency = null;
        _selectedAccountName = null;
        _selectedAccountType = null;
        if (accountChanged) _selectedRewardRuleIds = [];
      });
      _loadSelectedAccount(f.accountId!);
    }
  }

  /// 回顯已選類別(編輯模式 / 呼叫端帶入 initialCategoryId 預選時)。
  /// §7 共享账本:initialCategoryId 可能是 synthetic(< 0),要走
  /// SharedLedgerCategories 反查,跟旧 `TransactionEditorPage` 的逻辑一致。
  Future<void> _resolveInitialCategory() async {
    final id = widget.initialCategoryId;
    if (id == null) return;
    final repo = ref.read(repositoryProvider);
    Category? c;
    if (id < 0 && repo is LocalRepository) {
      c = await repo.db.findCategoryBySyntheticId(id);
    } else {
      c = await repo.getCategoryById(id);
    }
    if (c != null && mounted) {
      setState(() {
        _selectedCategory = c;
        _categoryGridExpanded = false;
      });
      _onCategoryChanged();
    }
  }

  /// v38 拆帳:編輯模式回顯已存在的拆分明細。跟 [_resolveInitialCategory]
  /// 對稱,只在 editingTransactionId 非 null 時跑;§7 共享帳本 synthetic
  /// 分類走 findCategoryBySyntheticId(同 [_resolveInitialCategory] 的做法,
  /// 只是反過來先用 [syntheticIdForSyncId] 從 syncId 算出 synthetic id)。
  Future<void> _resolveInitialSplits() async {
    final id = widget.editingTransactionId;
    if (id == null) return;
    final repo = ref.read(repositoryProvider);
    final rows = await repo.getTransactionSplits(id);
    if (rows.isEmpty) return;
    final lines = <_SplitLine>[];
    for (final row in rows) {
      Category? cat;
      final override = row.categorySyncIdOverride;
      if (override != null && override.isNotEmpty && repo is LocalRepository) {
        cat = await repo.db
            .findCategoryBySyntheticId(syntheticIdForSyncId(override));
      } else if (row.categoryId != null) {
        cat = await repo.getCategoryById(row.categoryId!);
      }
      if (cat != null) {
        lines.add(_SplitLine(category: cat, amount: row.amount, note: row.note));
      }
    }
    // 少於 2 筆代表分類都查無資料(異常態),退化成不显示拆帳,避免呈現
    // 一筆看起来像單一分類、又不能存檔(canSubmit 要求 >=2)的卡死狀態。
    if (lines.length < 2 || !mounted) return;
    setState(() {
      _splits
        ..clear()
        ..addAll(lines);
      _wasInitiallySplit = true;
      _selectedCategory = null;
      _categoryGridExpanded = false;
      _activeSplitIndex = 0;
      _loadAmountIntoKeypad(lines[0].amount);
    });
  }

  /// 获取默认账户ID（验证币种匹配）——从旧 `TransactionEditorPage` 搬来,
  /// 仅新建交易且没有指定初始账户时才生效。
  Future<void> _loadDefaultAccount() async {
    try {
      final defaultAccountId = widget.kind == 'income'
          ? await ref.read(defaultIncomeAccountIdProvider.future)
          : await ref.read(defaultExpenseAccountIdProvider.future);
      if (defaultAccountId == null) return;

      final ledger = await ref.read(ledgerByIdProvider(widget.ledgerId).future);
      if (ledger == null) return;

      final account =
          await ref.read(accountByIdProvider(defaultAccountId).future);
      if (account == null || account.hidden) return;
      if (account.currency != ledger.currency) return;

      if (!mounted) return;
      setState(() => _selectedAccountId = defaultAccountId);
      _loadSelectedAccount(defaultAccountId);
    } catch (_) {
      // 静默失败,退回「不选择账户」
    }
  }

  void _onCategoryChanged() {
    _loadRecentNotes();
    _loadRecentAmounts();
  }

  Future<void> _loadRecentNotes() async {
    final repo = ref.read(repositoryProvider);
    final c = _selectedCategory;
    final notes = await NoteHistoryService.getHistoryNotes(
      repository: repo,
      ledgerId: widget.ledgerId,
      scope: ref.read(noteHistoryScopeProvider),
      sort: ref.read(noteHistorySortProvider),
      categoryId: c?.id,
      categorySyncId: (c != null && c.id < 0) ? c.syncId : null,
      limit: ref.read(noteHistoryLimitProvider),
    );
    if (!mounted) return;
    setState(() => _frequentNotes = notes);
  }

  /// 常用金額列——只在選了「本地」類別(id>=0)時查詢;synthetic(共享帳本
  /// Owner)類別在本地 transactions 表裡查不到對應 category_id,直接跳過
  /// (不影響其餘記帳流程,見 `getRecentDistinctAmounts` 的方法註解)。
  Future<void> _loadRecentAmounts() async {
    final c = _selectedCategory;
    if (c == null || c.id < 0) {
      if (mounted) setState(() => _recentAmounts = []);
      return;
    }
    final repo = ref.read(repositoryProvider);
    final amounts = await repo.getRecentDistinctAmounts(
      ledgerId: widget.ledgerId,
      categoryId: c.id,
    );
    if (!mounted) return;
    setState(() => _recentAmounts = amounts);
  }

  /// 同時載入所選帳戶的幣種(給幣種優先聯動用)跟名稱(給帳戶列顯示用)。
  /// 正數 id 查主表;負數是共享帳本 Owner 資源的 synthetic id(§7),查
  /// SharedLedgerAccounts 鏡像——跟 `getAccountCurrencyByAnyId` 同一套規則。
  Future<void> _loadSelectedAccount(int accountId) async {
    final repo = ref.read(repositoryProvider);
    Account? acc;
    if (accountId >= 0) {
      acc = await repo.getAccount(accountId);
    } else if (repo is LocalRepository) {
      acc = await repo.db.findAccountBySyntheticId(accountId);
    }
    if (!mounted) return;
    setState(() {
      _selectedAccountName = acc?.name;
      _selectedAccountType = acc?.type;
      _selectedAccountCurrency = (acc?.currency.isNotEmpty ?? false)
          ? acc!.currency.toUpperCase()
          : null;
    });
  }

  String _txCurrency() {
    if (_selectedAccountId != null) {
      return _selectedAccountCurrency ??
          _pickedCurrency ??
          ref.read(currentLedgerCurrencyProvider);
    }
    return _pickedCurrency ?? ref.read(currentLedgerCurrencyProvider);
  }

  double? _currentRate() {
    if (_rateManuallySet) return double.tryParse(_rateStr ?? '');
    final rates = ref.read(effectiveRatesForLedgerProvider).valueOrNull;
    final er = rates?[_txCurrency()];
    return er == null ? null : double.tryParse(er.rate);
  }

  void _maybeAutoFetchRate() {
    final base = ref.read(currentLedgerCurrencyProvider);
    final txCurrency = _txCurrency();
    if (txCurrency == base || _rateManuallySet || _fetchingRate) return;
    if (_rateFetchAttemptedFor == txCurrency) return;
    final ratesAsync = ref.read(effectiveRatesForLedgerProvider);
    final rates = ratesAsync.valueOrNull;
    if (rates == null) return;
    if (rates.containsKey(txCurrency)) return;
    _rateFetchAttemptedFor = txCurrency;
    setState(() => _fetchingRate = true);
    refreshExchangeRatesFromUi(ref, force: true, extraQuotes: {txCurrency})
        .whenComplete(() {
      if (mounted) setState(() => _fetchingRate = false);
    });
  }

  Future<void> _pickCurrency() async {
    final l10n = AppLocalizations.of(context);
    final base = ref.read(currentLedgerCurrencyProvider);
    final picked = await showCurrencyPickerSheet(
      context,
      selected: _pickedCurrency ?? base,
      primaryColor: Theme.of(context).colorScheme.primary,
      title: l10n.txCurrencyPickerTitle,
      rateBase: base,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pickedCurrency =
          picked.toUpperCase() == base ? null : picked.toUpperCase();
      _rateStr = null;
      _rateManuallySet = false;
      _selectedAccountId = null;
      _selectedAccountCurrency = null;
      _selectedAccountName = null;
      _selectedAccountType = null;
      _selectedRewardRuleIds = [];
    });
  }

  Future<void> _editRate() async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController(
        text: _rateStr ?? _currentRate()?.toStringAsPrecision(6) ?? '');
    final entered = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(l10n.txRateLabel),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText:
                '1 ${_txCurrency()} = ? ${ref.read(currentLedgerCurrencyProvider)}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: Text(AppLocalizations.of(dctx).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
            child: Text(AppLocalizations.of(dctx).commonConfirm),
          ),
        ],
      ),
    );
    if (entered == null || !mounted) return;
    final v = double.tryParse(entered);
    if (v == null || v <= 0) return;
    setState(() {
      _rateStr = entered;
      _rateManuallySet = true;
    });
  }

  Widget _buildCurrencyChip(BuildContext context) {
    final text = Theme.of(context).textTheme;
    ref.watch(currentLedgerCurrencyProvider);
    final txCurrency = _txCurrency();
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _pickCurrency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: BeeTokens.surfaceKeySecondary(context),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            currencyFlag(context, txCurrency, width: 19, height: 14, radius: 4),
            const SizedBox(width: 5),
            Text(
              txCurrency,
              style: text.bodySmall?.copyWith(
                color: BeeTokens.textSecondary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(Icons.arrow_drop_down,
                size: 16, color: BeeTokens.iconSecondary(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrencySection(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final ledgerBase = ref.watch(currentLedgerCurrencyProvider);
    ref.watch(effectiveRatesForLedgerProvider);
    final txCurrency = _txCurrency();
    final isForeign = txCurrency != ledgerBase;
    if (!isForeign) return const SizedBox.shrink();

    final rate = _currentRate();
    if (rate == null && !_fetchingRate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeAutoFetchRate();
      });
    }
    final amount = double.tryParse(_amountStr) ?? 0.0;
    final preview = (rate != null && rate > 0) ? (amount * rate) : null;
    final rateMissing = rate == null && !_fetchingRate;

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          InkWell(
            onTap: rateMissing ? _editRate : null,
            child: Text(
              preview != null
                  ? l10n.txConvertedPreview(
                      preview.toStringAsFixed(2), ledgerBase)
                  : _fetchingRate
                      ? '≈ … $ledgerBase'
                      : l10n.txRateMissingHint,
              style: text.bodySmall?.copyWith(
                color: rateMissing
                    ? Theme.of(context).colorScheme.error
                    : BeeTokens.textTertiary(context),
              ),
            ),
          ),
        ],
      ),
    );
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

  void _pickAmountFromRecent(double amount) {
    setState(() {
      final s = amount.toStringAsFixed(2);
      final trimmed = s.contains('.')
          ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
          : s;
      _amountStr = trimmed.isEmpty ? '0' : trimmed;
      _acc = 0;
      _op = null;
    });
  }

  // ===== v38 拆帳(split into multiple categories) =====

  /// 目前小算盤(_amountStr/_acc/_op)代表的金額——跟 [_submit] 算 total
  /// 用的算式完全一致,拆帳/非拆帳共用同一套算盤狀態機。
  double get _keypadTotal =>
      _op == null ? _parsedAmount() : computeAmountOp(_acc, _op!, _parsedAmount());

  /// 把小算盤目前的金額寫回「正在編輯」的那一筆拆分明細。結構性操作(切換
  /// 焦點/新增/移除/還原)前都要先呼叫這個,否則使用者剛打的數字會在切換
  /// 時憑空消失。非拆帳模式或沒有焦點時是 no-op。
  void _commitActiveSplitAmount() {
    final i = _activeSplitIndex;
    if (i == null || i >= _splits.length) return;
    _splits[i].amount = _keypadTotal.abs();
  }

  /// 把小算盤重置成顯示 [amount](供切換到另一筆明細/新增明細時,讓金鑰盤
  /// 從那一筆既有金額或 0 開始,而不是延續前一筆殘留的運算式)。
  void _loadAmountIntoKeypad(double amount) {
    _amountStr = _fmtAbs(amount);
    _acc = 0;
    _op = null;
  }

  /// 第 [index] 筆明細目前應顯示的金額——若正是焦點所在,用小算盤的即時值
  /// (讓上方彙總圖示的總額能隨打字即時跳動);否則用已提交的值。
  double _liveAmountFor(int index) =>
      _activeSplitIndex == index ? _keypadTotal.abs() : _splits[index].amount;

  double get _splitsLiveTotal {
    var sum = 0.0;
    for (var i = 0; i < _splits.length; i++) {
      sum += _liveAmountFor(i);
    }
    return sum;
  }

  /// 拆帳入口:把目前已選的單一分類轉成第一筆明細,再讓使用者挑第二筆的
  /// 分類。跟週期性收支互斥(同一時間只能選一種),已經開了「週期」的話直接
  /// 提示、不進入拆帳模式。
  Future<void> _startSplitMode() async {
    final first = _selectedCategory;
    if (first == null) return;
    if (_recurringDraft != null) {
      showToast(context, AppLocalizations.of(context).txSplitRecurringConflict);
      return;
    }
    final picked = await showCategorySelector(
      context,
      type: widget.kind,
      excludeIds: [first.id],
    );
    if (picked == null || !mounted) return;
    final firstAmount = _keypadTotal.abs();
    setState(() {
      _splits
        ..clear()
        ..add(_SplitLine(category: first, amount: firstAmount))
        ..add(_SplitLine(category: picked, amount: 0));
      _activeSplitIndex = 1;
      _selectedCategory = null;
      _loadAmountIntoKeypad(0);
    });
  }

  /// 「+」新增一筆明細:先選分類,選完把小算盤焦點切過去讓使用者輸入金額。
  Future<void> _addSplitLine() async {
    _commitActiveSplitAmount();
    final excludeIds = _splits.map((s) => s.category.id).toList();
    final picked = await showCategorySelector(
      context,
      type: widget.kind,
      excludeIds: excludeIds,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _splits.add(_SplitLine(category: picked, amount: 0));
      _activeSplitIndex = _splits.length - 1;
      _loadAmountIntoKeypad(0);
    });
  }

  /// 點某一筆明細的圖示:非目前焦點時先把焦點切過去(金鑰盤跟著換);已經是
  /// 焦點的那一筆再點一次,代表使用者想換分類,直接開換分類選單——不然「已
  /// 經選好的分類」在點下去沒反應的情況下會被誤以為無法重選(長按雖然也能
  /// 換分類,但發現率低,見 docs/changes)。
  void _selectSplitLine(int index) {
    if (_activeSplitIndex == index) {
      _changeSplitLineCategory(index);
      return;
    }
    _commitActiveSplitAmount();
    setState(() {
      _activeSplitIndex = index;
      _loadAmountIntoKeypad(_splits[index].amount);
    });
  }

  /// 移除一筆明細——保底 2 筆(降到 1 筆語意上等於「沒有拆帳」,應該走
  /// [_revertSplitToSingleCategory],不是留一筆掛著)。
  void _removeSplitLine(int index) {
    if (_splits.length <= 2) return;
    _commitActiveSplitAmount();
    setState(() {
      _splits.removeAt(index);
      if (_activeSplitIndex == index) {
        _activeSplitIndex = 0;
        _loadAmountIntoKeypad(_splits[0].amount);
      } else if (_activeSplitIndex != null && _activeSplitIndex! > index) {
        _activeSplitIndex = _activeSplitIndex! - 1;
      }
    });
  }

  /// 更換某一筆明細的分類(不影響金額/備註)。
  Future<void> _changeSplitLineCategory(int index) async {
    final excludeIds = [
      for (var i = 0; i < _splits.length; i++)
        if (i != index) _splits[i].category.id,
    ];
    final picked = await showCategorySelector(
      context,
      type: widget.kind,
      currentCategoryId: _splits[index].category.id,
      excludeIds: excludeIds,
    );
    if (picked == null || !mounted) return;
    setState(() => _splits[index].category = picked);
  }

  /// 長按某一筆明細圖示:換分類 / 移除(< 3 筆時不給移除選項)這兩個動作。
  Future<void> _showSplitLineActions(int index) async {
    final l10n = AppLocalizations.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(l10n.txSplitChangeCategoryAction),
              onTap: () => Navigator.pop(ctx, 'change'),
            ),
            if (_splits.length > 2)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.txSplitRemoveLineAction),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'change') {
      await _changeSplitLineCategory(index);
    } else if (action == 'remove') {
      _removeSplitLine(index);
    }
  }

  /// 長按/點「多類別」彙總圖示:目前唯一動作是整組還原成單一分類。
  Future<void> _showSplitAggregateActions() async {
    final l10n = AppLocalizations.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.undo),
          title: Text(l10n.txSplitRevertAction),
          onTap: () => Navigator.pop(ctx, 'revert'),
        ),
      ),
    );
    if (action == 'revert') {
      await _revertSplitToSingleCategory();
    }
  }

  /// 把目前所有拆分明細的金額加總,選一個分類,還原成普通單分類交易。
  Future<void> _revertSplitToSingleCategory() async {
    _commitActiveSplitAmount();
    if (!mounted || _splits.isEmpty) return;
    final total = _splits.fold<double>(0, (sum, s) => sum + s.amount);
    final picked = await showCategorySelector(
      context,
      type: widget.kind,
      currentCategoryId: _splits.first.category.id,
      title: AppLocalizations.of(context).txSplitRevertPickCategoryTitle,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedCategory = picked;
      _categoryGridExpanded = false;
      _splits.clear();
      _activeSplitIndex = null;
      _loadAmountIntoKeypad(total);
    });
    _onCategoryChanged();
  }

  void _pickDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    // 日期/時間拆成兩個獨立欄位各自喚起專屬選擇器(月曆網格/HH:mm wheel),
    // 不再是合併的兩步 wheel 流程;不再限制只能选今天以前(可选未来日期)。
    final res = await showTransactionDatePicker(context, initial: _date);
    if (res == null || !mounted) return;
    setState(() {
      _date = DateTime(
          res.year, res.month, res.day, _date.hour, _date.minute, _date.second);
    });
  }

  void _pickTime() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    final res = await showTransactionTimePicker(
      context,
      initial: TimeOfDay(hour: _date.hour, minute: _date.minute),
    );
    if (res == null || !mounted) return;
    setState(() {
      _date = DateTime(_date.year, _date.month, _date.day, res.hour, res.minute,
          _date.second);
    });
  }

  Future<void> _openAccountPicker() async {
    final result = await AccountCardPicker.show(
      context,
      ledgerId: widget.ledgerId,
      selectedAccountId: _selectedAccountId,
      filterCurrency: _txCurrency(),
      pinnedAccountId: widget.initialAccountId,
    );
    // result == null:取消/滑动关闭,维持原本选择不变。
    // result.accountId == null:明确选了「不选择账户」,清空。
    if (result == null || !mounted) return;
    final id = result.accountId;
    final accountChanged = id != _selectedAccountId;
    setState(() {
      _selectedAccountId = id;
      _selectedAccountCurrency = null;
      _selectedAccountName = null;
      _selectedAccountType = null;
      // 換帳戶時清掉舊選的回饋規則——規則綁定特定信用卡帳戶,換帳戶後舊選
      // 擇不再有意義(甚至可能不屬於新帳戶,寫入會被 write 校驗擋掉)。
      if (accountChanged) _selectedRewardRuleIds = [];
    });
    if (id != null) _loadSelectedAccount(id);
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    double total;
    if (_splits.isNotEmpty) {
      _commitActiveSplitAmount();
      if (_splits.length < 2 || _splits.any((s) => s.amount <= 0)) return;
      total = _splits.fold<double>(0, (sum, s) => sum + s.amount);
    } else {
      if (_selectedCategory == null) return;
      total = _op == null
          ? _parsedAmount()
          : computeAmountOp(_acc, _op!, _parsedAmount());
      if (total.abs() <= 0) return;
    }
    final category = _selectedCategory ?? _splits.first.category;

    if (_selectedAccountId == null) {
      showToast(context, AppLocalizations.of(context).txAccountRequiredHint);
      return;
    }

    setState(() => _isSubmitting = true);

    final txCurrency = _txCurrency();
    final ledgerBase = ref.read(currentLedgerCurrencyProvider);
    double? nativeAmount;
    if (txCurrency == ledgerBase) {
      nativeAmount = total.abs();
    } else {
      final r = _currentRate();
      if (r == null || r <= 0) {
        setState(() => _isSubmitting = false);
        showToast(context, AppLocalizations.of(context).txRateMissingHint);
        return;
      }
      nativeAmount = total.abs() * r;
    }

    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
    widget.onSubmit(
      category,
      (
        amount: total.abs(),
        note: _nameCtrl.text.isEmpty ? null : _nameCtrl.text,
        merchant: _merchantCtrl.text.isEmpty ? null : _merchantCtrl.text,
        date: _date,
        accountId: _selectedAccountId,
        tagIds: _selectedTagIds,
        pendingAttachments: _pendingAttachments,
        excludeFromStats: _excludeFromStats,
        excludeFromBudget: _excludeFromBudget,
        currencyCode: txCurrency,
        nativeAmount: nativeAmount,
        rewardRuleIds: _selectedRewardRuleIds,
        recurringDraft:
            widget.editingTransactionId == null ? _recurringDraft : null,
        // 三態:目前拆帳中 → 整組明細;從未碰過拆帳 → null(維持原路徑);
        // 曾經是拆帳、這次還原了 → [](顯式清空,見 _wasInitiallySplit 註解)。
        splits: _splits.isNotEmpty
            ? _splits
                .map((s) => SplitLineResult(
                      categoryId: s.category.id < 0 ? null : s.category.id,
                      categorySyncId:
                          s.category.id < 0 ? s.category.syncId : null,
                      amount: s.amount,
                      note: s.note,
                    ))
                .toList()
            : (_wasInitiallySplit ? const <SplitLineResult>[] : null),
      ),
    ).whenComplete(() {
      // 正常存檔成功:上層已經 pop 頁面,這裡 mounted 已是 false,no-op。
      // 中止路徑(v36:使用者取消「此記錄/連同未來週期」選擇彈窗):頁面沒被
      // pop,要解除禁用狀態讓使用者能重新操作存檔鍵。
      if (mounted) setState(() => _isSubmitting = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 要求
    final primary = Theme.of(context).colorScheme.primary;
    final text = Theme.of(context).textTheme;

    final cur = _parsedAmount();
    final total = _op == null ? cur : computeAmountOp(_acc, _op!, cur);
    final isInCalcMode = _op != null;
    final canSubmit = _splits.isNotEmpty
        ? (_splits.length >= 2 &&
            List.generate(_splits.length, _liveAmountFor)
                .every((a) => a > 0))
        : (_selectedCategory != null &&
            (isInCalcMode ? true : total.abs() > 0));

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCategorySection(context),
                const SizedBox(height: 10),
                // 金额表达式行——外面包 GestureDetector,点一下主动收起
                // 名稱/商家欄位的系統鍵盤,讓底部小算盤重新出現(「只有輸入
                // 金額才叫用數字小算盤」)。
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          if (widget.editingTransactionId != null)
                            _TxAuthorAvatars(
                                editingTransactionId:
                                    widget.editingTransactionId!),
                          const Spacer(),
                          _buildCurrencyChip(context),
                          const SizedBox(width: 6),
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
                      _buildCurrencySection(context),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // 名稱欄(=備註,合併掉原本分開的名稱/備註兩個欄位)
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
                    prefixIcon: _frequentNotes.isNotEmpty
                        ? GestureDetector(
                            onTap: () async {
                              await showDialog(
                                context: context,
                                builder: (context) => NotePickerDialog(
                                  ledgerId: widget.ledgerId,
                                  categoryId: _selectedCategory?.id,
                                  categorySyncId: (_selectedCategory != null &&
                                          _selectedCategory!.id < 0)
                                      ? _selectedCategory!.syncId
                                      : null,
                                  onNotePicked: (note) {
                                    setState(() {
                                      _nameCtrl.text = note;
                                      _nameCtrl.selection =
                                          TextSelection.fromPosition(
                                              TextPosition(
                                                  offset: note.length));
                                    });
                                  },
                                ),
                              );
                            },
                            child: Icon(Icons.history,
                                color: BeeTokens.iconSecondary(context),
                                size: 20),
                          )
                        : null,
                    prefixIconConstraints: _frequentNotes.isNotEmpty
                        ? const BoxConstraints(minWidth: 40, minHeight: 20)
                        : null,
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
                _buildAccountRow(context),
                const SizedBox(height: 8),
                _buildTagAndAttachmentRow(),
                _buildEstimatedRewardRow(),
                const SizedBox(height: 8),
                _buildDateRow(context),
                // v38:拆帳交易不提供「週期」入口(兩者互斥,見
                // _startSplitMode 對稱的檢查)。
                if (widget.editingTransactionId == null &&
                    _splits.isEmpty) ...[
                  const SizedBox(height: 8),
                  _buildRecurringRow(context),
                ],
                const SizedBox(height: 10),
                if (_recentAmounts.isNotEmpty) ...[
                  _buildRecentAmountsRow(context),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
        ),
        // 小算盤固定貼底,不隨內容捲動;名稱/商家欄位聚焦時讓位給系統鍵盤,
        // 避免兩層鍵盤搶版面、還要往下滑才看得到送出鍵。
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

  Widget _buildCategorySection(BuildContext context) {
    if (_splits.isNotEmpty) {
      return _buildSplitChipStrip(context);
    }
    final c = _selectedCategory;
    if (c == null || _categoryGridExpanded) {
      // compactGrid:主类别网格固定 2 行(超出内部滚动),点有子类别的项目
      // 直接切换到子类别网格(index 0 固定「返回」),不再原地手风琴展开——
      // 见需求 #3。网格自身按 2 行定高,这里不用再套外层 SizedBox。
      return CategorySelector(
        kind: widget.kind,
        initialCategoryId: widget.initialCategoryId,
        compactGrid: true,
        onCategorySelected: (picked) {
          setState(() {
            _selectedCategory = picked;
            _categoryGridExpanded = false;
          });
          _onCategoryChanged();
        },
      );
    }
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _categoryGridExpanded = true),
            child: Row(
              children: [
                CategoryIconWidget(
                  category: c,
                  size: 24,
                  showBackground: true,
                  circular: true,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.unfold_more,
                    size: 16, color: BeeTokens.iconSecondary(context)),
              ],
            ),
          ),
        ),
        // v38 拆帳入口:只在已選好第一個分類、允許拆帳(非退款新增)時顯示。
        if (widget.allowSplit)
          IconButton(
            onPressed: _startSplitMode,
            tooltip: AppLocalizations.of(context).txSplitToggle,
            icon: Icon(Icons.call_split,
                size: 20, color: BeeTokens.iconSecondary(context)),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
      ],
    );
  }

  /// v38 拆帳模式的橫向圖示條:最前面是「多類別」聚合圖示(徽章=筆數、
  /// 顯示即時總額),依序是每筆明細的分類圖示+金額,最後是「+」新增。
  /// 比照使用者提供的 Moze 截圖排版。
  Widget _buildSplitChipStrip(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 86,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _SplitChip(
            onTap: _showSplitAggregateActions,
            onLongPress: _showSplitAggregateActions,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: BeeTokens.surfaceInput(context),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.apps,
                      color: BeeTokens.iconSecondary(context)),
                ),
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_splits.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
            label: l10n.txSplitAggregateLabel,
            amountText: _fmtAbs(_splitsLiveTotal),
            highlighted: false,
          ),
          for (var i = 0; i < _splits.length; i++) ...[
            const SizedBox(width: 10),
            _SplitChip(
              onTap: () => _selectSplitLine(i),
              onLongPress: () => _showSplitLineActions(i),
              icon: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: _activeSplitIndex == i
                      ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2)
                      : null,
                ),
                padding: const EdgeInsets.all(2),
                child: CategoryIconWidget(
                  category: _splits[i].category,
                  size: 26,
                  showBackground: true,
                  circular: true,
                ),
              ),
              label: _splits[i].category.name,
              amountText: _fmtAbs(_liveAmountFor(i)),
              highlighted: _activeSplitIndex == i,
            ),
          ],
          const SizedBox(width: 10),
          _SplitChip(
            onTap: _addSplitLine,
            icon: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: BeeTokens.surfaceInput(context),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add, color: BeeTokens.iconSecondary(context)),
            ),
            label: '',
            amountText: '',
            highlighted: false,
          ),
        ],
      ),
    );
  }

  Widget _buildAccountRow(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final accountFeatureAsync = ref.watch(accountFeatureEnabledProvider);
      return accountFeatureAsync.when(
        data: (enabled) {
          if (!enabled) return const SizedBox.shrink();
          final name = _selectedAccountId != null
              ? (_selectedAccountName ?? '')
              : AppLocalizations.of(context).accountNone;
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _openAccountPicker,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: BeeTokens.textPrimary(context), fontSize: 14),
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 18, color: BeeTokens.iconTertiary(context)),
                ],
              ),
            ),
          );
        },
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
      );
    });
  }

  Widget _buildDateRow(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final showTime = ref.watch(showTransactionTimeProvider);
    String fmtDate(DateTime d) => '${d.year}/${d.month}/${d.day}';
    String fmtTime(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    Widget field({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            SystemSound.play(SystemSoundType.click);
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: BeeTokens.surfaceInput(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: BeeTokens.iconSecondary(context)),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: text.bodyMedium?.copyWith(
                      color: BeeTokens.textPrimary(context),
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        field(
          icon: Icons.calendar_today_outlined,
          label: fmtDate(_date),
          onTap: _pickDate,
        ),
        if (showTime) ...[
          const SizedBox(width: 8),
          field(
            icon: Icons.access_time,
            label: fmtTime(_date),
            onTap: _pickTime,
          ),
        ],
      ],
    );
  }

  Future<void> _openRecurringSheet() async {
    final result = await RecurringRuleAdvancedSheet.show(
      context,
      anchorDate: _date,
      initialDraft: _recurringDraft,
    );
    // showModalBottomSheet 滑動關閉(未 pop 值)時 result 也是 null,跟「使用
    // 者主動選單次」無法區分——两种情况下都应该关掉週期,行为一致,不用像
    // AccountCardPicker 那样額外包一層區分。
    if (!mounted) return;
    setState(() => _recurringDraft = result);
  }

  Widget _buildRecurringRow(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = _recurringDraft;
    final label = draft == null ? l10n.txDetailOnce : draft.summary(l10n);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _openRecurringSheet,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: BeeTokens.surfaceInput(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.repeat,
                size: 16, color: BeeTokens.iconSecondary(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: BeeTokens.textPrimary(context), fontSize: 14),
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: BeeTokens.iconTertiary(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentAmountsRow(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _recentAmounts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final amount = _recentAmounts[i];
          final s = amount.toStringAsFixed(2);
          final label = s.contains('.')
              ? s
                  .replaceFirst(RegExp(r'0+$'), '')
                  .replaceFirst(RegExp(r'\.$'), '')
              : s;
          return GestureDetector(
            onTap: () => _pickAmountFromRecent(amount),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: BeeTokens.surfaceChip(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                      fontSize: 13, color: BeeTokens.textSecondary(context)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 純前端估算,不 call server——真正入帳金額仍由 BeeCount Cloud 排程計算
  /// (門檻/上限/共同上限群組等跨交易邏輯只有 server 端看得到完整資料)。
  /// 這裡只是金額輸入當下的即時提示,幫使用者判斷「大概能拿多少」。
  double _estimatedReward() {
    final rules = _selectedRewardRules();
    if (rules.isEmpty) return 0;
    final amount = _op == null
        ? _parsedAmount()
        : computeAmountOp(_acc, _op!, _parsedAmount());
    return estimateCardRewardTotal(rules, amount);
  }

  Widget _buildEstimatedRewardRow() {
    if (!_rewardRuleSelectionEnabled || _selectedRewardRuleIds.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final estimated = _estimatedReward();
    final currency = _txCurrency();
    final amountStr =
        '${getCurrencySymbol(currency)}${estimated.toStringAsFixed(2)}';
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          l10n.cardRewardRuleEstimatedReward(amountStr),
          style: TextStyle(
            fontSize: 12.5,
            color: BeeTokens.textSecondary(context),
          ),
        ),
      ),
    );
  }

  Widget _buildTagAndAttachmentRow() {
    final allTagsAsync = ref.watch(tagsForCurrentLedgerProvider);
    final allTags = allTagsAsync.valueOrNull ?? [];
    final selectedTags =
        allTags.where((t) => _selectedTagIds.contains(t.id)).toList();

    if (widget.editingTransactionId != null) {
      final attachmentsAsync = ref
          .watch(transactionAttachmentsProvider(widget.editingTransactionId!));
      final attachments = attachmentsAsync.valueOrNull ?? [];
      final totalCount = attachments.length + _pendingAttachments.length;
      return _buildRowContent(selectedTags, totalCount, attachments);
    }
    return _buildRowContent(selectedTags, _pendingAttachments.length, []);
  }

  Future<void> _showFlagsDialog() async {
    final l10n = AppLocalizations.of(context);
    final primary = ref.watch(primaryColorProvider);
    final showStats = true; // widget.kind 恒为 expense/income
    final showBudget = widget.kind == 'expense';

    bool stats = _excludeFromStats;
    bool budget = _excludeFromBudget;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Widget switchTile({
              required String title,
              required String hint,
              required bool value,
              required ValueChanged<bool> onChanged,
            }) {
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  title,
                  style: TextStyle(
                      color: BeeTokens.textPrimary(context),
                      fontSize: 15.0.scaled(context, ref)),
                ),
                subtitle: Text(
                  hint,
                  style: TextStyle(
                      color: BeeTokens.textTertiary(context),
                      fontSize: 12.0.scaled(context, ref)),
                ),
                value: value,
                activeColor: primary,
                onChanged: onChanged,
              );
            }

            return AlertDialog(
              backgroundColor: BeeTokens.surface(context),
              title: Text(
                l10n.txFlagDialogTitle,
                style: TextStyle(
                  color: BeeTokens.textPrimary(context),
                  fontSize: 17.0.scaled(context, ref),
                  fontWeight: FontWeight.w600,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showStats)
                    switchTile(
                      title: l10n.txFlagExcludeFromStats,
                      hint: l10n.txFlagExcludeFromStatsHint,
                      value: stats,
                      onChanged: (v) {
                        setDialogState(() => stats = v);
                        setState(() => _excludeFromStats = v);
                      },
                    ),
                  if (showBudget)
                    switchTile(
                      title: l10n.txFlagExcludeFromBudget,
                      hint: l10n.txFlagExcludeFromBudgetHint,
                      value: budget,
                      onChanged: (v) {
                        setDialogState(() => budget = v);
                        setState(() => _excludeFromBudget = v);
                      },
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(AppLocalizations.of(context).commonConfirm,
                      style: TextStyle(color: primary)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// v35:選中帳戶是信用卡時,才能挑紅利回饋規則——回饋方案綁定特定信用卡,
  /// 非信用卡帳戶(或沒選帳戶)選單裡不會有任何規則可挑。
  bool get _rewardRuleSelectionEnabled => _selectedAccountType == 'credit_card';

  List<CardRewardRule> _selectedRewardRules() {
    if (_selectedRewardRuleIds.isEmpty || _selectedAccountId == null) {
      return const [];
    }
    final all = ref
            .watch(cardRewardRulesForAccountProvider(_selectedAccountId!))
            .valueOrNull ??
        const [];
    return all.where((r) => _selectedRewardRuleIds.contains(r.syncId)).toList();
  }

  String _rewardChipLabel(CardRewardRule r) {
    final v = r.rateValue;
    final vs = v.toStringAsFixed(v == v.truncateToDouble() ? 0 : 2);
    return r.rateType == 'fixed_amount'
        ? '${r.label} ($vs)'
        : '${r.label} ($vs%)';
  }

  Future<void> _openRewardRuleSelector() async {
    if (_selectedAccountId == null) return;
    final result = await CardRewardRuleSelector.show(
      context,
      accountId: _selectedAccountId!,
      selectedSyncIds: _selectedRewardRuleIds,
    );
    if (result != null) {
      setState(() => _selectedRewardRuleIds = result);
    }
  }

  Widget _buildRowContent(List<Tag> selectedTags, int attachmentCount,
      List<TransactionAttachment> savedAttachments) {
    final l10n = AppLocalizations.of(context);
    final hasAttachments = attachmentCount > 0;
    final selectedRewardRules = _selectedRewardRules();
    final hasAnyChip =
        selectedTags.isNotEmpty || selectedRewardRules.isNotEmpty;

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
                if (result != null) {
                  setState(() => _selectedTagIds = result);
                }
              },
              behavior: HitTestBehavior.opaque,
              child: !hasAnyChip
                  ? Text(
                      l10n.tagSelectTitle,
                      style: TextStyle(
                          color: BeeTokens.textTertiary(context), fontSize: 14),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ...selectedTags.map((tag) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: TagChip(
                                    name: tag.name,
                                    color: tag.color,
                                    size: TagChipSize.small),
                              )),
                          ...selectedRewardRules.map((rule) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: TagChip(
                                  name: _rewardChipLabel(rule),
                                  size: TagChipSize.small,
                                  showDelete: true,
                                  onDelete: () => setState(() =>
                                      _selectedRewardRuleIds =
                                          _selectedRewardRuleIds
                                              .where((id) => id != rule.syncId)
                                              .toList()),
                                ),
                              )),
                        ],
                      ),
                    ),
            ),
          ),
          if (_rewardRuleSelectionEnabled) ...[
            const SizedBox(width: 16),
            GestureDetector(
              onTap: _openRewardRuleSelector,
              behavior: HitTestBehavior.opaque,
              child: Icon(
                selectedRewardRules.isNotEmpty
                    ? Icons.card_giftcard
                    : Icons.card_giftcard_outlined,
                size: 18,
                color: selectedRewardRules.isNotEmpty
                    ? Theme.of(context).colorScheme.primary
                    : BeeTokens.iconSecondary(context),
              ),
            ),
          ],
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
          const SizedBox(width: 16),
          GestureDetector(
            onTap: _showFlagsDialog,
            behavior: HitTestBehavior.opaque,
            child: Icon(
              (_excludeFromStats || _excludeFromBudget)
                  ? Icons.flag
                  : Icons.outlined_flag,
              size: 18,
              color: (_excludeFromStats || _excludeFromBudget)
                  ? ref.watch(primaryColorProvider)
                  : BeeTokens.iconSecondary(context),
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
}

/// 共享账本 tx 作者信息 —— 跟 `amount_editor_sheet.dart` 里的同名私有实现
/// 完全一致(那边是 modal 专用、这边是整页专用,各自独立一份小 widget 比
/// 硬拉一个跨文件共享的 export 简单,双方各自维护成本也低)。
class _TxAuthorInfo {
  const _TxAuthorInfo({
    required this.creatorUserId,
    required this.lastEditedByUserId,
    required this.currentUserId,
    required this.members,
  });

  final String? creatorUserId;
  final String? lastEditedByUserId;
  final String? currentUserId;
  final List<BeeCountCloudLedgerMember> members;

  BeeCountCloudLedgerMember? memberOf(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    for (final m in members) {
      if (m.userId == userId) return m;
    }
    return null;
  }
}

final _txAuthorInfoProvider =
    FutureProvider.autoDispose.family<_TxAuthorInfo?, int>((ref, txId) async {
  final repo = ref.watch(repositoryProvider);
  final tx = await repo.getTransactionById(txId);
  if (tx == null) return null;
  final ledger = await repo.getLedgerById(tx.ledgerId);
  if (ledger == null || !ledger.isShared) return null;
  final ledgerSyncId = ledger.syncId;
  if (ledgerSyncId == null || ledgerSyncId.isEmpty) return null;
  if (tx.createdByUserId == null && tx.lastEditedByUserId == null) return null;

  final cloud = await ref.watch(beecountCloudProviderInstance.future);
  if (cloud == null) return null;
  ref.watch(sharedResourceRefreshProvider);
  final me = await cloud.auth.currentUser;
  final members = await cloud.listMembers(ledgerId: ledgerSyncId);
  return _TxAuthorInfo(
    creatorUserId: tx.createdByUserId,
    lastEditedByUserId: tx.lastEditedByUserId,
    currentUserId: me?.id,
    members: members,
  );
});

/// v38 拆帳:橫向圖示條裡的單一圖示(彙總「多類別」/單筆明細/「+」共用同一
/// 個排版:圖示 + 一行文字標籤 + 一行金額)。
class _SplitChip extends StatelessWidget {
  const _SplitChip({
    required this.onTap,
    this.onLongPress,
    required this.icon,
    required this.label,
    required this.amountText,
    required this.highlighted,
  });

  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget icon;
  final String label;
  final String amountText;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted
        ? Theme.of(context).colorScheme.primary
        : BeeTokens.textPrimary(context);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 4),
            if (label.isNotEmpty)
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11, color: BeeTokens.textSecondary(context)),
              ),
            if (amountText.isNotEmpty)
              Text(
                amountText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color),
              ),
          ],
        ),
      ),
    );
  }
}

class _TxAuthorAvatars extends ConsumerWidget {
  const _TxAuthorAvatars({required this.editingTransactionId});

  final int editingTransactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final infoAsync = ref.watch(_txAuthorInfoProvider(editingTransactionId));
    final info = infoAsync.valueOrNull;
    if (info == null) return const SizedBox.shrink();

    final creatorId = info.creatorUserId;
    final editorId = info.lastEditedByUserId;
    final meId = info.currentUserId;
    final sameUser = creatorId != null && creatorId == editorId;

    if (sameUser && creatorId == meId) return const SizedBox.shrink();

    final cloud = ref.watch(beecountCloudProviderInstance).valueOrNull;
    final baseUrl = cloud?.baseUrl;

    final widgets = <Widget>[];
    if (sameUser) {
      widgets.add(_AvatarSlot(
        member: info.memberOf(creatorId),
        userIdFallback: creatorId,
        baseUrl: baseUrl,
        tooltipBuilder: (name) => l10n.sharedTxCreatedAndEditedBy(name),
      ));
    } else {
      if (creatorId != null) {
        widgets.add(_AvatarSlot(
          member: info.memberOf(creatorId),
          userIdFallback: creatorId,
          baseUrl: baseUrl,
          tooltipBuilder: (name) => l10n.sharedTxCreatedBy(name),
        ));
      }
      if (editorId != null && editorId != creatorId) {
        if (widgets.isNotEmpty) widgets.add(const SizedBox(width: 4));
        widgets.add(_AvatarSlot(
          member: info.memberOf(editorId),
          userIdFallback: editorId,
          baseUrl: baseUrl,
          tooltipBuilder: (name) => l10n.sharedTxEditedBy(name),
        ));
      }
    }
    if (widgets.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: widgets);
  }
}

class _AvatarSlot extends StatelessWidget {
  const _AvatarSlot({
    required this.member,
    required this.userIdFallback,
    required this.baseUrl,
    required this.tooltipBuilder,
  });

  final BeeCountCloudLedgerMember? member;
  final String userIdFallback;
  final String? baseUrl;
  final String Function(String name) tooltipBuilder;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final name = m != null
        ? (m.displayName?.isNotEmpty == true
            ? m.displayName!
            : m.email.split('@').first)
        : userIdFallback;
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final rel = m?.avatarUrl;
    final base = baseUrl;
    final absolute = (rel != null && rel.isNotEmpty)
        ? (rel.startsWith('http') ? rel : (base != null ? '$base$rel' : null))
        : null;
    return Tooltip(
      message: tooltipBuilder(name),
      triggerMode: TooltipTriggerMode.longPress,
      child: CircleAvatar(
        radius: 11,
        backgroundColor: BeeTokens.surfaceCapsule(context),
        foregroundImage: absolute != null ? NetworkImage(absolute) : null,
        child: Text(
          letter,
          style: TextStyle(
              fontSize: 11,
              color: BeeTokens.textSecondary(context),
              fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
