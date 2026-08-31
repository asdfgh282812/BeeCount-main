/// 「建議」分頁 + 智慧預設用的 3 個新 repository 查詢:
/// - getCategoryUsageSignals:建議分頁排序演算法的原始訊號來源。
/// - getMostUsedAccountForCategory:依類別靜默代入常用帳戶。
/// - getLastTransferAccounts:轉帳分頁預帶最近用過的兩個帳戶。
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

  group('getCategoryUsageSignals', () {
    test('依 ledgerId+type 過濾,依時間倒序,帶出 accountId/note', () async {
      final lid = await repo.createLedger(name: 'L');
      final otherLid = await repo.createLedger(name: 'L2');
      final cat = await repo.createCategory(name: '餐饮', kind: 'expense');
      final acc = await repo.createAccount(ledgerId: lid, name: 'Cash');

      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 30,
        categoryId: cat,
        accountId: acc,
        note: '午餐',
        happenedAt: DateTime(2026, 1, 1),
      );
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 50,
        categoryId: cat,
        accountId: acc,
        note: '晚餐',
        happenedAt: DateTime(2026, 1, 2),
      );
      // 不同 type,不该混进来。
      await repo.addTransaction(
        ledgerId: lid,
        type: 'income',
        amount: 999,
        categoryId: cat,
        happenedAt: DateTime(2026, 1, 3),
      );
      // 不同帳本,不该混进来。
      await repo.addTransaction(
        ledgerId: otherLid,
        type: 'expense',
        amount: 999,
        categoryId: cat,
        happenedAt: DateTime(2026, 1, 4),
      );

      final signals = await repo.getCategoryUsageSignals(
        ledgerId: lid,
        kind: 'expense',
        since: DateTime(2020, 1, 1),
      );

      expect(signals.length, 2);
      expect(signals.first.note, '晚餐'); // 時間倒序,最新的在前
      expect(signals.first.accountId, acc);
      expect(signals.last.note, '午餐');
    });

    test('since 之前的交易不納入', () async {
      final lid = await repo.createLedger(name: 'L');
      final cat = await repo.createCategory(name: '餐饮', kind: 'expense');
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 30,
        categoryId: cat,
        happenedAt: DateTime(2020, 1, 1),
      );
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 50,
        categoryId: cat,
        happenedAt: DateTime(2026, 1, 1),
      );

      final signals = await repo.getCategoryUsageSignals(
        ledgerId: lid,
        kind: 'expense',
        since: DateTime(2025, 1, 1),
      );

      expect(signals.length, 1);
      expect(signals.single.happenedAt, DateTime(2026, 1, 1));
    });
  });

  group('getMostUsedAccountForCategory', () {
    test('回傳筆數最多的帳戶,同筆數再比最近使用時間', () async {
      final lid = await repo.createLedger(name: 'L');
      final cat = await repo.createCategory(name: '餐饮', kind: 'expense');
      final cash = await repo.createAccount(ledgerId: lid, name: 'Cash');
      final card = await repo.createAccount(ledgerId: lid, name: 'Card');

      for (var i = 0; i < 3; i++) {
        await repo.addTransaction(
          ledgerId: lid,
          type: 'expense',
          amount: 10,
          categoryId: cat,
          accountId: cash,
          happenedAt: DateTime(2026, 1, 1 + i),
        );
      }
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 10,
        categoryId: cat,
        accountId: card,
        happenedAt: DateTime(2026, 2, 1),
      );

      final result = await repo.getMostUsedAccountForCategory(
        ledgerId: lid,
        categoryId: cat,
      );

      expect(result, cash);
    });

    test('沒有歷史紀錄回傳 null', () async {
      final lid = await repo.createLedger(name: 'L');
      final cat = await repo.createCategory(name: '餐饮', kind: 'expense');

      final result = await repo.getMostUsedAccountForCategory(
        ledgerId: lid,
        categoryId: cat,
      );

      expect(result, isNull);
    });
  });

  group('getLastTransferAccounts', () {
    test('回傳最近一筆轉帳的來源/目的帳戶', () async {
      final lid = await repo.createLedger(name: 'L');
      final a = await repo.createAccount(ledgerId: lid, name: 'A');
      final b = await repo.createAccount(ledgerId: lid, name: 'B');
      final c = await repo.createAccount(ledgerId: lid, name: 'C');

      await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 100,
        accountId: a,
        toAccountId: b,
        happenedAt: DateTime(2026, 1, 1),
      );
      await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 200,
        accountId: b,
        toAccountId: c,
        happenedAt: DateTime(2026, 1, 5),
      );

      final result = await repo.getLastTransferAccounts(ledgerId: lid);

      expect(result?.fromAccountId, b);
      expect(result?.toAccountId, c);
    });

    test('沒有轉帳紀錄時回傳 null', () async {
      final lid = await repo.createLedger(name: 'L');
      final result = await repo.getLastTransferAccounts(ledgerId: lid);
      expect(result, isNull);
    });
  });
}
