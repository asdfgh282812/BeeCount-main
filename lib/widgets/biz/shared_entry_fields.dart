/// 支出/收入/轉帳三個分頁共用的「已輸入欄位」快照——切換
/// `transaction_editor_page.dart` 的 tab 時,把離開的分頁目前輸入的這些欄位
/// 帶到新切到的分頁,取代切 tab 就看到空白表單的體驗。
///
/// 只涵蓋三個分頁概念上共通的欄位(金額/名稱/商家/日期時間/標籤/帳戶);
/// 類別、退款關聯、附件、幣別、信用卡回饋規則等分頁特有或語意不同的欄位不
/// 在這裡同步。`accountId` 對支出/收入是「選中的帳戶」,對轉帳是「轉出帳
/// 戶」——轉入帳戶不受同步影響,由使用者自己選。
typedef SharedEntryFields = ({
  String amountStr,
  double amountAcc,
  String? amountOp,
  DateTime date,
  String note,
  String merchant,
  List<int> tagIds,
  int? accountId,
  // 專案(v44)——同 accountId 的「null 不覆蓋」慣例:來源分頁沒選專案時
  // 維持目標分頁原本的選擇不動,只有非 null 才觸發套用。
  String? projectSyncId,
});
