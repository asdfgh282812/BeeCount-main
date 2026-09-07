/// 「建議」分頁 + 智慧預設用的 3 個新 repository 查詢:
/// - getCategoryUsageSignals:建議分頁排序演算法的原始訊號來源。
/// - getMostUsedAccountForCategory:依類別靜默代入常用帳戶。
/// - getLastTransferAccounts:轉帳分頁預帶最近用過的兩個帳戶(排除信用卡繳款)。
/// - getLastFromAccountForToAccount:依轉入帳戶預帶最近用過的來源帳戶,信用卡
///   繳費入口用這個依「這張卡」而非全帳本最近一筆轉帳來預帶。
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/utils/credit_card_payment.dart';

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

    test('排除信用卡繳款轉帳,回傳更早一筆一般轉帳', () async {
      final lid = await repo.createLedger(name: 'L');
      final a = await repo.createAccount(ledgerId: lid, name: 'A');
      final b = await repo.createAccount(ledgerId: lid, name: 'B');
      final card = await repo.createAccount(
          ledgerId: lid, name: 'Card', type: 'credit_card');

      await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 100,
        accountId: a,
        toAccountId: b,
        happenedAt: DateTime(2026, 1, 1),
      );
      // 最近一筆是信用卡繳款,不該被主頁「新增轉帳」拿去預帶。
      await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 500,
        accountId: b,
        toAccountId: card,
        note: creditCardPaymentNote(billingDay: 5),
        happenedAt: DateTime(2026, 1, 10),
      );

      final result = await repo.getLastTransferAccounts(ledgerId: lid);

      expect(result?.fromAccountId, a);
      expect(result?.toAccountId, b);
    });
  });

  group('getLastFromAccountForToAccount', () {
    test('依轉入帳戶查最近一次轉進它的來源帳戶,不同轉入帳戶互不干擾', () async {
      final lid = await repo.createLedger(name: 'L');
      final yushan = await repo.createAccount(ledgerId: lid, name: '永豐銀行');
      final taishin = await repo.createAccount(ledgerId: lid, name: '台新銀行');
      final yushanCard = await repo.createAccount(
          ledgerId: lid, name: '永豐信用卡', type: 'credit_card');
      final taishinCard = await repo.createAccount(
          ledgerId: lid, name: '台新信用卡', type: 'credit_card');

      // 8/7 用台新銀行繳台新信用卡。
      await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 1000,
        accountId: taishin,
        toAccountId: taishinCard,
        note: creditCardPaymentNote(billingDay: 5),
        happenedAt: DateTime(2026, 8, 7),
      );
      // 9/5 用永豐銀行繳永豐信用卡——時間更晚,但轉入帳戶不同。
      await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 2000,
        accountId: yushan,
        toAccountId: yushanCard,
        note: creditCardPaymentNote(billingDay: 10),
        happenedAt: DateTime(2026, 9, 5),
      );

      // 9/7 準備繳台新信用卡:應該拿回 8/7 用過的台新銀行,而不是全帳本
      // 最近一筆轉帳(永豐銀行)。
      final result = await repo.getLastFromAccountForToAccount(
        ledgerId: lid,
        toAccountId: taishinCard,
      );

      expect(result, taishin);
    });

    test('沒有轉進過這個帳戶時回傳 null', () async {
      final lid = await repo.createLedger(name: 'L');
      final card = await repo.createAccount(
          ledgerId: lid, name: 'Card', type: 'credit_card');
      final result = await repo.getLastFromAccountForToAccount(
        ledgerId: lid,
        toAccountId: card,
      );
      expect(result, isNull);
    });
  });
}
