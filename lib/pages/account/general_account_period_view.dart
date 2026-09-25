import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart' as db;
import '../../data/repositories/account_repository.dart'
    show AccountPeriodSummary;
import '../../providers.dart';
import '../../providers/account_period_providers.dart';
import '../../services/currency/rate_math.dart' show EffectiveRate;
import '../../styles/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/month_range.dart' show DateRange;
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../widgets/charts/balance_trend_chart.dart';
import '../transaction/transaction_editor_page.dart';
import '../../widgets/biz/account_avatar.dart';
import 'account_detail_page.dart'
    show
        AccountDetailPage,
        TransactionTile,
        accountTransactionsPaginatedProvider,
        AccountTransactionsPaginationState;
import 'accounts_page.dart' show convertBetweenCurrencies;

/// 一般帳戶(現金/銀行卡/房產/車輛/投資/保險/公積金/貸款)明細頁「交易明細」
/// tab:日期區間(綁定帳本 monthStartDay,比照專案週期,見
/// `account_period_providers.dart`)+ moze 風格摘要(轉出/轉入/總計橫條)+
/// 餘額趨勢折線圖 + 支出/收入/轉出/轉入四分頁 + 依日期排列的交易清單。
///
/// 信用卡/信用卡合併帳單群組走另一套帳單週期版面(見
/// `account_detail_page.dart::_buildTransactionsTab` 的 credit_card 分支),
/// 不受這個 widget 影響。
///
/// 一般主帳戶群組(`account_group` 但不是合併帳單,例如同一家銀行的台幣戶+
/// 外幣戶,判斷見 `account_group_utils.dart`)也走這裡:摘要/趨勢/交易清單
/// 改成聚合群組底下全部子帳戶,摘要與趨勢把各子帳戶原幣金額折算成群組幣種
/// 再加總(跟資產頁主帳戶合計同一套 `convertBetweenCurrencies`,缺匯率的
/// 子帳戶跳過並提示,不假裝按 1.0 折算),另外多一張子帳戶清單卡。
class GeneralAccountPeriodView extends ConsumerStatefulWidget {
  final db.Account account;
  final List<db.Category> categories;

  /// 一般主帳戶群組的子帳戶;非群組帳戶傳空清單(預設)。
  final List<db.Account> groupChildren;

  const GeneralAccountPeriodView({
    super.key,
    required this.account,
    required this.categories,
    this.groupChildren = const [],
  });

  @override
  ConsumerState<GeneralAccountPeriodView> createState() =>
      _GeneralAccountPeriodViewState();
}

