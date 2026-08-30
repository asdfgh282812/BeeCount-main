import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await db.into(db.ledgers).insert(
        LedgersCompanion.insert(name: 'L', currency: const d.Value('TWD')));
  });

  tearDown(() async => db.close());

  test('createAccount 不需要 swipesmartCardId 也能建立(YAGNI:建立時通常還沒對照)', () async {
    final id = await repo.createAccount(
      ledgerId: 1,
      name: '大戶信用卡',
      type: 'credit_card',
    );
    final acc = await (db.select(db.accounts)..where((a) => a.id.equals(id)))
        .getSingle();
    expect(acc.swipesmartCardId, isNull);
  });

  test('updateAccount 寫入 swipesmartCardId', () async {
    final id = await repo.createAccount(
      ledgerId: 1,
      name: '大戶信用卡',
      type: 'credit_card',
    );
    await repo.updateAccount(id, swipesmartCardId: 'sw-card-123');
    final acc = await (db.select(db.accounts)..where((a) => a.id.equals(id)))
        .getSingle();
    expect(acc.swipesmartCardId, 'sw-card-123');
  });

  test('clearSwipesmartCardId 清空既有對照', () async {
    final id = await repo.createAccount(
      ledgerId: 1,
      name: '大戶信用卡',
      type: 'credit_card',
    );
    await repo.updateAccount(id, swipesmartCardId: 'sw-card-123');
    await repo.updateAccount(id, clearSwipesmartCardId: true);
    final acc = await (db.select(db.accounts)..where((a) => a.id.equals(id)))
        .getSingle();
    expect(acc.swipesmartCardId, isNull);
  });
}
