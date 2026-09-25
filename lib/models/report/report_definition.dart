import 'report_filter.dart';
import 'report_period.dart';

/// 內建報表範本 key。名稱走 l10n(使用者改名後才存 [ReportDefinition.name])。
const kBuiltInWeekly = 'weekly';
const kBuiltInMonthly = 'monthly';
const kBuiltInYearly = 'yearly';

/// 一份可儲存的統計報表:期間 + 篩選。一律跟隨「目前帳本」(不綁特定帳本)
/// ——帳戶/分類/標籤本來就是 user-global,篩選條件換帳本仍然有效;專案/欠款
/// 是 ledger-scoped,換到別的帳本時對不到的 key 就自然不命中。
class ReportDefinition {
  final String id;

  /// null = 用內建名稱([builtInKey] 對應的 l10n 字串)。
  final String? name;
  final String? builtInKey;
  final ReportPeriod period;
  final ReportFilter filter;

  const ReportDefinition({
    required this.id,
    this.name,
    this.builtInKey,
    required this.period,
    this.filter = ReportFilter.none,
  });

  ReportDefinition copyWith({
    String? id,
    String? Function()? name,
    String? Function()? builtInKey,
    ReportPeriod? period,
    ReportFilter? filter,
  }) =>
      ReportDefinition(
        id: id ?? this.id,
        name: name != null ? name() : this.name,
        builtInKey: builtInKey != null ? builtInKey() : this.builtInKey,
        period: period ?? this.period,
        filter: filter ?? this.filter,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (name != null) 'name': name,
        if (builtInKey != null) 'builtIn': builtInKey,
        'period': period.toJson(),
        'filter': filter.toJson(),
      };

  static ReportDefinition? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final period = json['period'];
    return ReportDefinition(
      id: id,
      name: json['name'] as String?,
      builtInKey: json['builtIn'] as String?,
      period: period is Map
          ? ReportPeriod.fromJson(Map<String, dynamic>.from(period))
          : const RecurringPeriod(unit: ReportPeriodUnit.month),
      filter: ReportFilter.fromJson(json['filter']),
    );
  }

  static List<ReportDefinition> builtIns() => const [
        ReportDefinition(
          id: 'builtin-monthly',
          builtInKey: kBuiltInMonthly,
          period: RecurringPeriod(unit: ReportPeriodUnit.month),
        ),
        ReportDefinition(
          id: 'builtin-weekly',
          builtInKey: kBuiltInWeekly,
          period: RecurringPeriod(unit: ReportPeriodUnit.week),
        ),
        ReportDefinition(
          id: 'builtin-yearly',
          builtInKey: kBuiltInYearly,
          period: RecurringPeriod(unit: ReportPeriodUnit.year),
        ),
      ];
}
