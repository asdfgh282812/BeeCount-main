import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/ai/free_chat_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;
  late int ledgerId;
  late int accountId;
  late int foodCategoryId;
  late int salaryCategoryId;
  const executor = FreeChatToolExecutor();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    ledgerId = await repo.createLedger(name: 'test');
    accountId = await repo.createAccount(ledgerId: ledgerId, name: '现金');
    foodCategoryId = await repo.createCategory(name: '餐饮', kind: 'expense');
    salaryCategoryId = await repo.createCategory(name: '工资', kind: 'income');
  });

  tearDown(() async {
    await db.close();
  });

  group('get_spending_summary', () {
    test('基本收支總額', () async {
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 100,
        categoryId: foodCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 10),
      );
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'income',
        amount: 5000,
        categoryId: salaryCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 15),
      );

      final result = await executor.execute(
        'get_spending_summary',
        {'startDate': '2026-05-01', 'endDate': '2026-05-31'},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['income'], 5000.0);
      expect(result['expense'], 100.0);
      expect(result.containsKey('expenseByCategory'), isFalse);
    });

    test('endDate 當天的交易要算進去(邊界含當天)', () async {
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 50,
        categoryId: foodCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 31, 23, 30),
      );

      final result = await executor.execute(
        'get_spending_summary',
        {'startDate': '2026-05-01', 'endDate': '2026-05-31'},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['expense'], 50.0);
    });

    test('跨月跨年區間', () async {
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 30,
        categoryId: foodCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2025, 12, 31),
      );
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 70,
        categoryId: foodCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2026, 1, 1),
      );

      final result = await executor.execute(
        'get_spending_summary',
        {'startDate': '2025-12-01', 'endDate': '2026-01-31'},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['expense'], 100.0);
    });

    test('groupByCategory=true 回傳各分類金額', () async {
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 100,
        categoryId: foodCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 10),
      );

      final result = await executor.execute(
        'get_spending_summary',
        {
          'startDate': '2026-05-01',
          'endDate': '2026-05-31',
          'groupByCategory': true,
        },
        repo: repo,
        ledgerId: ledgerId,
      );

      final expenseByCategory = result['expenseByCategory'] as List;
      expect(expenseByCategory, hasLength(1));
      expect(expenseByCategory.first['name'], '餐饮');
      expect(expenseByCategory.first['total'], 100.0);
    });

    test('空結果:區間內無交易', () async {
      final result = await executor.execute(
        'get_spending_summary',
        {'startDate': '2030-01-01', 'endDate': '2030-01-31'},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['income'], 0.0);
      expect(result['expense'], 0.0);
    });

    test('缺少必填參數拋出 FreeChatToolException', () async {
      expect(
        () => executor.execute(
          'get_spending_summary',
          {'startDate': '2026-05-01'},
          repo: repo,
          ledgerId: ledgerId,
        ),
        throwsA(isA<FreeChatToolException>()),
      );
    });

    test('日期格式錯誤拋出 FreeChatToolException', () async {
      expect(
        () => executor.execute(
          'get_spending_summary',
          {'startDate': '不是日期', 'endDate': '2026-05-31'},
          repo: repo,
          ledgerId: ledgerId,
        ),
        throwsA(isA<FreeChatToolException>()),
      );
    });
  });

  group('get_budget_status', () {
    test('回傳總預算與分類預算使用情況', () async {
      await repo.createBudget(ledgerId: ledgerId, type: 'total', amount: 3000);
      await repo.createBudget(
        ledgerId: ledgerId,
        type: 'category',
        categoryId: foodCategoryId,
        amount: 1000,
      );
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 200,
        categoryId: foodCategoryId,
        accountId: accountId,
        happenedAt: DateTime.now(),
      );

      final result = await executor.execute(
        'get_budget_status',
        {},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['totalBudget'], isNotNull);
      expect((result['totalBudget'] as Map)['budget'], 3000.0);
      final categoryBudgets = result['categoryBudgets'] as List;
      expect(categoryBudgets, hasLength(1));
      expect(categoryBudgets.first['categoryName'], '餐饮');
      expect(categoryBudgets.first['used'], 200.0);
    });

    test('沒有任何預算時 totalBudget 為 null 且分類預算為空', () async {
      final result = await executor.execute(
        'get_budget_status',
        {},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['totalBudget'], isNull);
      expect(result['categoryBudgets'], isEmpty);
    });

    test('指定 month 參數', () async {
      await repo.createBudget(ledgerId: ledgerId, type: 'total', amount: 3000);

      final result = await executor.execute(
        'get_budget_status',
        {'month': '2026-01-15'},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['month'], '2026-01-01');
    });
  });

  group('query_transactions', () {
    test('依關鍵字過濾備註/商家', () async {
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 30,
        categoryId: foodCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 10),
        note: '午餐奶茶',
      );
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 20,
        categoryId: foodCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 11),
        note: '晚餐',
      );

      final result = await executor.execute(
        'query_transactions',
        {
          'startDate': '2026-05-01',
          'endDate': '2026-05-31',
          'keyword': '奶茶',
        },
        repo: repo,
        ledgerId: ledgerId,
      );

      final transactions = result['transactions'] as List;
      expect(transactions, hasLength(1));
      expect(transactions.first['note'], '午餐奶茶');
      expect(transactions.first['category'], '餐饮');
      expect(transactions.first['account'], '现金');
    });

    test('依分類名稱過濾', () async {
      final trafficCategoryId =
          await repo.createCategory(name: '交通', kind: 'expense');
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 30,
        categoryId: foodCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 10),
      );
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 15,
        categoryId: trafficCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 11),
      );

      final result = await executor.execute(
        'query_transactions',
        {
          'startDate': '2026-05-01',
          'endDate': '2026-05-31',
          'categoryName': '交通',
        },
        repo: repo,
        ledgerId: ledgerId,
      );

      final transactions = result['transactions'] as List;
      expect(transactions, hasLength(1));
      expect(transactions.first['category'], '交通');
    });

    test('limit/truncated 行為', () async {
      for (var i = 0; i < 5; i++) {
        await repo.addTransaction(
          ledgerId: ledgerId,
          type: 'expense',
          amount: 10.0 + i,
          categoryId: foodCategoryId,
          accountId: accountId,
          happenedAt: DateTime(2026, 5, 10 + i),
        );
      }

      final result = await executor.execute(
        'query_transactions',
        {'startDate': '2026-05-01', 'endDate': '2026-05-31', 'limit': 2},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect((result['transactions'] as List), hasLength(2));
      expect(result['truncated'], isTrue);
      expect(result['count'], 2);
    });

    test('limit 超過 50 會被夾到 50', () async {
      final result = await executor.execute(
        'query_transactions',
        {'startDate': '2026-05-01', 'endDate': '2026-05-31', 'limit': 999},
        repo: repo,
        ledgerId: ledgerId,
      );
      expect(result['truncated'], isFalse);
    });

    test('空結果:區間內無交易', () async {
      final result = await executor.execute(
        'query_transactions',
        {'startDate': '2030-01-01', 'endDate': '2030-01-31'},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['transactions'], isEmpty);
      expect(result['truncated'], isFalse);
    });
  });

  group('get_recurring_transactions', () {
    test('只回傳 enabled 的規則', () async {
      await repo.createRule(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 99,
        categoryId: foodCategoryId,
        accountId: accountId,
        note: '訂閱',
        frequency: 'monthly',
        nextRunAt: DateTime.now().add(const Duration(days: 30)),
      );
      final disabledRuleId = await repo.createRule(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 199,
        categoryId: foodCategoryId,
        accountId: accountId,
        note: '已停用',
        frequency: 'monthly',
        nextRunAt: DateTime.now().add(const Duration(days: 30)),
      );
      await repo.setRuleEnabled(disabledRuleId, false);

      final result = await executor.execute(
        'get_recurring_transactions',
        {},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['count'], 1);
      final rules = result['rules'] as List;
      expect(rules.first['note'], '訂閱');
    });

    test('沒有任何規則時回傳空清單', () async {
      final result = await executor.execute(
        'get_recurring_transactions',
        {},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['count'], 0);
      expect(result['rules'], isEmpty);
    });
  });

  test('未知工具名拋出 FreeChatToolException', () async {
    expect(
      () =>
          executor.execute('unknown_tool', {}, repo: repo, ledgerId: ledgerId),
      throwsA(isA<FreeChatToolException>()),
    );
  });
}
