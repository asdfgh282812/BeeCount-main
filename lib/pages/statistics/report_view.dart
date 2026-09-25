import 'package:flutter/material.dart';

import '../../models/report/report_dataset.dart';
import '../../models/report/report_definition.dart';
import '../../models/report/report_period.dart';
import '../../services/report/report_aggregator.dart';

/// 報表頁傳給各分頁的共用上下文:同一份資料集、同一個期間。
class ReportView {
  final ReportDefinition def;
  final ResolvedPeriod period;
  final ReportQuery query;
  final ReportDataset ds;
  final ReportAggregator agg;
  final String periodLabel;
  final int monthStartDay;

  /// 趨勢圖左右滑 = 上/下一期;沒有上/下一期時為 null。
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const ReportView({
    required this.def,
    required this.period,
    required this.query,
    required this.ds,
    required this.agg,
    required this.periodLabel,
    required this.monthStartDay,
    this.onPrev,
    this.onNext,
  });

  bool get filtered => def.filter.isActive;
}

/// 分頁底部留白,避免最後一列貼齊手勢列。
double reportBottomPadding(BuildContext context) =>
    24 + MediaQuery.of(context).viewPadding.bottom;
