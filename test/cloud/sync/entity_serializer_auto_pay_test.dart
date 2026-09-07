import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/cloud/sync/entity_serializer.dart';

void main() {
  late BeeDatabase db;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  test('serializeAccount 帶有 autoPayEnabled/autoPayFromAccountId 時原樣送出',
      () async {
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    final id = await db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: 1,
          name: '大戶信用卡',
          type: const d.Value('credit_card'),
          syncId: const d.Value('acc-sync-1'),
          autoPayEnabled: const d.Value(true),
          autoPayFromAccountId: const d.Value('src-sync-1'),
        ));
    final account = await (db.select(db.accounts)
          ..where((a) => a.id.equals(id)))
        .getSingle();

    final payload = EntitySerializer.serializeAccount(account);
    expect(payload['autoPayEnabled'], true);
    expect(payload['autoPayFromAccountId'], 'src-sync-1');
  });

  test(
      'serializeAccount 未開自動扣繳時 autoPayEnabled=false 且來源送出空字串(跟其它清除語意欄位一致的無條件送出慣例)',
      () async {
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    final id = await db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: 1,
          name: '大戶信用卡',
          type: const d.Value('credit_card'),
          syncId: const d.Value('acc-sync-2'),
        ));
    final account = await (db.select(db.accounts)
          ..where((a) => a.id.equals(id)))
        .getSingle();

    final payload = EntitySerializer.serializeAccount(account);
    expect(payload['autoPayEnabled'], false);
    expect(payload['autoPayFromAccountId'], '');
  });
}
