import 'dart:async';
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
import '../../services/data/merchant_history_service.dart';
import '../../models/merchant_history.dart';
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
import 'project_picker.dart';
import '../../services/data/category_service.dart';
import 'amount_adjustment_panel.dart';
import 'amount_calculator_keypad.dart';
import 'keyboard_suggestion_bar.dart';
import 'pull_to_submit_scroll_view.dart';
import '../currency/currency_picker_sheet.dart';
import '../currency/currency_flag.dart';
import '../ui/toast.dart';
import 'tag_chip.dart';
import '../../pages/attachment/attachment_preview_page.dart';
import 'recurring_rule_advanced_sheet.dart';
import 'shared_entry_fields.dart';
import 'installment_draft_sheet.dart';

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
  // v44:選定的專案 syncId(design doc §6)。null=不指定專案。跟其他 syncId
  // 關聯(debtSyncId 等)同款慣例——只存字串,不走本地 int FK。
  String? projectSyncId,
  // v49 分期付款——非 null 時上層改呼叫 createInstallmentPlan 而不是
  // addTransaction(同 recurringDraft 的角色)。只在新增模式
  // (editingTransactionId == null)且 kind == 'expense' 才可能非 null,見
  // 表單內 `_openRecurringSheet` 的 installmentAvailable 判斷。
  InstallmentDraft? installmentDraft,
  // v51 支出/收入手續費/折扣(對齐 BeeCount Cloud `read_tx_projection.
  // base_amount`/`fee_amount`/`fee_label`/`discount_amount`/
  // `discount_label`):`baseAmount` 非 null 時代表使用者開了手續費/折扣
  // 面板,[amount] 已經是套用公式後的淨額(見
  // `computeFeeDiscountNetAmount`),`baseAmount` 才是使用者輸入的原始金額。
  // 皆為 null = 沒有使用這個功能,行為退化回既有邏輯。拆帳模式不支援,恆為
  // null(見表單內 `_buildFeeDiscountToggle` 的 `_splits.isEmpty` 判斷)。
  double? baseAmount,
  double? feeAmount,
  String? feeLabel,
  double? discountAmount,
  String? discountLabel,
});

/// v36:`onSubmit` 回傳 `Future<void>`(原本是 `void`)——編輯「週期規則
/// occurrence」時上層要先跳「此記錄/連同未來週期」選擇彈窗,使用者取消時整
/// 個存檔動作會中止且不會 pop 頁面,表單需要知道「等它做完」才能解除
/// `_isSubmitting`,不然存檔鍵會卡在禁用狀態。正常存檔成功的路徑上層仍會
/// `Navigator.pop`,`_submit()` 的 `whenComplete` 在那之後才跑,`mounted`
/// 已经是 false,`if (mounted)` 保護下自然是 no-op,行為不變。
typedef TransactionSubmitCallback = Future<void> Function(
    Category category, AmountEditorResult result);

