import 'package:drift/drift.dart' as d;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/budget_providers.dart';
import '../../data/db.dart';
import '../../data/repositories/local/local_repository.dart';
import '../../data/repositories/transaction_repository.dart'
    show TransactionSplitInput;
import '../../utils/shared_ledger_picker_filter.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/transaction_entry_form.dart'
    show TransactionEntryForm, TransactionEntryFormState, AmountEditorResult;
import '../../widgets/biz/recurring_occurrence_dialogs.dart';
import '../../widgets/biz/shared_entry_fields.dart';
import '../../widgets/transaction/transfer_form.dart';
import '../../widgets/transaction/debt_entry_form.dart';
import '../../styles/tokens.dart';
import '../../services/billing/post_processor.dart';
import '../../services/attachment_service.dart';
import '../../services/data/tx_author_service.dart';

/// 交易编辑器页面
/// 支持创建/编辑收入、支出和转账记录
///
/// 三个分页都是单页式表单(比照 Moze 参考图):支出/收入用
/// `TransactionEntryForm`,转账用 `TransferForm`(v2 起也改成单页式,拿掉了
/// 「先选账户方格 → 再弹 AmountEditorSheet modal」的两步流程,`AmountEditorSheet`
/// 已删除)。类别/账户、金额、名称、商家、标签/附件/旗标、日期一次呈现。
class TransactionEditorPage extends ConsumerStatefulWidget {
  final String initialKind; // 'expense', 'income', or 'transfer'
  final int? initialCategoryId;
  final String? initialNote; // 用于金额输入弹窗回填备注
  final String? initialMerchant; // v33:回填商家
  final double? initialAmount;
  final DateTime? initialDate;
  final int? editingTransactionId;
  final int? initialAccountId;
  final int? initialToAccountId; // 转账时的目标账户
  final List<int>? initialTagIds; // 初始标签ID列表
  final bool initialExcludeFromStats; // 不计入收支，编辑模式回显
  final bool initialExcludeFromBudget; // 不计入预算，编辑模式回显
  // v30 多币种编辑回显(推隐含汇率用)
  final String? initialCurrencyCode;
  final double? initialNativeAmount;
  // v34:从「退款」入口打开时,带入原交易 syncId,存档时写进新交易的
  // refundOfSyncId。只有新建模式(editingTransactionId == null)会用到。
  final String? initialRefundOfSyncId;
  // v35:编辑/复制模式回填已勾选的信用卡紅利回饋規則(syncId 列表)。
  final List<String>? initialRewardRuleIds;
  // v36 修正:編輯「週期規則生成的 occurrence」時,呼叫端(`TransactionEditUtils
  // .editTransaction`)已經在進頁面之前問過「修改此記錄/連同未來週期」,這裡
  // 只是把選擇結果帶進來,存檔時直接沿用,不再重問一次。非週期交易維持 null。
  final RecurringEditScope? initialRecurringEditScope;

  const TransactionEditorPage({
    super.key,
    required this.initialKind,
    this.initialCategoryId,
    this.initialNote,
    this.initialMerchant,
    this.initialAmount,
    this.initialDate,
    this.editingTransactionId,
    this.initialAccountId,
    this.initialToAccountId,
    this.initialTagIds,
    this.initialExcludeFromStats = false,
    this.initialExcludeFromBudget = false,
    this.initialCurrencyCode,
    this.initialNativeAmount,
    this.initialRefundOfSyncId,
    this.initialRewardRuleIds,
    this.initialRecurringEditScope,
  });

  @override
  ConsumerState<TransactionEditorPage> createState() =>
      _TransactionEditorPageState();
}

