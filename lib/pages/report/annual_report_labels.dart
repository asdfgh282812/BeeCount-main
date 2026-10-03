import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/investment/stock_annual_report.dart';
import '../../services/report/annual_persona.dart';
import '../investment/investment_ui.dart';

/// 年度報告(頁面 + 海報共用)的在地化文字 / 圖示對照:把純函式輸出的 enum
/// ([StockStyleTag]、[AnnualPersonaType]、[PersonaReason])轉成顯示用內容。

String stockStyleLabel(AppLocalizations l10n, StockStyleTag tag) {
  switch (tag) {
    case StockStyleTag.activeTrader:
      return l10n.annualStockStyleActiveTrader;
    case StockStyleTag.dividendHunter:
      return l10n.annualStockStyleDividendHunter;
    case StockStyleTag.longTermHolder:
      return l10n.annualStockStyleLongTermHolder;
    case StockStyleTag.swingTrader:
      return l10n.annualStockStyleSwingTrader;
    case StockStyleTag.beginner:
      return l10n.annualStockStyleBeginner;
  }
}

String stockStyleDesc(AppLocalizations l10n, StockStyleTag tag) {
  switch (tag) {
    case StockStyleTag.activeTrader:
      return l10n.annualStockStyleActiveTraderDesc;
    case StockStyleTag.dividendHunter:
      return l10n.annualStockStyleDividendHunterDesc;
    case StockStyleTag.longTermHolder:
      return l10n.annualStockStyleLongTermHolderDesc;
    case StockStyleTag.swingTrader:
      return l10n.annualStockStyleSwingTraderDesc;
    case StockStyleTag.beginner:
      return l10n.annualStockStyleBeginnerDesc;
  }
}

IconData stockStyleIcon(StockStyleTag tag) {
  switch (tag) {
    case StockStyleTag.activeTrader:
      return Icons.bolt_rounded;
    case StockStyleTag.dividendHunter:
      return Icons.paid_rounded;
    case StockStyleTag.longTermHolder:
      return Icons.hourglass_bottom_rounded;
    case StockStyleTag.swingTrader:
      return Icons.swap_vert_rounded;
    case StockStyleTag.beginner:
      return Icons.rocket_launch_rounded;
  }
}

String personaName(AppLocalizations l10n, AnnualPersonaType t) {
  switch (t) {
    case AnnualPersonaType.stockTrader:
      return l10n.annualPersonaStockTrader;
    case AnnualPersonaType.dividendCollector:
      return l10n.annualPersonaDividendCollector;
    case AnnualPersonaType.superSaver:
      return l10n.annualPersonaSuperSaver;
    case AnnualPersonaType.consistentRecorder:
      return l10n.annualPersonaConsistentRecorder;
    case AnnualPersonaType.weekendSpender:
      return l10n.annualPersonaWeekendSpender;
    case AnnualPersonaType.focusedSpender:
      return l10n.annualPersonaFocusedSpender;
    case AnnualPersonaType.adventurer:
      return l10n.annualPersonaAdventurer;
    case AnnualPersonaType.steady:
      return l10n.annualPersonaSteady;
  }
}

String personaDesc(AppLocalizations l10n, AnnualPersonaType t) {
  switch (t) {
    case AnnualPersonaType.stockTrader:
      return l10n.annualPersonaStockTraderDesc;
    case AnnualPersonaType.dividendCollector:
      return l10n.annualPersonaDividendCollectorDesc;
    case AnnualPersonaType.superSaver:
      return l10n.annualPersonaSuperSaverDesc;
    case AnnualPersonaType.consistentRecorder:
      return l10n.annualPersonaConsistentRecorderDesc;
    case AnnualPersonaType.weekendSpender:
      return l10n.annualPersonaWeekendSpenderDesc;
    case AnnualPersonaType.focusedSpender:
      return l10n.annualPersonaFocusedSpenderDesc;
    case AnnualPersonaType.adventurer:
      return l10n.annualPersonaAdventurerDesc;
    case AnnualPersonaType.steady:
      return l10n.annualPersonaSteadyDesc;
  }
}

IconData personaIcon(AnnualPersonaType t) {
  switch (t) {
    case AnnualPersonaType.stockTrader:
      return Icons.candlestick_chart_rounded;
    case AnnualPersonaType.dividendCollector:
      return Icons.paid_rounded;
    case AnnualPersonaType.superSaver:
      return Icons.savings_rounded;
    case AnnualPersonaType.consistentRecorder:
      return Icons.local_fire_department_rounded;
    case AnnualPersonaType.weekendSpender:
      return Icons.celebration_rounded;
    case AnnualPersonaType.focusedSpender:
      return Icons.center_focus_strong_rounded;
    case AnnualPersonaType.adventurer:
      return Icons.explore_rounded;
    case AnnualPersonaType.steady:
      return Icons.balance_rounded;
  }
}

IconData personaReasonIcon(PersonaReasonKind k) {
  switch (k) {
    case PersonaReasonKind.savingsRate:
      return Icons.savings_rounded;
    case PersonaReasonKind.streak:
      return Icons.local_fire_department_rounded;
    case PersonaReasonKind.weekendHigh:
    case PersonaReasonKind.weekdayHigh:
      return Icons.date_range_rounded;
    case PersonaReasonKind.topCategory:
      return Icons.category_rounded;
    case PersonaReasonKind.stockStyle:
    case PersonaReasonKind.stockPnl:
      return Icons.candlestick_chart_rounded;
    case PersonaReasonKind.records:
      return Icons.edit_note_rounded;
  }
}

String _oneDecimal(double v) => v.toStringAsFixed(1);

/// [hide] 為 true 時隱藏金額(股票損益那一條)。
String personaReasonText(AppLocalizations l10n, PersonaReason r,
    {bool hide = false}) {
  switch (r.kind) {
    case PersonaReasonKind.savingsRate:
      return l10n.annualPersonaReasonSavingsRate(_oneDecimal(r.value));
    case PersonaReasonKind.streak:
      return l10n.annualPersonaReasonStreak(r.value.round());
    case PersonaReasonKind.weekendHigh:
      return l10n.annualPersonaReasonWeekendHigh(_oneDecimal(r.value));
    case PersonaReasonKind.weekdayHigh:
      return l10n.annualPersonaReasonWeekdayHigh(_oneDecimal(r.value));
    case PersonaReasonKind.topCategory:
      return l10n.annualPersonaReasonTopCategory(
          r.label ?? '', r.value.toStringAsFixed(0));
    case PersonaReasonKind.stockStyle:
      return l10n.annualPersonaReasonStockStyle(
          r.style == null ? '' : stockStyleLabel(l10n, r.style!));
    case PersonaReasonKind.stockPnl:
      return l10n.annualPersonaReasonStockPnl(
          hide ? '****' : formatStockMoney(r.value, r.label, signed: true));
    case PersonaReasonKind.records:
      return l10n.annualPersonaReasonRecords(r.value.round());
  }
}
