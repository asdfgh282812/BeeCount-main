import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart' as db;
import '../../providers.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../styles/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../utils/transaction_edit_utils.dart';
import '../../utils/currencies.dart';
import '../../widgets/category_icon.dart';
import '../../utils/account_type_utils.dart';
import '../../widgets/charts/account_category_pie_chart.dart';
import '../transaction/transaction_editor_page.dart';
import 'account_edit_page.dart';

// ============================================
// Providers
// ============================================

/// 分页交易状态
class AccountTransactionsPaginationState {
  final List<db.Transaction> transactions;
  final bool isLoading;
  final bool hasMore;

  const AccountTransactionsPaginationState({
    this.transactions = const [],
    this.isLoading = false,
    this.hasMore = true,
  });

  AccountTransactionsPaginationState copyWith({
    List<db.Transaction>? transactions,
    bool? isLoading,
    bool? hasMore,
  }) {
    return AccountTransactionsPaginationState(
      transactions: transactions ?? this.transactions,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

class AccountTransactionsPaginationNotifier
    extends StateNotifier<AccountTransactionsPaginationState> {
  final Ref ref;
  final int accountId;
  /// 资金流向过滤:'expense'=支出+转出,'income'=收入+转入,null=全部
  final String? flow;
  /// 主帳戶(合併帳單分組)聚合視圖:一併拉取這些子帳戶的交易。
  final List<int> extraAccountIds;
  static const _pageSize = 50;

  AccountTransactionsPaginationNotifier(
      this.ref, this.accountId, this.flow, this.extraAccountIds)
      : super(const AccountTransactionsPaginationState()) {
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    state = state.copyWith(isLoading: true);
    try {
      final repo = ref.read(repositoryProvider);
      final transactions = await repo.getAccountTransactions(
        accountId,
        limit: _pageSize,
        offset: 0,
        flow: flow,
        extraAccountIds: extraAccountIds.isEmpty ? null : extraAccountIds,
      );
      state = AccountTransactionsPaginationState(
        transactions: transactions,
        isLoading: false,
        hasMore: transactions.length >= _pageSize,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true);
    try {
      final repo = ref.read(repositoryProvider);
      final transactions = await repo.getAccountTransactions(
        accountId,
        limit: _pageSize,
        offset: state.transactions.length,
        flow: flow,
        extraAccountIds: extraAccountIds.isEmpty ? null : extraAccountIds,
      );
      state = state.copyWith(
        transactions: [...state.transactions, ...transactions],
        isLoading: false,
        hasMore: transactions.length >= _pageSize,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> refresh() async {
    state = const AccountTransactionsPaginationState(isLoading: true);
    try {
      final repo = ref.read(repositoryProvider);
      final transactions = await repo.getAccountTransactions(
        accountId,
        limit: _pageSize,
        offset: 0,
        flow: flow,
        extraAccountIds: extraAccountIds.isEmpty ? null : extraAccountIds,
      );
      state = AccountTransactionsPaginationState(
        transactions: transactions,
        isLoading: false,
        hasMore: transactions.length >= _pageSize,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }
}

/// [extraIdsKey]:主帳戶聚合視圖的子帳戶 id 清單,逗號分隔且已排序(空字串
/// = 沒有子帳戶),用字串而非 List 是因為 Riverpod family key 需要值相等,
/// List 沒有結構相等會導致每次都判定成新 key、緩存失效。
final accountTransactionsPaginatedProvider = StateNotifierProvider.family
    .autoDispose<AccountTransactionsPaginationNotifier,
        AccountTransactionsPaginationState,
        ({int accountId, String? flow, String extraIdsKey})>(
  (ref, params) {
    final extraIds = params.extraIdsKey.isEmpty
        ? const <int>[]
        : params.extraIdsKey.split(',').map(int.parse).toList();
    return AccountTransactionsPaginationNotifier(
        ref, params.accountId, params.flow, extraIds);
  },
);

/// 帳單週期交易(信用卡「交易明細」tab 的對帳彙總用):按選定週期一次拉全量
/// (單一帳單週期筆數天然有限,不用分頁),供彙總卡片跟交易列表共用同一份
/// 資料,兩處數字保證一致。
final accountBillingPeriodTransactionsProvider = FutureProvider.family
    .autoDispose<List<db.Transaction>,
        ({int accountId, String extraIdsKey, DateTime start, DateTime end})>(
  (ref, params) async {
    final repo = ref.watch(repositoryProvider);
    final extraIds = params.extraIdsKey.isEmpty
        ? null
        : params.extraIdsKey.split(',').map(int.parse).toList();
    return repo.getAccountTransactions(
      params.accountId,
      limit: 1000,
      offset: 0,
      extraAccountIds: extraIds,
      startDate: params.start,
      endDate: params.end,
    );
  },
);

/// 分类统计 Provider
final accountCategoryStatsProvider = FutureProvider.family
    .autoDispose<List<({int? id, String name, String? icon, double total})>,
        ({int accountId, String type})>((ref, params) async {
  final repo = ref.watch(repositoryProvider);
  return repo.getAccountCategoryStats(params.accountId, type: params.type);
});

// ============================================
// Page
// ============================================

/// 账户详情页面
class AccountDetailPage extends ConsumerStatefulWidget {
  final db.Account account;

  const AccountDetailPage({
    super.key,
    required this.account,
  });

  @override
  ConsumerState<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends ConsumerState<AccountDetailPage>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late final TabController _tabController;
  /// 详情页图表 tab: 0=支出分布, 1=收入分布
  int _detailChartTab = 0;
  /// 帳單週期導航偏移(信用卡「交易明細」tab):0=本期,負數=更早的週期。
  int _billingPeriodOffset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// 列表的资金流向过滤,跟随图表 tab:支出=支出+转出,收入=收入+转入。
  /// 信用卡没有 tab 切换,保持展示全部交易(消费+还款转账)。
  String? get _listFlow {
    if (widget.account.type == 'credit_card') return null;
    return _detailChartTab == 0 ? 'expense' : 'income';
  }

  /// 主帳戶(合併帳單分組)的子帳戶清單:同幣種與否都算,只要 parentAccountId
  /// 指向這張卡的 syncId。找不到 syncId(理論上不會發生)時視為沒有子帳戶。
  List<db.Account> _children(List<db.Account> allAccounts) {
    final syncId = widget.account.syncId;
    if (syncId == null || syncId.isEmpty) return const [];
    return allAccounts.where((a) => a.parentAccountId == syncId).toList();
  }

  /// Riverpod family key 用:子帳戶 id 逗號分隔(已排序,保證同一組子帳戶不
  /// 論 stream 回傳順序如何都命中同一個 provider 實例)。
  String _extraIdsKey(List<db.Account> children) {
    final ids = children.map((a) => a.id).toList()..sort();
    return ids.join(',');
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final allAccounts =
          ref.read(allAccountsStreamProvider).valueOrNull ?? const [];
      ref
          .read(accountTransactionsPaginatedProvider((
            accountId: widget.account.id,
            flow: _listFlow,
            extraIdsKey: _extraIdsKey(_children(allAccounts)),
          )).notifier)
          .loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final account = widget.account;
    final allAccounts =
        ref.watch(allAccountsStreamProvider).valueOrNull ?? const <db.Account>[];
    final children = _children(allAccounts);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          // ======== 简洁头部 ========
          PrimaryHeader(
            title: account.name,
            subtitle: getAccountTypeLabel(context, account.type),
            showBack: true,
            compact: true,
            actions: [
              IconButton(
                icon: Icon(
                  Icons.edit_outlined,
                  color: BeeTokens.iconPrimary(context),
                  size: 20,
                ),
                onPressed: () async {
                  final currentLedger = ref.read(currentLedgerProvider).asData?.value;
                  if (currentLedger == null) return;
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AccountEditPage(
                        account: account,
                        ledgerId: currentLedger.id,
                      ),
                    ),
                  );
                  if (result == true && mounted) {
                    Navigator.pop(context, true);
                  }
                },
              ),
            ],
          ),
          // ======== 交易明細 / 帳戶資訊 tab ========
          Container(
            color: BeeTokens.surface(context),
            child: TabBar(
              controller: _tabController,
              labelColor: ref.watch(primaryColorProvider),
              unselectedLabelColor: BeeTokens.textSecondary(context),
              indicatorColor: ref.watch(primaryColorProvider),
              tabs: [
                Tab(text: l10n.accountDetailTabTransactions),
                Tab(text: l10n.accountDetailTabInfo),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTransactionsTab(context, account, children, l10n),
                _buildInfoTab(context, account, children, l10n),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 「交易明細」tab:估值账户维持原本的估值卡片;信用卡用帳單週期彙總卡
  /// +（子帳戶存在時聚合)交易列表;其它可交易账户维持原本 余额/收入支出卡
  /// + 概览卡 + 图表 + 分页交易列表。
  Widget _buildTransactionsTab(
    BuildContext context,
    db.Account account,
    List<db.Account> children,
    AppLocalizations l10n,
  ) {
    final primaryColor = ref.watch(primaryColorProvider);
    final statsAsync = ref.watch(accountStatsProvider(account.id));
    final currencyCode = account.currency;
    final categoriesAsync = ref.watch(categoriesProvider);
    final isValuation = isValuationOnlyType(account.type);
    final typeColor = getColorForAccountType(account.type, primaryColor);

    if (isValuation) {
      return ListView(
        padding: EdgeInsets.symmetric(vertical: 8.0.scaled(context, ref)),
        children: [
          _buildValuationCard(context, ref, account, statsAsync, currencyCode, primaryColor, l10n),
        ],
      );
    }

    if (account.type == 'credit_card') {
      return ListView(
        padding: EdgeInsets.symmetric(vertical: 8.0.scaled(context, ref)),
        children: [
          _buildBillingSummaryCard(context, account, children, l10n, primaryColor, currencyCode),
          SizedBox(height: 8.0.scaled(context, ref)),
          _buildBillingTransactionList(
            context, account, children, currencyCode, primaryColor,
            categoriesAsync.asData?.value ?? [], l10n, typeColor,
          ),
        ],
      );
    }

    final expenseStatsAsync = ref.watch(accountCategoryStatsProvider(
        (accountId: account.id, type: 'expense')));
    final incomeStatsAsync = ref.watch(accountCategoryStatsProvider(
        (accountId: account.id, type: 'income')));
    final paginationState = ref.watch(accountTransactionsPaginatedProvider((
      accountId: account.id,
      flow: _listFlow,
      extraIdsKey: '',
    )));

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(vertical: 8.0.scaled(context, ref)),
      children: [
        _buildStatsCard(context, ref, account, statsAsync, currencyCode, l10n),
        SizedBox(height: 4.0.scaled(context, ref)),
        _buildOverviewCard(
          context, ref, account, statsAsync,
          currencyCode, primaryColor, typeColor, l10n,
        ),
        SizedBox(height: 8.0.scaled(context, ref)),
        _buildDetailChartSection(
          context, ref, l10n, primaryColor,
          expenseStatsAsync, incomeStatsAsync, typeColor,
          isCreditCard: false,
        ),
        SizedBox(height: 12.0.scaled(context, ref)),
        _buildTransactionList(
          context,
          paginationState,
          currencyCode,
          primaryColor,
          categoriesAsync.asData?.value ?? [],
          l10n,
          typeColor,
          accountNameById: const {},
        ),
      ],
    );
  }

  /// 「帳戶資訊」tab:信用卡保留原本的额度/账单日概览卡(含快速还款按钮),
  /// 加上欄位式資訊清單(名稱/幣種/分組/子帳戶數量/自動扣繳/低額度提醒等);
  /// 其它账户只顯示欄位清單。
  Widget _buildInfoTab(
    BuildContext context,
    db.Account account,
    List<db.Account> children,
    AppLocalizations l10n,
  ) {
    final primaryColor = ref.watch(primaryColorProvider);
    final statsAsync = ref.watch(accountStatsProvider(account.id));
    final currencyCode = account.currency;
    final typeColor = getColorForAccountType(account.type, primaryColor);

    return ListView(
      padding: EdgeInsets.symmetric(vertical: 8.0.scaled(context, ref)),
      children: [
        if (account.type == 'credit_card') ...[
          _buildOverviewCard(
            context, ref, account, statsAsync,
            currencyCode, primaryColor, typeColor, l10n,
          ),
          SizedBox(height: 8.0.scaled(context, ref)),
        ],
        _buildInfoFieldsCard(context, account, children, l10n),
      ],
    );
  }

  /// 余额/收入/支出统计卡片
  Widget _buildStatsCard(
    BuildContext context,
    WidgetRef ref,
    db.Account account,
    AsyncValue<({double balance, double income, double expense})> statsAsync,
    String currencyCode,
    AppLocalizations l10n,
  ) {
    return SectionCard(
      margin: EdgeInsets.symmetric(horizontal: 12.0.scaled(context, ref)),
      child: statsAsync.when(
        data: (stats) => Row(
          children: [
            Expanded(
              child: _DetailStatCell(
                label: account.type == 'credit_card'
                    ? l10n.creditCardOwed
                    : l10n.accountBalance,
                value: stats.balance,
                currencyCode: currencyCode,
              ),
            ),
            Container(
              width: 1,
              height: 36.0.scaled(context, ref),
              color: BeeTokens.divider(context),
            ),
            Expanded(
              child: _DetailStatCell(
                label: l10n.homeIncome,
                value: stats.income,
                currencyCode: currencyCode,
              ),
            ),
            Container(
              width: 1,
              height: 36.0.scaled(context, ref),
              color: BeeTokens.divider(context),
            ),
            Expanded(
              child: _DetailStatCell(
                label: l10n.homeExpense,
                value: stats.expense,
                currencyCode: currencyCode,
              ),
            ),
          ],
        ),
        loading: () => SizedBox(
          height: 60.0.scaled(context, ref),
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, __) => const SizedBox.shrink(),
      ),
    );
  }

  /// 估值账户专属卡片
  Widget _buildValuationCard(
    BuildContext context,
    WidgetRef ref,
    db.Account account,
    AsyncValue<({double balance, double income, double expense})> statsAsync,
    String currencyCode,
    Color primaryColor,
    AppLocalizations l10n,
  ) {
    final isLiability = isLiabilityType(account.type);
    final valueLabel = isLiability ? l10n.valuationCurrentDebt : l10n.valuationCurrentValue;
    final updateLabel = isLiability ? l10n.valuationUpdateDebt : l10n.valuationUpdateValue;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.0.scaled(context, ref)),
      child: SectionCard(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(20.0.scaled(context, ref)),
          child: Column(
            children: [
              // 类型图标
              AccountTypeIcon(
                type: account.type,
                size: 48.0.scaled(context, ref),
              ),
              SizedBox(height: 12.0.scaled(context, ref)),
              // 标签
              Text(
                valueLabel,
                style: TextStyle(
                  fontSize: 13,
                  color: BeeTokens.textSecondary(context),
                ),
              ),
              SizedBox(height: 6.0.scaled(context, ref)),
              // 金额
              statsAsync.when(
                data: (stats) => AmountText(
                  value: isLiability ? stats.balance.abs() : stats.balance,
                  signed: false,
                  showCurrency: true,
                  useCompactFormat: ref.watch(compactAmountProvider),
                  currencyCode: currencyCode,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
                loading: () => SizedBox(
                  height: 36.0.scaled(context, ref),
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                error: (_, __) => const Text('-'),
              ),
              SizedBox(height: 8.0.scaled(context, ref)),
              // 上次更新时间
              if (account.updatedAt != null)
                Text(
                  l10n.valuationLastUpdated(
                    '${account.updatedAt!.year}-${account.updatedAt!.month.toString().padLeft(2, '0')}-${account.updatedAt!.day.toString().padLeft(2, '0')}',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: BeeTokens.textTertiary(context),
                  ),
                ),
              // 备注
              if (account.note != null && account.note!.isNotEmpty) ...[
                SizedBox(height: 8.0.scaled(context, ref)),
                Text(
                  account.note!,
                  style: TextStyle(
                    fontSize: 13,
                    color: BeeTokens.textSecondary(context),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              SizedBox(height: 16.0.scaled(context, ref)),
              // 更新估值按钮
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showUpdateValuationDialog(
                    context, ref, account, isLiability, currencyCode, l10n,
                  ),
                  icon: Icon(Icons.edit_outlined, size: 16, color: Colors.white),
                  label: Text(updateLabel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(vertical: 12.0.scaled(context, ref)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0.scaled(context, ref)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 更新估值弹窗
  Future<void> _showUpdateValuationDialog(
    BuildContext context,
    WidgetRef ref,
    db.Account account,
    bool isLiability,
    String currencyCode,
    AppLocalizations l10n,
  ) async {
    final controller = TextEditingController(
      text: account.initialBalance.abs().toStringAsFixed(2),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) {
        final primaryColor = ref.watch(primaryColorProvider);
        return AlertDialog(
          title: Text(isLiability ? l10n.valuationUpdateDebt : l10n.valuationUpdateValue),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              prefixText: '${getCurrencySymbol(currencyCode)} ',
              hintText: isLiability ? l10n.valuationDebtHint : l10n.valuationAccountHint,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () {
                final value = double.tryParse(controller.text.trim());
                if (value != null) {
                  Navigator.pop(ctx, value);
                }
              },
              style: TextButton.styleFrom(foregroundColor: primaryColor),
              child: Text(l10n.commonOk),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result != null) {
      final repo = ref.read(repositoryProvider);
      // 贷款存储为负数
      final storedValue = isLiability ? -result.abs() : result;
      await repo.updateAccountValuation(account.id, storedValue);

      if (mounted) {
        // 刷新数据
        ref.invalidate(accountStatsProvider(account.id));
        showToast(context, l10n.commonSave);
        // 返回上一页刷新数据
        Navigator.pop(context, true);
      }
    }
  }

  /// 账户概览卡片（合并 metadata + 类型统计信息）
  Widget _buildOverviewCard(
    BuildContext context,
    WidgetRef ref,
    db.Account account,
    AsyncValue<({double balance, double expense, double income})> statsAsync,
    String currencyCode,
    Color primaryColor,
    Color typeColor,
    AppLocalizations l10n,
  ) {
    final hasMetadata = _hasMetadata(account);
    final hasTypeStats = account.type == 'credit_card';

    if (!hasMetadata && !hasTypeStats) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.0.scaled(context, ref)),
      child: SectionCard(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(12.0.scaled(context, ref)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // metadata 行
              if (hasMetadata) ...[
                _buildMetadataInline(context, account),
                if (hasTypeStats)
                  Divider(height: 20, color: BeeTokens.divider(context)),
              ],
              // 类型专属统计
              if (hasTypeStats)
                statsAsync.when(
                  data: (stats) => _buildTypeStatsInline(
                    context, ref, account, stats, currencyCode, primaryColor, typeColor, l10n,
                  ),
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// metadata 内联显示
  Widget _buildMetadataInline(BuildContext context, db.Account account) {
    final parts = <String>[];
    if (account.bankName != null && account.bankName!.isNotEmpty) {
      parts.add(account.bankName!);
    }
    if (account.cardLastFour != null && account.cardLastFour!.isNotEmpty) {
      parts.add('**** ${account.cardLastFour!}');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (parts.isNotEmpty)
          Text(
            parts.join(' · '),
            style: TextStyle(
              fontSize: 13,
              color: BeeTokens.textSecondary(context),
            ),
          ),
        if (account.note != null && account.note!.isNotEmpty) ...[
          if (parts.isNotEmpty) const SizedBox(height: 4),
          Text(
            account.note!,
            style: TextStyle(
              fontSize: 12,
              color: BeeTokens.textTertiary(context),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  /// 类型专属统计内联显示
  Widget _buildTypeStatsInline(
    BuildContext context,
    WidgetRef ref,
    db.Account account,
    ({double balance, double expense, double income}) stats,
    String currencyCode,
    Color primaryColor,
    Color typeColor,
    AppLocalizations l10n,
  ) {
    if (account.type == 'credit_card') {
      final creditLimit = account.creditLimit;
      final usedAmount = stats.balance < 0 ? -stats.balance : 0.0;
      final usageRate = (creditLimit != null && creditLimit > 0)
          ? (usedAmount / creditLimit).clamp(0.0, 1.0)
          : 0.0;

      // 计算距还款日天数
      final hasBillingInfo = account.billingDay != null && account.paymentDueDay != null;
      int? daysUntilPayment;
      if (account.paymentDueDay != null) {
        final now = DateTime.now();
        final today = now.day;
        final dueDay = account.paymentDueDay!;
        if (today <= dueDay) {
          daysUntilPayment = dueDay - today;
        } else {
          // 已过本月还款日，算到下月
          final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
          daysUntilPayment = daysInMonth - today + dueDay;
        }
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 当前欠款(待还) —— 永远显示,不依赖额度
          Row(
            children: [
              Text(
                l10n.creditCardOwed,
                style: TextStyle(fontSize: 13, color: BeeTokens.textSecondary(context)),
              ),
              const Spacer(),
              AmountText(
                value: usedAmount,
                signed: false,
                showCurrency: false,
                useCompactFormat: ref.watch(compactAmountProvider),
                currencyCode: currencyCode,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: BeeTokens.textPrimary(context),
                ),
              ),
            ],
          ),
          // 额度/已用/可用 + 进度条 —— 仅设过额度时
          if (creditLimit != null) ...[
            SizedBox(height: 12.0.scaled(context, ref)),
            Row(
              children: [
                Expanded(child: _OverviewStatCell(label: l10n.creditLimit, value: creditLimit)),
                Expanded(child: _OverviewStatCell(label: l10n.creditUsed, value: usedAmount)),
                Expanded(child: _OverviewStatCell(label: l10n.creditAvailable, value: creditLimit - usedAmount)),
              ],
            ),
            SizedBox(height: 8.0.scaled(context, ref)),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: usageRate,
                backgroundColor: BeeTokens.divider(context),
                valueColor: AlwaysStoppedAnimation<Color>(
                  usageRate < 0.5 ? BeeTokens.success(context)
                      : usageRate < 0.8 ? BeeTokens.warning(context)
                      : BeeTokens.error(context),
                ),
                minHeight: 4,
              ),
            ),
          ],
          // 账单日/还款日信息
          if (hasBillingInfo || account.paymentDueDay != null) ...[
            SizedBox(height: 10.0.scaled(context, ref)),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: 12.0.scaled(context, ref),
                vertical: 10.0.scaled(context, ref),
              ),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8.0.scaled(context, ref)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: primaryColor,
                  ),
                  SizedBox(width: 8.0.scaled(context, ref)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasBillingInfo)
                          Text(
                            l10n.creditCardBillingInfo(account.billingDay!, account.paymentDueDay!),
                            style: TextStyle(
                              fontSize: 12,
                              color: BeeTokens.textSecondary(context),
                            ),
                          ),
                        if (daysUntilPayment != null) ...[
                          if (hasBillingInfo) SizedBox(height: 2.0.scaled(context, ref)),
                          Text(
                            daysUntilPayment == 0
                                ? l10n.creditCardPaymentDueToday
                                : l10n.creditCardDaysUntilPayment(daysUntilPayment),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: daysUntilPayment <= 3
                                  ? BeeTokens.error(context)
                                  : daysUntilPayment <= 7
                                      ? BeeTokens.warning(context)
                                      : primaryColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 8.0.scaled(context, ref)),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _quickTransfer(
                context, account,
                toAccountId: account.id,
              ),
              icon: Icon(Icons.payment, size: 16, color: primaryColor),
              label: Text(l10n.creditCardQuickRepay),
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryColor,
                side: BorderSide(color: primaryColor.withValues(alpha: 0.3)),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  /// 详情页图表区域（支出分布/收入分布 切换）
  Widget _buildDetailChartSection(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Color primaryColor,
    AsyncValue<List<({int? id, String name, String? icon, double total})>> expenseStatsAsync,
    AsyncValue<List<({int? id, String name, String? icon, double total})>> incomeStatsAsync,
    Color typeColor, {
    required bool isCreditCard,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.0.scaled(context, ref)),
      child: SectionCard(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(12.0.scaled(context, ref)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 分段切换器
              Row(
                children: [
                  _DetailChartTab(
                    label: l10n.homeExpense,
                    isSelected: isCreditCard || _detailChartTab == 0,
                    primaryColor: primaryColor,
                    onTap: () => setState(() => _detailChartTab = 0),
                  ),
                  if (!isCreditCard) ...[
                    SizedBox(width: 6.0.scaled(context, ref)),
                    _DetailChartTab(
                      label: l10n.homeIncome,
                      isSelected: _detailChartTab == 1,
                      primaryColor: primaryColor,
                      onTap: () => setState(() => _detailChartTab = 1),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 12.0.scaled(context, ref)),
              // 图表内容
              if (isCreditCard || _detailChartTab == 0)
                expenseStatsAsync.when(
                  data: (data) {
                    if (data.isEmpty) {
                      return SizedBox(
                        height: 180,
                        child: Center(
                          child: Text('-', style: TextStyle(color: BeeTokens.textTertiary(context))),
                        ),
                      );
                    }
                    return AccountCategoryPieChart(
                      expenseData: data,
                      incomeData: const [],
                      accentColor: primaryColor,
                      embedded: true,
                      type: 'expense',
                    );
                  },
                  loading: () => const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  error: (_, __) => const SizedBox(height: 180),
                )
              else
                incomeStatsAsync.when(
                  data: (data) {
                    if (data.isEmpty) {
                      return SizedBox(
                        height: 180,
                        child: Center(
                          child: Text('-', style: TextStyle(color: BeeTokens.textTertiary(context))),
                        ),
                      );
                    }
                    return AccountCategoryPieChart(
                      expenseData: const [],
                      incomeData: data,
                      accentColor: primaryColor,
                      embedded: true,
                      type: 'income',
                    );
                  },
                  loading: () => const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  error: (_, __) => const SizedBox(height: 180),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _hasMetadata(db.Account account) {
    return (account.bankName != null && account.bankName!.isNotEmpty) ||
        (account.cardLastFour != null && account.cardLastFour!.isNotEmpty) ||
        (account.note != null && account.note!.isNotEmpty);
  }

  // ============================================
  // 帳單週期(信用卡「交易明細」/「帳戶資訊」tab 共用)
  // ============================================

  /// 帳單週期起訖:[offset]=0 為涵蓋今天的本期,負數往前推一期一期算。
  /// 沒設 billingDay 時退化成「每月 1 號」起算的自然月。
  ({DateTime start, DateTime end}) _billingPeriod(db.Account account, int offset) {
    final day = account.billingDay ?? 1;
    final now = DateTime.now();
    var anchorYear = now.year;
    var anchorMonth = now.month;
    if (now.day < day) {
      anchorMonth -= 1;
      if (anchorMonth == 0) {
        anchorMonth = 12;
        anchorYear -= 1;
      }
    }
    anchorMonth += offset;
    while (anchorMonth <= 0) {
      anchorMonth += 12;
      anchorYear -= 1;
    }
    while (anchorMonth > 12) {
      anchorMonth -= 12;
      anchorYear += 1;
    }
    final start = DateTime(anchorYear, anchorMonth, day);
    final nextStart = DateTime(anchorYear, anchorMonth + 1, day);
    final end = nextStart.subtract(const Duration(days: 1));
    return (start: start, end: end);
  }

  /// 繳款期限(帳戶資訊 tab):帳單週期結束後的第一個 paymentDueDay。
  DateTime _dueDate(DateTime periodEnd, int paymentDueDay) {
    var year = periodEnd.year;
    var month = periodEnd.month;
    var candidate = DateTime(year, month, paymentDueDay);
    if (!candidate.isAfter(periodEnd)) {
      month += 1;
      if (month > 12) {
        month = 1;
        year += 1;
      }
      candidate = DateTime(year, month, paymentDueDay);
    }
    return candidate;
  }

  String _formatYmd(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  // ============================================
  // 「交易明細」tab:信用卡帳單彙總卡片
  // ============================================

  Widget _buildBillingSummaryCard(
    BuildContext context,
    db.Account account,
    List<db.Account> children,
    AppLocalizations l10n,
    Color primaryColor,
    String currencyCode,
  ) {
    final period = _billingPeriod(account, _billingPeriodOffset);
    final txAsync = ref.watch(accountBillingPeriodTransactionsProvider((
      accountId: account.id,
      extraIdsKey: _extraIdsKey(children),
      start: period.start,
      end: period.end,
    )));

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.0.scaled(context, ref)),
      child: SectionCard(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 週期導航
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.chevron_left, size: 20,
                      color: BeeTokens.iconSecondary(context)),
                  onPressed: () => setState(() => _billingPeriodOffset -= 1),
                ),
                Text(
                  '${_formatYmd(period.start)} – ${_formatYmd(period.end)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.chevron_right, size: 20,
                      color: _billingPeriodOffset < 0
                          ? BeeTokens.iconSecondary(context)
                          : BeeTokens.iconTertiary(context)),
                  onPressed: _billingPeriodOffset < 0
                      ? () => setState(() => _billingPeriodOffset += 1)
                      : null,
                ),
              ],
            ),
            Divider(height: 16.0.scaled(context, ref), color: BeeTokens.divider(context)),
            txAsync.when(
              data: (txs) => _buildBillingSummaryRows(
                  context, txs, account, children, l10n, currencyCode),
              loading: () => Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0.scaled(context, ref)),
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  /// 彙總數字:新增花費/已繳金額是真實可算的(消費總額、轉入還款總額);
  /// 上期欠款/帳單分期/對帳筆數目前没有历史快照/分期/对账数据模型,
  /// 按「原本 app 不支援的功能先带 0/空值」处理。
  Widget _buildBillingSummaryRows(
    BuildContext context,
    List<db.Transaction> txs,
    db.Account account,
    List<db.Account> children,
    AppLocalizations l10n,
    String currencyCode,
  ) {
    final ids = {account.id, ...children.map((c) => c.id)};
    double newSpending = 0;
    double paidIn = 0;
    for (final tx in txs) {
      if (tx.type == 'expense' && ids.contains(tx.accountId)) {
        newSpending += tx.amount;
      } else if (tx.type == 'transfer' && ids.contains(tx.toAccountId)) {
        paidIn += tx.amount;
      }
    }
    const priorBalance = 0.0;
    final amountDue = -newSpending - priorBalance;
    final amountPaid = paidIn;
    final remaining = amountDue + amountPaid;
    final isPaidOff = remaining >= -0.005;
    final useCompact = ref.watch(compactAmountProvider);

    Widget amountValue(double v) => AmountText(
          value: v,
          signed: true,
          showCurrency: false,
          useCompactFormat: useCompact,
          currencyCode: currencyCode,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: BeeTokens.textPrimary(context),
          ),
        );

    Widget row(String label, Widget value) => Padding(
          padding: EdgeInsets.symmetric(vertical: 6.0.scaled(context, ref)),
          child: Row(
            children: [
              Text(label,
                  style: TextStyle(fontSize: 13, color: BeeTokens.textSecondary(context))),
              const Spacer(),
              value,
            ],
          ),
        );

    return Column(
      children: [
        row(l10n.billingSummaryNewSpending, amountValue(-newSpending)),
        row(l10n.billingSummaryPriorBalance, amountValue(priorBalance)),
        row(l10n.billingSummaryAmountDue, amountValue(amountDue)),
        row(l10n.billingSummaryAmountPaid, amountValue(amountPaid)),
        row(
          l10n.billingSummaryInstallments,
          Text('---', style: TextStyle(fontSize: 13, color: BeeTokens.textTertiary(context))),
        ),
        row(
          l10n.billingSummaryReconciledCount,
          Text('${txs.length} / ${txs.length}',
              style: TextStyle(fontSize: 13, color: BeeTokens.textPrimary(context))),
        ),
        row(
          l10n.billingSummaryRemaining,
          isPaidOff
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.billingSummaryPaidOff,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: BeeTokens.success(context),
                      ),
                    ),
                    SizedBox(width: 4.0.scaled(context, ref)),
                    Icon(Icons.check_circle, size: 15, color: BeeTokens.success(context)),
                  ],
                )
              : amountValue(remaining),
        ),
      ],
    );
  }

  /// 帳單週期交易列表(信用卡):跟彙總卡片同一份 [accountBillingPeriodTransactionsProvider]
  /// 資料,數字保證對得上;有子帳戶時每筆交易帶上所屬子帳戶名稱標籤。
  Widget _buildBillingTransactionList(
    BuildContext context,
    db.Account account,
    List<db.Account> children,
    String currencyCode,
    Color primaryColor,
    List<db.Category> categories,
    AppLocalizations l10n,
    Color typeColor,
  ) {
    final period = _billingPeriod(account, _billingPeriodOffset);
    final txAsync = ref.watch(accountBillingPeriodTransactionsProvider((
      accountId: account.id,
      extraIdsKey: _extraIdsKey(children),
      start: period.start,
      end: period.end,
    )));
    final accountNameById = <int, String>{
      if (children.isNotEmpty) account.id: account.name,
      for (final c in children) c.id: c.name,
    };

    return txAsync.when(
      data: (txs) => _buildBillingPeriodTransactionList(
        context, txs, currencyCode, primaryColor, categories, l10n, accountNameById,
      ),
      loading: () => Padding(
        padding: EdgeInsets.symmetric(vertical: 32.0.scaled(context, ref)),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  // ============================================
  // 「帳戶資訊」tab:欄位式資訊清單
  // ============================================

  TextStyle _infoValueStyle(BuildContext context) =>
      TextStyle(fontSize: 14, color: BeeTokens.textPrimary(context));

  Widget _buildInfoFieldsCard(
    BuildContext context,
    db.Account account,
    List<db.Account> children,
    AppLocalizations l10n,
  ) {
    final useCompact = ref.watch(compactAmountProvider);
    final rows = <Widget>[
      _InfoRow(
        label: l10n.accountNameLabel,
        value: Text(account.name, style: _infoValueStyle(context)),
      ),
      _InfoRow(
        label: l10n.accountMainCurrencyLabel,
        value: Text(account.currency, style: _infoValueStyle(context)),
      ),
      _InfoRow(
        label: l10n.accountGroupLabel,
        value: Text(getAccountTypeLabel(context, account.type), style: _infoValueStyle(context)),
      ),
    ];

    if (account.type == 'credit_card') {
      final period = _billingPeriod(account, 0);
      if (account.billingDay != null) {
        rows.add(_InfoRow(
          label: l10n.billingDay,
          value: Text(
            '${_formatYmd(period.start)} – ${_formatYmd(period.end)}',
            style: _infoValueStyle(context),
          ),
        ));
      }
      if (account.paymentDueDay != null) {
        final due = _dueDate(period.end, account.paymentDueDay!);
        rows.add(_InfoRow(
          label: l10n.paymentDueDay,
          value: Text(_formatYmd(due), style: _infoValueStyle(context)),
        ));
      }
      if (account.creditLimit != null) {
        rows.add(_InfoRow(
          label: l10n.creditLimit,
          value: AmountText(
            value: account.creditLimit!,
            signed: false,
            showCurrency: false,
            useCompactFormat: useCompact,
            currencyCode: account.currency,
            style: _infoValueStyle(context),
          ),
        ));
      }
      rows.add(_InfoRow(
        label: l10n.accountSubAccountsLabel,
        value: Text(
          children.isEmpty ? '-' : l10n.accountSubAccountsCount(children.length),
          style: _infoValueStyle(context),
        ),
      ));
      rows.add(_InfoRow(
        label: l10n.accountAutoPayLabel,
        value: Text(l10n.accountAutoPayNone, style: _infoValueStyle(context)),
      ));
      // 可用額度不足提醒:目前没有这个提醒功能,先展示为关闭的占位开关。
      rows.add(_InfoSwitchRow(label: l10n.accountLowCreditAlertLabel, value: false));
    }

    // 納入總餘額:目前所有账户(隐藏账户也不例外)一律计入净资产,没有排除
    // 开关,这里如实展示成常亮、不可交互的占位开关。
    rows.add(_InfoSwitchRow(label: l10n.accountIncludeInNetWorthLabel, value: true));

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.0.scaled(context, ref)),
      child: SectionCard(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.symmetric(horizontal: 12.0.scaled(context, ref)),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, color: BeeTokens.divider(context)),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionList(
    BuildContext context,
    AccountTransactionsPaginationState state,
    String currencyCode,
    Color primaryColor,
    List<db.Category> categories,
    AppLocalizations l10n,
    Color typeColor, {
    required Map<int, String> accountNameById,
  }) {
    final transactions = state.transactions;
    return _buildTransactionListBody(
      context, transactions, state.isLoading, state.hasMore,
      currencyCode, primaryColor, categories, l10n, accountNameById,
    );
  }

  /// 帳單週期彙總視圖(信用卡「交易明細」tab)專用:資料來源是一次性拉全量的
  /// [accountBillingPeriodTransactionsProvider],不是分頁 state,渲染邏輯跟
  /// [_buildTransactionList] 共用同一個 body。
  Widget _buildBillingPeriodTransactionList(
    BuildContext context,
    List<db.Transaction> transactions,
    String currencyCode,
    Color primaryColor,
    List<db.Category> categories,
    AppLocalizations l10n,
    Map<int, String> accountNameById,
  ) {
    return _buildTransactionListBody(
      context, transactions, false, false,
      currencyCode, primaryColor, categories, l10n, accountNameById,
    );
  }

  Widget _buildTransactionListBody(
    BuildContext context,
    List<db.Transaction> transactions,
    bool isLoading,
    bool hasMore,
    String currencyCode,
    Color primaryColor,
    List<db.Category> categories,
    AppLocalizations l10n,
    Map<int, String> accountNameById,
  ) {
    // 沿用旧的局部变量名,方便复用下面原封不动的渲染逻辑。
    final state = AccountTransactionsPaginationState(
      transactions: transactions, isLoading: isLoading, hasMore: hasMore);

    if (transactions.isEmpty && !state.isLoading) {
      return SectionCard(
        child: Padding(
          padding: EdgeInsets.all(32.0.scaled(context, ref)),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 48.0.scaled(context, ref),
                  color: BeeTokens.textTertiary(context),
                ),
                SizedBox(height: 8.0.scaled(context, ref)),
                Text(
                  l10n.accountNoTransactions,
                  style: TextStyle(
                    fontSize: 14,
                    color: BeeTokens.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(12.0.scaled(context, ref)),
            child: Row(
              children: [
                Text(
                  l10n.accountTransactionHistory,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
                const Spacer(),
                if (transactions.isNotEmpty)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8.0.scaled(context, ref),
                      vertical: 2.0.scaled(context, ref),
                    ),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(10.0.scaled(context, ref)),
                    ),
                    child: Text(
                      '${transactions.length}${state.hasMore ? '+' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        color: primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ...transactions.asMap().entries.map((entry) {
            final index = entry.key;
            final tx = entry.value;

            return Column(
              children: [
                if (index > 0) BeeTokens.cardDivider(context),
                _TransactionTile(
                  transaction: tx,
                  currencyCode: currencyCode,
                  primaryColor: primaryColor,
                  ledgers:
                      ref.watch(ledgersStreamProvider).asData?.value ?? [],
                  categories: categories,
                  currentAccountId: widget.account.id,
                  accountTagName: accountNameById[tx.accountId],
                  onTap: () => _editTransaction(context, ref, tx),
                ),
              ],
            );
          }),
          // 加载指示器
          if (state.isLoading)
            Padding(
              padding: EdgeInsets.all(16.0.scaled(context, ref)),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child:
                      CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (!state.hasMore && transactions.isNotEmpty)
            Padding(
              padding: EdgeInsets.all(12.0.scaled(context, ref)),
              child: Center(
                child: Text(
                  l10n.accountNoMoreData,
                  style: TextStyle(
                    fontSize: 12,
                    color: BeeTokens.textTertiary(context),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editTransaction(
      BuildContext context, WidgetRef ref, db.Transaction tx) async {
    final categoryAsync = tx.categoryId != null
        ? await ref.read(categoriesProvider.future)
        : null;
    final category = categoryAsync?.cast<db.Category?>().firstWhere(
          (c) => c?.id == tx.categoryId,
          orElse: () => null,
        );

    if (!context.mounted) return;
    await TransactionEditUtils.editTransaction(context, ref, tx, category);

    // 刷新数据
    ref.invalidate(accountStatsProvider(widget.account.id));
    final allAccounts =
        ref.read(allAccountsStreamProvider).valueOrNull ?? const [];
    ref
        .read(accountTransactionsPaginatedProvider((
          accountId: widget.account.id,
          flow: _listFlow,
          extraIdsKey: _extraIdsKey(_children(allAccounts)),
        )).notifier)
        .refresh();
    // 帳單週期彙總視圖(信用卡):整個 family 一起失效,不用逐一算週期 key。
    ref.invalidate(accountBillingPeriodTransactionsProvider);
    ref.invalidate(accountCategoryStatsProvider(
        (accountId: widget.account.id, type: 'expense')));
    ref.invalidate(accountCategoryStatsProvider(
        (accountId: widget.account.id, type: 'income')));
  }

  void _quickTransfer(
    BuildContext context,
    db.Account account, {
    int? toAccountId,
    int? fromAccountId,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionEditorPage(
          initialKind: 'transfer',
          initialAccountId: fromAccountId,
          initialToAccountId: toAccountId,
          quickAdd: true,
        ),
      ),
    );
  }

}

// ============================================
// 概览统计单元格（新版，用于合并的概览卡片）
// ============================================

/// 「帳戶資訊」tab 的欄位列:左標籤 + 右任意 value widget(文字/金額)。
class _InfoRow extends StatelessWidget {
  final String label;
  final Widget value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14, color: BeeTokens.textSecondary(context)),
          ),
          const Spacer(),
          value,
        ],
      ),
    );
  }
}

/// 「帳戶資訊」tab 的開關列。目前都是没有真实后端逻辑的占位展示
/// (onChanged: null 禁用交互),如实反映现状而不是假装可配置。
class _InfoSwitchRow extends StatelessWidget {
  final String label;
  final bool value;

  const _InfoSwitchRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: BeeTokens.textSecondary(context)),
            ),
          ),
          Switch(value: value, onChanged: null),
        ],
      ),
    );
  }
}

class _OverviewStatCell extends ConsumerWidget {
  final String label;
  final double value;

  const _OverviewStatCell({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        AmountText(
          value: value,
          signed: false,
          showCurrency: false,
          useCompactFormat: ref.watch(compactAmountProvider),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: BeeTokens.textPrimary(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: BeeTokens.textTertiary(context),
          ),
        ),
      ],
    );
  }
}

// ============================================
// 详情页图表 Tab 切换按钮
// ============================================

class _DetailChartTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color primaryColor;
  final VoidCallback onTap;

  const _DetailChartTab({
    required this.label,
    required this.isSelected,
    required this.primaryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? primaryColor : BeeTokens.border(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? primaryColor : BeeTokens.textSecondary(context),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ============================================
// 时段切换芯片
// ============================================

// ============================================
// Hero 统计单元格（头部用，白色文字）
// ============================================

class _DetailStatCell extends ConsumerWidget {
  final String label;
  final double value;
  final String currencyCode;

  const _DetailStatCell({
    required this.label,
    required this.value,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: BeeTokens.textTertiary(context),
          ),
        ),
        SizedBox(height: 4.0.scaled(context, ref)),
        AmountText(
          value: value,
          signed: false,
          showCurrency: true,
          useCompactFormat: ref.watch(compactAmountProvider),
          currencyCode: currencyCode,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: BeeTokens.textPrimary(context),
          ),
        ),
      ],
    );
  }
}

// ============================================
// 交易列表项
// ============================================

class _TransactionTile extends ConsumerWidget {
  final db.Transaction transaction;
  final String currencyCode;
  final Color primaryColor;
  final List<db.Ledger> ledgers;
  final List<db.Category> categories;
  final VoidCallback onTap;
  final int? currentAccountId;
  /// 主帳戶(合併帳單分組)聚合視圖用:這筆交易實際所屬的子帳戶名稱,非空時
  /// 在分类/账本标签旁多渲染一个帐户名标签(参照範例圖「永豐 Sport 卡」)。
  final String? accountTagName;

  const _TransactionTile({
    required this.transaction,
    required this.currencyCode,
    required this.primaryColor,
    required this.ledgers,
    required this.categories,
    required this.onTap,
    this.currentAccountId,
    this.accountTagName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Color amountColor;
    final l10n = AppLocalizations.of(context);
    final transferCategory = ref.watch(transferCategoryProvider).valueOrNull;

    bool isTransferOut = false;
    bool isTransferIn = false;
    if (transaction.type == 'transfer' && currentAccountId != null) {
      isTransferOut = transaction.accountId == currentAccountId;
      isTransferIn = transaction.toAccountId == currentAccountId;
    }

    switch (transaction.type) {
      case 'income':
        amountColor = BeeTokens.incomeColor(context, ref);
        break;
      case 'expense':
        amountColor = BeeTokens.expenseColor(context, ref);
        break;
      case 'transfer':
        amountColor = isTransferOut
            ? BeeTokens.expenseColor(context, ref)
            : BeeTokens.incomeColor(context, ref);
        break;
      default:
        amountColor = BeeTokens.textPrimary(context);
    }

    final category = transaction.type == 'transfer'
        ? transferCategory
        : (transaction.categoryId != null
            ? categories.cast<db.Category?>().firstWhere(
                  (c) => c?.id == transaction.categoryId,
                  orElse: () => null,
                )
            : null);

    String displayTitle;
    String? displaySubtitle;
    String? noteSuffix; // 非转账时，备注接在分类名后面（对齐首页）

    if (transaction.type == 'transfer') {
      if (transaction.note?.isNotEmpty == true) {
        displayTitle = transaction.note!;
      } else {
        displayTitle = l10n.transferTitle;
      }

      if (isTransferOut && transaction.toAccountId != null) {
        final toAccountAsync =
            ref.watch(accountByIdProvider(transaction.toAccountId!));
        final toAccountName = toAccountAsync.value?.name;
        if (toAccountName != null) {
          displaySubtitle = '${l10n.transferToPrefix} $toAccountName';
        }
      } else if (isTransferIn && transaction.accountId != null) {
        final fromAccountAsync =
            ref.watch(accountByIdProvider(transaction.accountId!));
        final fromAccountName = fromAccountAsync.value?.name;
        if (fromAccountName != null) {
          displaySubtitle = '${l10n.transferFromPrefix} $fromAccountName';
        }
      }
    } else {
      // 分类名常驻，备注接在分类名后面（对齐首页 / TransactionListItem）
      displayTitle = category != null
          ? category.name
          : (transaction.type == 'income' ? l10n.homeIncome : l10n.homeExpense);
      if (transaction.note?.isNotEmpty == true && transaction.note != displayTitle) {
        noteSuffix = transaction.note;
      }
    }

    final ledger = ledgers.cast<db.Ledger?>().firstWhere(
          (l) => l?.id == transaction.ledgerId,
          orElse: () => null,
        );
    String ledgerName = ledger?.name ?? '';
    if (ledgerName == 'Default Ledger') {
      ledgerName = l10n.ledgersDefaultLedgerName;
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12.0.scaled(context, ref),
          vertical: 12.0.scaled(context, ref),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: CategoryIconWidget(
                category: category,
                size: 18,
              ),
            ),
            SizedBox(width: 12.0.scaled(context, ref)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            text: displayTitle,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: BeeTokens.textPrimary(context),
                            ),
                            children: [
                              if (noteSuffix != null)
                                TextSpan(
                                  text: '  ($noteSuffix)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: BeeTokens.textSecondary(context),
                                  ),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (ledgerName.isNotEmpty) ...[
                        SizedBox(width: 6.0.scaled(context, ref)),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6.0.scaled(context, ref),
                            vertical: 2.0.scaled(context, ref),
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(
                                4.0.scaled(context, ref)),
                          ),
                          child: Text(
                            ledgerName,
                            style: TextStyle(
                              fontSize: 11,
                              color: primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                      if (accountTagName != null && accountTagName!.isNotEmpty) ...[
                        SizedBox(width: 6.0.scaled(context, ref)),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6.0.scaled(context, ref),
                            vertical: 2.0.scaled(context, ref),
                          ),
                          decoration: BoxDecoration(
                            color: BeeTokens.textTertiary(context).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(
                                4.0.scaled(context, ref)),
                          ),
                          child: Text(
                            accountTagName!,
                            style: TextStyle(
                              fontSize: 11,
                              color: BeeTokens.textSecondary(context),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (displaySubtitle != null)
                    Padding(
                      padding:
                          EdgeInsets.only(top: 2.0.scaled(context, ref)),
                      child: Text(
                        displaySubtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                    ),
                  Padding(
                    padding:
                        EdgeInsets.only(top: 2.0.scaled(context, ref)),
                    child: Text(
                      _formatDate(transaction.happenedAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: BeeTokens.textTertiary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AmountText(
              value: transaction.type == 'expense'
                  ? -transaction.amount
                  : transaction.type == 'transfer'
                      ? (isTransferOut
                          ? -transaction.amount
                          : transaction.amount)
                      : transaction.amount,
              signed: true,
              showCurrency: false,
              currencyCode: currencyCode,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: amountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final local = date.toLocal();

    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }

    return '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
