import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart' as db;
import '../../l10n/app_localizations.dart';
import '../../models/card_reward_summary.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../utils/card_reward_calc.dart';
import '../../utils/category_utils.dart';
import '../../utils/currencies.dart';
import '../../widgets/biz/amount_text.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/biz/transaction_detail_card.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/ui/ui.dart';

/// 紅利回饋明細頁:單一規則在某個週期內套用的所有交易,含每筆的估算回饋金
/// 與入帳時程標籤。從帳戶頁「交易明細」tab 的紅利回饋分組卡片點入。
///
/// 週期可前後翻頁(獨立於帳戶頁帳單彙總卡片的週期導覽),資料來源見
/// [cardRewardRulePeriodSummaryProvider]——同一份估算公式跟記帳表單/交易
/// 詳情卡共用([lib/utils/card_reward_calc.dart]),實際入帳金額仍以 Server
/// 端排程結果為準。
class CardRewardDetailPage extends ConsumerStatefulWidget {
  final db.Account account;
  final List<db.Account> children;
  final int ruleId;
  final String currencyCode;

  const CardRewardDetailPage({
    super.key,
    required this.account,
    required this.children,
    required this.ruleId,
    required this.currencyCode,
  });

  @override
  ConsumerState<CardRewardDetailPage> createState() =>
      _CardRewardDetailPageState();
}

class _CardRewardDetailPageState extends ConsumerState<CardRewardDetailPage> {
  int _offset = 0;

  String get _extraIdsKey {
    final ids = widget.children.map((a) => a.id).toList()..sort();
    return ids.join(',');
  }

