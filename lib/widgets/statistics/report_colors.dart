import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/report/report_aggregator.dart';
import '../../styles/tokens.dart';

/// 統計報表金額的顏色。收入/支出跟隨「外觀設定 → 收支顏色」
/// (`incomeExpenseColorSchemeProvider`,見 [BeeTokens.incomeColor]);回饋金
/// 是拿到的錢,用收入色;轉帳不是收支,用中性的轉帳色。
Color reportFlowColor(BuildContext context, WidgetRef ref, String flow) {
  switch (flow) {
    case ReportFlow.income:
    case ReportFlow.reward:
      return BeeTokens.incomeColor(context, ref);
    case ReportFlow.transfer:
      return BeeTokens.chartTransfer(context);
    case ReportFlow.expense:
    default:
      return BeeTokens.expenseColor(context, ref);
  }
}

/// 結餘:≥ 0 用收入色,< 0 用支出色。
Color reportBalanceColor(BuildContext context, WidgetRef ref, double value) =>
    value >= 0
        ? BeeTokens.incomeColor(context, ref)
        : BeeTokens.expenseColor(context, ref);

String reportFlowLabel(AppLocalizations l10n, String flow) {
  switch (flow) {
    case ReportFlow.income:
      return l10n.homeIncome;
    case ReportFlow.transfer:
      return l10n.transferTitle;
    case ReportFlow.reward:
      return l10n.reportFlowReward;
    case ReportFlow.expense:
    default:
      return l10n.homeExpense;
  }
}
