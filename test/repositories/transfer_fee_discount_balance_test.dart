/// v46 轉帳手續費/折損 — Repository 层契约(design doc
/// docs/superpowers/specs/2026-08-29-transfer-fee-discount-design.md §2/§3):
///   - addTransaction/updateTransaction 的 feeAmount/feeLabel/discountAmount/
///     discountLabel 参数正确写入/更新(updateTransaction 是 tri-state)。
///   - 余额计算的转出脚改用 `_transferOutEffect`(amount + feeAmount ?? 0)、
///     转入脚改用 `_transferInEffect`((toAmount ?? amount) - discountAmount ?? 0):
///     两者皆 null(旧数据/没有手续费折损)→ 行为与改动前完全一致(回归)。
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

  group('addTransaction/updateTransaction 的 fee/discount 参数', () {
    test('addTransaction 传 feeAmount/feeLabel/discountAmount/discountLabel → 直接写入',
        () async {
      final lid = await seedLedger();
      final from = await seedAccount(id: 1, currency: 'CNY');
      final to = await seedAccount(id: 2, currency: 'CNY');
      final id = await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 1000,
        accountId: from,
        toAccountId: to,
        happenedAt: DateTime(2026, 8, 29),
        feeAmount: 10,
        feeLabel: '跨行手續費',
        discountAmount: 5,
        discountLabel: '到帳折損',
      );
      final tx = await repo.getTransactionById(id);
      expect(tx!.feeAmount, 10);
      expect(tx.feeLabel, '跨行手續費');
      expect(tx.discountAmount, 5);
      expect(tx.discountLabel, '到帳折損');
    });

    test('addTransaction 不传 fee/discount → 落 null', () async {
      final lid = await seedLedger();
      final from = await seedAccount(id: 1, currency: 'CNY');
      final to = await seedAccount(id: 2, currency: 'CNY');
      final id = await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 1000,
        accountId: from,
        toAccountId: to,
        happenedAt: DateTime(2026, 8, 29),
      );
      final tx = await repo.getTransactionById(id);
      expect(tx!.feeAmount, isNull);
      expect(tx.feeLabel, isNull);
      expect(tx.discountAmount, isNull);
      expect(tx.discountLabel, isNull);
    });

    test('updateTransaction 不传 fee/discount → 不动既有值', () async {
      final lid = await seedLedger();
      final from = await seedAccount(id: 1, currency: 'CNY');
      final to = await seedAccount(id: 2, currency: 'CNY');
      final id = await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 1000,
        accountId: from,
        toAccountId: to,
        happenedAt: DateTime(2026, 8, 29),
        feeAmount: 10,
        feeLabel: '手續費',
      );
      await repo.updateTransaction(
        id: id,
        type: 'transfer',
        amount: 1200,
        happenedAt: DateTime(2026, 8, 29),
      );
      final tx = await repo.getTransactionById(id);
      expect(tx!.amount, 1200);
      expect(tx.feeAmount, 10); // 未传,保留原值
      expect(tx.feeLabel, '手續費');
    });

    test('updateTransaction 显式传 d.Value<double?>(null) → 清空(使用者關閉手續費面板)',
        () async {
      final lid = await seedLedger();
      final from = await seedAccount(id: 1, currency: 'CNY');
      final to = await seedAccount(id: 2, currency: 'CNY');
      final id = await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 1000,
        accountId: from,
        toAccountId: to,
        happenedAt: DateTime(2026, 8, 29),
        feeAmount: 10,
        feeLabel: '手續費',
        discountAmount: 5,
        discountLabel: '折損',
      );
      await repo.updateTransaction(
        id: id,
        type: 'transfer',
        amount: 1000,
        happenedAt: DateTime(2026, 8, 29),
        feeAmount: const d.Value<double?>(null),
        feeLabel: const d.Value<String?>(null),
        discountAmount: const d.Value<double?>(null),
        discountLabel: const d.Value<String?>(null),
      );
      final tx = await repo.getTransactionById(id);
      expect(tx!.feeAmount, isNull);
      expect(tx.feeLabel, isNull);
      expect(tx.discountAmount, isNull);
      expect(tx.discountLabel, isNull);
    });
  });

  group('余额计算:_transferOutEffect / _transferInEffect', () {
    test('两者皆 null(旧数据)→ 行为与改动前完全一致(回归)', () async {
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
      expect(await repo.getAccountExpense(from), closeTo(200, 1e-9));
      expect(await repo.getAccountIncome(to), closeTo(200, 1e-9));
    });

    test('只有转出侧手续费:转出账户多扣、转入账户不受影响', () async {
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
        feeAmount: 15,
      );
      expect(await repo.getAccountBalance(from), closeTo(1000 - 200 - 15, 1e-9));
      expect(await repo.getAccountBalance(to), closeTo(200, 1e-9));
      expect(await repo.getAccountExpense(from), closeTo(215, 1e-9));
    });

    test('只有转入侧折损:转入账户少收、转出账户不受影响', () async {
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
        discountAmount: 8,
      );
      expect(await repo.getAccountBalance(from), closeTo(1000 - 200, 1e-9));
      expect(await repo.getAccountBalance(to), closeTo(200 - 8, 1e-9));
      expect(await repo.getAccountIncome(to), closeTo(192, 1e-9));
    });

    test('转出手续费 + 转入折损同时存在:两侧各自独立疊加', () async {
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
        feeAmount: 15,
        discountAmount: 8,
      );
      expect(await repo.getAccountBalance(from), closeTo(1000 - 200 - 15, 1e-9));
      expect(await repo.getAccountBalance(to), closeTo(200 - 8, 1e-9));
    });

    test('跨幣別轉帳 + 轉入側折損:折損疊加在 toAmount 之上,不是 amount', () async {
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
        discountAmount: 20,
      );
      expect(await repo.getAccountBalance(from), closeTo(100000 - 4711, 1e-9));
      expect(await repo.getAccountBalance(to), closeTo(999.87 - 20, 1e-9));
    });

    test('feeAmount/discountAmount = 0 时行为等同 null(边界情况)', () async {
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
        feeAmount: 0,
        discountAmount: 0,
      );
      expect(await repo.getAccountBalance(from), closeTo(800, 1e-9));
      expect(await repo.getAccountBalance(to), closeTo(200, 1e-9));
    });

    test('getAccountBalanceInLedger / getAccountGlobalBalance 也套用手续费/折损公式',
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
        feeAmount: 15,
        discountAmount: 8,
      );
      expect(await repo.getAccountBalanceInLedger(from, lid),
          closeTo(-215, 1e-9));
      expect(await repo.getAccountBalanceInLedger(to, lid), closeTo(192, 1e-9));
      expect(await repo.getAccountGlobalBalance(from),
          closeTo(1000 - 215, 1e-9));
      expect(await repo.getAccountGlobalBalance(to), closeTo(192, 1e-9));
    });

    test('getAccountDailyBalances:手续费/折损在 range 前累加 + 逐日累加两处都生效',
        () async {
      final lid = await seedLedger();
      final from = await seedAccount(id: 1, currency: 'CNY', initial: 0);
      final to = await seedAccount(id: 2, currency: 'CNY', initial: 0);
      // 一笔在 range 之前(测 range 前累加分支),一笔在 range 内(测逐日累加分支)。
      await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 200,
        accountId: from,
        toAccountId: to,
        happenedAt: DateTime(2026, 8, 25),
        discountAmount: 8,
      );
      await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 100,
        accountId: from,
        toAccountId: to,
        happenedAt: DateTime(2026, 8, 29),
        discountAmount: 3,
      );

      final beforeRange = await repo.getAccountDailyBalances(
        to,
        startDate: DateTime(2026, 8, 26),
        endDate: DateTime(2026, 8, 28),
      );
      expect(beforeRange.first.balance, closeTo(192, 1e-9));

      final withinRange = await repo.getAccountDailyBalances(
        to,
        startDate: DateTime(2026, 8, 26),
        endDate: DateTime(2026, 8, 29),
      );
      expect(withinRange.last.balance, closeTo(192 + 97, 1e-9));

      final fromDaily = await repo.getAccountDailyBalances(
        from,
        startDate: DateTime(2026, 8, 26),
        endDate: DateTime(2026, 8, 29),
      );
      expect(fromDaily.last.balance, closeTo(-300, 1e-9));
    });
  });
}