  String _formatYmd(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  String _formatMd(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  String _trimRateZeros(double v) {
    final s = v.toStringAsFixed(2);
    return s.contains('.')
        ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : s;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ruleAsync = ref.watch(cardRewardRuleByIdProvider(widget.ruleId));

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.cardRewardDetailTitle,
            showBack: true,
          ),
          Expanded(
            child: ruleAsync.when(
              data: (rule) {
                if (rule == null) {
                  return Center(child: Text(l10n.commonError));
                }
                return _buildBody(context, l10n, rule);
              },
              loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
              error: (_, __) => Center(child: Text(l10n.commonError)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, AppLocalizations l10n, db.CardRewardRule rule) {
    final summaryAsync = ref.watch(cardRewardRulePeriodSummaryProvider((
      rule: rule,
      accountId: widget.account.id,
      extraIdsKey: _extraIdsKey,
      billingDay: widget.account.billingDay,
      offset: _offset,
    )));

    return summaryAsync.when(
      data: (summary) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _buildSummaryCard(context, l10n, rule, summary),
          const SizedBox(height: 12),
          _buildTransactionList(context, l10n, rule, summary),
        ],
      ),
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => Center(child: Text(l10n.commonError)),
    );
  }

  /// 「還可以刷多少」投影文案——單一週期跟自然月拆分後的子週期共用同一份算法,
  /// 差別只在傳進來的 [totalSpend] 是整顆帳單週期還是單一自然月的加總。
  String _capHint(
      AppLocalizations l10n, db.CardRewardRule rule, double totalSpend) {
    if (rule.capAmount == null) return l10n.cardRewardDetailNoCap;
    if (rule.rateType == 'percentage' && rule.rateValue > 0) {
      final neededSpend = rule.capAmount! / (rule.rateValue / 100);
      final remaining = neededSpend - totalSpend;
      if (remaining <= 0.5) return l10n.cardRewardDetailCapReached;
      final amountStr =
          '${getCurrencySymbol(widget.currencyCode)}${remaining.toStringAsFixed(0)}';
      return l10n.cardRewardDetailCapRemaining(amountStr);
    }
    final amountStr =
        '${getCurrencySymbol(widget.currencyCode)}${rule.capAmount!.toStringAsFixed(0)}';
    return l10n.cardRewardDetailCapAmount(amountStr);
  }

  Widget _buildSummaryCard(BuildContext context, AppLocalizations l10n,
      db.CardRewardRule rule, CardRewardRuleSummary summary) {
    final rateLabel = rule.rateType == 'percentage'
        ? '${_trimRateZeros(rule.rateValue)}%'
        : null;
    final useCompact = ref.watch(compactAmountProvider);
    final breakdown = summary.monthlyBreakdown;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SectionCard(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    rule.label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: BeeTokens.textPrimary(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (rateLabel != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: BeeTokens.warning(context).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      rateLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: BeeTokens.warning(context),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.chevron_left,
                      size: 20, color: BeeTokens.iconSecondary(context)),
                  onPressed: () => setState(() => _offset -= 1),
                ),
                Text(
                  // periodStart 是查詢用的 inclusive-both 邊界(上次結帳日
                  // 隔天),顯示的週期文字要換算回結帳日本身,對齊帳戶詳情頁
                  // 帳單彙總卡片的 label 格式(見 card_reward_period.dart::
                  // billingCyclePeriod 文件註解)。
                  '${_formatYmd(summary.periodStart.subtract(const Duration(days: 1)))} – ${_formatYmd(summary.periodEnd)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.chevron_right,
                      size: 20,
                      color: _offset < 0
                          ? BeeTokens.iconSecondary(context)
                          : BeeTokens.iconTertiary(context)),
                  onPressed:
                      _offset < 0 ? () => setState(() => _offset += 1) : null,
                ),
              ],
            ),
            Divider(height: 20, color: BeeTokens.divider(context)),
            if (breakdown == null) ...[
              Center(
                child: AmountText(
                  value: summary.totalReward,
                  signed: true,
                  showCurrency: true,
                  useCompactFormat: useCompact,
                  currencyCode: widget.currencyCode,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: BeeTokens.incomeColor(context, ref),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _capHint(l10n, rule, summary.totalSpend),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: BeeTokens.textSecondary(context),
                  ),
                ),
              ),
            ] else
              // 帳單週期橫跨多個自然月且規則以自然月算上限:上限跟著每個
              // 自然月各自重置,分開列出各自的符合條件消費/已獲得回饋/還可
              // 以刷,而不是把整顆帳單週期併成一段去對單一自然月的上限。
              ...breakdown.asMap().entries.map((entry) {
                final index = entry.key;
                final month = entry.value;
                return Padding(
                  padding: EdgeInsets.only(top: index > 0 ? 14 : 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (index > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Divider(
                              height: 1, color: BeeTokens.divider(context)),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.cardRewardDetailMonthLabel(
                                    month.periodStart.month,
                                    '${_formatYmd(month.periodStart)} ~ ${_formatYmd(month.periodEnd)}',
                                  ),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: BeeTokens.textPrimary(context),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l10n.cardRewardDetailQualifiedSpend(
                                      month.totalSpend.toStringAsFixed(0)),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: BeeTokens.textSecondary(context),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _capHint(l10n, rule, month.totalSpend),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: BeeTokens.textSecondary(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AmountText(
                            value: month.totalReward,
                            signed: true,
                            showCurrency: false,
                            useCompactFormat: useCompact,
                            currencyCode: widget.currencyCode,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: BeeTokens.incomeColor(context, ref),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionList(BuildContext context, AppLocalizations l10n,
      db.CardRewardRule rule, CardRewardRuleSummary summary) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final categories = categoriesAsync.asData?.value ?? const <db.Category>[];
    final transactions = summary.transactions;

    if (transactions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SectionCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                l10n.cardRewardDetailEmptyState,
                style: TextStyle(
                    fontSize: 13, color: BeeTokens.textSecondary(context)),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SectionCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: transactions.asMap().entries.map((entry) {
            final index = entry.key;
            final tx = entry.value;
            db.Category? category;
            for (final c in categories) {
              if (c.id == tx.categoryId) {
                category = c;
                break;
              }
            }
            return Column(
              children: [
                if (index > 0) BeeTokens.cardDivider(context),
                _buildTransactionRow(
                    context, l10n, rule, summary, tx, category),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTransactionRow(
    BuildContext context,
    AppLocalizations l10n,
    db.CardRewardRule rule,
    CardRewardRuleSummary summary,
    db.Transaction tx,
    db.Category? category,
  ) {
    final categoryKind =
        category?.kind ?? (tx.type == 'income' ? 'income' : 'expense');
    final displayName = CategoryUtils.getDisplayName(category?.name, context,
        kind: categoryKind);
    final noteText =
        (tx.note != null && tx.note!.isNotEmpty) ? tx.note! : displayName;
    // 用 rewardByTransactionId(累計扣減週期上限後的結果),不能再各自呼叫
    // estimateCardRewardForRule——那樣算出來的單筆金額沒有跟本週期內其他交易
    // 共用 capAmount,逐筆列表加總會超過彙總卡片顯示的 totalReward。
    final reward = summary.rewardByTransactionId[tx.id] ?? 0;
    // 有自然月拆分時,period_end 入帳應該對到這筆交易「自己所在的自然月」
    // 結尾,不是整顆帳單週期的結尾——否則橫跨兩個自然月時,前一個自然月的
    // 交易會被錯誤地套用後一個自然月的入帳日推算。
    final settlementPeriodEnd = summary.monthlyBreakdown
            ?.firstWhere(
              (month) =>
                  !tx.happenedAt.isBefore(month.periodStart) &&
                  !tx.happenedAt.isAfter(month.periodEnd),
              orElse: () => summary,
            )
            .periodEnd ??
        summary.periodEnd;
    final settlementDate = estimateCardRewardSettlementDate(
      rule: rule,
      happenedAt: tx.happenedAt,
      periodEnd: settlementPeriodEnd,
    );

    Widget? badge;
    if (settlementDate != null) {
      final isFuture = settlementDate.isAfter(DateTime.now());
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: (isFuture
                  ? BeeTokens.warning(context)
                  : BeeTokens.success(context))
              .withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          isFuture
              ? l10n.cardRewardDetailSettlementBadge(_formatMd(settlementDate))
              : l10n.cardRewardDetailSettledBadge(_formatMd(settlementDate)),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isFuture
                ? BeeTokens.warning(context)
                : BeeTokens.success(context),
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => showTransactionDetailCard(context, ref, tx, category),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CategoryIconWidget(
              category: category,
              categoryName: displayName,
              size: 36,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    noteText,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: BeeTokens.textPrimary(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        _formatYmd(tx.happenedAt),
                        style: TextStyle(
                            fontSize: 12,
                            color: BeeTokens.textTertiary(context)),
                      ),
                      Text(
                        ' · ',
                        style: TextStyle(
                            fontSize: 12,
                            color: BeeTokens.textTertiary(context)),
                      ),
                      AmountText(
                        value: tx.amount,
                        signed: false,
                        currencyCode: tx.currencyCode ?? widget.currencyCode,
                        decimals: 0,
                        style: TextStyle(
                            fontSize: 12,
                            color: BeeTokens.textTertiary(context)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AmountText(
                  value: reward,
                  signed: false,
                  showCurrency: true,
                  currencyCode: widget.currencyCode,
                  decimals: 2,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: BeeTokens.incomeColor(context, ref),
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(height: 4),
                  badge,
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
