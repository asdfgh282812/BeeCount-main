/// 帳戶清單拖曳排序(帳戶清單「編輯排序」拖曳功能)— Repository 层测试。
///
/// 覆盖:
/// - `updateAccountSortOrders` 落值(sortOrder 按传入顺序写入)。
/// - `updateAccountSortOrders` 记 user-global change(同步依赖)——这是本次
///   修的坑:原本直接委托 `_accountRepo`,不记 change,拖曳排序永远不会推到
///   云端(见 account_hidden_test.dart 头部注释提到的同一类历史问题)。
/// - 无 changeTracker(未登录同步)时仍能正常落值,不报错。
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/cloud/sync/change_tracker.dart';

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

  test('updateAccountSortOrders 落值(按传入顺序写 sortOrder)', () async {
    final lid = await repo.createLedger(name: 'L');
    final aId = await repo.createAccount(ledgerId: lid, name: 'A');
    final bId = await repo.createAccount(ledgerId: lid, name: 'B');
    final cId = await repo.createAccount(ledgerId: lid, name: 'C');

    await repo.updateAccountSortOrders([
      (id: cId, sortOrder: 0),
      (id: aId, sortOrder: 1),
      (id: bId, sortOrder: 2),
    ]);

    final a = await repo.getAccount(aId);
    final b = await repo.getAccount(bId);
    final c = await repo.getAccount(cId);
    expect(c!.sortOrder, 0);
    expect(a!.sortOrder, 1);
    expect(b!.sortOrder, 2);
  });

  test('updateAccountSortOrders 记 user-global change(拖曳排序必须能同步)', () async {
    final tracker = ChangeTracker(db);
    final trackedRepo = LocalRepository(db, changeTracker: tracker);
    final lid = await trackedRepo.createLedger(name: 'L');
    final aId = await trackedRepo.createAccount(
        ledgerId: lid, name: 'A', syncId: 'ax-sort-1');
    final bId = await trackedRepo.createAccount(
        ledgerId: lid, name: 'B', syncId: 'ax-sort-2');

    await trackedRepo.updateAccountSortOrders([
      (id: bId, sortOrder: 0),
      (id: aId, sortOrder: 1),
    ]);

    for (final syncId in ['ax-sort-1', 'ax-sort-2']) {
      final changes = await (db.select(db.localChanges)
            ..where((c) => c.entityType.equals('account'))
            ..where((c) => c.entitySyncId.equals(syncId))
            ..where((c) => c.action.equals('update')))
          .get();
      expect(changes, isNotEmpty,
          reason:
              '拖曳排序必须走会记 change 的 updateAccountSortOrders,否则新顺序不会 push 到云端');
    }
  });

  test('无 changeTracker 时 updateAccountSortOrders 仍正常落值', () async {
    final lid = await repo.createLedger(name: 'L');
    final aId = await repo.createAccount(ledgerId: lid, name: 'A');

    await repo.updateAccountSortOrders([(id: aId, sortOrder: 5)]);

    final a = await repo.getAccount(aId);
    expect(a!.sortOrder, 5);
  });
}