class _TransactionEditorPageState extends ConsumerState<TransactionEditorPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  int _lastTabIndex = 0;

  // v36 修正:支出/收入/轉帳三個分頁各自是獨立的 State(`AutomaticKeepAliveClientMixin`
  // 只保證「切走再切回來」資料不丟,不會讓三個分頁互相同步)。這三個
  // GlobalKey 讓 `_syncSharedFieldsOnTabChange` 能在切 tab 時讀出離開的分頁
  // 目前輸入了什麼、寫進新切到的分頁,體感上像是共用同一份草稿。
  final _expenseFormKey = GlobalKey<TransactionEntryFormState>();
  final _incomeFormKey = GlobalKey<TransactionEntryFormState>();
  final _transferFormKey = GlobalKey<TransferFormState>();
  final _debtFormKey = GlobalKey<DebtEntryFormState>();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    // 设置初始tab: 0=支出, 1=收入, 2=转账
    if (widget.initialKind == 'income') {
      _tab.index = 1;
    } else if (widget.initialKind == 'transfer') {
      _tab.index = 2;
    } else {
      _tab.index = 0;
    }
    _lastTabIndex = _tab.index;
    _tab.addListener(_unfocusOnTabSwitch);
    _tab.addListener(_syncSharedFieldsOnTabChange);
  }

  @override
  void dispose() {
    _tab.removeListener(_unfocusOnTabSwitch);
    _tab.removeListener(_syncSharedFieldsOnTabChange);
    _tab.dispose();
    super.dispose();
  }

  /// 切换支出/收入/转账 tab 时强制收起系统键盘。
  ///
  /// TabBarView 底层是 PageView,三个子表单(两个 TransactionEntryForm +
  /// 一个 TransferForm)全程保持挂载;切到别的 tab 不会让旧 tab 里聚焦的
  /// 名稱/商家欄位自動失焦。如果不主动 unfocus,旧 tab 的系统键盘会继续
  /// 停留在画面上,跟新 tab 自己的自定义数字小算盘(只在没有欄位聚焦时才
  /// 渲染,见 TransactionEntryForm._textFieldFocused)同时出现、彼此重叠。
  void _unfocusOnTabSwitch() {
    if (_tab.indexIsChanging) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  /// 切 tab 時把離開的分頁目前輸入的共用欄位(金額/名稱/商家/日期時間/標籤/
  /// 帳戶)帶到新切到的分頁——解決「支出輸入 600 後切收入,收入還是空白」
  /// 的問題(見 docs/changes 對這個 bug 的說明)。
  ///
  /// `_tab.index` 在使用者點 tab 的當下就同步更新(動畫只是視覺過場),所以
  /// 直接比對 `index != _lastTabIndex` 就能在「index 真的變了」那一刻恰好
  /// 觸發一次,不用額外判斷 `indexIsChanging`(那個只反映動畫有沒有在跑,
  /// 用來擋這裡反而會在動畫結束又多觸發一次)。
  ///
  /// 這個 listener 是在 `initState` 註冊的,比 `TabBarView` 內部訂閱
  /// `_tab` 的 listener 還早(`TabBarView` 要等到 `build()` 才建立、才訂
  /// 閱)。`ChangeNotifier` 依註冊順序同步呼叫 listener,所以「切到的那個
  /// 分頁」在這個 method 執行的當下**還沒被 `TabBarView` build 出來**——
  /// 新分頁的 `GlobalKey.currentState` 還是 null,`_applySharedFields`
  /// 會整個 no-op,新分頁接著才用自己預設的空白狀態 build 出來(表現成
  /// 「金額被重置為 0」)。
  ///
  /// 套用動作要延後,但延後「一幀」不夠:`TabBarView` 底層是 `PageView`,
  /// 切分頁是 `_tab.animateTo(...)` 驅動、跨越 `kTabScrollDuration`
  /// (300ms、約 18 幀)的動畫,`PageView` 的 cache 視窗要等動畫推進到一定
  /// 進度、目標分頁真的進到 cache 範圍內才會把它 build 出來——不是「換頁那
  /// 一刻」就已經 mount 完成。用單次 `addPostFrameCallback` 太早,新分頁的
  /// `GlobalKey.currentState` 常常還是 null。改成「每一幀都檢查一次,還沒
  /// build 出來就排下一幀繼續等」,直到套用成功或超過重試上限(30 幀,約
  /// 500ms,遠超過切頁動畫本身的時長)才放棄。
  void _syncSharedFieldsOnTabChange() {
    if (_tab.index == _lastTabIndex) return;
    final fromIndex = _lastTabIndex;
    final toIndex = _tab.index;
    _lastTabIndex = toIndex;
    final exported = _exportSharedFields(fromIndex);
    if (exported == null) return;
    _applySharedFieldsWhenReady(toIndex, exported);
  }

  void _applySharedFieldsWhenReady(int tabIndex, SharedEntryFields fields,
      {int attemptsLeft = 30}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_applySharedFields(tabIndex, fields)) return;
      if (attemptsLeft <= 0) return;
      _applySharedFieldsWhenReady(tabIndex, fields,
          attemptsLeft: attemptsLeft - 1);
    });
  }

  SharedEntryFields? _exportSharedFields(int tabIndex) {
    switch (tabIndex) {
      case 0:
        return _expenseFormKey.currentState?.exportSharedFields();
      case 1:
        return _incomeFormKey.currentState?.exportSharedFields();
      case 2:
        return _transferFormKey.currentState?.exportSharedFields();
      case 3:
        return _debtFormKey.currentState?.exportSharedFields();
    }
    return null;
  }

  /// 回傳是否真的套用成功(目標分頁的 `GlobalKey.currentState` 已 mount)
  /// ——`_applySharedFieldsWhenReady` 靠這個回傳值判斷要不要排下一幀重試。
  ///
  /// tabIndex 2(轉帳)跟 3(欠款)以前共用同一個 `_ => null` default 分支,
  /// 導致切到欠款分頁時,匯出的欄位被誤套用到隱藏的轉帳分頁狀態,欠款分頁
  /// 本身什麼都沒拿到——這裡拆成各自獨立的分支。
  bool _applySharedFields(int tabIndex, SharedEntryFields fields) {
    final GlobalKey<TransactionEntryFormState>? entryKey = switch (tabIndex) {
      0 => _expenseFormKey,
      1 => _incomeFormKey,
      _ => null,
    };
    if (entryKey != null) {
      final state = entryKey.currentState;
      if (state == null) return false;
      state.applySharedFields(fields);
      return true;
    }
    if (tabIndex == 3) {
      final debtState = _debtFormKey.currentState;
      if (debtState == null) return false;
      debtState.applySharedFields(fields);
      return true;
    }
    final transferState = _transferFormKey.currentState;
    if (transferState == null) return false;
    transferState.applySharedFields(fields);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final ledgerId = ref.watch(currentLedgerIdProvider);
    return Scaffold(
      body: Column(
        children: [
          // 紧凑顶部：去除多余留白 + 选中下划线
          PrimaryHeader(
            title: '',
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            bottom: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: TabBar(
                            controller: _tab,
                            isScrollable: false,
                            labelColor: BeeTokens.textPrimary(context),
                            unselectedLabelColor:
                                BeeTokens.textSecondary(context),
                            indicator: UnderlineTabIndicator(
                              borderSide: BorderSide(
                                  width: 2,
                                  color: BeeTokens.textPrimary(context)),
                              insets: const EdgeInsets.symmetric(horizontal: 0),
                            ),
                            tabs: [
                              Tab(
                                  text: AppLocalizations.of(context)!
                                      .categoryExpense),
                              Tab(
                                  text: AppLocalizations.of(context)!
                                      .categoryIncome),
                              Tab(
                                  text: AppLocalizations.of(context)!
                                      .transferTitle),
                              Tab(
                                  text: AppLocalizations.of(context)!
                                      .debtTabLabel),
                            ],
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(AppLocalizations.of(context)!.commonCancel,
                            style: TextStyle(
                                color: BeeTokens.textPrimary(context))),
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                TransactionEntryForm(
                  key: _expenseFormKey,
                  kind: 'expense',
                  initialCategoryId: widget.initialCategoryId,
                  initialDate: widget.initialDate ?? DateTime.now(),
                  initialAmount: widget.initialAmount,
                  initialNote: widget.initialNote,
                  initialMerchant: widget.initialMerchant,
                  initialAccountId: widget.initialAccountId,
                  initialTagIds: widget.initialTagIds,
                  ledgerId: ledgerId,
                  editingTransactionId: widget.editingTransactionId,
                  initialExcludeFromStats: widget.initialExcludeFromStats,
                  initialExcludeFromBudget: widget.initialExcludeFromBudget,
                  initialCurrencyCode: widget.initialCurrencyCode,
                  initialNativeAmount: widget.initialNativeAmount,
                  initialRewardRuleIds: widget.initialRewardRuleIds,
                  // v38:退款新增入口不能同時是拆帳交易(對齊 web 端的互斥規則)。
                  allowSplit: widget.initialRefundOfSyncId == null,
                  onSubmit: (c, r) => _handleSubmit(c, 'expense', r),
                ),
                TransactionEntryForm(
                  key: _incomeFormKey,
                  kind: 'income',
                  initialCategoryId: widget.initialCategoryId,
                  initialDate: widget.initialDate ?? DateTime.now(),
                  initialAmount: widget.initialAmount,
                  initialNote: widget.initialNote,
                  initialMerchant: widget.initialMerchant,
                  initialAccountId: widget.initialAccountId,
                  initialTagIds: widget.initialTagIds,
                  ledgerId: ledgerId,
                  editingTransactionId: widget.editingTransactionId,
                  initialExcludeFromStats: widget.initialExcludeFromStats,
                  initialExcludeFromBudget: widget.initialExcludeFromBudget,
                  initialCurrencyCode: widget.initialCurrencyCode,
                  initialNativeAmount: widget.initialNativeAmount,
                  initialRewardRuleIds: widget.initialRewardRuleIds,
                  allowSplit: widget.initialRefundOfSyncId == null,
                  onSubmit: (c, r) => _handleSubmit(c, 'income', r),
                ),
                TransferForm(
                  key: _transferFormKey,
                  onTransferComplete: () {
                    // 关闭交易编辑器
                    Navigator.pop(context);
                  },
                  initialFromAccountId: widget.initialAccountId,
                  initialToAccountId: widget.initialToAccountId,
                  editingTransactionId: widget.editingTransactionId,
                  initialAmount: widget.initialAmount,
                  initialNote: widget.initialNote,
                  initialMerchant: widget.initialMerchant,
                  initialDate: widget.initialDate,
                  initialTagIds: widget.initialTagIds,
                  recurringEditScope: widget.initialRecurringEditScope,
                ),
                DebtEntryForm(
                  key: _debtFormKey,
                  onDebtCreated: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 存檔 orchestration——原本是 `AmountEditorSheet.onSubmit` 的 callback
  /// body(見改版前 git 歷史),整段搬過來,行為不變:synthetic id 處理、
  /// shared-ledger override、附件儲存、tag 主表/override 分流、
  /// `PostProcessor.sync`、provider 刷新。
  Future<void> _handleSubmit(
      Category c, String kind, AmountEditorResult res) async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    final repo = ref.read(repositoryProvider);
    final attachmentService = ref.read(attachmentServiceProvider);
    int transactionId;
    // §7 v25:Category 是来自 SharedLedger* 的 synthetic (id<0)时,
    // categoryId 留 null,override 走 syncId。同理对 account/toAccount。
    // res.accountId 可能也是 synthetic(Account picker 用同一规则)。
    final isSyntheticCategory = c.id < 0;
    final isSyntheticAccount = res.accountId != null && res.accountId! < 0;
    final categoryIdForWrite = isSyntheticCategory ? null : c.id;
    // synthetic / picker 返 null 时账户 id 写 null。
    // addTransaction 的 accountId 是 int?(直接传 null 即写 null);
    // updateTransaction 的 accountId 是 dynamic,dart null 被解释成
    // Value.absent(=不更新该字段) → 用户选"不选择账户"无效;必须显式
    // 传 d.Value<int?>(null) 才会真清空旧 accountId。
    final accountIdForAdd = isSyntheticAccount ? null : res.accountId;
    final accountIdForUpdate = d.Value<int?>(accountIdForAdd);
    final categoryOverride = isSyntheticCategory ? c.syncId : null;
    final accountOverride = isSyntheticAccount
        ? await _resolveSyncIdByAccountId(res.accountId!, ledgerId)
        : null;
    // v38 拆帳:三態語義直接透傳(null=不動;[]=顯式清空;非空=整組覆蓋),
    // 見 AmountEditorResult.splits / TransactionRepository.updateTransaction
    // 的註解。categoryId/categorySyncIdOverride 在 splits 非空時會被 repo
    // 內部強制清空,這裡不用重複處理。
    final splitsForWrite = res.splits
        ?.map((s) => TransactionSplitInput(
              categoryId: s.categoryId,
              categorySyncIdOverride: s.categorySyncId,
              amount: s.amount,
              note: s.note,
            ))
        .toList();
    if (widget.editingTransactionId != null) {
      // v36 修正:「修改此記錄」vs「修改連同未來週期」的選擇彈窗理想上已經在
      // 進入這個編輯頁「之前」由呼叫端(`TransactionEditUtils.editTransaction`)
      // 問過,結果透過 `widget.initialRecurringEditScope` 帶進來,這裡直接沿
      // 用不重問(原本在存檔這一刻才問,使用者從明細頁點編輯鉛筆會先看到完
      // 整表單,體感像是彈窗沒出現)。呼叫端忘了先問(或直接構造這個 page 略
      // 過入口)時當安全網,存檔這一刻補問一次。純本地一次性交易
      // (recurringRuleId == null)這個值本來就是 null,不受影響。
      final original =
          await repo.getTransactionById(widget.editingTransactionId!);
      RecurringEditScope? recurringScope = widget.initialRecurringEditScope;
      if (original?.recurringRuleId != null && recurringScope == null) {
        if (!mounted) return;
        recurringScope = await showRecurringEditChoiceSheet(context);
        if (recurringScope == null) {
          // 使用者取消選擇——整個存檔動作中止,不寫入任何變更。表單那顆存檔鍵
          // 靠 onSubmit 回傳的 Future 完成後自動解除 _isSubmitting,不用在
          // 這裡另外處理。
          return;
        }
      }

      // 编辑模式：使用repository更新交易(不论「此记录」还是「连同未来周期」
      // 都先执行这一步——被直接编辑的这一笔本来就该拿到完整的欄位变更,附件/
      // 汇率/账单标记等「連同未來週期」批次不转发的欄位靠这次调用落地)。
      await repo.updateTransaction(
        id: widget.editingTransactionId!,
        type: kind,
        amount: res.amount,
        categoryId: categoryIdForWrite,
        note: res.note,
        merchant: res.merchant,
        happenedAt: res.date,
        accountId: accountIdForUpdate,
        categorySyncIdOverride: categoryOverride,
        accountSyncIdOverride: accountOverride,
        excludeFromStats: res.excludeFromStats,
        excludeFromBudget: res.excludeFromBudget,
        currencyCode: res.currencyCode,
        nativeAmount: res.nativeAmount,
        rewardRuleIds: res.rewardRuleIds,
        splits: splitsForWrite,
      );
      transactionId = widget.editingTransactionId!;
      // 共享账本:本地 lastEditedByUserId 立即回填,UI 头像组直接展示
      // 当前 user 为编辑人(否则要等 server 下次 pull 才回来)
      await TxAuthorService.markEdited(ref, transactionId);

      if (recurringScope == RecurringEditScope.thisOnly) {
        // 「此記錄」:標記 overridden,之后「連同未來週期」的批次更新要跳过
        // 这一笔。updateTransaction 已经记过一条 change,push 时序列化器统一
        // 读 DB 最新状态,这里不用再补一条 change(同本文件 TAG override 那段
        // 注释的既有惯例)。
        if (repo is LocalRepository) {
          await (repo.db.update(repo.db.transactions)
                ..where((t) => t.id.equals(transactionId)))
              .write(const TransactionsCompanion(
                  recurringOccurrenceOverridden: d.Value(true)));
        }
      } else if (recurringScope == RecurringEditScope.thisAndFuture) {
        // 「連同未來週期」:把「規則模板」欄位(不含附件/匯率/帳單標記——這些
        // 是逐筆概念,見 RecurringRuleRepository.updateRuleAndFuture 的窄欄位
        // 集合)轉發給規則本身 + 同規則、未來、未被單獨編輯過的既有 occurrence。
        final rule = await repo.getRuleBySyncId(original!.recurringRuleId!);
        if (rule != null) {
          await repo.updateRuleAndFuture(
            ruleId: rule.id,
            anchorTransactionId: transactionId,
            type: kind,
            amount: res.amount,
            categoryId: categoryIdForWrite,
            accountId: accountIdForAdd,
            note: res.note,
            merchant: res.merchant,
          );
        }
      }
    } else if (res.recurringDraft != null) {
      // v36:新增時開啟了「週期」——建規則(內部會依演算法批次生成第一個視窗
      // 的 occurrence,含當下這一筆),不再另外呼叫 addTransaction。
      final draft = res.recurringDraft!;
      final ruleId = await repo.createRule(
        ledgerId: ledgerId,
        type: kind,
        amount: res.amount,
        categoryId: categoryIdForWrite,
        accountId: accountIdForAdd,
        note: res.note,
        merchant: res.merchant,
        rewardRuleSyncIds: res.rewardRuleIds,
        frequency: draft.frequency,
        interval: draft.interval,
        advancedRule: draft.advancedRule,
        nextRunAt: res.date,
        endAt: draft.endAt,
      );
      final rule = await repo.getRuleById(ruleId);
      int? firstOccurrenceId;
      if (rule?.syncId != null && repo is LocalRepository) {
        final first = await (repo.db.select(repo.db.transactions)
              ..where((t) => t.recurringRuleId.equals(rule!.syncId!))
              ..orderBy([(t) => d.OrderingTerm.asc(t.happenedAt)])
              ..limit(1))
            .getSingleOrNull();
        firstOccurrenceId = first?.id;
      }
      transactionId = firstOccurrenceId ?? -1;
      if (transactionId != -1) {
        await TxAuthorService.markCreated(ref, transactionId);
      }
    } else {
      transactionId = await repo.addTransaction(
        ledgerId: ledgerId,
        type: kind,
        amount: res.amount,
        categoryId: categoryIdForWrite,
        happenedAt: res.date,
        note: res.note,
        merchant: res.merchant,
        accountId: accountIdForAdd,
        categorySyncIdOverride: categoryOverride,
        accountSyncIdOverride: accountOverride,
        excludeFromStats: res.excludeFromStats,
        excludeFromBudget: res.excludeFromBudget,
        currencyCode: res.currencyCode,
        nativeAmount: res.nativeAmount,
        refundOfSyncId: widget.initialRefundOfSyncId,
        rewardRuleIds: res.rewardRuleIds,
        splits: splitsForWrite,
      );
      // 共享账本:新建本地 tx 也回填创建人 + 编辑人(同一个 user)
      await TxAuthorService.markCreated(ref, transactionId);
    }
    // 保存待上传的附件
    if (res.pendingAttachments.isNotEmpty) {
      await attachmentService.saveAttachments(
        transactionId: transactionId,
        sourceFiles: res.pendingAttachments,
        startIndex: 0,
      );
      // 刷新附件列表缓存
      ref.read(attachmentListRefreshProvider.notifier).state++;
    }
    // 更新标签关联
    // §7 共享账本:tag.id < 0 是 synthetic(Owner tag from SharedLedger*),
    // 主表 Tags 没该行,不能直接写 transaction_tags.tag_id。分两类:
    // - 正数 id → 写 transaction_tags 主表(老路径)
    // - 负数 id → 走 SharedLedgerTags 反查 syncId → 写 transaction_tag_overrides
    final normalTagIds = res.tagIds.where((id) => id >= 0).toList();
    final syntheticTagIds = res.tagIds.where((id) => id < 0).toList();

    if (normalTagIds.isNotEmpty) {
      await repo.updateTransactionTags(
        transactionId: transactionId,
        tagIds: normalTagIds,
      );
      ref.read(tagListRefreshProvider.notifier).state++;
    } else if (widget.editingTransactionId != null) {
      // 编辑模式没主表 tag → 清掉旧主表关联
      await repo.removeAllTagsFromTransaction(transactionId);
      ref.read(tagListRefreshProvider.notifier).state++;
    }

    // §7 写 override:先反查 tx.syncId + 把 synthetic tag_id 翻译成
    // Owner tag syncId,再 upsert 进 TransactionTagOverrides
    if (repo is LocalRepository) {
      final txRow = await (repo.db.select(repo.db.transactions)
            ..where((t) => t.id.equals(transactionId)))
          .getSingleOrNull();
      final txSyncId = txRow?.syncId;
      if (txSyncId != null) {
        await (repo.db.delete(repo.db.transactionTagOverrides)
              ..where((t) => t.transactionSyncId.equals(txSyncId)))
            .go();
        if (syntheticTagIds.isNotEmpty) {
          final allShared =
              await repo.db.select(repo.db.sharedLedgerTags).get();
          final now = DateTime.now().toUtc();
          for (final sid in syntheticTagIds) {
            for (final s in allShared) {
              if (syntheticIdForSyncId(s.syncId) == sid) {
                await repo.db.into(repo.db.transactionTagOverrides).insert(
                      TransactionTagOverridesCompanion.insert(
                        transactionSyncId: txSyncId,
                        tagSyncId: s.syncId,
                        createdAt: now,
                      ),
                    );
                break;
              }
            }
          }
          ref.read(tagListRefreshProvider.notifier).state++;
        }
        // 这里**不再**重复 recordLedgerChange(transaction:update)。
        // 之前为了"override 变化也走 push"专门补一条 update,但
        // - addTransaction / updateTransaction 已经登记过一次 change
        // - _serializeEntityForPush('transaction') 在 push 时**统一**读 DB
        //   最新状态(包括 transaction_tag_overrides 表),payload 自然含
        //   最新 overrides
        // 结论:那条补登记的 update 跟前面的 create/update 推同样 payload,
        // 服务端 sync_changes 表凭空多一条 row(已观察到共享账本 Editor
        // 创建 tx 时 1 秒内 2 条 identical upsert)。直接砍。
      }
    }
    // 统一处理：自动/手动同步与状态刷新（后台静默）
    PostProcessor.sync(ref, ledgerId: ledgerId);
    // 刷新：账本笔数与全局统计
    ref.invalidate(countsForLedgerProvider(ledgerId));
    ref.read(statsRefreshProvider.notifier).state++;
    // 刷新：预算数据
    ref.read(budgetRefreshProvider.notifier).state++;
    // 更新小组件数据（后台执行，不阻塞UI）
    if (mounted) {
      updateAppWidget(ref, context);
    }
    // 先关闭页面，再播放反馈
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    // 反馈：轻微触感 + 系统点击音
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
  }

  /// §7 v25:account picker 返 synthetic Account(id<0)时,把 id 反查
  /// SharedLedgerAccounts 拿 syncId,写到 tx.accountSyncIdOverride。
  /// 失败返 null,调用方应回到 accountId int 路径(synthetic 不一致时的兜底)。
  Future<String?> _resolveSyncIdByAccountId(int accountId, int ledgerId) async {
    if (accountId >= 0) return null;
    final repo = ref.read(repositoryProvider);
    if (repo is! LocalRepository) return null;
    // 反查:本地 ledger.syncId → SharedLedgerAccounts ledgerSyncId 范围
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
}
