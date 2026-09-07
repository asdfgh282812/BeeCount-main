// reevaluateAllCreditCardReminders 是「有 repo 的呼叫端」(見該函式開頭
// docstring):main.dart 啟動/app.dart resumed/全域設定頁面儲存時都呼叫它,
// 用 creditCardDueByChildAsOf 算好 remainingDue 再傳進
// CreditCardReminderService 的排程方法。①②③現在是**全域**設定(不分卡,
// SharedPreferences key 不帶 accountId 後綴),這裡驗證同一組全域設定會套用
// 到傳入的每一張信用卡帳戶。實際排程呼叫 NotificationFactory.getInstance()
// 在非 Android/iOS 的測試環境會拋 UnsupportedError,但那層 try/catch 在
// CreditCardReminderService 內部(見 credit_card_reminder_providers.dart),
// 所以這裡只能驗證「不會往外拋例外、correctly 讀 repo/SharedPreferences 設定」,
// 排程本身是否真的呼叫到通知外掛不在這個測試的能力範圍內。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/providers/credit_card_reminder_reevaluation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
  });

  tearDown(() async => db.close());

  Future<int> seedLedger() {
    return db.into(db.ledgers).insert(LedgersCompanion.insert(
          name: '台幣帳本',
          monthStartDay: const Value(1),
        ));
  }

  Future<int> seedCreditCardAccount(int ledgerId, String name,
      {int billingDay = 5, int paymentDueDay = 20}) {
    return db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: ledgerId,
          name: name,
          type: const Value('credit_card'),
          billingDay: Value(billingDay),
          paymentDueDay: Value(paymentDueDay),
          syncId: Value(name),
        ));
  }

  test('沒有啟用任何全域開關時,不會拋例外(全部提前 cancel)', () async {
    SharedPreferences.setMockInitialValues({});
    final ledgerId = await seedLedger();
    final accountId = await seedCreditCardAccount(ledgerId, '測試卡');
    final account = (await repo.getCreditCardAccounts())
        .firstWhere((a) => a.id == accountId);

    await reevaluateAllCreditCardReminders(
      repo: repo,
      creditCardAccounts: [account],
    );
  });

  test('全域開啟②③開關 + 有應繳金額時,套用到多張卡都不會拋例外', () async {
    // 全域設定不帶 accountId 後綴——同一組設定套用到下面兩張信用卡帳戶。
    SharedPreferences.setMockInitialValues({
      'cc_reminder_enabled': true,
      'cc_reminder_days': 5,
      'cc_billing_reminder_enabled': true,
      'cc_due_reminder_enabled': true,
      'cc_due_reminder_maxdays': 5,
      'cc_reminder_hour': 9,
      'cc_reminder_minute': 30,
    });
    final ledgerId = await seedLedger();
    final expenseCat = await db
        .into(db.categories)
        .insert(CategoriesCompanion.insert(name: '購物', kind: 'expense'));
    final accountId1 = await seedCreditCardAccount(ledgerId, '測試卡1',
        billingDay: 5, paymentDueDay: 20);
    final accountId2 = await seedCreditCardAccount(ledgerId, '測試卡2',
        billingDay: 10, paymentDueDay: 25);

    for (final accountId in [accountId1, accountId2]) {
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 500,
        categoryId: expenseCat,
        accountId: accountId,
        happenedAt: DateTime.now().subtract(const Duration(days: 10)),
      );
    }

    final accounts = await repo.getCreditCardAccounts();
    expect(accounts.length, 2);

    await reevaluateAllCreditCardReminders(
      repo: repo,
      creditCardAccounts: accounts,
    );
  });

  test('skipIfCloudActive=true 時直接走取消分支,不會拋例外', () async {
    SharedPreferences.setMockInitialValues({
      'cc_reminder_enabled': true,
      'cc_billing_reminder_enabled': true,
      'cc_due_reminder_enabled': true,
    });
    final ledgerId = await seedLedger();
    final accountId = await seedCreditCardAccount(ledgerId, '測試卡');
    final account = (await repo.getCreditCardAccounts())
        .firstWhere((a) => a.id == accountId);

    await reevaluateAllCreditCardReminders(
      repo: repo,
      creditCardAccounts: [account],
      skipIfCloudActive: true,
    );
  });

  test('billingDay/paymentDueDay 缺一即跳過②③(①提前提醒獨立判斷)', () async {
    SharedPreferences.setMockInitialValues({
      'cc_billing_reminder_enabled': true,
    });
    final ledgerId = await seedLedger();
    final accountId =
        await db.into(db.accounts).insert(AccountsCompanion.insert(
              ledgerId: ledgerId,
              name: '沒設定帳單日的卡',
              type: const Value('credit_card'),
              syncId: const Value('no-billing-day'),
            ));
    final account = (await repo.getCreditCardAccounts())
        .firstWhere((a) => a.id == accountId);

    await reevaluateAllCreditCardReminders(
      repo: repo,
      creditCardAccounts: [account],
    );
  });
}
