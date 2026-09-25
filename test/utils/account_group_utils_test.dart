import 'package:beecount/data/db.dart' as db;
import 'package:beecount/utils/account_group_utils.dart';
import 'package:flutter_test/flutter_test.dart';

db.Account _account({
  required int id,
  required String type,
  String? syncId,
  String? parentAccountId,
  double? creditLimit,
  int? billingDay,
  int? paymentDueDay,
  bool autoPayEnabled = false,
}) =>
    db.Account(
      id: id,
      ledgerId: 1,
      name: 'a$id',
      type: type,
      currency: 'TWD',
      initialBalance: 0,
      sortOrder: 0,
      creditLimit: creditLimit,
      billingDay: billingDay,
      paymentDueDay: paymentDueDay,
      syncId: syncId,
      hidden: false,
      parentAccountId: parentAccountId,
      includeInTotal: true,
      autoPayEnabled: autoPayEnabled,
      hideAmount: false,
    );

void main() {
  final group = _account(id: 1, type: 'account_group', syncId: 'g1');

  test('accountGroupChildren 用 parentAccountId 對 syncId 反查', () {
    final all = [
      group,
      _account(id: 2, type: 'bank_card', parentAccountId: 'g1'),
      _account(id: 3, type: 'bank_card', parentAccountId: 'other'),
      _account(id: 4, type: 'cash'),
    ];
    expect(accountGroupChildren(group, all).map((a) => a.id), [2]);
    expect(accountGroupChildren(_account(id: 9, type: 'account_group'), all),
        isEmpty);
  });

  test('全是銀行卡子帳戶 → 一般群組', () {
    final children = [
      _account(id: 2, type: 'bank_card', parentAccountId: 'g1'),
      _account(id: 3, type: 'bank_card', parentAccountId: 'g1'),
    ];
    expect(resolveAccountGroupDisplayType(group, children), 'bank_card');
    expect(isCreditCardAccountGroup(group, children), isFalse);
  });

  test('銀行卡子帳戶 + 主帳戶殘留帳單欄位 → 仍以子帳戶為準,一般群組', () {
    final withFields =
        _account(id: 1, type: 'account_group', syncId: 'g1', billingDay: 5);
    final children = [
      _account(id: 2, type: 'bank_card', parentAccountId: 'g1'),
    ];
    expect(isCreditCardAccountGroup(withFields, children), isFalse);
  });

  test('有任一張信用卡子帳戶 → 合併帳單群組', () {
    final children = [
      _account(id: 2, type: 'bank_card', parentAccountId: 'g1'),
      _account(id: 3, type: 'credit_card', parentAccountId: 'g1'),
    ];
    expect(resolveAccountGroupDisplayType(group, children), 'credit_card');
    expect(isCreditCardAccountGroup(group, children), isTrue);
    expect(accountGroupHasCreditCardChild(children), isTrue);
  });

  test('沒有子帳戶:看主帳戶自己的帳單欄位', () {
    expect(isCreditCardAccountGroup(group, const []), isFalse);
    for (final g in [
      _account(id: 1, type: 'account_group', creditLimit: 1000),
      _account(id: 1, type: 'account_group', billingDay: 5),
      _account(id: 1, type: 'account_group', paymentDueDay: 20),
      _account(id: 1, type: 'account_group', autoPayEnabled: true),
    ]) {
      expect(isCreditCardAccountGroup(g, const []), isTrue);
    }
  });

  test('非群組帳戶原樣回傳 type,且不是合併帳單群組', () {
    final card = _account(id: 5, type: 'credit_card');
    expect(resolveAccountGroupDisplayType(card, const []), 'credit_card');
    expect(isCreditCardAccountGroup(card, const []), isFalse);
  });
}
