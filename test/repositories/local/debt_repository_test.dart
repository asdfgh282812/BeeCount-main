// 借還款(v39)Repository 層測試:狀態推導(open/partial/settled/closed)、
// 刪除守衛(有還款記錄不能刪)、淨欠款餘額計算。
//
// 狀態推導對齐 BeeCount Cloud `routers/read/ledgers.py::list_debts`:
// closedAt 優先於金額判斷(可以在未還清時手動結案)。

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/debt_repository.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

void main() {
  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
  });

  tearDown(() async => db.close());

  Future<int> seedLedger() {
    return db.into(db.ledgers).insert(LedgersCompanion.insert(name: '测试账本'));
  }

  test('新建欠款無還款 → 狀態 open,剩餘 = 本金', () async {
    final lid = await seedLedger();
    final id = await repo.createDebt(
      ledgerId: lid,
      direction: kDebtDirectionPayable,
      counterpartyName: '小明',
      principalAmount: 1000,
    );

    final withStatus = await repo.getDebtWithStatus(id);
    expect(withStatus, isNotNull);
    expect(withStatus!.status, kDebtStatusOpen);
    expect(withStatus.remainingAmount, 1000);
    expect(withStatus.repaidAmount, 0);
  });

  test('部分還款 → 狀態 partial,剩餘 = 本金 - 已還', () async {
    final lid = await seedLedger();
    final id = await repo.createDebt(
      ledgerId: lid,
      direction: kDebtDirectionPayable,
      counterpartyName: '小明',
      principalAmount: 1000,
    );
    final debt = (await repo.getDebt(id))!;

    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 300,
      happenedAt: DateTime(2026, 1, 1),
      debtSyncId: debt.syncId,
    );

    final withStatus = await repo.getDebtWithStatus(id);
    expect(withStatus!.status, kDebtStatusPartial);
    expect(withStatus.remainingAmount, 700);
    expect(withStatus.repaidAmount, 300);
  });

  test('還清 → 狀態 settled', () async {
    final lid = await seedLedger();
    final id = await repo.createDebt(
      ledgerId: lid,
      direction: kDebtDirectionReceivable,
      counterpartyName: '小華',
      principalAmount: 500,
    );
    final debt = (await repo.getDebt(id))!;

    await repo.addTransaction(
      ledgerId: lid,
      type: 'income',
      amount: 500,
      happenedAt: DateTime(2026, 1, 1),
      debtSyncId: debt.syncId,
    );

    final withStatus = await repo.getDebtWithStatus(id);
    expect(withStatus!.status, kDebtStatusSettled);
    expect(withStatus.remainingAmount, 0);
  });

  test('手動結案優先於金額判斷 → 即使未還清也是 closed', () async {
    final lid = await seedLedger();
    final id = await repo.createDebt(
      ledgerId: lid,
      direction: kDebtDirectionPayable,
      counterpartyName: '呆帳對象',
      principalAmount: 1000,
    );

    await repo.closeDebt(id);

    final withStatus = await repo.getDebtWithStatus(id);
    expect(withStatus!.status, kDebtStatusClosed);
    expect(withStatus.remainingAmount, 1000,
        reason: 'closed 不代表已還清,只是不再追蹤');
  });

  test('reopenDebt 清空 closedAt → 狀態依金額重新推導', () async {
    final lid = await seedLedger();
    final id = await repo.createDebt(
      ledgerId: lid,
      direction: kDebtDirectionPayable,
      counterpartyName: '對象',
      principalAmount: 1000,
    );
    await repo.closeDebt(id);
    await repo.reopenDebt(id);

    final withStatus = await repo.getDebtWithStatus(id);
    expect(withStatus!.status, kDebtStatusOpen);
  });

  test('已有還款記錄的欠款不能刪除', () async {
    final lid = await seedLedger();
    final id = await repo.createDebt(
      ledgerId: lid,
      direction: kDebtDirectionPayable,
      counterpartyName: '對象',
      principalAmount: 1000,
    );
    final debt = (await repo.getDebt(id))!;
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      happenedAt: DateTime(2026, 1, 1),
      debtSyncId: debt.syncId,
    );

    expect(await repo.hasRepayments(id), isTrue);
    expect(() => repo.deleteDebt(id), throwsStateError);
  });

  test('沒有還款記錄的欠款可以刪除', () async {
    final lid = await seedLedger();
    final id = await repo.createDebt(
      ledgerId: lid,
      direction: kDebtDirectionPayable,
      counterpartyName: '對象',
      principalAmount: 1000,
    );

    await repo.deleteDebt(id);
    expect(await repo.getDebt(id), isNull);
  });

  test('updateDebt 的 clearDueAt/clearNote 能顯式清空欄位', () async {
    final lid = await seedLedger();
    final id = await repo.createDebt(
      ledgerId: lid,
      direction: kDebtDirectionPayable,
      counterpartyName: '對象',
      principalAmount: 1000,
      dueAt: DateTime(2026, 3, 1),
      note: '備註',
    );

    await repo.updateDebt(id, clearDueAt: true, clearNote: true);

    final debt = await repo.getDebt(id);
    expect(debt!.dueAt, isNull);
    expect(debt.note, isNull);
  });

  test('updateDebt 不能改本金/方向(接口本身不提供這兩個參數)', () async {
    final lid = await seedLedger();
    final id = await repo.createDebt(
      ledgerId: lid,
      direction: kDebtDirectionPayable,
      counterpartyName: '對象',
      principalAmount: 1000,
    );

    await repo.updateDebt(id, counterpartyName: '新名字');

    final debt = await repo.getDebt(id);
    expect(debt!.principalAmount, 1000);
    expect(debt.direction, kDebtDirectionPayable);
    expect(debt.counterpartyName, '新名字');
  });

  test('getNetDebtBalance:receivable 為正、payable 為負,closed 不計入', () async {
    final lid = await seedLedger();

    await repo.createDebt(
      ledgerId: lid,
      direction: kDebtDirectionReceivable,
      counterpartyName: 'A',
      principalAmount: 300,
    );
    await repo.createDebt(
      ledgerId: lid,
      direction: kDebtDirectionPayable,
      counterpartyName: 'B',
      principalAmount: 100,
    );
    final closedId = await repo.createDebt(
      ledgerId: lid,
      direction: kDebtDirectionPayable,
      counterpartyName: 'C(已結案)',
      principalAmount: 500,
    );
    await repo.closeDebt(closedId);

    final net = await repo.getNetDebtBalance(lid);
    expect(net, 200, reason: '300(receivable) - 100(payable),closed 的 500 不計入');
  });

  test('getDebtBalancesByLedgerForAllLedgers 跨帳本聚合', () async {
    final lid1 = await seedLedger();
    final lid2 = await seedLedger();

    await repo.createDebt(
      ledgerId: lid1,
      direction: kDebtDirectionReceivable,
      counterpartyName: 'A',
      principalAmount: 100,
    );
    await repo.createDebt(
      ledgerId: lid2,
      direction: kDebtDirectionPayable,
      counterpartyName: 'B',
      principalAmount: 50,
    );

    final balances = await repo.getDebtBalancesByLedgerForAllLedgers();
    final byLedger = {for (final b in balances) b.ledgerId: b};

    expect(byLedger[lid1]!.receivableRemaining, 100);
    expect(byLedger[lid1]!.payableRemaining, 0);
    expect(byLedger[lid2]!.receivableRemaining, 0);
    expect(byLedger[lid2]!.payableRemaining, 50);
  });
}
