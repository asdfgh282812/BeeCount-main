import '../investment/stock_annual_report.dart';

/// 年度報告「年度稱號 / 人設」(純函式,不碰 DB / UI)。
///
/// 規則依優先序取第一個符合者(順序見 [AnnualPersona.decide]);每個稱號再配
/// 2~3 個「理由」chip,理由只取資料真的存在的事實,UI 負責把
/// [PersonaReason] 轉成在地化文字。
enum AnnualPersonaType {
  /// 積極交易的股票玩家(股票風格 activeTrader)。
  stockTrader,

  /// 領息獵人(股票風格 dividendHunter)。
  dividendCollector,

  /// 儲蓄率 ≥ 30%。
  superSaver,

  /// 最長連續記帳 ≥ 30 天。
  consistentRecorder,

  /// 週末日均支出 ≥ 平日 1.5 倍。
  weekendSpender,

  /// 單一分類占支出 ≥ 40%。
  focusedSpender,

  /// 入不敷出(儲蓄率 < 0)。
  adventurer,

  /// 其餘:收支平穩。
  steady,
}

enum PersonaReasonKind {
  savingsRate,
  streak,
  weekendHigh,
  weekdayHigh,
  topCategory,
  stockStyle,
  stockPnl,
  records,
}

class PersonaReason {
  final PersonaReasonKind kind;

  /// savingsRate:百分比(例 32.5);streak:天數;weekend/weekdayHigh:倍數;
  /// topCategory:占比百分比;stockPnl:損益金額;records:筆數。
  final double value;

  /// topCategory:分類名稱;stockPnl:幣別代碼。
  final String? label;

  /// stockStyle 用。
  final StockStyleTag? style;

  const PersonaReason(this.kind, this.value, {this.label, this.style});
}

class AnnualPersona {
  final AnnualPersonaType type;
  final List<PersonaReason> reasons;

  const AnnualPersona(this.type, this.reasons);

  /// [weekendWeekdayRatio]:週末日均支出 / 平日日均支出,資料不足時 null。
  /// [topCategoryShare]:最大支出分類占支出 0~1,沒有時 null。
  static AnnualPersona decide({
    required int totalRecords,
    required int totalDays,
    required double totalIncome,
    required double totalExpense,
    required int maxConsecutiveDays,
    double? weekendWeekdayRatio,
    String? topCategoryName,
    double? topCategoryShare,
    StockCurrencyAnnual? stock,
  }) {
    final savingsRate =
        totalIncome > 0 ? (totalIncome - totalExpense) / totalIncome : null;
    final topShareOk = topCategoryShare != null &&
        topCategoryShare >= 0.4 &&
        topCategoryName != null &&
        topCategoryName.isNotEmpty;

    AnnualPersonaType type;
    if (stock != null && stock.styleTag == StockStyleTag.activeTrader) {
      type = AnnualPersonaType.stockTrader;
    } else if (stock != null &&
        stock.styleTag == StockStyleTag.dividendHunter) {
      type = AnnualPersonaType.dividendCollector;
    } else if (savingsRate != null && savingsRate >= 0.3) {
      type = AnnualPersonaType.superSaver;
    } else if (maxConsecutiveDays >= 30) {
      type = AnnualPersonaType.consistentRecorder;
    } else if (weekendWeekdayRatio != null && weekendWeekdayRatio >= 1.5) {
      type = AnnualPersonaType.weekendSpender;
    } else if (topShareOk) {
      type = AnnualPersonaType.focusedSpender;
    } else if (savingsRate != null && savingsRate < 0) {
      type = AnnualPersonaType.adventurer;
    } else {
      type = AnnualPersonaType.steady;
    }

    // 候選理由:依資料存在與否產生,再把「跟稱號最相關」的排前面,取前 3。
    final candidates = <PersonaReason>[];
    if (stock != null) {
      candidates.add(PersonaReason(PersonaReasonKind.stockStyle, 0,
          style: stock.styleTag));
      if (stock.hasSells) {
        candidates.add(PersonaReason(
            PersonaReasonKind.stockPnl, stock.realizedPnl,
            label: stock.currency));
      }
    }
    if (savingsRate != null) {
      candidates
          .add(PersonaReason(PersonaReasonKind.savingsRate, savingsRate * 100));
    }
    if (maxConsecutiveDays >= 2) {
      candidates.add(PersonaReason(
          PersonaReasonKind.streak, maxConsecutiveDays.toDouble()));
    }
    if (weekendWeekdayRatio != null) {
      if (weekendWeekdayRatio >= 1.3) {
        candidates.add(
            PersonaReason(PersonaReasonKind.weekendHigh, weekendWeekdayRatio));
      } else if (weekendWeekdayRatio > 0 && weekendWeekdayRatio <= 0.7) {
        candidates.add(PersonaReason(
            PersonaReasonKind.weekdayHigh, 1 / weekendWeekdayRatio));
      }
    }
    if (topCategoryShare != null &&
        topCategoryName != null &&
        topCategoryName.isNotEmpty &&
        topCategoryShare > 0) {
      candidates.add(PersonaReason(
          PersonaReasonKind.topCategory, topCategoryShare * 100,
          label: topCategoryName));
    }
    candidates
        .add(PersonaReason(PersonaReasonKind.records, totalRecords.toDouble()));

    const relevant = <AnnualPersonaType, List<PersonaReasonKind>>{
      AnnualPersonaType.stockTrader: [
        PersonaReasonKind.stockStyle,
        PersonaReasonKind.stockPnl,
      ],
      AnnualPersonaType.dividendCollector: [
        PersonaReasonKind.stockStyle,
        PersonaReasonKind.stockPnl,
      ],
      AnnualPersonaType.superSaver: [PersonaReasonKind.savingsRate],
      AnnualPersonaType.consistentRecorder: [
        PersonaReasonKind.streak,
        PersonaReasonKind.records,
      ],
      AnnualPersonaType.weekendSpender: [PersonaReasonKind.weekendHigh],
      AnnualPersonaType.focusedSpender: [PersonaReasonKind.topCategory],
      AnnualPersonaType.adventurer: [PersonaReasonKind.savingsRate],
      AnnualPersonaType.steady: [PersonaReasonKind.savingsRate],
    };
    final first = relevant[type] ?? const <PersonaReasonKind>[];
    final ordered = <PersonaReason>[
      ...candidates.where((r) => first.contains(r.kind)),
      ...candidates.where((r) => !first.contains(r.kind)),
    ];
    return AnnualPersona(type, ordered.take(3).toList());
  }
}
