/// 統計口徑的退款沖銷(docs/changes/2026-09-25-refund-netting.md)。
///
/// 退款單(`refundOfSyncId` 非空)不算它自己的類型,改成「反方向的負值」:
/// 收入型退款(退一筆支出)= 支出 −x、支出型退款(退一筆收入,例如 Cloud
/// 自動產生的回饋金沖銷)= 收入 −x。跟 BeeCount Cloud
/// `routers/read/workspace.py::_stat_legs` 同一口徑,兩端總額才對得上。
///
/// 退款算在退款單自己的日期(不回頭改原交易那一期),分類歸屬扣回原交易
/// 的分類——由呼叫端查原交易決定,這裡只管方向與正負號。
library;

bool isRefundOf(String? refundOfSyncId) =>
    refundOfSyncId != null && refundOfSyncId.isNotEmpty;

/// 回傳這筆交易在收支統計裡的方向與正負號;轉帳/調整等不計入收支 → null。
({String flow, double sign})? statFlowOf(String type, String? refundOfSyncId) {
  final refund = isRefundOf(refundOfSyncId);
  switch (type) {
    case 'income':
      return refund
          ? (flow: 'expense', sign: -1.0)
          : (flow: 'income', sign: 1.0);
    case 'expense':
      return refund
          ? (flow: 'income', sign: -1.0)
          : (flow: 'expense', sign: 1.0);
  }
  return null;
}

/// 查 [flow] 統計時要一起撈的交易類型:本身類型 + 反向類型(其中的退款單)。
List<String> statTypesFor(String flow) {
  switch (flow) {
    case 'income':
      return const ['income', 'expense'];
    case 'expense':
      return const ['expense', 'income'];
  }
  return [flow];
}