class _GeneralAccountPeriodViewState
    extends ConsumerState<GeneralAccountPeriodView> {
  /// 支出/收入/轉出/轉入 四分頁,對應 repository `flow` 的四個值(互斥,見
  /// `AccountRepository.getAccountTransactions` 文件註解)。
  static const _flows = ['expense', 'income', 'transfer_out', 'transfer_in'];
  int _activeFlowIndex = 0;

  /// 清單排序圖示:false=新→舊(預設),true=舊→新。
  bool _ascending = false;

  int get _accountId => widget.account.id;

  bool get _isGroup => widget.account.type == 'account_group';

  /// 子帳戶 id(已排序、逗號分隔),給分頁交易 provider 的 extraIdsKey。
  String get _extraIdsKey {
    final ids = widget.groupChildren.map((a) => a.id).toList()..sort();
    return ids.join(',');
  }

  /// 群組自己 + 全部子帳戶 id(已排序、逗號分隔)。
  String get _memberIdsKey {
    final ids = [_accountId, ...widget.groupChildren.map((a) => a.id)]..sort();
    return ids.join(',');
  }

  Map<int, db.Account> get _membersById => {
        _accountId: widget.account,
        for (final c in widget.groupChildren) c.id: c,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);
    final currencyCode = widget.account.currency;

    final ledger = ref.watch(currentLedgerProvider).asData?.value;
    final monthStartDay = ledger?.monthStartDay ?? 1;
    final offset = ref.watch(accountPeriodOffsetProvider)[_accountId] ?? 0;
    final range = accountPeriodRange(offset, monthStartDay);
    final periodEnd = inclusiveEnd(range);

    // 群組:各子帳戶原幣數字折算成群組幣種後加總;缺匯率的幣種收進
    // missingCurrencies,摘要卡下方提示。
    final rates = ref.watch(effectiveRatesProvider).valueOrNull;
    final base = ref.watch(baseCurrencyProvider).toUpperCase();
    final missingCurrencies = <String>{};
    final AsyncValue<AccountPeriodSummary> summaryAsync;
    final AsyncValue<List<({DateTime date, double balance})>> trendAsync;
    if (_isGroup) {
      final groupParams = (
        memberIdsKey: _memberIdsKey,
        start: range.start,
        end: periodEnd,
      );
      summaryAsync = ref
          .watch(accountGroupPeriodSummariesProvider(groupParams))
          .whenData((m) =>
              _mergeSummaries(m, currencyCode, rates, base, missingCurrencies));
      trendAsync = ref
          .watch(accountGroupBalanceTrendsProvider(groupParams))
          .whenData((m) =>
              _mergeTrends(m, currencyCode, rates, base, missingCurrencies));
    } else {
      summaryAsync = ref.watch(accountPeriodSummaryProvider((
        accountId: _accountId,
        start: range.start,
        end: periodEnd,
      )));
      trendAsync = ref.watch(accountBalanceTrendProvider((
        accountId: _accountId,
        start: range.start,
        end: periodEnd,
      )));
    }
    final paginationState = ref.watch(accountTransactionsPaginatedProvider((
      accountId: _accountId,
      flow: _flows[_activeFlowIndex],
      extraIdsKey: _isGroup ? _extraIdsKey : '',
      startDate: range.start,
      endDate: periodEnd,
      ascending: _ascending,
    )));

    return ListView(
      padding: EdgeInsets.symmetric(vertical: 8.0.scaled(context, ref)),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.0.scaled(context, ref)),
          child: SectionCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PeriodRangeSelector(
                  label:
                      '${_formatYmd(range.start)} – ${_formatYmd(periodEnd)}',
                  onPrev: () => ref
                      .read(accountPeriodOffsetProvider.notifier)
                      .setOffset(_accountId, offset + 1),
                  onNext: offset > 0
                      ? () => ref
                          .read(accountPeriodOffsetProvider.notifier)
                          .setOffset(_accountId, offset - 1)
                      : null,
                  onTapLabel: () =>
                      _openPeriodPicker(context, offset, monthStartDay),
                ),
                Divider(
                    height: 16.0.scaled(context, ref),
                    color: BeeTokens.divider(context)),
                summaryAsync.when(
                  data: (summary) =>
                      _buildSummaryRows(context, summary, currencyCode, l10n),
                  loading: () => Padding(
                    padding: EdgeInsets.symmetric(
                        vertical: 24.0.scaled(context, ref)),
                    child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                if (missingCurrencies.isNotEmpty) ...[
                  SizedBox(height: 6.0.scaled(context, ref)),
                  Text(
                    l10n.accountGroupUnconvertedHint(
                        (missingCurrencies.toList()..sort()).join('/')),
                    style: TextStyle(
                      fontSize: 11,
                      color: BeeTokens.textTertiary(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_isGroup) ...[
          SizedBox(height: 8.0.scaled(context, ref)),
          Padding(
            padding:
                EdgeInsets.symmetric(horizontal: 12.0.scaled(context, ref)),
            child: _buildMembersCard(
                context, l10n, primaryColor, currencyCode, rates, base),
          ),
        ],
        SizedBox(height: 8.0.scaled(context, ref)),
        trendAsync.when(
          data: (data) => data.length < 2
              ? const SizedBox.shrink()
              : Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 12.0.scaled(context, ref)),
                  child: BalanceTrendChart(data: data),
                ),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        SizedBox(height: 8.0.scaled(context, ref)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.0.scaled(context, ref)),
          child: _buildFlowTabs(context, l10n, primaryColor),
        ),
        SizedBox(height: 8.0.scaled(context, ref)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.0.scaled(context, ref)),
          child: _buildRecordsSection(
              context, paginationState, currencyCode, primaryColor, l10n,
              range: range),
        ),
      ],
    );
  }

  /// 摘要橫條:純支出/純收入/轉出/轉入(只列有資料的類別,比照 moze 截圖—
  /// 該帳期沒有的類別不佔一行)+ 一定會顯示的「總計」淨額列。
  Widget _buildSummaryRows(
    BuildContext context,
    AccountPeriodSummary summary,
    String currencyCode,
    AppLocalizations l10n,
  ) {
    final rows =
        <({String label, int count, double signedAmount, Color color})>[];
    if (summary.expenseCount > 0) {
      rows.add((
        label: l10n.homeExpense,
        count: summary.expenseCount,
        signedAmount: -summary.expenseTotal,
        color: BeeTokens.expenseColor(context, ref),
      ));
    }
    if (summary.incomeCount > 0) {
      rows.add((
        label: l10n.homeIncome,
        count: summary.incomeCount,
        signedAmount: summary.incomeTotal,
        color: BeeTokens.incomeColor(context, ref),
      ));
    }
    if (summary.transferOutCount > 0) {
      rows.add((
        label: l10n.accountFlowTransferOut,
        count: summary.transferOutCount,
        signedAmount: -summary.transferOutTotal,
        color: BeeTokens.expenseColor(context, ref),
      ));
    }
    if (summary.transferInCount > 0) {
      rows.add((
        label: l10n.accountFlowTransferIn,
        count: summary.transferInCount,
        signedAmount: summary.transferInTotal,
        color: BeeTokens.incomeColor(context, ref),
      ));
    }

    if (rows.isEmpty) {
      return Center(
        child:
            Text('-', style: TextStyle(color: BeeTokens.textTertiary(context))),
      );
    }

    final maxAbs =
        rows.map((r) => r.signedAmount.abs()).reduce((a, b) => a > b ? a : b);
    final totalCount = summary.expenseCount +
        summary.incomeCount +
        summary.transferOutCount +
        summary.transferInCount;
    final netTotal = summary.incomeTotal +
        summary.transferInTotal -
        summary.expenseTotal -
        summary.transferOutTotal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          _summaryRow(
            context,
            label: row.label,
            count: row.count,
            signedAmount: row.signedAmount,
            color: row.color,
            barFraction: maxAbs == 0 ? 0 : row.signedAmount.abs() / maxAbs,
            currencyCode: currencyCode,
          ),
        _summaryRow(
          context,
          label: l10n.projectDetailNetTotalLabel,
          count: totalCount,
          signedAmount: netTotal,
          color: BeeTokens.textPrimary(context),
          barFraction: null,
          currencyCode: currencyCode,
          isTotal: true,
        ),
      ],
    );
  }

  Widget _summaryRow(
    BuildContext context, {
    required String label,
    required int count,
    required double signedAmount,
    required Color color,
    required double? barFraction,
    required String currencyCode,
    bool isTotal = false,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.0.scaled(context, ref)),
      child: Row(
        children: [
          Text(
            '$label $count',
            style: TextStyle(
              fontSize: 12,
              color: isTotal ? BeeTokens.textPrimary(context) : color,
              fontWeight: isTotal ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          if (barFraction != null)
            Expanded(
              child: Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: 8.0.scaled(context, ref)),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: barFraction.clamp(0.02, 1.0),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            )
          else
            const Spacer(),
          AmountText(
            value: signedAmount,
            signed: true,
            showCurrency: false,
            currencyCode: currencyCode,
            useCompactFormat: ref.watch(compactAmountProvider),
            style: TextStyle(
              fontSize: 13,
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.w600,
              color: isTotal ? BeeTokens.textPrimary(context) : color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowTabs(
      BuildContext context, AppLocalizations l10n, Color primaryColor) {
    final labels = [
      l10n.homeExpense,
      l10n.homeIncome,
      l10n.accountFlowTransferOut,
      l10n.accountFlowTransferIn,
    ];
    return Wrap(
      spacing: 6.0.scaled(context, ref),
      runSpacing: 6.0.scaled(context, ref),
      children: [
        for (var i = 0; i < labels.length; i++)
          _FlowTabChip(
            label: labels[i],
            isSelected: _activeFlowIndex == i,
            primaryColor: primaryColor,
            onTap: () => setState(() => _activeFlowIndex = i),
          ),
      ],
    );
  }

  Widget _buildRecordsSection(
    BuildContext context,
    AccountTransactionsPaginationState state,
    String currencyCode,
    Color primaryColor,
    AppLocalizations l10n, {
    required DateRange range,
  }) {
    final l10nSort = _ascending
        ? l10n.reconciliationMenuSortOldest
        : l10n.reconciliationMenuSortNewest;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(12.0.scaled(context, ref)),
            child: Row(
              children: [
                Text(
                  l10n.billingGeneralRecordsTitle(state.transactions.length),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: l10nSort,
                  icon: Icon(Icons.swap_vert,
                      size: 20, color: BeeTokens.iconSecondary(context)),
                  onPressed: () => setState(() => _ascending = !_ascending),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.add_circle_outline,
                      size: 20, color: primaryColor),
                  onPressed: () => _onAdd(context, range),
                ),
              ],
            ),
          ),
          if (state.isLoading && state.transactions.isEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: 24.0.scaled(context, ref)),
              child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (state.transactions.isEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: 24.0.scaled(context, ref)),
              child: Center(
                child: Text(
                  l10n.accountNoTransactions,
                  style: TextStyle(
                      fontSize: 13, color: BeeTokens.textSecondary(context)),
                ),
              ),
            )
          else ...[
            ...state.transactions.asMap().entries.map((entry) {
              final index = entry.key;
              final tx = entry.value;
              return Column(
                children: [
                  if (index > 0) BeeTokens.cardDivider(context),
                  _buildTile(context, tx, currencyCode, primaryColor),
                ],
              );
            }),
            if (state.hasMore)
              Center(
                child: TextButton(
                  onPressed: state.isLoading
                      ? null
                      : () => ref
                          .read(accountTransactionsPaginatedProvider((
                            accountId: _accountId,
                            flow: _flows[_activeFlowIndex],
                            extraIdsKey: _isGroup ? _extraIdsKey : '',
                            startDate: range.start,
                            endDate: inclusiveEnd(range),
                            ascending: _ascending,
                          )).notifier)
                          .loadMore(),
                  child: state.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l10n.commonLoadMore),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 交易清單單列。群組模式下每筆交易用它實際所屬子帳戶的幣種顯示金額、
  /// 用那個子帳戶判斷轉出/轉入方向(轉入分頁看 toAccountId,其它看
  /// accountId),並在時間列標上子帳戶名稱。
  Widget _buildTile(BuildContext context, db.Transaction tx,
      String currencyCode, Color primaryColor) {
    db.Account? member;
    int? currentAccountId = _accountId;
    if (_isGroup) {
      final members = _membersById;
      final memberId = _flows[_activeFlowIndex] == 'transfer_in'
          ? tx.toAccountId
          : tx.accountId;
      member = members[memberId];
      currentAccountId = memberId;
    }
    return TransactionTile(
      transaction: tx,
      currencyCode: member?.currency ?? currencyCode,
      primaryColor: primaryColor,
      ledgers: ref.watch(ledgersStreamProvider).asData?.value ?? const [],
      categories: widget.categories,
      currentAccountId: currentAccountId,
      accountTagName: _isGroup ? member?.name : null,
      onTap: (category) => _openTransactionDetail(context, tx, category),
    );
  }

  /// 各成員原幣摘要 → 折算成群組幣種 [to] 後加總。缺匯率的成員(且該期
  /// 確實有交易)跳過,幣種記進 [missing]。
  AccountPeriodSummary _mergeSummaries(
    Map<int, AccountPeriodSummary> byMember,
    String to,
    Map<String, EffectiveRate>? rates,
    String base,
    Set<String> missing,
  ) {
    double expenseTotal = 0, incomeTotal = 0;
    double transferOutTotal = 0, transferInTotal = 0;
    int expenseCount = 0, incomeCount = 0;
    int transferOutCount = 0, transferInCount = 0;
    final members = _membersById;
    byMember.forEach((id, s) {
      final from = members[id]?.currency ?? to;
      final rate = convertBetweenCurrencies(
          amount: 1, from: from, to: to, rates: rates, base: base);
      final hasData = s.expenseCount +
              s.incomeCount +
              s.transferOutCount +
              s.transferInCount >
          0;
      if (rate == null) {
        if (hasData) missing.add(from.toUpperCase());
        return;
      }
      expenseTotal += s.expenseTotal * rate;
      incomeTotal += s.incomeTotal * rate;
      transferOutTotal += s.transferOutTotal * rate;
      transferInTotal += s.transferInTotal * rate;
      expenseCount += s.expenseCount;
      incomeCount += s.incomeCount;
      transferOutCount += s.transferOutCount;
      transferInCount += s.transferInCount;
    });
    return (
      expenseTotal: expenseTotal,
      expenseCount: expenseCount,
      incomeTotal: incomeTotal,
      incomeCount: incomeCount,
      transferOutTotal: transferOutTotal,
      transferOutCount: transferOutCount,
      transferInTotal: transferInTotal,
      transferInCount: transferInCount,
    );
  }

  /// 各成員原幣每日餘額 → 折算成群組幣種後逐日加總。不納入總餘額的子帳戶
  /// 不併入(跟資產頁主帳戶合計的 includeInTotal 口徑一致)。
  List<({DateTime date, double balance})> _mergeTrends(
    Map<int, List<({DateTime date, double balance})>> byMember,
    String to,
    Map<String, EffectiveRate>? rates,
    String base,
    Set<String> missing,
  ) {
    final members = _membersById;
    final totals = <DateTime, double>{};
    byMember.forEach((id, points) {
      final member = members[id];
      if (member == null || (id != _accountId && !member.includeInTotal)) {
        return;
      }
      final rate = convertBetweenCurrencies(
          amount: 1, from: member.currency, to: to, rates: rates, base: base);
      if (rate == null) {
        if (points.any((p) => p.balance != 0)) {
          missing.add(member.currency.toUpperCase());
        }
        return;
      }
      for (final p in points) {
        totals[p.date] = (totals[p.date] ?? 0) + p.balance * rate;
      }
    });
    final dates = totals.keys.toList()..sort();
    return [for (final d in dates) (date: d, balance: totals[d]!)];
  }

  /// 一般群組的子帳戶清單卡:標題列右側是折算後合計餘額(同資產頁主帳戶
  /// 表頭口徑:群組自己 + 納入總餘額的子帳戶),每列子帳戶顯示原幣餘額,
  /// 點擊進該子帳戶自己的明細頁。
  Widget _buildMembersCard(
    BuildContext context,
    AppLocalizations l10n,
    Color primaryColor,
    String currencyCode,
    Map<String, EffectiveRate>? rates,
    String base,
  ) {
    final allStats = ref.watch(allAccountStatsProvider).valueOrNull;
    final useCompact = ref.watch(compactAmountProvider);
    final children = widget.groupChildren;

    double? total;
    if (allStats != null) {
      total = allStats[_accountId]?.balance ?? 0;
      for (final c in children) {
        if (!c.includeInTotal) continue;
        final converted = convertBetweenCurrencies(
          amount: allStats[c.id]?.balance ?? 0,
          from: c.currency,
          to: currencyCode,
          rates: rates,
          base: base,
        );
        if (converted != null) total = total! + converted;
      }
    }

    return SectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(12.0.scaled(context, ref)),
            child: Row(
              children: [
                Text(
                  l10n.accountSubAccountsLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
                const Spacer(),
                if (total != null) ...[
                  Text(
                    l10n.accountGroupBalanceTotalLabel,
                    style: TextStyle(
                        fontSize: 12, color: BeeTokens.textSecondary(context)),
                  ),
                  SizedBox(width: 6.0.scaled(context, ref)),
                  AmountText(
                    value: total,
                    signed: false,
                    showCurrency: false,
                    currencyCode: currencyCode,
                    useCompactFormat: useCompact,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (children.isEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: 16.0.scaled(context, ref)),
              child: Center(
                child: Text(
                  l10n.accountGroupNoChildrenHint,
                  style: TextStyle(
                      fontSize: 13, color: BeeTokens.textSecondary(context)),
                ),
              ),
            )
          else
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) BeeTokens.cardDivider(context),
              InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AccountDetailPage(account: children[i]),
                )),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.0.scaled(context, ref),
                    vertical: 10.0.scaled(context, ref),
                  ),
                  child: Row(
                    children: [
                      AccountAvatar(
                        account: children[i],
                        primaryColor: primaryColor,
                        size: 28,
                      ),
                      SizedBox(width: 10.0.scaled(context, ref)),
                      Expanded(
                        child: Text(
                          children[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: BeeTokens.textPrimary(context),
                          ),
                        ),
                      ),
                      if (children[i].currency.toUpperCase() !=
                          currencyCode.toUpperCase()) ...[
                        Text(
                          children[i].currency.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            color: BeeTokens.textTertiary(context),
                          ),
                        ),
                        SizedBox(width: 4.0.scaled(context, ref)),
                      ],
                      AmountText(
                        value: allStats?[children[i].id]?.balance ?? 0,
                        signed: false,
                        showCurrency: false,
                        currencyCode: children[i].currency,
                        useCompactFormat: useCompact,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: BeeTokens.textPrimary(context),
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          size: 18, color: BeeTokens.iconSecondary(context)),
                    ],
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }

  Future<void> _openPeriodPicker(
      BuildContext context, int offset, int monthStartDay) async {
    final selected = await showPeriodRangeListPicker(
      context,
      periodType: 'monthly',
      currentOffset: offset,
      monthStartDay: monthStartDay,
    );
    if (selected != null && mounted) {
      ref.read(accountPeriodOffsetProvider.notifier).setOffset(
            _accountId,
            selected,
          );
    }
  }

  Future<void> _onAdd(BuildContext context, DateRange range) async {
    final flow = _flows[_activeFlowIndex];
    // 群組本身是純管理容器,帳戶選擇器也不列它——從群組頁新增時不預選帳戶,
    // 讓使用者自己挑子帳戶。
    final accountId = _isGroup ? null : _accountId;
    final page = switch (flow) {
      'income' => TransactionEditorPage(
          initialKind: 'income',
          initialAccountId: accountId,
          initialDate: range.start,
        ),
      'transfer_out' => TransactionEditorPage(
          initialKind: 'transfer',
          initialAccountId: accountId,
          initialDate: range.start,
        ),
      'transfer_in' => TransactionEditorPage(
          initialKind: 'transfer',
          initialToAccountId: accountId,
          initialDate: range.start,
        ),
      _ => TransactionEditorPage(
          initialKind: 'expense',
          initialAccountId: accountId,
          initialDate: range.start,
        ),
    };
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (!context.mounted) return;
    // 摘要/趨勢圖已經在 watch `statsRefreshProvider`(TransactionEditorPage
    // 存檔時會 bump),這裡只需要手動刷新分頁交易清單。
    ref.invalidate(accountTransactionsPaginatedProvider);
  }

  /// 交易明細列表點擊:彈出唯讀詳情卡(比照首頁),而非直接跳編輯頁——編輯
  /// 只能透過卡片右上角的編輯圖示進入,見 [showTransactionDetailCard]。
  Future<void> _openTransactionDetail(
      BuildContext context, db.Transaction tx, db.Category? category) async {
    await showTransactionDetailCard(context, ref, tx, category);
    if (!context.mounted) return;
    ref.invalidate(accountStatsProvider(_accountId));
    ref.invalidate(accountTransactionsPaginatedProvider);
    ref.read(statsRefreshProvider.notifier).state++;
  }

  String _formatYmd(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

/// 支出/收入/轉出/轉入 四分頁的單一分頁樣式,比照舊版
/// `_DetailChartTab`(信用卡帳單彙總卡片改版後已刪除,這裡是唯一使用者)。
class _FlowTabChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color primaryColor;
  final VoidCallback onTap;

  const _FlowTabChip({
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
