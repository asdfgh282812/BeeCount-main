import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/report/report_dataset.dart';
import '../../styles/tokens.dart';
import '../../utils/category_utils.dart';
import '../biz/amount_text.dart';
import '../biz/transaction_detail_card.dart';
import '../category_icon.dart';

/// 統計報表「排行」/「總覽 TOP 3」用的精簡交易列:名次 + 分類圖示 + 名稱 +
/// 日期 + 金額,點擊開交易詳情卡(同交易列表)。
class ReportTxRow extends ConsumerWidget {
  final ReportTxView view;

  /// 顯示金額(拆帳交易被篩選時只算命中的明細)。
  final double amount;
  final int? rank;

  /// 金額文字顏色(收入/支出色);null = 預設字色。
  final Color? amountColor;

  const ReportTxRow({
    super.key,
    required this.view,
    required this.amount,
    this.rank,
    this.amountColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = view.t;
    final note = t.note?.trim();
    final categoryName = view.category == null
        ? (t.hasSplits ? null : l10n.commonUncategorized)
        : CategoryUtils.getDisplayName(view.category!.name, context);
    final title = (note != null && note.isNotEmpty)
        ? note
        : (categoryName ?? l10n.commonUncategorized);
    final d = t.happenedAt.toLocal();
    final sub = [
      '${d.year}/${d.month}/${d.day}',
      if (note != null && note.isNotEmpty && categoryName != null) categoryName,
      if (view.account != null) view.account!.name,
    ].join(' · ');

    return InkWell(
      onTap: () => showTransactionDetailCard(context, ref, t, view.category),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            if (rank != null)
              SizedBox(
                width: 28,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: rank! <= 3
                        ? BeeTokens.primary(context)
                        : BeeTokens.textTertiary(context),
                  ),
                ),
              ),
            CategoryIconWidget(
              category: view.category,
              categoryName: view.category?.name,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: BeeTokens.textTertiary(context))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AmountText(
              value: amount,
              signed: false,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: amountColor),
            ),
          ],
        ),
      ),
    );
  }
}
