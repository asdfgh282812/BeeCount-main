/// 統計報表的篩選條件(對齊 MOZE「包含/排除」)。所有實體一律以 **syncId**
/// 字串當 key(沒有 syncId 的舊資料用 `id:<本地 id>` 兜底,見
/// [reportEntityKey]),不存本地 int id——報表定義存在 SharedPreferences,
/// 將來如果要跟 profile 一起同步,跨裝置 int id 不一致會讓條件整個失效。
library;

import 'dart:convert';

enum FilterMode { include, exclude }

/// 本地實體的報表 key:有 syncId 用 syncId,沒有就用 `id:<id>`。
String reportEntityKey(String? syncId, int id) =>
    (syncId != null && syncId.isNotEmpty) ? syncId : 'id:$id';

/// 一組 key 的包含/排除條件。[values] 為空且 [includeNone] 為 false 時視為
/// 未啟用。[includeNone] 代表「(無)」這個選項——例:標籤條件勾「(無)」=
/// 沒有任何標籤的交易。
class KeySetFilter {
  final FilterMode mode;
  final Set<String> values;
  final bool includeNone;

  const KeySetFilter({
    this.mode = FilterMode.include,
    this.values = const {},
    this.includeNone = false,
  });

  static const empty = KeySetFilter();

  bool get isActive => values.isNotEmpty || includeNone;

  int get selectedCount => values.length + (includeNone ? 1 : 0);

  bool _hit(String? v) =>
      (v == null || v.isEmpty) ? includeNone : values.contains(v);

  /// 單值欄位(商家、名稱、專案…)。
  bool matchesSingle(String? v) {
    if (!isActive) return true;
    final hit = _hit(v);
    return mode == FilterMode.include ? hit : !hit;
  }

  /// 多值欄位(標籤、轉帳的轉出/轉入帳戶):任一命中即算命中;空集合 =「(無)」。
  bool matchesAny(Iterable<String> vs) {
    if (!isActive) return true;
    final list = vs.where((v) => v.isNotEmpty).toList();
    final hit = list.isEmpty ? includeNone : list.any(values.contains);
    return mode == FilterMode.include ? hit : !hit;
  }

  KeySetFilter copyWith(
          {FilterMode? mode, Set<String>? values, bool? includeNone}) =>
      KeySetFilter(
        mode: mode ?? this.mode,
        values: values ?? this.values,
        includeNone: includeNone ?? this.includeNone,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'values': (values.toList()..sort()),
        if (includeNone) 'none': true,
      };

