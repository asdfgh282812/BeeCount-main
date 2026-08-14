/// 帳戶詳情頁「交易明細」tab 的主帳戶聚合視圖(主子帳戶改版)—— Repository
/// 层 `getAccountTransactions` 的 `extraAccountIds` / `startDate` / `endDate`
/// 扩展参数测试。
///
/// 覆盖:
/// - `extraAccountIds` 把子帳戶的交易一併按 account_id/to_account_id IN (...)
///   查出來,不漏、不重複、跟单账户查询互不影响。
/// - `startDate`/`endDate` 按帳單週期篩選,邊界(端點當天)含入。
/// - `flow` 過濾(expense/income)在多帳戶聚合下依然生效。
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
  });

  tearDown(() async => db.close());

  test('extraAccountIds 聚合主卡 + 子卡的交易,不漏也不重复', () async {
    final lid = await repo.createLedger(name: 'L');
    final parent = await repo.createAccount(
        ledgerId: lid, name: '永豐信用卡', type: 'credit_card');
    final child1 = await repo.createAccount(
        ledgerId: lid, name: '永豐 Sport 卡', type: 'credit_card');
    final child2 = await repo.createAccount(
        ledgerId: lid, name: '大戶信用卡', type: 'credit_card');
    final other = await repo.createAccount(
        ledgerId: lid, name: '無關帳戶', type: 'credit_card');

    final day = DateTime(2026, 7, 15);
    await repo.addTransaction(
        ledgerId: lid, type: 'expense', amount: 100, accountId: parent, happenedAt: day);
    await repo.addTransaction(
        ledgerId: lid, type: 'expense', amount: 200, accountId: child1, happenedAt: day);
    await repo.addTransaction(
        ledgerId: lid, type: 'expense', amount: 300, accountId: child2, happenedAt: day);
    await repo.addTransaction(
        ledgerId: lid, type: 'expense', amount: 999, accountId: other, happenedAt: day);

    final txs = await repo.getAccountTransactions(
      parent,
      extraAccountIds: [child1, child2],
    );

    expect(txs.length, 3);
    expect(txs.map((t) => t.amount).toSet(), {100.0, 200.0, 300.0});
  });

  test('startDate/endDate 按帳單週期篩選,端點當天含入', () async {
    final lid = await repo.createLedger(name: 'L');
    final aid = await repo.createAccount(ledgerId: lid, name: 'A', type: 'credit_card');

    await repo.addTransaction(
        ledgerId: lid, type: 'expense', amount: 10, accountId: aid,
        happenedAt: DateTime(2026, 7, 5, 23, 59)); // 週期外(前一天)
    await repo.addTransaction(
        ledgerId: lid, type: 'expense', amount: 20, accountId: aid,
        happenedAt: DateTime(2026, 7, 6, 0, 0)); // 週期起點當天
    await repo.addTransaction(
        ledgerId: lid, type: 'expense', amount: 30, accountId: aid,
        happenedAt: DateTime(2026, 8, 5, 23, 59)); // 週期終點當天
    await repo.addTransaction(
        ledgerId: lid, type: 'expense', amount: 40, accountId: aid,
        happenedAt: DateTime(2026, 8, 6, 0, 0)); // 週期外(下一期)

    final txs = await repo.getAccountTransactions(
      aid,
      startDate: DateTime(2026, 7, 6),
      endDate: DateTime(2026, 8, 5),
    );

    expect(txs.map((t) => t.amount).toSet(), {20.0, 30.0});
  });

  test('flow 過濾在多帳戶聚合下依然生效', () async {
    final lid = await repo.createLedger(name: 'L');
    final parent = await repo.createAccount(ledgerId: lid, name: 'P', type: 'credit_card');
    final child = await repo.createAccount(ledgerId: lid, name: 'C', type: 'credit_card');
    final bank = await repo.createAccount(ledgerId: lid, name: 'Bank');

    final day = DateTime(2026, 7, 15);
    await repo.addTransaction(
        ledgerId: lid, type: 'expense', amount: 50, accountId: child, happenedAt: day);
    // 從 bank 轉入 child 卡的還款,flow=expense 時不該出現(转入不是流出)。
    await repo.addTransaction(
        ledgerId: lid, type: 'transfer', amount: 50, accountId: bank,
        toAccountId: child, happenedAt: day);

    final txs = await repo.getAccountTransactions(
      parent,
      extraAccountIds: [child],
      flow: 'expense',
    );

    expect(txs.length, 1);
    expect(txs.single.type, 'expense');
  });
}
