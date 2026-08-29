/// v45 跨幣別轉帳 — Repository 层契约(design doc
/// docs/superpowers/specs/2026-08-29-cross-currency-transfers-design.md §5):
///   - addTransaction/updateTransaction 的 toAmount 参数正确写入/更新
///   - 6 处余额计算的转入脚改用 toAmount ?? amount:
///     toAmount 非 null(跨币别)→ 转入账户按 toAmount 计;
///     toAmount 为 null(同币别/旧数据)→ 两边都按 amount 计(既有行为回归)。
import 'package:drift/drift.dart' as d;
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

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

  Future<int> seedLedger({String currency = 'CNY'}) async {
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', '$currency')");
    return 1;
  }

  Future<int> seedAccount(
      {required int id, required String currency, double initial = 0}) async {
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, currency, initial_balance) "
        "VALUES ($id, 1, 'A$id', '$currency', $initial)");
    return id;
  }

  group('addTransaction/updateTransaction 的 toAmount 参数', () {
    test('addTransaction 传 toAmount → 直接写入', () async {
      final lid = await seedLedger();
      final from = await seedAccount(id: 1, currency: 'JPY');
      final to = await seedAccount(id: 2, currency: 'TWD');
      final id = await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 5000,
        accountId: from,
        toAccountId: to,
        happenedAt: DateTime(2026, 8, 29),
        toAmount: 999.87,
      );
      final tx = await repo.getTransactionById(id);
      expect(tx!.toAmount, 999.87);
    });

    test('addTransaction 不传 toAmount → 落 null(同币别/非转账)', () async {
      final lid = await seedLedger();
      final from = await seedAccount(id: 1, currency: 'CNY');
      final id = await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 30,
        accountId: from,
        happenedAt: DateTime(2026, 8, 29),
      );
      final tx = await repo.getTransactionById(id);
      expect(tx!.toAmount, isNull);
    });

    test('updateTransaction 不传 toAmount → 不动既有值', () async {
      final lid = await seedLedger();
      final from = await seedAccount(id: 1, currency: 'JPY');
      final to = await seedAccount(id: 2, currency: 'TWD');
      final id = await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 5000,
        accountId: from,
        toAccountId: to,
        happenedAt: DateTime(2026, 8, 29),
        toAmount: 999.87,
      );
      await repo.updateTransaction(
        id: id,
        type: 'transfer',
        amount: 6000,
        note: '改备注',
        happenedAt: DateTime(2026, 8, 29),
      );
      final tx = await repo.getTransactionById(id);
      expect(tx!.amount, 6000);
      expect(tx.toAmount, 999.87); // 未传 toAmount,保留原值
    });

    test('updateTransaction 显式传 d.Value<double?>(null) → 清空(帳戶對改回同幣別)',
        () async {
      final lid = await seedLedger();
      final from = await seedAccount(id: 1, currency: 'JPY');
      final to = await seedAccount(id: 2, currency: 'TWD');
      final id = await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 5000,
        accountId: from,
        toAccountId: to,
        happenedAt: DateTime(2026, 8, 29),
        toAmount: 999.87,
      );
      await repo.updateTransaction(
        id: id,
        type: 'transfer',
        amount: 5000,
        happenedAt: DateTime(2026, 8, 29),
        toAmount: const d.Value<double?>(null),
      );
      final tx = await repo.getTransactionById(id);
      expect(tx!.toAmount, isNull);
    });
  });

  group('余额计算:转入脚 toAmount ?? amount', () {
    test('getAccountBalance:跨币别转账,转入账户按 toAmount 计', () async {
      final lid = await seedLedger();
      final from = await seedAccount(id: 1, currency: 'JPY', initial: 100000);
      final to = await seedAccount(id: 2, currency: 'TWD', initial: 0);
      await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 4711, // JPY 转出
        accountId: from,
        toAccountId: to,
        happenedAt: DateTime(2026, 8, 29),
        toAmount: 999.87, // TWD 转入
      );
      expect(await repo.getAccountBalance(from), closeTo(100000 - 4711, 1e-9));
      expect(await repo.getAccountBalance(to), closeTo(999.87, 1e-9));
    });

    test('getAccountBalance:toAmount 为 null(同币别)→ 两边都按 amount 计(既有行为回归)',
        () async {
      final lid = await seedLedger();
      final from = await seedAccount(id: 1, currency: 'CNY', initial: 1000);
      final to = await seedAccount(id: 2, currency: 'CNY', initial: 0);
      await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 200,
        accountId: from,
        toAccountId: to,
        happenedAt: DateTime(2026, 8, 29),
      );
      expect(await repo.getAccountBalance(from), closeTo(800, 1e-9));
      expect(await repo.getAccountBalance(to), closeTo(200, 1e-9));
    });

    test('getAccountGlobalBalance:跨币别转账,转入账户按 toAmount 计', () async {
      final lid = await seedLedger();
      final from = await seedAccount(id: 1, currency: 'JPY', initial: 100000);
      final to = await seedAccount(id: 2, currency: 'TWD', initial: 0);
      await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 4711,
        accountId: from,
        toAccountId: to,
        happenedAt: DateTime(2026, 8, 29),
        toAmount: 999.87,
      );
      expect(await repo.getAccountGlobalBalance(from),
          closeTo(100000 - 4711, 1e-9));
      expect(await repo.getAccountGlobalBalance(to), closeTo(999.87, 1e-9));
    });

    test('getAccountBalanceInLedger:跨币别转账,转入账户按 toAmount 计', () async {
      final lid = await seedLedger();
      final from = await seedAccount(id: 1, currency: 'JPY', initial: 0);
      final to = await seedAccount(id: 2, currency: 'TWD', initial: 0);
      await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 4711,
        accountId: from,
        toAccountId: to,
        happenedAt: DateTime(2026, 8, 29),
        toAmount: 999.87,
      );
      expect(await repo.getAccountBalanceInLedger(from, lid),
          closeTo(-4711, 1e-9));
      expect(
          await repo.getAccountBalanceInLedger(to, lid), closeTo(999.87, 1e-9));
    });

    test('getAccountIncome:跨币别转入按 toAmount 计入收入', () async {
      final lid = await seedLedger();
      final from = await seedAccount(id: 1, currency: 'JPY');
      final to = await seedAccount(id: 2, currency: 'TWD');
      await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 4711,
        accountId: from,
        toAccountId: to,
        happenedAt: DateTime(2026, 8, 29),
        toAmount: 999.87,
      );
      expect(await repo.getAccountIncome(to), closeTo(999.87, 1e-9));
      expect(await repo.getAccountIncome(from), 0);
    });

    test('getAccountDailyBalances:跨币别转入按 toAmount 计(range 前累加 + 逐日累加两处)',
        () async {
      final lid = await seedLedger();
      final from = await seedAccount(id: 1, currency: 'JPY', initial: 0);
      final to = await seedAccount(id: 2, currency: 'TWD', initial: 0);
      // 一笔在 range 之前(测 range 前累加分支),一笔在 range 内(测逐日累加分支)。
      await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 4711,
        accountId: from,
        toAccountId: to,
        happenedAt: DateTime(2026, 8, 25),
        toAmount: 999.87,
      );
      await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 1000,
        accountId: from,
        toAccountId: to,
        happenedAt: DateTime(2026, 8, 29),
        toAmount: 212.34,
      );

      final beforeRange = await repo.getAccountDailyBalances(
        to,
        startDate: DateTime(2026, 8, 26),
        endDate: DateTime(2026, 8, 28),
      );
      expect(beforeRange.first.balance, closeTo(999.87, 1e-9));

      final withinRange = await repo.getAccountDailyBalances(
        to,
        startDate: DateTime(2026, 8, 26),
        endDate: DateTime(2026, 8, 29),
      );
      expect(withinRange.last.balance, closeTo(999.87 + 212.34, 1e-9));
    });
  });
}
