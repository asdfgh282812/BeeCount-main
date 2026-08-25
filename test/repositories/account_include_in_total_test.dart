/// 帳戶「不納入總餘額」(account.includeInTotal) — Repository 层测试。
///
/// 跟 test/repositories/account_hidden_test.dart 的 D1「隐藏不影响总额」反向
/// 断言正好相反：includeInTotal=false 的账户**应该**从总额类统计里被排除，
/// 但仍正常出现在 getAllAccounts() / 合併帳單主卡子卡加总的收支口径里。
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

  test('createAccount 默认 includeInTotal=true(=納入)', () async {
    final lid = await repo.createLedger(name: 'L');
    final aid = await repo.createAccount(ledgerId: lid, name: 'A');
    final a = await repo.getAccount(aid);
    expect(a!.includeInTotal, true);
  });

  test('updateAccount(id, includeInTotal: false) 落值且记 change', () async {
    final tracker = ChangeTracker(db);
    final trackedRepo = LocalRepository(db, changeTracker: tracker);
    final lid = await trackedRepo.createLedger(name: 'L');
    final aid = await trackedRepo.createAccount(
        ledgerId: lid, name: 'A', syncId: 'ax-incl-1');

    await trackedRepo.updateAccount(aid, includeInTotal: false);

    final a = await trackedRepo.getAccount(aid);
    expect(a!.includeInTotal, false);

    final changes = await (db.select(db.localChanges)
          ..where((c) => c.entityType.equals('account'))
          ..where((c) => c.entitySyncId.equals('ax-incl-1'))
          ..where((c) => c.action.equals('update')))
        .get();
    expect(changes, isNotEmpty,
        reason: '不納入總餘額必须走会记 change 的 updateAccount,否则不会 push 到云端');
  });

  test('updateAccount 只改 name 时,includeInTotal 不被动(absent 保护)',
      () async {
    final lid = await repo.createLedger(name: 'L');
    final aid = await repo.createAccount(ledgerId: lid, name: 'A');
    await repo.updateAccount(aid, includeInTotal: false);
    await repo.updateAccount(aid, name: 'A2'); // 不传 includeInTotal
    final a = await repo.getAccount(aid);
    expect(a!.includeInTotal, false); // 未被抹
    expect(a.name, 'A2');
  });

  test('includeInTotal=false 的账户从 getNetWorthBreakdown 排除', () async {
    final lid = await repo.createLedger(name: 'L');
    await repo.createAccount(ledgerId: lid, name: 'A', initialBalance: 1000);
    final excludedId = await repo.createAccount(
        ledgerId: lid, name: 'B', initialBalance: 500);

    final before = await repo.getNetWorthBreakdown();

    await repo.updateAccount(excludedId, includeInTotal: false);
    final after = await repo.getNetWorthBreakdown();

    expect(after.totalAssets, before.totalAssets - 500,
        reason: '不納入總餘額的账户应从总资产里排除');
    expect(after.netWorth, before.netWorth - 500);
  });

  test('includeInTotal=false 的账户从 getAssetCompositionByType 排除',
      () async {
    final lid = await repo.createLedger(name: 'L');
    await repo.createAccount(
        ledgerId: lid, name: 'A', type: 'cash', initialBalance: 1000);
    final excludedId = await repo.createAccount(
        ledgerId: lid, name: 'B', type: 'cash', initialBalance: 500);

    final before = await repo.getAssetCompositionByType();
    final beforeCash =
        before.firstWhere((e) => e.type == 'cash').totalBalance;

    await repo.updateAccount(excludedId, includeInTotal: false);
    final after = await repo.getAssetCompositionByType();
    final afterCash = after.firstWhere((e) => e.type == 'cash').totalBalance;

    expect(afterCash, beforeCash - 500, reason: '不納入總餘額的账户应从资产构成里排除');
  });

  test('includeInTotal=false 的账户仍正常出现在 getAllAccounts()', () async {
    final lid = await repo.createLedger(name: 'L');
    final excludedId = await repo.createAccount(ledgerId: lid, name: 'B');
    await repo.updateAccount(excludedId, includeInTotal: false);

    final all = await repo.getAllAccounts();
    expect(all.map((a) => a.id), contains(excludedId),
        reason: '不納入總餘額只影响总额统计,账户本身仍应正常出现在清单里');
  });
}
