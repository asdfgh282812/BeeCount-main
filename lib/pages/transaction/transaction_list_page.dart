import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../providers.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../styles/tokens.dart';
import '../../l10n/app_localizations.dart';
import 'search_page.dart';

enum _DateFilter { today, week, month, all }

/// 原「明細」首页内容 —— 现挪到日历 tab 头部的按钮后面。
/// 与网页端一致，提供 今日/七天内/一个月内/全部 时间条件，默认「今日」。
class TransactionListPage extends ConsumerStatefulWidget {
  const TransactionListPage({super.key});

  @override
  ConsumerState<TransactionListPage> createState() =>
      _TransactionListPageState();
}

class _TransactionListPageState extends ConsumerState<TransactionListPage> {
  _DateFilter _filter = _DateFilter.today;

  /// 过滤区间 [下界(含), 上界(不含)];_DateFilter.all 返回 null 表示不限制。
  (DateTime, DateTime)? _filterRange(_DateFilter filter) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    switch (filter) {
      case _DateFilter.today:
        return (today, tomorrow);
      case _DateFilter.week:
        return (today.subtract(const Duration(days: 6)), tomorrow);
      case _DateFilter.month:
        return (DateTime(now.year, now.month - 1, now.day), tomorrow);
      case _DateFilter.all:
        return null;
    }
  }

  List<
      ({
        Transaction t,
        Category? category,
        Account? account,
        Account? toAccount
      })> _applyFilter(
    List<
            ({
              Transaction t,
              Category? category,
              Account? account,
              Account? toAccount
            })>
        transactions,
  ) {
    final range = _filterRange(_filter);
    if (range == null) return transactions;
    final (start, end) = range;
    return transactions.where((item) {
      final happenedAt = item.t.happenedAt;
      return !happenedAt.isBefore(start) && happenedAt.isBefore(end);
    }).toList();
  }

  String _filterLabel(AppLocalizations l10n, _DateFilter filter) {
    switch (filter) {
      case _DateFilter.today:
        return l10n.transactionListFilterToday;
      case _DateFilter.week:
        return l10n.transactionListFilterWeek;
      case _DateFilter.month:
        return l10n.transactionListFilterMonth;
      case _DateFilter.all:
        return l10n.transactionListFilterAll;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.watch(repositoryProvider);
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final hide = ref.watch(hideAmountsProvider);
    final primaryColor = ref.watch(primaryColorProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.transactionListTitle,
            showBack: true,
            actions: [
              IconButton(
                tooltip: AppLocalizations.of(context).homeSearch,
                padding: const EdgeInsets.all(6),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: Size.zero,
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const SearchPage()),
                  );
                },
                icon: Icon(Icons.search,
                    size: 20, color: Theme.of(context).iconTheme.color),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                for (final filter in _DateFilter.values) ...[
                  _FilterChip(
                    label: _filterLabel(l10n, filter),
                    isSelected: _filter == filter,
                    primaryColor: primaryColor,
                    onTap: () => setState(() => _filter = filter),
                  ),
                  if (filter != _DateFilter.values.last)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<
                List<
                    ({
                      Transaction t,
                      Category? category,
                      Account? account,
                      Account? toAccount
                    })>>(
              stream: repo.transactionsWithCategoryAll(ledgerId: ledgerId),
              builder: (context, snapshot) {
                final transactions = _applyFilter(snapshot.data ?? []);
                return TransactionList(
                  transactions: transactions,
                  hideAmounts: hide,
                  emptyWidget: AppEmpty(
                    text: l10n.homeNoRecords,
                    subtext: l10n.homeNoRecordsSubtext,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color primaryColor;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.primaryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? primaryColor
                : (BeeTokens.isDark(context)
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? Colors.white
                  : BeeTokens.textSecondary(context),
            ),
          ),
        ),
      ),
    );
  }
}