/// 依 design doc §4 判斷商家欄位文字變動後是否該排入(debounce 後觸發)一次
/// 刷卡建議查詢。抽成純函式方便單元測試,不用整個 widget tree/網路
/// mock——刻意不接收任何 focus 狀態,避免重蹈舊版用兩個 FocusNode 的
/// `hasFocus` OR 起來判斷「都失焦了」的覆轍(商家→名稱連續輸入時,商家欄
/// 失焦的同一個 focus transaction 內名稱欄已經拿到焦點,兩邊 `hasFocus`
/// 都讀到變更後的狀態,判斷式恆為 true,永遠不會真正觸發)。
bool shouldQueueSwipesmartRecommendation({
  required bool hasKey,
  required String kind,
  required double amount,
  required String merchant,
  required ({double amount, String merchant})? lastQuery,
}) {
  if (!hasKey) return false;
  if (kind != 'expense') return false;
  if (amount <= 0 || merchant.isEmpty) return false;
  if (lastQuery?.amount == amount && lastQuery?.merchant == merchant) {
    return false; // 同一組合已經查過,不重打
  }
  return true;
}

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
  // v44:編輯模式回填已指定的專案(design doc §6)。只存 syncId,initState
  // 用它非同步反查完整 Project 顯示名稱/icon(見 _resolveInitialProject)。
  final String? initialProjectSyncId;
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
  // v51 支出/收入手續費/折扣:編輯既有交易時回填(比照 TransferForm 的
  // initialFeeAmount 等——命名刻意保持一致,方便 transaction_editor_page.dart
  // 直接透傳同一組 widget 參數給支出/收入表單跟轉帳表單)。
  final double? initialBaseAmount;
  final double? initialFeeAmount;
  final String? initialFeeLabel;
  final double? initialDiscountAmount;
  final String? initialDiscountLabel;

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
    this.initialProjectSyncId,
    required this.ledgerId,
    this.editingTransactionId,
    this.initialExcludeFromStats = false,
    this.initialExcludeFromBudget = false,
    this.initialCurrencyCode,
    this.initialNativeAmount,
    this.initialRewardRuleIds,
    this.allowSplit = true,
    required this.onSubmit,
    this.initialBaseAmount,
    this.initialFeeAmount,
    this.initialFeeLabel,
    this.initialDiscountAmount,
    this.initialDiscountLabel,
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
  // 使用者是否已經「主動」選過帳戶(手動開帳戶選單 / 點 SwipeSmart 推薦卡片)。
  // true 之後 [_maybeApplyPerCategoryAccountDefault] 不再靜默覆蓋,換分類也一樣
  // ——避免使用者剛手動選好帳戶,又因為換了個分類被自動代入蓋掉。
  bool _accountManuallySet = false;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _merchantCtrl = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _merchantFocus = FocusNode();
  double _acc = 0;
  String? _op;
  // 底部小算盤只在使用者點金額欄位時才顯示,不再預設開啟——見
  // `_textFieldFocused` getter旁的說明。
  bool _amountFocused = false;

  // v44:選定的專案(design doc §6)。跟 _selectedCategory 一樣持有完整
  // Project 物件供 UI 顯示名稱/icon,存檔時只送出 syncId。
  Project? _selectedProject;

  List<NoteHistoryEntry> _frequentNotes = [];
  List<MerchantHistoryEntry> _frequentMerchants = [];
  List<double> _recentAmounts = [];

  bool _isSubmitting = false;

  late List<int> _selectedTagIds;
  late List<String> _selectedRewardRuleIds;
  List<File> _pendingAttachments = [];
  // v36:週期性收支——只在新增模式提供入口(見 _buildRecurringRow),編輯既有
  // 交易一律走原本的單筆更新流程,不支援回填/再次調整規則(範圍決策,詳見
  // docs/changes)。v49 起跟 _installmentDraft 共用同一個「進階設定」彈窗
  // (單次/週期/分期三選一,見 recurring_rule_advanced_sheet.dart),兩者
  // 互斥(_openRecurringSheet 每次只回填其中一個,另一個設回 null)。
  RecurringRuleDraft? _recurringDraft;

  // v49 分期付款——同 _recurringDraft 的角色,只在新增模式的 expense tab
  // 可能非 null(見 _openRecurringSheet 傳給彈窗的 installmentAvailable),
  // 跟拆帳互斥(見 _startSplitMode 對稱的檢查)。
  InstallmentDraft? _installmentDraft;

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

  // ===== SwipeSmart 刷卡建議(design doc 2026-08-30 §4)=====
  List<SwipeSmartCardRecommendation> _recommendations = [];
  bool _swipesmartHasKey = false;
  Timer? _recommendationDebounce;
  ({double amount, String merchant})? _lastRecommendationQuery;

  // v51 支出/收入手續費/折扣:金額旁「+」展開單一面板(手續費列 + 折扣列
  // 同時顯示),寫法比照 transfer_form.dart 的轉出/轉入面板,但只有一個
  // enabled 旗標——支出/收入只有一個方向,不像轉帳有兩側各自獨立開關。
  bool _feeDiscountEnabled = false;
  final TextEditingController _feeLabelCtrl = TextEditingController();
  final TextEditingController _feeAmountCtrl = TextEditingController();
  final TextEditingController _discountLabelCtrl = TextEditingController();
  final TextEditingController _discountAmountCtrl = TextEditingController();
  final FocusNode _feeLabelFocus = FocusNode();
  final FocusNode _feeAmountFocus = FocusNode();
  final FocusNode _discountLabelFocus = FocusNode();
  final FocusNode _discountAmountFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(_onTextFieldFocusChange);
    _merchantFocus.addListener(_onTextFieldFocusChange);
    _feeLabelFocus.addListener(_onTextFieldFocusChange);
    _feeAmountFocus.addListener(_onTextFieldFocusChange);
    _discountLabelFocus.addListener(_onTextFieldFocusChange);
    _discountAmountFocus.addListener(_onTextFieldFocusChange);
    _checkSwipesmartKey();
    _merchantCtrl.addListener(_maybeQueueRecommendation);
    _date = widget.initialDate;
    _excludeFromStats = widget.initialExcludeFromStats;
    _excludeFromBudget = widget.initialExcludeFromBudget;
    _selectedAccountId = widget.initialAccountId;
    _selectedTagIds = List.from(widget.initialTagIds ?? []);
    _selectedRewardRuleIds = List.from(widget.initialRewardRuleIds ?? []);
    _pickedCurrency = widget.initialCurrencyCode?.toUpperCase();

    // v51 支出/收入手續費/折扣:編輯模式若有 baseAmount,小算盤要顯示使用者
    // 當初輸入的原始金額,不是套用公式後的淨額(initialAmount)。
    final initAmount = widget.initialBaseAmount ?? widget.initialAmount ?? 0;
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

    // v51 支出/收入手續費/折扣:編輯既有交易回填,比照 transfer_form.dart
    // initState 的 initialFeeAmount 處理。
    if (widget.initialBaseAmount != null) {
      _feeDiscountEnabled = true;
      if (widget.initialFeeAmount != null) {
        _feeAmountCtrl.text = _fmtAbs(widget.initialFeeAmount!);
        _feeLabelCtrl.text = widget.initialFeeLabel ?? '';
      }
      if (widget.initialDiscountAmount != null) {
        _discountAmountCtrl.text = _fmtAbs(widget.initialDiscountAmount!);
        _discountLabelCtrl.text = widget.initialDiscountLabel ?? '';
      }
    }

    _resolveInitialCategory();
    _resolveInitialSplits();
    _resolveInitialProject();
    if (widget.editingTransactionId == null &&
        widget.initialAccountId == null) {
      _loadDefaultAccount();
    }
  }

  @override
  void dispose() {
    _recommendationDebounce?.cancel();
    _merchantCtrl.removeListener(_maybeQueueRecommendation);
    _nameCtrl.dispose();
    _merchantCtrl.dispose();
    _nameFocus.dispose();
    _merchantFocus.dispose();
    _feeLabelCtrl.dispose();
    _feeAmountCtrl.dispose();
    _discountLabelCtrl.dispose();
    _discountAmountCtrl.dispose();
    _feeLabelFocus.dispose();
    _feeAmountFocus.dispose();
    _discountLabelFocus.dispose();
    _discountAmountFocus.dispose();
    super.dispose();
  }

  Future<void> _checkSwipesmartKey() async {
    try {
      final cloud = await ref.read(beecountCloudProviderInstance.future);
      if (cloud == null || !mounted) return;
      final status = await cloud.getSwipeSmartKeyStatus();
      if (!mounted) return;
      setState(() => _swipesmartHasKey = status.hasKey);
    } catch (_) {
      // 靜默失敗——這是附加功能,絕不能因為查狀態失敗而影響記帳表單本身。
    }
  }

  /// 商家欄位文字變動時(debounce 500ms)檢查是否該打一次推薦請求。只在
  /// 支出交易、有 Key、金額 > 0、商家非空時才打;同一組(金額,商家)不
  /// 重複打(design doc §4)。
  ///
  /// 原本用 `_nameFocus`/`_merchantFocus` 的失焦事件觸發(`_textFieldFocused`
  /// 兩欄 OR 起來判斷「都失焦了」),但商家→名稱這種常見的連續輸入流程裡,
  /// 商家欄失焦的同一個 focus transaction 內名稱欄已經拿到焦點,兩個
  /// FocusNode 的 listener 觸發時讀到的 `hasFocus` 已經是變更後的狀態,
  /// `_textFieldFocused` 恆為 true,永遠不會真正觸發——改成直接監聽商家
  /// controller 的文字變動,用 debounce 取代「失焦」語意,不受欄位切換順序
  /// 影響。
  void _maybeQueueRecommendation() {
    final amount = double.tryParse(_amountStr) ?? 0;
    final merchant = _merchantCtrl.text.trim();
    if (!shouldQueueSwipesmartRecommendation(
      hasKey: _swipesmartHasKey,
      kind: widget.kind,
      amount: amount,
      merchant: merchant,
      lastQuery: _lastRecommendationQuery,
    )) {
      return;
    }

    _recommendationDebounce?.cancel();
    _recommendationDebounce = Timer(const Duration(milliseconds: 500), () {
      _fetchRecommendation(amount, merchant);
    });
  }

  Future<void> _fetchRecommendation(double amount, String merchant) async {
    try {
      final cloud = await ref.read(beecountCloudProviderInstance.future);
      if (cloud == null || !mounted) return;

      final db = ref.read(databaseProvider);
      final ledger = await (db.select(db.ledgers)
            ..where((l) => l.id.equals(widget.ledgerId)))
          .getSingleOrNull();
      final serverLedgerId = ledger?.syncId ?? widget.ledgerId.toString();

      final results = await cloud.getCardRecommendation(
        ledgerId: serverLedgerId,
        amount: amount,
        merchant: merchant,
      );
      if (!mounted) return;
      // 未對照的建議帳戶不動,直接跳過——沒有本地帳戶可代入,顯示了使用者也
      // 點不出結果,不如乾脆不列出來(2026-08-30 §8 後續回報的體驗調整)。
      final mapped =
          results.where((r) => r.accountId != null).toList(growable: true);
      setState(() {
        _recommendations = mapped;
        _lastRecommendationQuery = (amount: amount, merchant: merchant);
      });
    } catch (_) {
      // 靜默失敗——絕不能讓這個附加功能擋住記帳流程(design doc §4)。
      if (mounted) setState(() => _recommendations = []);
    }
  }

  /// 點一張(必為已對照)建議卡片:代入帳戶,並把它挪到列表最前面,讓「剛選
  /// 的那張」永遠是使用者下次瞄一眼就能看到的第一張。
  Future<void> _onRecommendationTapped(SwipeSmartCardRecommendation rec) async {
    final db = ref.read(databaseProvider);
    final account = await (db.select(db.accounts)
          ..where((a) => a.syncId.equals(rec.accountId!)))
        .getSingleOrNull();
    if (account == null || !mounted) return;
    // 比照 [_openAccountPicker]/[_loadSelectedAccount] 同步帳戶名稱/幣別/
    // 類型——少了這步帳戶列會顯示空白,且信用卡回饋選單靠
    // `_selectedAccountType == 'credit_card'`(_rewardRuleSelectionEnabled)
    // 判斷是否顯示,沒填就永遠不會出現。
    final accountChanged = _selectedAccountId != account.id;
    setState(() {
      _selectedAccountId = account.id;
      _accountManuallySet = true;
      _selectedAccountName = account.name;
      _selectedAccountType = account.type;
      _selectedAccountCurrency =
          account.currency.isNotEmpty ? account.currency.toUpperCase() : null;
      if (accountChanged) _selectedRewardRuleIds = [];
      _recommendations
        ..remove(rec)
        ..insert(0, rec);
    });
    // 只代入帳戶,不寫入回饋快取(見 [_openRewardRuleSelector] 的說明)——
    // 但若這個帳戶+目前分類先前已有使用者手動選過的回饋規則,直接套用。
    _maybeAutoApplyRewardCache();
  }

  /// 名稱/商家欄位聚焦時收起底部小算盤(改用 iOS 原生鍵盤,可輸入中文),
  /// 並清掉 `_amountFocused`——小算盤只能靠點金額欄位重新叫出來,不會因為
  /// 文字欄位失焦就自己跳回來(避免「很容易自己跳出來」的體驗問題)。
  void _onTextFieldFocusChange() {
    if (!mounted) return;
    if (_textFieldFocused) {
      setState(() => _amountFocused = false);
    } else {
      setState(() {});
    }
  }

  bool get _textFieldFocused =>
      _nameFocus.hasFocus ||
      _merchantFocus.hasFocus ||
      _feeLabelFocus.hasFocus ||
      _feeAmountFocus.hasFocus ||
      _discountLabelFocus.hasFocus ||
      _discountAmountFocus.hasFocus;

  /// 鍵盤上方建議 chip 列點選後套用——保留鍵盤開啟(比照 moze,選完可能還要
  /// 微調文字),游標移到文字結尾方便接著打字。
  void _applyNoteSuggestion(String note) {
    setState(() {
      _nameCtrl.text = note;
      _nameCtrl.selection =
          TextSelection.fromPosition(TextPosition(offset: note.length));
    });
  }

  void _applyMerchantSuggestion(String merchant) {
    setState(() {
      _merchantCtrl.text = merchant;
      _merchantCtrl.selection =
          TextSelection.fromPosition(TextPosition(offset: merchant.length));
    });
  }

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
        projectSyncId: _selectedProject?.syncId,
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
      _maybeAutoApplyRewardCache();
    }
    if (f.projectSyncId != null &&
        f.projectSyncId != _selectedProject?.syncId) {
      _resolveProjectBySyncId(f.projectSyncId!);
    }
  }

  Future<void> _resolveProjectBySyncId(String syncId) async {
    final repo = ref.read(repositoryProvider);
    final project = await repo.getProjectBySyncId(syncId);
    if (project != null && mounted) {
      setState(() => _selectedProject = project);
    }
  }

  /// 供「建議」分頁點類別後呼叫(`transaction_editor_page.dart` 透過
  /// `GlobalKey<TransactionEntryFormState>` 呼叫,跟 [applySharedFields] 同款
  /// 跨分頁呼叫寫法)。選中類別、收合類別網格,並用 `viaSuggestion: true`
  /// 讓備註歷史這一次強制只看當前分類、嘗試靜默代入常用帳戶/回饋規則。
  void selectCategoryFromSuggestion(Category c) {
    if (!mounted) return;
    setState(() {
      _selectedCategory = c;
      _categoryGridExpanded = false;
    });
    _onCategoryChanged(viaSuggestion: true);
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

  /// 回顯已選專案(編輯模式 / 呼叫端帶入 initialProjectSyncId 預選時)。
  /// v44:專案只存 syncId(design doc §3.2 同 debtSyncId 模式),沒有本地
  /// int FK 可以同步回顯,只能非同步反查——跟 [_resolveInitialCategory] 的
  /// synthetic-id 反查同樣是「編輯時才需要多一趟查詢」,但這裡沒有
  /// synthetic 的問題(專案不參與 §7 共享帳本 override 機制)。
  Future<void> _resolveInitialProject() async {
    final syncId = widget.initialProjectSyncId;
    if (syncId == null) return;
    final repo = ref.read(repositoryProvider);
    final project = await repo.getProjectBySyncId(syncId);
    if (project != null && mounted) {
      setState(() => _selectedProject = project);
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
        lines
            .add(_SplitLine(category: cat, amount: row.amount, note: row.note));
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

      if (!mounted) return;
      setState(() => _selectedAccountId = defaultAccountId);
      _loadSelectedAccount(defaultAccountId);
    } catch (_) {
      // 静默失败,退回「不选择账户」
    }
  }

  /// [viaSuggestion] true 代表這次選類別是從「建議」分頁點過來的(見
  /// [selectCategoryFromSuggestion])——備註歷史這一次強制只看當前分類,
  /// 不管全域設定,並嘗試靜默代入這個分類的常用帳戶/回饋規則。一般類別格
  /// (`onCategorySelected`)維持預設 false,行為不變。
  void _onCategoryChanged({bool viaSuggestion = false}) {
    _loadRecentNotes(
        scopeOverride: viaSuggestion ? NoteHistoryScope.currentCategory : null);
    _loadRecentMerchants();
    _loadRecentAmounts();
    _maybeApplyPerCategoryAccountDefault();
  }

  Future<void> _loadRecentNotes({NoteHistoryScope? scopeOverride}) async {
    final repo = ref.read(repositoryProvider);
    final c = _selectedCategory;
    final notes = await NoteHistoryService.getHistoryNotes(
      repository: repo,
      ledgerId: widget.ledgerId,
      scope: scopeOverride ?? ref.read(noteHistoryScopeProvider),
      sort: ref.read(noteHistorySortProvider),
      categoryId: c?.id,
      categorySyncId: (c != null && c.id < 0) ? c.syncId : null,
      limit: ref.read(noteHistoryLimitProvider),
    );
    if (!mounted) return;
    setState(() => _frequentNotes = notes);
  }

  /// 商家欄位「依類別記住常用商家」——恆依當前類別過濾,沒有 scope 設定
  /// 可調(跟 [_loadRecentNotes] 不同,商家沒有全域範圍偏好設定)。
  Future<void> _loadRecentMerchants() async {
    final repo = ref.read(repositoryProvider);
    final c = _selectedCategory;
    final merchants = await MerchantHistoryService.getHistoryMerchants(
      repository: repo,
      ledgerId: widget.ledgerId,
      categoryId: c?.id,
      categorySyncId: (c != null && c.id < 0) ? c.syncId : null,
    );
    if (!mounted) return;
    setState(() => _frequentMerchants = merchants);
  }

  /// 依目前分類靜默代入歷史上最常用的帳戶——只在「全新交易、還沒指定初始
  /// 帳戶、使用者也還沒手動選過帳戶」時才生效,語意上比照 [_loadDefaultAccount]
  /// 的「靜默預設」,不是先高亮再等使用者確認。
  Future<void> _maybeApplyPerCategoryAccountDefault() async {
    if (widget.editingTransactionId != null) return;
    if (widget.initialAccountId != null) return;
    if (_accountManuallySet) return;
    final c = _selectedCategory;
    if (c == null || c.id < 0) return; // synthetic(共享帳本)分類查無本地交易
    final repo = ref.read(repositoryProvider);
    final accountId = await repo.getMostUsedAccountForCategory(
      ledgerId: widget.ledgerId,
      categoryId: c.id,
    );
    if (accountId == null || !mounted) return;
    // 查詢這段時間使用者可能已經手動選了帳戶,或換了別的分類——都不要覆蓋。
    if (_accountManuallySet || _selectedCategory?.id != c.id) return;
    final account = await ref.read(accountByIdProvider(accountId).future);
    if (account == null || account.hidden || !mounted) return;
    if (_accountManuallySet || _selectedCategory?.id != c.id) return;
    setState(() => _selectedAccountId = accountId);
    _loadSelectedAccount(accountId);
    _maybeAutoApplyRewardCache();
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

  /// 幣別換算對話框:「換算金額」「匯率」兩欄互相即時反推(單純本地乘除,
  /// 不需要 debounce/非同步),外加「採用線上匯率」開關——開啟時兩欄唯讀並
  /// 顯示自動抓取的線上匯率換算結果,關閉後才能手動編輯。確認送出時一律以
  /// 當下畫面顯示的「匯率」數值寫回 `_rateStr`/`_rateManuallySet`。
  Future<void> _editRate() async {
    final l10n = AppLocalizations.of(context);
    final txCurrency = _txCurrency();
    final ledgerBase = ref.read(currentLedgerCurrencyProvider);
    final amount = double.tryParse(_amountStr) ?? 0.0;

    double? onlineRate() {
      final rates = ref.read(effectiveRatesForLedgerProvider).valueOrNull;
      final er = rates?[txCurrency];
      return er == null ? null : double.tryParse(er.rate);
    }

    bool useOnline = !_rateManuallySet;
    final currentRate = _currentRate();
    final rateCtrl = TextEditingController(
        text: _rateStr ?? currentRate?.toStringAsPrecision(6) ?? '');
    final convertedCtrl = TextEditingController(
        text: (currentRate != null && amount > 0)
            ? (amount * currentRate).toStringAsFixed(2)
            : '');

    bool syncing = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setDialogState) {
          void syncConvertedFromRate() {
            if (syncing) return;
            syncing = true;
            final r = double.tryParse(rateCtrl.text);
            if (r != null && amount > 0) {
              convertedCtrl.text = (amount * r).toStringAsFixed(2);
            }
            syncing = false;
          }

          void syncRateFromConverted() {
            if (syncing) return;
            syncing = true;
            final c = double.tryParse(convertedCtrl.text);
            if (c != null && amount > 0) {
              rateCtrl.text = (c / amount).toStringAsPrecision(6);
            }
            syncing = false;
          }

          return AlertDialog(
            title: Text(l10n.txConvertDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(l10n.txUseOnlineRateLabel)),
                    Switch(
                      value: useOnline,
                      onChanged: (v) {
                        setDialogState(() {
                          useOnline = v;
                          if (v) {
                            final r = onlineRate();
                            rateCtrl.text =
                                r != null ? r.toStringAsPrecision(6) : '';
                            convertedCtrl.text = (r != null && amount > 0)
                                ? (amount * r).toStringAsFixed(2)
                                : '';
                          }
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: convertedCtrl,
                  enabled: !useOnline,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: '${l10n.txConvertedAmountLabel} ($ledgerBase)',
                  ),
                  onChanged: (_) => setDialogState(syncRateFromConverted),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: rateCtrl,
                  enabled: !useOnline,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: l10n.txRateLabel,
                    hintText: '1 $txCurrency = ? $ledgerBase',
                  ),
                  onChanged: (_) => setDialogState(syncConvertedFromRate),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: Text(AppLocalizations.of(dctx).commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: Text(AppLocalizations.of(dctx).commonConfirm),
              ),
            ],
          );
        },
      ),
    );
    // 不在这里 dispose 这两个 controller:AlertDialog 关闭走的是退场动画,
    // Navigator.pop 之后 TextField 还会在动画期间再 build 几帧,提早 dispose
    // 会炸 "TextEditingController used after being disposed"。两个 controller
    // 生命周期到此为止就没有其他持有者了,随 GC 回收,不是长期泄漏。
    final finalRateText = rateCtrl.text.trim();
    if (confirmed != true || !mounted) return;
    if (useOnline) {
      setState(() {
        _rateManuallySet = false;
        _rateStr = null;
      });
      return;
    }
    final v = double.tryParse(finalRateText);
    if (v == null || v <= 0) return;
    setState(() {
      _rateStr = finalRateText;
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
            onTap: _editRate,
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
  double get _keypadTotal => _op == null
      ? _parsedAmount()
      : computeAmountOp(_acc, _op!, _parsedAmount());

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
    if (_installmentDraft != null) {
      showToast(
          context, AppLocalizations.of(context).txInstallmentSplitConflict);
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
      allowAllCurrencies: true,
    );
    // result == null:取消/滑动关闭,维持原本选择不变。
    // result.accountId == null:明确选了「不选择账户」,清空。
    if (result == null || !mounted) return;
    final id = result.accountId;
    final accountChanged = id != _selectedAccountId;
    setState(() {
      _selectedAccountId = id;
      _accountManuallySet = true;
      _selectedAccountCurrency = null;
      _selectedAccountName = null;
      _selectedAccountType = null;
      // 換帳戶時清掉舊選的回饋規則——規則綁定特定信用卡帳戶,換帳戶後舊選
      // 擇不再有意義(甚至可能不屬於新帳戶,寫入會被 write 校驗擋掉)。
      if (accountChanged) _selectedRewardRuleIds = [];
    });
    if (id != null) {
      _loadSelectedAccount(id);
      _maybeAutoApplyRewardCache();
    }
  }

  Future<void> _openProjectPicker() async {
    final result = await ProjectPicker.show(
      context,
      ledgerId: widget.ledgerId,
      selectedProjectSyncId: _selectedProject?.syncId,
    );
    // result == null:取消/滑動關閉,維持原本選擇不變。
    // result.project == null:明確選了「不指定專案」,清空。
    if (result == null || !mounted) return;
    setState(() => _selectedProject = result.project);
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

    // v51 支出/收入手續費/折扣:面板開啟時(拆帳模式下面板不會開啟,見
    // _buildFeeDiscountToggle 的 _splits.isEmpty 判斷)驗證兩個金額皆須 ≥0
    // (比照 Cloud `_normalize_fee_discount_amount`),通過後用
    // computeFeeDiscountNetAmount 重算淨額覆蓋 total——這個 total 之後會
    // 驅動下面的 nativeAmount 折算跟 onSubmit 的 amount 欄位,兩邊自然對齊。
    double? resolvedBaseAmount;
    double? resolvedFeeAmount;
    String? resolvedFeeLabel;
    double? resolvedDiscountAmount;
    String? resolvedDiscountLabel;
    if (_feeDiscountEnabled && _splits.isEmpty) {
      resolvedFeeAmount = double.tryParse(_feeAmountCtrl.text) ?? 0;
      resolvedDiscountAmount = double.tryParse(_discountAmountCtrl.text) ?? 0;
      if (resolvedFeeAmount < 0 || resolvedDiscountAmount < 0) {
        showToast(context,
            AppLocalizations.of(context).transferAdjustmentNegativeError);
        return;
      }
      final l10n = AppLocalizations.of(context);
      resolvedFeeLabel = _feeLabelCtrl.text.isEmpty
          ? l10n.transactionFeeLabelHint
          : _feeLabelCtrl.text;
      resolvedDiscountLabel = _discountLabelCtrl.text.isEmpty
          ? l10n.transactionDiscountLabelHint
          : _discountLabelCtrl.text;
      resolvedBaseAmount = total.abs();
      total = computeFeeDiscountNetAmount(
        type: widget.kind,
        baseAmount: resolvedBaseAmount,
        feeAmount: resolvedFeeAmount,
        discountAmount: resolvedDiscountAmount,
      );
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
        projectSyncId: _selectedProject?.syncId,
        installmentDraft:
            widget.editingTransactionId == null ? _installmentDraft : null,
        baseAmount: resolvedBaseAmount,
        feeAmount: resolvedFeeAmount,
        feeLabel: resolvedFeeLabel,
        discountAmount: resolvedDiscountAmount,
        discountLabel: resolvedDiscountLabel,
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
            List.generate(_splits.length, _liveAmountFor).every((a) => a > 0))
        : (_selectedCategory != null &&
            (isInCalcMode ? true : total.abs() > 0));

    return PullToSubmitScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      canSubmit: canSubmit,
      isSubmitting: _isSubmitting,
      onSubmit: _submit,
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 小算盤只在使用者點過金額欄位後才顯示,不再預設開啟;名稱/商家欄位
          // 聚焦時讓位給系統鍵盤,避免兩層鍵盤搶版面、還要往下滑才看得到送出鍵。
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
          // 名稱/商家欄位聚焦時,貼著系統鍵盤上緣跳出歷史建議(比照 moze),
          // 取代舊版「點時鐘圖示彈出視窗」的做法——不需要另外點,聚焦就看得到。
          if (_nameFocus.hasFocus && _frequentNotes.isNotEmpty)
            KeyboardSuggestionBar(
              suggestions: _frequentNotes.map((e) => e.note).toList(),
              onSelected: _applyNoteSuggestion,
            )
          else if (_merchantFocus.hasFocus && _frequentMerchants.isNotEmpty)
            KeyboardSuggestionBar(
              suggestions: _frequentMerchants.map((e) => e.merchant).toList(),
              onSelected: _applyMerchantSuggestion,
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCategorySection(context),
          const SizedBox(height: 10),
          // 金额表达式行——点一下叫出底部小算盤,同时收起名稱/商家
          // 欄位的系統鍵盤(「只有點金額欄位才叫用數字小算盤」)。
          GestureDetector(
            key: const Key('amountDisplayTap'),
            behavior: HitTestBehavior.translucent,
            onTap: () {
              FocusScope.of(context).unfocus();
              setState(() => _amountFocused = true);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    if (widget.editingTransactionId != null)
                      _TxAuthorAvatars(
                          editingTransactionId: widget.editingTransactionId!),
                    const Spacer(),
                    _buildCurrencyChip(context),
                    // v51 支出/收入手續費/折扣:拆帳模式下不提供(比照拆帳跟
                    // 「進階設定」互斥的既有規則)。
                    if (_splits.isEmpty)
                      AdjustmentToggleButton(
                        key: const Key('feeDiscountToggle'),
                        enabled: _feeDiscountEnabled,
                        tooltip: AppLocalizations.of(context)
                            .transactionAddFeeDiscountButton,
                        onPressed: () => setState(() {
                          _feeDiscountEnabled = !_feeDiscountEnabled;
                          if (!_feeDiscountEnabled) {
                            _feeLabelCtrl.clear();
                            _feeAmountCtrl.clear();
                            _discountLabelCtrl.clear();
                            _discountAmountCtrl.clear();
                          }
                        }),
                      ),
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
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          amountOpGlyph(_op!),
                          style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600, color: primary),
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
                if (_feeDiscountEnabled && _splits.isEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: _buildFeeDiscountPanel(context, total),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          // 名稱欄(=備註,合併掉原本分開的名稱/備註兩個欄位)
          TextField(
            key: const Key('nameField'),
            controller: _nameCtrl,
            focusNode: _nameFocus,
            style: TextStyle(color: BeeTokens.textPrimary(context)),
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context).transactionNameHint,
              hintStyle: TextStyle(color: BeeTokens.textTertiary(context)),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: BeeTokens.surfaceInput(context),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          // 商家欄(v33 新增,獨立於名稱/備註的自由文本欄位)
          TextField(
            key: const Key('merchantField'),
            controller: _merchantCtrl,
            focusNode: _merchantFocus,
            style: TextStyle(color: BeeTokens.textPrimary(context)),
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context).transactionMerchantHint,
              hintStyle: TextStyle(color: BeeTokens.textTertiary(context)),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: BeeTokens.surfaceInput(context),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              prefixIcon: Icon(Icons.storefront_outlined,
                  color: BeeTokens.iconSecondary(context), size: 18),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 40, minHeight: 20),
            ),
          ),
          if (_recommendations.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _recommendations.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final rec = _recommendations[index];
                  return GestureDetector(
                    onTap: () => _onRecommendationTapped(rec),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: BeeTokens.surfaceInput(context),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: BeeTokens.iconPrimary(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${rec.bankName} ${rec.cardName}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: BeeTokens.textPrimary(context),
                            ),
                          ),
                          Text(
                            '+${rec.estimatedReward.toStringAsFixed(0)} (${(rec.effectiveRate * 100).toStringAsFixed(1)}%)',
                            style: TextStyle(
                              fontSize: 11,
                              color: BeeTokens.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 8),
          _buildAccountRow(context),
          const SizedBox(height: 8),
          _buildProjectRow(context),
          const SizedBox(height: 8),
          _buildTagAndAttachmentRow(),
          _buildEstimatedRewardRow(),
          const SizedBox(height: 8),
          _buildDateRow(context),
          // v38:拆帳交易不提供「進階設定(單次/週期/分期)」入口(兩者互斥,
          // 見 _startSplitMode 對稱的檢查)。v49 起分期併進同一個「進階設定」
          // 彈窗(見 recurring_rule_advanced_sheet.dart 的
          // RecurringRuleAdvancedSheet),不再是獨立入口。
          if (widget.editingTransactionId == null && _splits.isEmpty) ...[
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
    );
  }

  String _fmtAbs(double v) {
    final s = v.abs().toStringAsFixed(2);
    final r1 = s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '') : s;
    return r1.endsWith('.') ? r1.substring(0, r1.length - 1) : r1;
  }

  /// v51 支出/收入手續費/折扣:「+」展開後的單一面板,手續費列 + 折扣列 +
  /// 淨額預覽同時顯示(比照 BeeCount Cloud 網頁版 `TransactionsPanel.tsx`,
  /// 跟轉帳的「轉出/轉入兩側各自獨立面板」不同形狀——支出/收入只有一個方向,
  /// 一個「移除」就清空兩列)。[baseAmount] 是目前小算盤代表的金額(可能含
  /// +/- 連續運算後的結果),用來即時預覽套用公式後的淨額。
  Widget _buildFeeDiscountPanel(BuildContext context, double baseAmount) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final currency = _txCurrency();
    final fee = double.tryParse(_feeAmountCtrl.text) ?? 0;
    final discount = double.tryParse(_discountAmountCtrl.text) ?? 0;
    final net = computeFeeDiscountNetAmount(
      type: widget.kind,
      baseAmount: baseAmount.abs(),
      feeAmount: fee < 0 ? 0 : fee,
      discountAmount: discount < 0 ? 0 : discount,
    );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BeeTokens.surfaceElevated(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdjustmentFieldRow(
            labelFieldKey: const Key('feeLabelField'),
            amountFieldKey: const Key('feeAmountField'),
            labelCtrl: _feeLabelCtrl,
            labelFocus: _feeLabelFocus,
            amountCtrl: _feeAmountCtrl,
            amountFocus: _feeAmountFocus,
            currency: currency,
            labelHint: l10n.transactionFeeLabelHint,
            amountHint: l10n.transferAmountLabel,
            onAmountChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          AdjustmentFieldRow(
            labelFieldKey: const Key('discountLabelField'),
            amountFieldKey: const Key('discountAmountField'),
            labelCtrl: _discountLabelCtrl,
            labelFocus: _discountLabelFocus,
            amountCtrl: _discountAmountCtrl,
            amountFocus: _discountAmountFocus,
            currency: currency,
            labelHint: l10n.transactionDiscountLabelHint,
            amountHint: l10n.transferAmountLabel,
            onAmountChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${l10n.transactionFeeDiscountTotalLabel} ${_fmtAbs(net)}',
                style: text.bodySmall?.copyWith(
                  color: BeeTokens.textSecondary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              InkWell(
                key: const Key('feeDiscountRemove'),
                onTap: () => setState(() {
                  _feeDiscountEnabled = false;
                  _feeLabelCtrl.clear();
                  _feeAmountCtrl.clear();
                  _discountLabelCtrl.clear();
                  _discountAmountCtrl.clear();
                }),
                child: Text(
                  l10n.transferRemoveAdjustmentButton,
                  style: text.bodySmall
                      ?.copyWith(color: BeeTokens.textTertiary(context)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
                  child:
                      Icon(Icons.apps, color: BeeTokens.iconSecondary(context)),
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

  /// v44:「選擇專案」欄位(design doc §6),比照 _buildAccountRow 的樣式。
  /// 恆顯示(同帳戶列)——帳本裡還沒有任何專案時,點開 picker 會看到空狀態
  /// 提示,不在這裡就把整列藏起來(藏起來會讓使用者以為記帳頁完全沒有專案
  /// 功能)。建專案的入口仍在專案總覽頁,不在這裡提供「新增專案」捷徑。
  Widget _buildProjectRow(BuildContext context) {
    final name = _selectedProject?.name ??
        AppLocalizations.of(context).projectPickerNone;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _openProjectPicker,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: BeeTokens.surfaceInput(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              _selectedProject != null
                  ? CategoryService.getCategoryIcon(_selectedProject!.icon)
                  : Icons.folder_outlined,
              size: 18,
              color: BeeTokens.iconSecondary(context),
            ),
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

  /// 開啟「進階設定」彈窗(單次/週期/分期三選一,見
  /// `recurring_rule_advanced_sheet.dart` 的 `RecurringRuleAdvancedSheet`)。
  /// 分期只在新增模式的 expense tab 開放。拆帳互斥的檢查放在
  /// `_startSplitMode`(對稱)。
  Future<void> _openRecurringSheet() async {
    final l10n = AppLocalizations.of(context);
    if (_splits.isNotEmpty) {
      showToast(context, l10n.txInstallmentSplitConflict);
      return;
    }
    final result = await RecurringRuleAdvancedSheet.show(
      context,
      anchorDate: _date,
      initialDraft: _recurringDraft,
      installmentAvailable:
          widget.editingTransactionId == null && widget.kind == 'expense',
      initialInstallmentDraft: _installmentDraft,
    );
    // showModalBottomSheet 滑動關閉(未 pop 值)時 result 也是 null,跟「使用
    // 者主動選單次」無法區分——两种情况下都应该把週期/分期都关掉,行为一致,
    // 不用像 AccountCardPicker 那样額外包一層區分。
    if (!mounted) return;
    setState(() {
      _recurringDraft = result?.recurring;
      _installmentDraft = result?.installment;
    });
  }

  Widget _buildRecurringRow(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recurring = _recurringDraft;
    final installment = _installmentDraft;
    final label = installment != null
        ? installment.summary(l10n)
        : recurring == null
            ? l10n.txDetailOnce
            : recurring.summary(l10n);
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
            Icon(installment != null ? Icons.calendar_view_month : Icons.repeat,
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
      _rememberRewardChoice(result);
    }
  }

  /// 使用者手動選/清空回饋規則後,寫入本機學習快取(見
  /// [RewardChoiceCacheRepository] 的範圍說明:只有這裡是寫入點,
  /// SwipeSmart 卡片點選跟依類別靜默代入帳戶都只讀不寫)。
  void _rememberRewardChoice(List<String> rewardRuleIds) {
    final c = _selectedCategory;
    final accountId = _selectedAccountId;
    if (c == null || c.id < 0 || accountId == null || accountId < 0) return;
    final repo = ref.read(repositoryProvider);
    if (rewardRuleIds.isEmpty) {
      repo.clearRewardChoice(
          ledgerId: widget.ledgerId, categoryId: c.id, accountId: accountId);
    } else {
      repo.upsertRewardChoice(
        ledgerId: widget.ledgerId,
        categoryId: c.id,
        accountId: accountId,
        rewardRuleIds: rewardRuleIds,
      );
    }
  }

  /// 依「類別+帳戶」自動代入使用者上次手動選過的回饋規則。絕不覆蓋這次
  /// 已經有選擇的規則(不管是使用者剛手動選的,還是這個方法自己剛代入的)。
  Future<void> _maybeAutoApplyRewardCache() async {
    if (!_rewardRuleSelectionEnabled) return;
    if (_selectedRewardRuleIds.isNotEmpty) return;
    final c = _selectedCategory;
    final accountId = _selectedAccountId;
    if (c == null || c.id < 0 || accountId == null || accountId < 0) return;
    final repo = ref.read(repositoryProvider);
    final cached = await repo.getCachedRewardRuleIds(
      ledgerId: widget.ledgerId,
      categoryId: c.id,
      accountId: accountId,
    );
    if (cached == null || cached.isEmpty || !mounted) return;
    // 查詢期間狀態可能已經變了(換了類別/帳戶,或使用者自己手動選了)。
    if (_selectedCategory?.id != c.id ||
        _selectedAccountId != accountId ||
        _selectedRewardRuleIds.isNotEmpty) {
      return;
    }
    final available =
        await ref.read(cardRewardRulesForAccountProvider(accountId).future);
    final validIds = available.map((r) => r.syncId).toSet();
    final filtered = cached.where(validIds.contains).toList();
    if (filtered.isEmpty || !mounted) return;
    if (_selectedCategory?.id != c.id ||
        _selectedAccountId != accountId ||
        _selectedRewardRuleIds.isNotEmpty) {
      return;
    }
    setState(() => _selectedRewardRuleIds = filtered);
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
