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

    test('省略 endDate 代表不限結束時間(不再拋例外)', () async {
      final result = await executor.execute(
        'get_spending_summary',
        {'startDate': '2026-05-01'},
        repo: repo,
        ledgerId: ledgerId,
      );

      final range = result['range'] as Map;
      expect(range['requestedStartDate'], '2026-05-01');
      expect(range['requestedEndDate'], isNull);
      expect(range['allTime'], isFalse);
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

      final transactions = (result['sample'] as Map)['transactions'] as List;
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

      final transactions = (result['sample'] as Map)['transactions'] as List;
      expect(transactions, hasLength(1));
      expect(transactions.first['category'], '交通');
    });

    test('limit 只影響樣本,彙總仍涵蓋全部命中', () async {
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

      final sample = result['sample'] as Map;
      expect(sample['transactions'] as List, hasLength(2));
      expect(sample['count'], 2);
      expect(sample['isPartial'], isTrue);
      // 彙總不受 limit 影響:5 筆 10+11+12+13+14 = 60
      expect(result['matchedCount'], 5);
      expect(result['totalExpense'], 60.0);
    });

    test('limit 超過 50 會被夾到 50', () async {
      final result = await executor.execute(
        'query_transactions',
        {'startDate': '2026-05-01', 'endDate': '2026-05-31', 'limit': 999},
        repo: repo,
        ledgerId: ledgerId,
      );
      expect((result['sample'] as Map)['isPartial'], isFalse);
    });

    test('空結果:區間內無交易', () async {
      final result = await executor.execute(
        'query_transactions',
        {'startDate': '2030-01-01', 'endDate': '2030-01-31'},
        repo: repo,
        ledgerId: ledgerId,
      );

      final sample = result['sample'] as Map;
      expect(sample['transactions'], isEmpty);
      expect(sample['isPartial'], isFalse);
      expect(result['matchedCount'], 0);
      expect(result['totalExpense'], 0.0);
    });
  });

  // ============================================================
  // 本輪新增能力(見 docs/changes/2026-09-19-ai-free-chat-query-overhaul.md)
  // ============================================================

  group('query_transactions 彙總不受 limit 截斷', () {
    test('60 筆、limit 5:總額仍涵蓋全部 60 筆', () async {
      for (var i = 0; i < 60; i++) {
        await repo.addTransaction(
          ledgerId: ledgerId,
          type: 'expense',
          amount: 10,
          categoryId: foodCategoryId,
          accountId: accountId,
          happenedAt: DateTime(2026, 5, 1).add(Duration(days: i)),
        );
      }

      final result = await executor.execute(
        'query_transactions',
        {'allTime': true, 'limit': 5},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['matchedCount'], 60);
      expect(result['totalExpense'], 600.0);
      final sample = result['sample'] as Map;
      expect(sample['transactions'] as List, hasLength(5));
      expect(sample['isPartial'], isTrue);
      expect(result['note'], contains('60'));
    });

    test('limit 0:只回彙總,不回樣本', () async {
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 88,
        categoryId: foodCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 10),
      );

      final result = await executor.execute(
        'query_transactions',
        {'allTime': true, 'limit': 0},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['matchedCount'], 1);
      expect(result['totalExpense'], 88.0);
      expect((result['sample'] as Map)['transactions'], isEmpty);
    });

    test('byCategory 分類小計也涵蓋全部命中', () async {
      final trafficId = await repo.createCategory(name: '交通', kind: 'expense');
      for (var i = 0; i < 3; i++) {
        await repo.addTransaction(
          ledgerId: ledgerId,
          type: 'expense',
          amount: 100,
          categoryId: foodCategoryId,
          accountId: accountId,
          happenedAt: DateTime(2026, 5, 10 + i),
        );
      }
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 50,
        categoryId: trafficId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 20),
      );

      final result = await executor.execute(
        'query_transactions',
        {'allTime': true, 'limit': 1},
        repo: repo,
        ledgerId: ledgerId,
      );

      final byCat = (result['byCategory'] as List).cast<Map>();
      // 依金額由大到小
      expect(byCat.first['name'], '餐饮');
      expect(byCat.first['total'], 300.0);
      expect(byCat.first['count'], 3);
      expect(byCat[1]['name'], '交通');
      expect(byCat[1]['total'], 50.0);
    });
  });

  group('query_transactions 全部期間', () {
    setUp(() async {
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 500,
        categoryId: foodCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2024, 3, 2),
      );
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 300,
        categoryId: foodCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 10),
      );
    });

    test('兩個日期都省略 → 涵蓋全部,並回報實際區間', () async {
      final result = await executor.execute(
        'query_transactions',
        {},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['matchedCount'], 2);
      expect(result['totalExpense'], 800.0);
      final range = result['range'] as Map;
      expect(range['allTime'], isTrue);
      // 這兩個欄位是安全網:就算模型漏填日期,使用者也看得出範圍
      expect(range['actualFirstDate'], '2024-03-02');
      expect(range['actualLastDate'], '2026-05-10');
    });

    test('只省略 startDate → 下界無限,endDate 當天仍含入', () async {
      final result = await executor.execute(
        'query_transactions',
        {'endDate': '2026-05-10'},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['matchedCount'], 2);
      final range = result['range'] as Map;
      expect(range['requestedStartDate'], isNull);
      expect(range['requestedEndDate'], '2026-05-10');
    });

    test('allTime:true 覆蓋明確指定的日期', () async {
      final result = await executor.execute(
        'query_transactions',
        {'allTime': true, 'startDate': '2026-01-01', 'endDate': '2026-12-31'},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['matchedCount'], 2, reason: '2024 那筆不應被日期排除');
      expect((result['range'] as Map)['requestedStartDate'], isNull);
    });
  });

  group('query_transactions 關鍵字強化', () {
    test('關鍵字命中分類名稱(備註為空)', () async {
      final rehabId = await repo.createCategory(name: '復健科', kind: 'expense');
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 500,
        categoryId: rehabId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 10),
      );
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 99,
        categoryId: foodCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 11),
      );

      final result = await executor.execute(
        'query_transactions',
        {'allTime': true, 'keyword': '復健'},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['matchedCount'], 1);
      expect(result['totalExpense'], 500.0);
    });

    test('分類名稱簡繁互通', () async {
      final rehabId = await repo.createCategory(name: '复健科', kind: 'expense');
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 500,
        categoryId: rehabId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 10),
      );

      final result = await executor.execute(
        'query_transactions',
        {'allTime': true, 'keyword': '復健'},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['matchedCount'], 1, reason: '繁體查詢應命中簡體分類名');
    });

    test('keyword 給陣列時任一命中即算', () async {
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 500,
        categoryId: foodCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 10),
        note: '复健治療',
      );

      final result = await executor.execute(
        'query_transactions',
        {
          'allTime': true,
          'keyword': ['復健', '复健', '物理治療'],
        },
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['matchedCount'], 1);
      expect((result['filters'] as Map)['keyword'], hasLength(3));
    });

    test('關鍵字也比對商家名稱', () async {
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 150,
        categoryId: foodCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 10),
        merchant: '星巴克',
      );

      final result = await executor.execute(
        'query_transactions',
        {'allTime': true, 'keyword': '星巴克'},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['matchedCount'], 1);
    });
  });

  group('query_transactions 分類解析', () {
    test('完全相等優先,不會誤拉包含同字的分類', () async {
      final breakfastId =
          await repo.createCategory(name: '早餐', kind: 'expense');
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
        type: 'expense',
        amount: 50,
        categoryId: breakfastId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 11),
      );

      final result = await executor.execute(
        'query_transactions',
        {'allTime': true, 'categoryName': '餐饮'},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['matchedCount'], 1);
      expect((result['filters'] as Map)['resolvedCategories'], ['餐饮']);
    });

    test('沒有完全相等時退化為包含比對,並回報解析結果', () async {
      final breakfastId =
          await repo.createCategory(name: '早餐', kind: 'expense');
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 50,
        categoryId: breakfastId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 11),
      );

      final result = await executor.execute(
        'query_transactions',
        {'allTime': true, 'categoryName': '餐'},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['matchedCount'], 1);
      expect((result['filters'] as Map)['resolvedCategories'], contains('早餐'));
    });

    test('指定父分類會自動含子分類', () async {
      final parentId = await repo.createCategory(name: '醫療', kind: 'expense');
      final childId = await repo.createCategory(
        name: '牙科',
        kind: 'expense',
        parentId: parentId,
      );
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 3000,
        categoryId: childId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 10),
      );

      final result = await executor.execute(
        'query_transactions',
        {'allTime': true, 'categoryName': '醫療'},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['matchedCount'], 1, reason: '子分類的交易必須算進父分類');
      expect(result['totalExpense'], 3000.0);
    });

    test('type 參數排除同名的另一種分類', () async {
      final bonusExpense =
          await repo.createCategory(name: '獎金', kind: 'expense');
      final bonusIncome = await repo.createCategory(name: '獎金', kind: 'income');
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 100,
        categoryId: bonusExpense,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 10),
      );
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'income',
        amount: 9000,
        categoryId: bonusIncome,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 11),
      );

      final result = await executor.execute(
        'query_transactions',
        {'allTime': true, 'categoryName': '獎金', 'type': 'income'},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['matchedCount'], 1);
      expect(result['totalIncome'], 9000.0);
      expect(result['totalExpense'], 0.0);
    });

    test('type 參數只接受 expense/income', () async {
      expect(
        () => executor.execute(
          'query_transactions',
          {'allTime': true, 'type': 'transfer'},
          repo: repo,
          ledgerId: ledgerId,
        ),
        throwsA(isA<FreeChatToolException>()),
      );
    });
  });

  group('query_transactions 統計口徑', () {
    test('excludeFromStats 的交易在彙總與樣本中一致地被排除', () async {
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
        type: 'expense',
        amount: 9999,
        categoryId: foodCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 11),
        excludeFromStats: true,
      );

      final result = await executor.execute(
        'query_transactions',
        {'allTime': true},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['matchedCount'], 1);
      expect(result['totalExpense'], 100.0);
      expect((result['sample'] as Map)['transactions'] as List, hasLength(1));
    });

    test('轉帳不計入任何總額', () async {
      final other = await repo.createAccount(ledgerId: ledgerId, name: '銀行');
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'transfer',
        amount: 2000,
        accountId: accountId,
        toAccountId: other,
        happenedAt: DateTime(2026, 5, 10),
      );

      final result = await executor.execute(
        'query_transactions',
        {'allTime': true},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['matchedCount'], 0);
      expect(result['totalExpense'], 0.0);
      expect(result['totalIncome'], 0.0);
    });

    test('多幣種交易以 nativeAmount 計入', () async {
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 100,
        categoryId: foodCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 10),
        currencyCode: 'USD',
        nativeAmount: 3200,
      );

      final result = await executor.execute(
        'query_transactions',
        {'allTime': true},
        repo: repo,
        ledgerId: ledgerId,
      );

      expect(result['totalExpense'], 3200.0);
    });
  });

  test('不再有 N+1:逐筆 getCategoryById 完全不被呼叫', () async {
    final counting = _CountingRepository(db);
    for (var i = 0; i < 20; i++) {
      await counting.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 10,
        categoryId: foodCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2026, 5, 1).add(Duration(days: i)),
      );
    }
    counting.getCategoryByIdCalls = 0;

    await executor.execute(
      'query_transactions',
      {'allTime': true, 'categoryName': '餐饮'},
      repo: counting,
      ledgerId: ledgerId,
    );

    expect(counting.getCategoryByIdCalls, 0,
        reason: '分類名稱改成迴圈外一次載入 Map,不應再逐筆查詢');
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

/// 只為了斷言「不再有 N+1」而存在:計數 [getCategoryById] 的呼叫次數。
class _CountingRepository extends LocalRepository {
  _CountingRepository(super.db);

  int getCategoryByIdCalls = 0;

  @override
  Future<Category?> getCategoryById(int categoryId) {
    getCategoryByIdCalls++;
    return super.getCategoryById(categoryId);
  }
}
