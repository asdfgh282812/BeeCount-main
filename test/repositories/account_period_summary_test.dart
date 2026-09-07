/// 一般帳戶明細頁「日期區間」摘要與四分頁篩選 —— Repository 层
/// `getAccountPeriodSummary` / `getAccountTransactions` 的 flow 四值互斥
/// (expense/income/transfer_out/transfer_in)测试。
///
/// 覆盖:
/// - 純支出/純收入/轉出/轉入各自加總+計數,轉帳不再疊加進支出/收入。
/// - `excludeFromStats=true` 的交易排除在摘要之外(對齐既有支出/收入統計口径)。
/// - `getAccountTransactions` 的 `flow: 'transfer_out'`/`'transfer_in'` 互斥,
///   不再像旧版一样把轉帳疊加進支出/收入分頁。
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

  test('getAccountPeriodSummary:純支出/純收入/轉出/轉入各自加總+計數,互斥不疊加',
      () async {
    final lid = await repo.createLedger(name: 'L');
    final wallet = await repo.createAccount(ledgerId: lid, name: '錢包');
    final bank = await repo.createAccount(ledgerId: lid, name: '銀行');

    final day = DateTime(2026, 7, 15);
    await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 100,
        accountId: wallet,
        happenedAt: day);
    await repo.addTransaction(
        ledgerId: lid,
        type: 'income',
        amount: 50,
        accountId: wallet,
        happenedAt: day);
    // 錢包 -> 銀行:對錢包來說是轉出。
    await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 30,
        accountId: wallet,
        toAccountId: bank,
        happenedAt: day);
    // 銀行 -> 錢包:對錢包來說是轉入。
    await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 20,
        accountId: bank,
        toAccountId: wallet,
        happenedAt: day);

    final summary = await repo.getAccountPeriodSummary(
      wallet,
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 7, 31),
    );

    expect(summary.expenseTotal, 100.0);
    expect(summary.expenseCount, 1);
    expect(summary.incomeTotal, 50.0);
    expect(summary.incomeCount, 1);
    expect(summary.transferOutTotal, 30.0);
    expect(summary.transferOutCount, 1);
    expect(summary.transferInTotal, 20.0);
    expect(summary.transferInCount, 1);
  });

  test('getAccountPeriodSummary:排除 excludeFromStats=true 的交易', () async {
    final lid = await repo.createLedger(name: 'L');
    final wallet = await repo.createAccount(ledgerId: lid, name: '錢包');

    final day = DateTime(2026, 7, 15);
    await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 100,
        accountId: wallet,
        happenedAt: day);
    await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 999,
        accountId: wallet,
        happenedAt: day,
        excludeFromStats: true);

    final summary = await repo.getAccountPeriodSummary(
      wallet,
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 7, 31),
    );

    expect(summary.expenseTotal, 100.0);
    expect(summary.expenseCount, 1);
  });

  test('getAccountTransactions:flow transfer_out/transfer_in 互斥,不疊加進支出/收入',
      () async {
    final lid = await repo.createLedger(name: 'L');
    final wallet = await repo.createAccount(ledgerId: lid, name: '錢包');
    final bank = await repo.createAccount(ledgerId: lid, name: '銀行');

    final day = DateTime(2026, 7, 15);
    await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 100,
        accountId: wallet,
        happenedAt: day);
    await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 30,
        accountId: wallet,
        toAccountId: bank,
        happenedAt: day);
    await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 20,
        accountId: bank,
        toAccountId: wallet,
        happenedAt: day);

    final expenseOnly =
        await repo.getAccountTransactions(wallet, flow: 'expense');
    expect(expenseOnly.length, 1);
    expect(expenseOnly.single.type, 'expense');

    final transferOut =
        await repo.getAccountTransactions(wallet, flow: 'transfer_out');
    expect(transferOut.length, 1);
    expect(transferOut.single.amount, 30.0);

    final transferIn =
        await repo.getAccountTransactions(wallet, flow: 'transfer_in');
    expect(transferIn.length, 1);
    expect(transferIn.single.amount, 20.0);
  });

  test('getAccountTransactions:ascending 控制排序方向', () async {
    final lid = await repo.createLedger(name: 'L');
    final wallet = await repo.createAccount(ledgerId: lid, name: '錢包');

    await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 10,
        accountId: wallet,
        happenedAt: DateTime(2026, 7, 1));
    await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 20,
        accountId: wallet,
        happenedAt: DateTime(2026, 7, 15));

    final desc = await repo.getAccountTransactions(wallet);
    expect(desc.map((t) => t.amount).toList(), [20.0, 10.0]);

    final asc =
        await repo.getAccountTransactions(wallet, ascending: true);
    expect(asc.map((t) => t.amount).toList(), [10.0, 20.0]);
  });
}
