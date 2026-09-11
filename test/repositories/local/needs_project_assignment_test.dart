// 「待確認專案」(v59 needs_project_assignment,design 2026-09-11)Repository 層
// 測試:addTransaction 打旗標後可透過 getTransactionsNeedingProjectAssignment
// 查到,setTransactionProjectAssignment 補選專案後旗標清空、不再出現在清單裡;
// 補選「不指定專案」(projectSyncId: null)同樣算完成,清空旗標。

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

  test(
      'addTransaction with needsProjectAssignment:true is queryable and clearable',
      () async {
    final lid = await repo.createLedger(name: 'L', currency: 'CNY');
    final txId = await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 42,
      happenedAt: DateTime(2026, 1, 1),
      needsProjectAssignment: true,
    );

    var pending = await repo.getTransactionsNeedingProjectAssignment(lid);
    expect(pending.map((t) => t.id), contains(txId));

    final projectId = await repo.createProject(ledgerId: lid, name: '日本旅行');
    final project = await repo.getProject(projectId);
    await repo.setTransactionProjectAssignment(
        id: txId, projectSyncId: project!.syncId);

    pending = await repo.getTransactionsNeedingProjectAssignment(lid);
    expect(pending.map((t) => t.id), isNot(contains(txId)));
    final updated = await repo.getTransactionById(txId);
    expect(updated!.projectSyncId, project.syncId);
    expect(updated.needsProjectAssignment, false);
  });

  test('setTransactionProjectAssignment(projectSyncId: null) 明確選「不指定」也清空旗標',
      () async {
    final lid = await repo.createLedger(name: 'L', currency: 'CNY');
    final txId = await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 42,
      happenedAt: DateTime(2026, 1, 1),
      needsProjectAssignment: true,
    );

    await repo.setTransactionProjectAssignment(id: txId, projectSyncId: null);

    final updated = await repo.getTransactionById(txId);
    expect(updated!.projectSyncId, isNull);
    expect(updated.needsProjectAssignment, false);
    final pending = await repo.getTransactionsNeedingProjectAssignment(lid);
    expect(pending.map((t) => t.id), isNot(contains(txId)));
  });
}
