/// 帳戶「調整總額」— `LocalRepository.createAdjustmentTransaction` 回歸測試。
///
/// 覆蓋:
/// - 建出來的交易 `type='adjustment'`、金額等於呼叫方傳入的差額。
/// - 必須走會記 change 的路徑(2026-08-28 修 bug 前直接委托底層
///   `_transactionRepo.createAdjustmentTransaction`,跳過 `ChangeTracker`,
///   建出來的調整交易永遠不會 push 上雲端)。
/// - 調整交易照樣被計入 `getAccountBalance`。
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/cloud/sync/change_tracker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  test('createAdjustmentTransaction 记 change(否则调整不会同步上云端)', () async {
    final tracker = ChangeTracker(db);
    final repo = LocalRepository(db, changeTracker: tracker);
    final lid = await repo.createLedger(name: 'L');
    final aid = await repo.createAccount(
        ledgerId: lid, name: 'A', syncId: 'ax-adjustment-1');

    await repo.createAdjustmentTransaction(
      ledgerId: lid,
      accountId: aid,
      amount: 123.45,
      happenedAt: DateTime(2026, 8, 28),
      note: '餘額調整',
    );

    final changes = await (db.select(db.localChanges)
          ..where((c) => c.entityType.equals('transaction')))
        .get();
    expect(changes, isNotEmpty, reason: '调整交易必须走会记 change 的路径,否则不会 push 到云端');
  });

  test('createAdjustmentTransaction 建出的交易 type=adjustment 且计入余额', () async {
    final repo = LocalRepository(db);
    final lid = await repo.createLedger(name: 'L');
    final aid = await repo.createAccount(ledgerId: lid, name: 'A');

    await repo.createAdjustmentTransaction(
      ledgerId: lid,
      accountId: aid,
      amount: 50,
      happenedAt: DateTime(2026, 8, 28),
    );

    final txs = await (db.select(db.transactions)
          ..where((t) => t.accountId.equals(aid)))
        .get();
    expect(txs, hasLength(1));
    expect(txs.single.type, 'adjustment');

    final balance = await repo.getAccountBalance(aid);
    expect(balance, 50);
  });
}
