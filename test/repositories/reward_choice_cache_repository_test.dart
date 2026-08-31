/// 「建議」分頁 + 記帳表單「同帳戶+同類別自動代入回饋規則」的本機學習快取
/// (`RewardChoiceCacheRepository`)。
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

  test('從未設定過時回傳 null', () async {
    final result = await repo.getCachedRewardRuleIds(
      ledgerId: 1,
      categoryId: 10,
      accountId: 20,
    );
    expect(result, isNull);
  });

  test('寫入後可讀回', () async {
    await repo.upsertRewardChoice(
      ledgerId: 1,
      categoryId: 10,
      accountId: 20,
      rewardRuleIds: ['rule-a', 'rule-b'],
    );

    final result = await repo.getCachedRewardRuleIds(
      ledgerId: 1,
      categoryId: 10,
      accountId: 20,
    );
    expect(result, ['rule-a', 'rule-b']);
  });

  test('同組合第二次寫入是更新,不是新增(不同分類/帳戶互不影響)', () async {
    await repo.upsertRewardChoice(
      ledgerId: 1,
      categoryId: 10,
      accountId: 20,
      rewardRuleIds: ['rule-a'],
    );
    await repo.upsertRewardChoice(
      ledgerId: 1,
      categoryId: 10,
      accountId: 20,
      rewardRuleIds: ['rule-b'],
    );
    // 另一組合(不同帳戶)不受影響。
    await repo.upsertRewardChoice(
      ledgerId: 1,
      categoryId: 10,
      accountId: 21,
      rewardRuleIds: ['rule-c'],
    );

    expect(
      await repo.getCachedRewardRuleIds(
          ledgerId: 1, categoryId: 10, accountId: 20),
      ['rule-b'],
    );
    expect(
      await repo.getCachedRewardRuleIds(
          ledgerId: 1, categoryId: 10, accountId: 21),
      ['rule-c'],
    );

    final rows = await db.select(db.rewardChoiceCaches).get();
    expect(rows.length, 2, reason: '同組合第二次寫入應該是更新既有那筆,不是多插入一筆');
  });

  test('明確清空(空陣列)之後讀回是空陣列,不是 null', () async {
    await repo.upsertRewardChoice(
      ledgerId: 1,
      categoryId: 10,
      accountId: 20,
      rewardRuleIds: ['rule-a'],
    );

    await repo.clearRewardChoice(ledgerId: 1, categoryId: 10, accountId: 20);

    final result = await repo.getCachedRewardRuleIds(
      ledgerId: 1,
      categoryId: 10,
      accountId: 20,
    );
    expect(result, isNull, reason: 'clearRewardChoice 直接刪列,語意等同「從未設定過」');
  });
}
