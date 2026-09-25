import '../data/db.dart' as db;

/// 主帳戶(`type == 'account_group'`)相關的共用判斷。
///
/// 主帳戶本身沒有「信用卡群組 / 一般群組」的欄位——種類是從子帳戶類型(以及
/// 還沒有子帳戶時,主帳戶自己身上有沒有設帳單欄位)推出來的,這樣不用改
/// schema 也不用動 BeeCount Cloud 的同步契約(web 端
/// `resolveAccountGroupDisplayType` 是同一套規則)。資產頁分組、明細頁版面、
/// 編輯頁要不要顯示合併帳單設定都走這裡,避免三處各自判斷而不一致。

/// [group] 的子帳戶:`parentAccountId` 指向它的 syncId。
List<db.Account> accountGroupChildren(
    db.Account group, Iterable<db.Account> allAccounts) {
  final syncId = group.syncId;
  if (syncId == null || syncId.isEmpty) return const [];
  return allAccounts.where((a) => a.parentAccountId == syncId).toList();
}

/// 主帳戶自己身上是否設了任一個合併帳單欄位(額度/帳單日/還款日/自動扣繳)。
bool hasAccountGroupBillingFields(db.Account group) =>
    group.creditLimit != null ||
    group.billingDay != null ||
    group.paymentDueDay != null ||
    group.autoPayEnabled;

/// 主帳戶的展示類型:子帳戶類型一致就跟著子帳戶;不一致時信用卡優先(有任何
/// 一張信用卡就得走合併帳單);還沒有子帳戶時看主帳戶自己有沒有設帳單欄位。
/// 非 account_group 帳戶原樣返回自己的 type。
String resolveAccountGroupDisplayType(
    db.Account account, Iterable<db.Account> children) {
  if (account.type != 'account_group') return account.type;
  if (children.isEmpty) {
    return hasAccountGroupBillingFields(account) ? 'credit_card' : 'bank_card';
  }
  final childTypes = children.map((c) => c.type).toSet();
  if (childTypes.length == 1) return childTypes.first;
  return childTypes.contains('credit_card') ? 'credit_card' : 'bank_card';
}

/// 是否為「信用卡合併帳單」群組(明細頁走帳單週期版面、編輯頁顯示額度/
/// 帳單日/還款日)。其它群組(例如同一家銀行的台幣戶+外幣戶)是一般群組,
/// 明細頁走一般帳戶的期間版面,只是把子帳戶的交易聚合起來。
bool isCreditCardAccountGroup(
        db.Account account, Iterable<db.Account> children) =>
    account.type == 'account_group' &&
    resolveAccountGroupDisplayType(account, children) == 'credit_card';

/// 子帳戶裡有信用卡時,群組固定是合併帳單群組(編輯頁的開關鎖定為開)。
bool accountGroupHasCreditCardChild(Iterable<db.Account> children) =>
    children.any((c) => c.type == 'credit_card');
