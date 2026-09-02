import '../../l10n/app_localizations.dart';

/// 「設為分期」草稿——`transaction_entry_form.dart` 新增模式(expense)下
/// 透過「進階設定」彈窗(`recurring_rule_advanced_sheet.dart` 的
/// `RecurringRuleAdvancedSheet`,單次/週期/分期三選一)選了分期後,把攤還
/// 參數暫存在這裡,送出時上層改呼叫 `createInstallmentPlan` 而非
/// `addTransaction`(同 `RecurringRuleDraft` 的角色)。金額/首期日期/帳戶/
/// 分類/備註沿用表單本身既有欄位,不重複收集。
///
/// 2026-09-03:欄位收集的 UI 原本是這個檔案裡一個獨立的
/// `InstallmentDraftSheet` 彈窗,跟既有的「進階設定」彈窗(單次/週期)並列成
/// 表單裡兩個平行入口——但設計文件 §5.1 對標 Moze 的位置本來就是同一個
/// 「單次/週期/分期」三選一 tab bar,不該疊加第二個入口,已把欄位 UI 併進
/// `RecurringRuleAdvancedSheet` 的第三個 tab,這裡只留資料模型
/// (見 docs/changes/2026-09-03-installment-tracking-ux-fixes.md)。
class InstallmentDraft {
  final int periods;
  final String
      repaymentMethod; // equal_installment / equal_principal / fixed_interest
  final String interestPeriod; // monthly / daily
  final double interestRate; // 年利率,小數(0.06 = 6%)
  final bool roundAmounts;
  final String remainderPosition; // first / last
  final int gracePeriodMonths;

  const InstallmentDraft({
    required this.periods,
    this.repaymentMethod = 'equal_principal',
    this.interestPeriod = 'monthly',
    this.interestRate = 0.0,
    this.roundAmounts = true,
    this.remainderPosition = 'last',
    this.gracePeriodMonths = 0,
  });

  InstallmentDraft copyWith({
    int? periods,
    String? repaymentMethod,
    String? interestPeriod,
    double? interestRate,
    bool? roundAmounts,
    String? remainderPosition,
    int? gracePeriodMonths,
  }) {
    return InstallmentDraft(
      periods: periods ?? this.periods,
      repaymentMethod: repaymentMethod ?? this.repaymentMethod,
      interestPeriod: interestPeriod ?? this.interestPeriod,
      interestRate: interestRate ?? this.interestRate,
      roundAmounts: roundAmounts ?? this.roundAmounts,
      remainderPosition: remainderPosition ?? this.remainderPosition,
      gracePeriodMonths: gracePeriodMonths ?? this.gracePeriodMonths,
    );
  }

  /// 摘要文字,給交易表單的「進階設定」欄位顯示。例如「12 期 · 等額本金 · 年利率6%」。
  String summary(AppLocalizations l10n) {
    final methodLabel = switch (repaymentMethod) {
      'equal_installment' => l10n.installmentMethodEqualInstallment,
      'fixed_interest' => l10n.installmentMethodFixedInterest,
      _ => l10n.installmentMethodEqualPrincipal,
    };
    final ratePercent = interestRate * 100;
    final rateLabel = ratePercent == ratePercent.roundToDouble()
        ? ratePercent.toStringAsFixed(0)
        : ratePercent.toStringAsFixed(2);
    return '${l10n.installmentPeriodsCountLabel(periods)} · $methodLabel · $rateLabel%';
  }
}
