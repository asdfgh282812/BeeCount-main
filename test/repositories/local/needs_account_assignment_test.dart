// 「待確認帳戶」(v40 needs_account_assignment)Repository 層測試:
// addTransaction 打旗標後可透過 getTransactionsNeedingAccountAssignment 查到,
// setTransactionAccountAssignment 補選帳戶後旗標清空、不再出現在清單裡。

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

void main() {
  // repo.createAccount 内部会 logger.debug(...),logger 单例首次使用时会
  // 建原生桥接 MethodChannel + 读 SharedPreferences,需要 binding 先初始化
  // 且 mock 好 SharedPreferences(同 debt_repository_test.dart 等既有测试)。
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
  });

  tearDown(() async => db.close());

  test('addTransaction with needsAccountAssignment:true is queryable and clearable', () async {
    final lid = await repo.createLedger(name: 'L', currency: 'CNY');
    final txId = await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 42,
      happenedAt: DateTime(2026, 1, 1),
      needsAccountAssignment: true,
    );

    var pending = await repo.getTransactionsNeedingAccountAssignment(lid);
    expect(pending.map((t) => t.id), contains(txId));

    final accountId = await repo.createAccount(
      ledgerId: 0,
      name: 'Cash',
      type: 'cash',
      currency: 'CNY',
      initialBalance: 0,
    );
    await repo.setTransactionAccountAssignment(id: txId, accountId: accountId);

    pending = await repo.getTransactionsNeedingAccountAssignment(lid);
    expect(pending.map((t) => t.id), isNot(contains(txId)));
    final updated = await repo.getTransactionById(txId);
    expect(updated!.accountId, accountId);
    expect(updated.needsAccountAssignment, false);
  });
}
