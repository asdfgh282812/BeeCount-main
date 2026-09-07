import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart' as db;
import '../../data/repositories/account_repository.dart' show AccountPeriodSummary;
import '../../providers.dart';
import '../../providers/account_period_providers.dart';
import '../../styles/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/month_range.dart' show DateRange;
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../widgets/charts/balance_trend_chart.dart';
import '../transaction/transaction_editor_page.dart';
import 'account_detail_page.dart'
    show
        TransactionTile,
        accountTransactionsPaginatedProvider,
        AccountTransactionsPaginationState;

/// 一般帳戶(現金/銀行卡/房產/車輛/投資/保險/公積金/貸款)明細頁「交易明細」
/// tab:日期區間(綁定帳本 monthStartDay,比照專案週期,見
/// `account_period_providers.dart`)+ moze 風格摘要(轉出/轉入/總計橫條)+
/// 餘額趨勢折線圖 + 支出/收入/轉出/轉入四分頁 + 依日期排列的交易清單。
///
/// 信用卡/`account_group` 走另一套帳單週期版面(見
/// `account_detail_page.dart::_buildTransactionsTab` 的 credit_card 分支),
/// 不受這個 widget 影響。
class GeneralAccountPeriodView extends ConsumerStatefulWidget {
  final db.Account account;
  final List<db.Category> categories;

  const GeneralAccountPeriodView({
    super.key,
    required this.account,
    required this.categories,
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

    final summaryAsync = ref.watch(accountPeriodSummaryProvider((
      accountId: _accountId,
      start: range.start,
      end: periodEnd,
    )));
    final trendAsync = ref.watch(accountBalanceTrendProvider((
      accountId: _accountId,
      start: range.start,
      end: periodEnd,
    )));
    final paginationState = ref.watch(accountTransactionsPaginatedProvider((
      accountId: _accountId,
      flow: _flows[_activeFlowIndex],
      extraIdsKey: '',
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
              ],
            ),
          ),
        ),
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
    final rows = <({String label, int count, double signedAmount, Color color})>[];
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
        child: Text('-', style: TextStyle(color: BeeTokens.textTertiary(context))),
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
                padding: EdgeInsets.symmetric(
                    horizontal: 8.0.scaled(context, ref)),
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
                  TransactionTile(
                    transaction: tx,
                    currencyCode: currencyCode,
                    primaryColor: primaryColor,
                    ledgers: ref.watch(ledgersStreamProvider).asData?.value ??
                        const [],
                    categories: widget.categories,
                    currentAccountId: _accountId,
                    onTap: (category) =>
                        _openTransactionDetail(context, tx, category),
                  ),
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
                            extraIdsKey: '',
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
    final page = switch (flow) {
      'income' => TransactionEditorPage(
          initialKind: 'income',
          initialAccountId: _accountId,
          initialDate: range.start,
        ),
      'transfer_out' => TransactionEditorPage(
          initialKind: 'transfer',
          initialAccountId: _accountId,
          initialDate: range.start,
        ),
      'transfer_in' => TransactionEditorPage(
          initialKind: 'transfer',
          initialToAccountId: _accountId,
          initialDate: range.start,
        ),
      _ => TransactionEditorPage(
          initialKind: 'expense',
          initialAccountId: _accountId,
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
