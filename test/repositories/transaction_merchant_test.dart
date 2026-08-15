/// 交易「商家」欄位(v33 新增,`Transactions.merchant`)往返測試。
///
/// 覆蓋:
/// - `addTransaction` 寫入的 merchant 能透過 `getTransactionById` 讀回。
/// - `updateTransaction` 能更新既有 merchant,也能顯式傳 `null` 清空(跟
///   `note` 同一套語意)。
/// - `EntitySerializer.serializeTransaction` 恒帶 `merchant` 鍵(push payload
///   契約,BeeCount Cloud 的 `_LEDGER_MERGE_SPECS["transaction"]` 已有對應
///   `("merchant","merchant")`,鍵名不能改)。
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/cloud/sync/entity_serializer.dart';

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

  test('addTransaction 寫入的 merchant 能讀回', () async {
    final lid = await repo.createLedger(name: 'L');
    final cat = await repo.createCategory(name: '餐饮', kind: 'expense');

    final txId = await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 88,
      categoryId: cat,
      happenedAt: DateTime(2026, 8, 15),
      merchant: '全家便利商店',
    );

    final tx = await repo.getTransactionById(txId);
    expect(tx?.merchant, '全家便利商店');
  });

  test('updateTransaction 能更新 merchant,顯式傳 null 會清空', () async {
    final lid = await repo.createLedger(name: 'L');
    final cat = await repo.createCategory(name: '餐饮', kind: 'expense');

    final txId = await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 88,
      categoryId: cat,
      happenedAt: DateTime(2026, 8, 15),
      merchant: '星巴克',
    );

    await repo.updateTransaction(
      id: txId,
      type: 'expense',
      amount: 88,
      merchant: '路易莎咖啡',
    );
    var tx = await repo.getTransactionById(txId);
    expect(tx?.merchant, '路易莎咖啡');

    await repo.updateTransaction(
      id: txId,
      type: 'expense',
      amount: 88,
      merchant: null,
    );
    tx = await repo.getTransactionById(txId);
    expect(tx?.merchant, isNull);
  });

  test('serializeTransaction 恒帶 merchant 鍵(push payload 契約)', () async {
    final lid = await repo.createLedger(name: 'L');
    final cat = await repo.createCategory(name: '餐饮', kind: 'expense');
    final txId = await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 88,
      categoryId: cat,
      happenedAt: DateTime(2026, 8, 15),
      merchant: '全聯',
    );
    final tx = (await repo.getTransactionById(txId))!;

    final payload = EntitySerializer.serializeTransaction(tx);
    expect(payload.containsKey('merchant'), isTrue);
    expect(payload['merchant'], '全聯');

    final txNoMerchant = (await repo.getTransactionById(await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 10,
      categoryId: cat,
      happenedAt: DateTime(2026, 8, 15),
    )))!;
    final payload2 = EntitySerializer.serializeTransaction(txNoMerchant);
    // 没传 merchant 时是 null,但键必须仍在(恒发,跟 note 同款——省略 vs
    // 显式 null 在 server merge 语意不同,详见 entity_serializer.dart 注释)。
    expect(payload2.containsKey('merchant'), isTrue);
    expect(payload2['merchant'], isNull);
  });
}
