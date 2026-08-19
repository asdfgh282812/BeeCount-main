// v38 拆帳(split transaction)repository 层契约测试:
// - addTransaction/updateTransaction 传 splits 时,主表 hasSplits/categoryId
//   与 TransactionSplits 子表的写入行为
// - splits=null(不传)/ []( 显式清空,还原成单一分类)/ 非空(整组替换) 三态语义
// - deleteTransaction 级联删除拆帳明細

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/data/repositories/transaction_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
  });

  tearDown(() async => db.close());

  Future<int> addCategory(String name) =>
      repo.createCategory(name: name, kind: 'expense');

  test('addTransaction 带 splits:主表 hasSplits=true 且 categoryId=null,明細按序写入', () async {
    final food = await addCategory('餐饮');
    final cloth = await addCategory('衣物');

    final id = await repo.addTransaction(
      ledgerId: 1,
      type: 'expense',
      amount: 100,
      categoryId: food, // 有 splits 时应被忽略/强制清空
      happenedAt: DateTime(2026, 8, 1),
      splits: [
        TransactionSplitInput(categoryId: food, amount: 60, note: '午饭'),
        TransactionSplitInput(categoryId: cloth, amount: 40),
      ],
    );

    final tx = await repo.getTransactionById(id);
    expect(tx!.hasSplits, isTrue);
    expect(tx.categoryId, isNull);
    expect(tx.amount, 100);

    final splits = await repo.getTransactionSplits(id);
    expect(splits.length, 2);
    expect(splits[0].categoryId, food);
    expect(splits[0].amount, 60);
    expect(splits[0].note, '午饭');
    expect(splits[0].sortOrder, 0);
    expect(splits[1].categoryId, cloth);
    expect(splits[1].amount, 40);
    expect(splits[1].sortOrder, 1);
  });

  test('addTransaction 不带 splits(null):行为跟原本单分类交易一致', () async {
    final food = await addCategory('餐饮');
    final id = await repo.addTransaction(
      ledgerId: 1,
      type: 'expense',
      amount: 50,
      categoryId: food,
      happenedAt: DateTime(2026, 8, 1),
    );

    final tx = await repo.getTransactionById(id);
    expect(tx!.hasSplits, isFalse);
    expect(tx.categoryId, food);
    expect(await repo.getTransactionSplits(id), isEmpty);
  });

  test('updateTransaction 传非空 splits:整组替换旧明細,主表转为拆帳状态', () async {
    final a = await addCategory('A');
    final b = await addCategory('B');
    final c = await addCategory('C');

    final id = await repo.addTransaction(
      ledgerId: 1,
      type: 'expense',
      amount: 30,
      categoryId: a,
      happenedAt: DateTime(2026, 8, 1),
    );

    await repo.updateTransaction(
      id: id,
      type: 'expense',
      amount: 90,
      categoryId: null,
      happenedAt: DateTime(2026, 8, 1),
      splits: [
        TransactionSplitInput(categoryId: b, amount: 50),
        TransactionSplitInput(categoryId: c, amount: 40),
      ],
    );

    final tx = await repo.getTransactionById(id);
    expect(tx!.hasSplits, isTrue);
    expect(tx.categoryId, isNull);
    expect(tx.amount, 90);
    final splits = await repo.getTransactionSplits(id);
    expect(splits.map((s) => s.categoryId), [b, c]);

    // 再次替换:旧明細应被整组删除重建,不是追加
    await repo.updateTransaction(
      id: id,
      type: 'expense',
      amount: 90,
      categoryId: null,
      happenedAt: DateTime(2026, 8, 1),
      splits: [TransactionSplitInput(categoryId: a, amount: 90)],
    );
    final splits2 = await repo.getTransactionSplits(id);
    expect(splits2.length, 1);
    expect(splits2.single.categoryId, a);
  });

  test('updateTransaction 传空列表 splits:還原成單一分類,清空明細与 hasSplits', () async {
    final a = await addCategory('A');
    final b = await addCategory('B');

    final id = await repo.addTransaction(
      ledgerId: 1,
      type: 'expense',
      amount: 100,
      happenedAt: DateTime(2026, 8, 1),
      splits: [
        TransactionSplitInput(categoryId: a, amount: 60),
        TransactionSplitInput(categoryId: b, amount: 40),
      ],
    );

    await repo.updateTransaction(
      id: id,
      type: 'expense',
      amount: 100,
      categoryId: a, // 还原后生效的单一分类
      happenedAt: DateTime(2026, 8, 1),
      splits: const [],
    );

    final tx = await repo.getTransactionById(id);
    expect(tx!.hasSplits, isFalse);
    expect(tx.categoryId, a);
    expect(await repo.getTransactionSplits(id), isEmpty);
  });

  test('updateTransaction 不传 splits(null):不动既有拆帳明細/状态', () async {
    final a = await addCategory('A');
    final b = await addCategory('B');
    final id = await repo.addTransaction(
      ledgerId: 1,
      type: 'expense',
      amount: 100,
      happenedAt: DateTime(2026, 8, 1),
      splits: [
        TransactionSplitInput(categoryId: a, amount: 60),
        TransactionSplitInput(categoryId: b, amount: 40),
      ],
    );

    // 只改备注,不碰 splits
    await repo.updateTransaction(
      id: id,
      type: 'expense',
      amount: 100,
      categoryId: null,
      note: '改备注',
      happenedAt: DateTime(2026, 8, 1),
    );

    final tx = await repo.getTransactionById(id);
    expect(tx!.hasSplits, isTrue);
    expect(tx.note, '改备注');
    expect((await repo.getTransactionSplits(id)).length, 2);
  });

  test('deleteTransaction 级联删除拆帳明細', () async {
    final a = await addCategory('A');
    final b = await addCategory('B');
    final id = await repo.addTransaction(
      ledgerId: 1,
      type: 'expense',
      amount: 100,
      happenedAt: DateTime(2026, 8, 1),
      splits: [
        TransactionSplitInput(categoryId: a, amount: 60),
        TransactionSplitInput(categoryId: b, amount: 40),
      ],
    );

    await repo.deleteTransaction(id);

    expect(await repo.getTransactionById(id), isNull);
    expect(await repo.getTransactionSplits(id), isEmpty);
  });
}
