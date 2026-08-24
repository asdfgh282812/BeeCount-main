// 借還款(v39)Repository 層測試:狀態推導(open/partial/settled/closed)、
// 刪除守衛(有還款記錄不能刪)、淨欠款餘額計算。
//
// 狀態推導對齐 BeeCount Cloud `routers/read/ledgers.py::list_debts`:
// closedAt 優先於金額判斷(可以在未還清時手動結案)。

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/debt_repository.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

void main() {
  // repo.createAccount 内部会 logger.debug(...),logger 单例首次使用时会
  // 建原生桥接 MethodChannel + 读 SharedPreferences,需要 binding 先初始化
  // 且 mock 好 SharedPreferences(同 account_hidden_test.dart 等既有测试)。
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

  test('createDebtWithOriginTransaction creates both rows atomically, linked one-way via originTransactionSyncId', () async {
    final ledgerId = await repo.createLedger(name: 'L', currency: 'CNY');
    final accountId = await repo.createAccount(
      ledgerId: 0,
      name: 'Cash',
      type: 'cash',
      currency: 'CNY',
      initialBalance: 0,
    );

    final debtId = await repo.createDebtWithOriginTransaction(
      ledgerId: ledgerId,
      direction: kDebtDirectionPayable,
      counterpartyName: 'Alice',
      principalAmount: 500,
      accountId: accountId,
    );

    final debt = await repo.getDebt(debtId);
    expect(debt, isNotNull);
    expect(debt!.principalAmount, 500);

    final txs = await repo.getTransactionsByLedger(ledgerId);
    expect(txs, hasLength(1));
    expect(txs.first.type, 'income'); // payable = 我欠款 = 帳戶餘額 +本金
    expect(txs.first.amount, 500);
    expect(txs.first.accountId, accountId);
    // 起點交易不與欠款連結(不打 debtSyncId,避免污染還款金額加總,見
    // A.2),但反過來欠款會記住起點交易的 syncId,見下方
    // getDebtByOriginTransactionSyncId 測試。
    expect(txs.first.debtSyncId, isNull);
    expect(debt.originTransactionSyncId, txs.first.syncId);
    expect(debt.originTransactionSyncId, isNotNull);

    final balance = await repo.getAccountBalance(accountId);
    expect(balance, 500);
  });

  test('getDebtByOriginTransactionSyncId 能反查回起點交易對應的欠款', () async {
    final ledgerId = await repo.createLedger(name: 'L3', currency: 'CNY');
    final accountId = await repo.createAccount(
      ledgerId: 0,
      name: 'Cash3',
      type: 'cash',
      currency: 'CNY',
      initialBalance: 0,
    );

    final debtId = await repo.createDebtWithOriginTransaction(
      ledgerId: ledgerId,
      direction: kDebtDirectionPayable,
      counterpartyName: 'Carol',
      principalAmount: 200,
      accountId: accountId,
    );
    final debt = (await repo.getDebt(debtId))!;
    final originTx = (await repo.getTransactionsByLedger(ledgerId)).single;

    final found =
        await repo.getDebtByOriginTransactionSyncId(originTx.syncId!);
    expect(found, isNotNull);
    expect(found!.id, debtId);

    // 一筆普通(非起點)交易的 syncId 不該反查到任何欠款。
    final notFound = await repo.getDebtByOriginTransactionSyncId('unrelated');
    expect(notFound, isNull);

    // 還款交易帶的是 debtSyncId,不是 originTransactionSyncId——反查不該
    // 命中,兩個欄位語意不能混。
    await repo.addTransaction(
      ledgerId: ledgerId,
      type: 'expense',
      amount: 50,
      accountId: accountId,
      happenedAt: DateTime.now(),
      debtSyncId: debt.syncId,
    );
    final repaymentTx = (await repo.getTransactionsByLedger(ledgerId))
        .firstWhere((t) => t.debtSyncId != null);
    final foundByRepayment =
        await repo.getDebtByOriginTransactionSyncId(repaymentTx.syncId!);
    expect(foundByRepayment, isNull);
  });

  test('createDebtWithOriginTransaction/updateDebt 能設定與清除 categoryId', () async {
    final ledgerId = await repo.createLedger(name: 'L4', currency: 'CNY');
    final accountId = await repo.createAccount(
      ledgerId: 0,
      name: 'Cash4',
      type: 'cash',
      currency: 'CNY',
      initialBalance: 0,
    );
    final categoryId = await repo.createCategory(
      name: '借還款',
      kind: 'income',
      icon: 'default',
    );

    final debtId = await repo.createDebtWithOriginTransaction(
      ledgerId: ledgerId,
      direction: kDebtDirectionPayable,
      counterpartyName: 'Dave',
      principalAmount: 100,
      accountId: accountId,
      categoryId: categoryId,
    );
    var debt = (await repo.getDebt(debtId))!;
    expect(debt.categoryId, categoryId);
    var originTx =
        (await repo.getTransactionBySyncId(debt.originTransactionSyncId!))!;
    expect(originTx.categoryId, categoryId,
        reason: '起點交易的分類要跟 Debts.categoryId 連動,否則交易列表/明細卡看到的還是未分類');

    await repo.updateDebt(debtId, clearCategoryId: true);
    debt = (await repo.getDebt(debtId))!;
    expect(debt.categoryId, isNull);
    originTx =
        (await repo.getTransactionBySyncId(debt.originTransactionSyncId!))!;
    expect(originTx.categoryId, isNull,
        reason: '清空 debt 分類也要連動清空起點交易的分類');
  });

  test('createDebtWithOriginTransaction: receivable direction creates an expense', () async {
    final ledgerId = await repo.createLedger(name: 'L2', currency: 'CNY');
    final accountId = await repo.createAccount(
      ledgerId: 0,
      name: 'Cash2',
      type: 'cash',
      currency: 'CNY',
      initialBalance: 0,
    );

    await repo.createDebtWithOriginTransaction(
      ledgerId: ledgerId,
      direction: kDebtDirectionReceivable,
      counterpartyName: 'Bob',
      principalAmount: 300,
      accountId: accountId,
    );

    final txs = await repo.getTransactionsByLedger(ledgerId);
    expect(txs.first.type, 'expense'); // receivable = 款項應收 = 帳戶餘額 -本金
    final balance = await repo.getAccountBalance(accountId);
    expect(balance, -300);
  });

  test('renameCounterparty 一次改名同一帳本下所有同名記錄', () async {
    final lid = await seedLedger();
    final id1 = await repo.createDebt(
      ledgerId: lid,
      direction: kDebtDirectionPayable,
      counterpartyName: '小明',
      principalAmount: 100,
    );
    final id2 = await repo.createDebt(
      ledgerId: lid,
      direction: kDebtDirectionReceivable,
      counterpartyName: '小明',
      principalAmount: 200,
    );
    // 別的帳本裡同名的記錄不該被動到。
    final otherLedger = await seedLedger();
    final idOther = await repo.createDebt(
      ledgerId: otherLedger,
      direction: kDebtDirectionPayable,
      counterpartyName: '小明',
      principalAmount: 300,
    );
    // 同帳本、不同名字的記錄也不該被動到。
    final idOtherName = await repo.createDebt(
      ledgerId: lid,
      direction: kDebtDirectionPayable,
      counterpartyName: '小華',
      principalAmount: 400,
    );

    final count = await repo.renameCounterparty(
      ledgerId: lid,
      oldName: '小明',
      newName: '小明(已改名)',
    );
    expect(count, 2);

    expect((await repo.getDebt(id1))!.counterpartyName, '小明(已改名)');
    expect((await repo.getDebt(id2))!.counterpartyName, '小明(已改名)');
    expect((await repo.getDebt(idOther))!.counterpartyName, '小明');
    expect((await repo.getDebt(idOtherName))!.counterpartyName, '小華');
  });

  test('renameCounterparty 找不到符合的名字時回傳 0,不拋錯', () async {
    final lid = await seedLedger();
    final count = await repo.renameCounterparty(
      ledgerId: lid,
      oldName: '不存在的對象',
      newName: '新名字',
    );
    expect(count, 0);
  });

  test('excludedFromTotal 預設為 false,且只影響總額統計不影響清單', () async {
    final lid = await seedLedger();
    final id = await repo.createDebt(
      ledgerId: lid,
      direction: kDebtDirectionReceivable,
      counterpartyName: '對象',
      principalAmount: 1000,
    );
    expect((await repo.getDebt(id))!.excludedFromTotal, isFalse);

    await repo.updateDebt(id, excludedFromTotal: true);
    final debt = await repo.getDebt(id);
    expect(debt!.excludedFromTotal, isTrue);

    // 總額統計要排除它。
    final net = await repo.getNetDebtBalance(lid);
    expect(net, 0, reason: '排除計入總額後不該再貢獻淨欠款餘額');
    final balances = await repo.getDebtBalancesByLedgerForAllLedgers();
    final entry = balances.where((b) => b.ledgerId == lid).toList();
    expect(entry, isEmpty, reason: '這個帳本唯一的欠款被排除,不該出現在總額聚合裡');

    // 清單/狀態查詢仍要照常顯示。
    final withStatus = await repo.getDebtsWithStatus(lid);
    expect(withStatus, hasLength(1));
    expect(withStatus.first.debt.id, id);
  });

  test('刪除起點交易且無還款記錄 → 欠款一併被刪除', () async {
    final ledgerId = await repo.createLedger(name: 'L', currency: 'CNY');
    final accountId = await repo.createAccount(
      ledgerId: 0,
      name: 'Cash',
      type: 'cash',
      currency: 'CNY',
      initialBalance: 0,
    );
    final debtId = await repo.createDebtWithOriginTransaction(
      ledgerId: ledgerId,
      direction: kDebtDirectionPayable,
      counterpartyName: 'Dave',
      principalAmount: 500,
      accountId: accountId,
    );
    final originTx = (await repo.getTransactionsByLedger(ledgerId)).single;

    await repo.deleteTransaction(originTx.id);

    expect(await repo.getDebt(debtId), isNull,
        reason: '起點交易被刪、又沒有任何還款記錄,這筆欠款已經沒有交易佐證,'
            '欠款管理頁面上的紀錄應該一併清掉');
  });

  test('刪除起點交易但已有還款記錄 → 欠款保留(守衛擋住,不誤刪有記錄的欠款)', () async {
    final ledgerId = await repo.createLedger(name: 'L2', currency: 'CNY');
    final accountId = await repo.createAccount(
      ledgerId: 0,
      name: 'Cash2',
      type: 'cash',
      currency: 'CNY',
      initialBalance: 0,
    );
    final debtId = await repo.createDebtWithOriginTransaction(
      ledgerId: ledgerId,
      direction: kDebtDirectionPayable,
      counterpartyName: 'Erin',
      principalAmount: 500,
      accountId: accountId,
    );
    final debt = (await repo.getDebt(debtId))!;
    await repo.addTransaction(
      ledgerId: ledgerId,
      type: 'expense',
      amount: 100,
      happenedAt: DateTime(2026, 1, 1),
      accountId: accountId,
      debtSyncId: debt.syncId,
    );
    final originTx = (await repo.getTransactionsByLedger(ledgerId))
        .firstWhere((t) => t.debtSyncId == null);

    await repo.deleteTransaction(originTx.id);

    expect(await repo.getDebt(debtId), isNotNull,
        reason: '已有還款記錄的欠款不該被刪交易連帶誤刪,跟主動刪欠款的'
            'DEBT_HAS_REPAYMENTS 守衛是同一條規則');
  });

  test('刪除還款交易(非起點)不影響欠款本身', () async {
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
    final repaymentTx = (await repo.getTransactionsByLedger(lid)).single;

    await repo.deleteTransaction(repaymentTx.id);

    expect(await repo.getDebt(id), isNotNull,
        reason: '刪的是還款交易,不是起點交易,欠款本身應該照常保留');
  });
}
