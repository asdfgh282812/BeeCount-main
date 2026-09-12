/// 帳戶頁面單帳戶金額隱藏(account.hideAmount) — Repository 层测试。
///
/// 跟 test/repositories/account_include_in_total_test.dart 同款范式,但断言
/// 方向不同:hideAmount 纯粹是帳戶頁面該列數字的顯示與否,不影响任何金額
/// 计算/加总(見 docs/superpowers/specs/
/// 2026-09-13-account-hide-amount-design.md),所以这里钉住的是「设了
/// hideAmount 之后,总额类统计完全不变」。
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

  test('createAccount 默认 hideAmount=false(金額不隱藏)', () async {
    final lid = await repo.createLedger(name: 'L');
    final aid = await repo.createAccount(ledgerId: lid, name: 'A');
    final a = await repo.getAccount(aid);
    expect(a!.hideAmount, false);
  });

  test('updateAccount(id, hideAmount: true) 落值且记 change', () async {
    final tracker = ChangeTracker(db);
    final trackedRepo = LocalRepository(db, changeTracker: tracker);
    final lid = await trackedRepo.createLedger(name: 'L');
    final aid = await trackedRepo.createAccount(
        ledgerId: lid, name: 'A', syncId: 'ax-hideamt-1');

    await trackedRepo.updateAccount(aid, hideAmount: true);

    final a = await trackedRepo.getAccount(aid);
    expect(a!.hideAmount, true);

    final changes = await (db.select(db.localChanges)
          ..where((c) => c.entityType.equals('account'))
          ..where((c) => c.entitySyncId.equals('ax-hideamt-1'))
          ..where((c) => c.action.equals('update')))
        .get();
    expect(changes, isNotEmpty,
        reason: '單帳戶金額隱藏必须走会记 change 的 updateAccount,否则不会 push 到云端');
  });

  test('setAccountHideAmount 便捷法等同 updateAccount(hideAmount:)', () async {
    final lid = await repo.createLedger(name: 'L');
    final aid = await repo.createAccount(ledgerId: lid, name: 'A');

    await repo.setAccountHideAmount(aid, true);
    var a = await repo.getAccount(aid);
    expect(a!.hideAmount, true);

    await repo.setAccountHideAmount(aid, false);
    a = await repo.getAccount(aid);
    expect(a!.hideAmount, false);
  });

  test('updateAccount 只改 name 时,hideAmount 不被动(absent 保护)', () async {
    final lid = await repo.createLedger(name: 'L');
    final aid = await repo.createAccount(ledgerId: lid, name: 'A');
    await repo.updateAccount(aid, hideAmount: true);
    await repo.updateAccount(aid, name: 'A2'); // 不传 hideAmount
    final a = await repo.getAccount(aid);
    expect(a!.hideAmount, true); // 未被抹
    expect(a.name, 'A2');
  });

  test('hideAmount=true 的账户仍正常出现在 getAllAccounts()', () async {
    final lid = await repo.createLedger(name: 'L');
    final aid = await repo.createAccount(ledgerId: lid, name: 'B');
    await repo.updateAccount(aid, hideAmount: true);

    final all = await repo.getAllAccounts();
    expect(all.map((a) => a.id), contains(aid),
        reason: '單帳戶金額隱藏只影响帳戶頁面該列顯示,账户本身仍应正常出现在清单里');
  });

  test('hideAmount 不影响 getNetWorthBreakdown / getAssetCompositionByType',
      () async {
    final lid = await repo.createLedger(name: 'L');
    await repo.createAccount(
        ledgerId: lid, name: 'A', type: 'cash', initialBalance: 1000);
    final targetId = await repo.createAccount(
        ledgerId: lid, name: 'B', type: 'cash', initialBalance: 500);

    final beforeNw = await repo.getNetWorthBreakdown();
    final beforeComp = await repo.getAssetCompositionByType();
    final beforeCash =
        beforeComp.firstWhere((e) => e.type == 'cash').totalBalance;

    await repo.updateAccount(targetId, hideAmount: true);

    final afterNw = await repo.getNetWorthBreakdown();
    final afterComp = await repo.getAssetCompositionByType();
    final afterCash =
        afterComp.firstWhere((e) => e.type == 'cash').totalBalance;

    expect(afterNw.totalAssets, beforeNw.totalAssets,
        reason: '單帳戶金額隱藏不该影响总资产计算');
    expect(afterNw.netWorth, beforeNw.netWorth);
    expect(afterCash, beforeCash, reason: '單帳戶金額隱藏不该影响资产构成加总');
  });
}