  static KeySetFilter fromJson(Object? json) {
    if (json is! Map) return empty;
    return KeySetFilter(
      mode: json['mode'] == 'exclude' ? FilterMode.exclude : FilterMode.include,
      values: {
        for (final v in (json['values'] as List? ?? const [])) v.toString()
      },
      includeNone: json['none'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KeySetFilter &&
      other.mode == mode &&
      other.includeNone == includeNone &&
      other.values.length == values.length &&
      other.values.containsAll(values);

  @override
  int get hashCode =>
      Object.hash(mode, includeNone, Object.hashAllUnordered(values));
}

/// 記錄類型篩選的三個群組。`adjustment`(餘額調整)等其他非收支類型併入
/// [transfer] 群組——它們跟轉帳一樣不計入收支統計,只出現在明細列表。
const kReportRecordTypes = ['expense', 'income', 'transfer'];

String reportRecordTypeGroup(String txType) =>
    (txType == 'expense' || txType == 'income') ? txType : 'transfer';

class ReportFilter {
  final KeySetFilter accounts;
  final KeySetFilter projects;

  /// 分類 key;選到一級分類時,其子分類一併命中(比對時看 entry 自己跟父
  /// 分類的 key,見 `ReportEntry.categoryKeys`)。
  final KeySetFilter categories;
  final KeySetFilter tags;

  /// 對象:存欠款的 counterpartyName(同名的多筆欠款視為同一個對象,跟
  /// 「標籤和對象」分頁的分組口徑一致)。
  final KeySetFilter counterparties;
  final KeySetFilter names;
  final KeySetFilter merchants;

  /// 金額範圍,比對整筆交易的本位幣金額(不是拆帳明細)。
  final double? minAmount;
  final double? maxAmount;

  /// 允許的記錄類型群組(見 [kReportRecordTypes])。
  final Set<String> recordTypes;

  const ReportFilter({
    this.accounts = KeySetFilter.empty,
    this.projects = KeySetFilter.empty,
    this.categories = KeySetFilter.empty,
    this.tags = KeySetFilter.empty,
    this.counterparties = KeySetFilter.empty,
    this.names = KeySetFilter.empty,
    this.merchants = KeySetFilter.empty,
    this.minAmount,
    this.maxAmount,
    this.recordTypes = const {'expense', 'income', 'transfer'},
  });

  static const none = ReportFilter();

  bool get hasAmountRange => minAmount != null || maxAmount != null;

  bool get recordTypesActive => !kReportRecordTypes.every(recordTypes.contains);

  /// 啟用中的條件數(報表頁篩選按鈕的徽章用)。
  int get activeCount => [
        accounts.isActive,
        projects.isActive,
        categories.isActive,
        tags.isActive,
        counterparties.isActive,
        names.isActive,
        merchants.isActive,
        hasAmountRange,
        recordTypesActive,
      ].where((b) => b).length;

  bool get isActive => activeCount > 0;

  ReportFilter copyWith({
    KeySetFilter? accounts,
    KeySetFilter? projects,
    KeySetFilter? categories,
    KeySetFilter? tags,
    KeySetFilter? counterparties,
    KeySetFilter? names,
    KeySetFilter? merchants,
    double? Function()? minAmount,
    double? Function()? maxAmount,
    Set<String>? recordTypes,
  }) =>
      ReportFilter(
        accounts: accounts ?? this.accounts,
        projects: projects ?? this.projects,
        categories: categories ?? this.categories,
        tags: tags ?? this.tags,
        counterparties: counterparties ?? this.counterparties,
        names: names ?? this.names,
        merchants: merchants ?? this.merchants,
        minAmount: minAmount != null ? minAmount() : this.minAmount,
        maxAmount: maxAmount != null ? maxAmount() : this.maxAmount,
        recordTypes: recordTypes ?? this.recordTypes,
      );

  Map<String, dynamic> toJson() => {
        if (accounts.isActive) 'accounts': accounts.toJson(),
        if (projects.isActive) 'projects': projects.toJson(),
        if (categories.isActive) 'categories': categories.toJson(),
        if (tags.isActive) 'tags': tags.toJson(),
        if (counterparties.isActive) 'counterparties': counterparties.toJson(),
        if (names.isActive) 'names': names.toJson(),
        if (merchants.isActive) 'merchants': merchants.toJson(),
        if (minAmount != null) 'min': minAmount,
        if (maxAmount != null) 'max': maxAmount,
        'types': (recordTypes.toList()..sort()),
      };

  static ReportFilter fromJson(Object? json) {
    if (json is! Map) return none;
    final types = json['types'];
    return ReportFilter(
      accounts: KeySetFilter.fromJson(json['accounts']),
      projects: KeySetFilter.fromJson(json['projects']),
      categories: KeySetFilter.fromJson(json['categories']),
      tags: KeySetFilter.fromJson(json['tags']),
      counterparties: KeySetFilter.fromJson(json['counterparties']),
      names: KeySetFilter.fromJson(json['names']),
      merchants: KeySetFilter.fromJson(json['merchants']),
      minAmount: (json['min'] as num?)?.toDouble(),
      maxAmount: (json['max'] as num?)?.toDouble(),
      recordTypes: types is List
          ? {
              for (final t in types)
                if (kReportRecordTypes.contains(t)) t.toString()
            }
          : const {'expense', 'income', 'transfer'},
    );
  }

  /// 穩定排序過的 JSON 字串,當 provider family key 的相等判斷用。
  String get canonical => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is ReportFilter && other.canonical == canonical;

  @override
  int get hashCode => canonical.hashCode;
}
