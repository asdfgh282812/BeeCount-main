/// 「建議」分頁排序演算法(`CategorySuggestionService`)。
///
/// `computeScores` 是純函式,覆蓋:
/// - 時間衰減:同樣次數下,最近才用過的分類分數較高。
/// - 時段/星期條件機率:只在當前時段/星期用過的分類該項訊號拉滿。
/// - 帳戶情境:歷史上跟目前情境帳戶相符比例高的分類分數較高。
/// - 預算懲罰門檻(0.9/1.0 邊界)。
/// - 空歷史時回傳空清單(由呼叫端 `getSuggestedCategories` 負責冷啟動 fallback,
///   見 category_suggestion_getSuggestedCategories_test 那組)。
///
/// `getSuggestedCategories` 需要真的 repository 查資料,用 in-memory Drift
/// (跟其他 repository 測試同款寫法)驗證冷啟動 fallback + 排序反查行為。
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/budget_repository.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/models/category_suggestion.dart';
import 'package:beecount/services/data/category_suggestion_service.dart';

void main() {
  group('computeScores', () {
    test('沒有歷史訊號回傳空清單', () {
      final scores = CategorySuggestionService.computeScores(
        signals: const [],
        budgetUsages: const [],
        now: DateTime(2026, 1, 1, 12),
      );
      expect(scores, isEmpty);
    });

    test('同樣次數下,最近才用過的分類 recencyFreq 較高、總分排前面', () {
      final now = DateTime(2026, 1, 30, 3); // 凌晨,不落在任何一方的時段優勢裡
      final signals = [
        // 分類 1:30 天前用過 1 次(半衰期 14 天,幾乎衰減完)。
        CategoryUsageSignal(
            categoryId: 1, happenedAt: now.subtract(const Duration(days: 30))),
        // 分類 2:1 天前用過 1 次。
        CategoryUsageSignal(
            categoryId: 2, happenedAt: now.subtract(const Duration(days: 1))),
      ];

      final scores = CategorySuggestionService.computeScores(
        signals: signals,
        budgetUsages: const [],
        now: now,
      );

      final byId = {for (final s in scores) s.categoryId: s};
      expect(byId[2]!.recencyFreq, greaterThan(byId[1]!.recencyFreq));
      expect(scores.first.categoryId, 2, reason: '總分應該由高到低排序');
    });

    test('時段條件機率:只在當前時段用過的分類該項訊號拉滿', () {
      // 當下是中午 12 點(午餐時段)。
      final now = DateTime(2026, 1, 30, 12);
      final signals = [
        // 分類 1:3 次都在午餐時段。
        CategoryUsageSignal(categoryId: 1, happenedAt: DateTime(2026, 1, 27, 12)),
        CategoryUsageSignal(categoryId: 1, happenedAt: DateTime(2026, 1, 28, 12)),
        CategoryUsageSignal(categoryId: 1, happenedAt: DateTime(2026, 1, 29, 12)),
        // 分類 2:3 次都在宵夜時段(23點),從沒在午餐時段出現過。
        CategoryUsageSignal(categoryId: 2, happenedAt: DateTime(2026, 1, 27, 23)),
        CategoryUsageSignal(categoryId: 2, happenedAt: DateTime(2026, 1, 28, 23)),
        CategoryUsageSignal(categoryId: 2, happenedAt: DateTime(2026, 1, 29, 23)),
      ];

      final scores = CategorySuggestionService.computeScores(
        signals: signals,
        budgetUsages: const [],
        now: now,
      );
      final byId = {for (final s in scores) s.categoryId: s};

      expect(byId[1]!.timeOfDay, 1.0);
      expect(byId[2]!.timeOfDay, 0.0);
    });

    test('帳戶情境:歷史上用目前情境帳戶的比例決定 accountContext', () {
      final now = DateTime(2026, 1, 30, 3);
      final signals = [
        CategoryUsageSignal(
            categoryId: 1, happenedAt: now, accountId: 100),
        CategoryUsageSignal(
            categoryId: 1, happenedAt: now, accountId: 100),
        CategoryUsageSignal(
            categoryId: 1, happenedAt: now, accountId: 200),
      ];

      final scores = CategorySuggestionService.computeScores(
        signals: signals,
        budgetUsages: const [],
        now: now,
        contextAccountId: 100,
      );

      expect(scores.single.accountContext, closeTo(2 / 3, 1e-9));
    });

    test('沒有情境帳戶時 accountContext 恆為 0', () {
      final now = DateTime(2026, 1, 30, 3);
      final signals = [
        CategoryUsageSignal(categoryId: 1, happenedAt: now, accountId: 100),
      ];

      final scores = CategorySuggestionService.computeScores(
        signals: signals,
        budgetUsages: const [],
        now: now,
      );

      expect(scores.single.accountContext, 0.0);
    });

    test('預算懲罰門檻:>=1.0 懲罰 0.3,>=0.9 懲罰 0.6,其餘 1.0', () {
      final now = DateTime(2026, 1, 30, 3);
      final signals = [
        CategoryUsageSignal(categoryId: 1, happenedAt: now), // exceeded
        CategoryUsageSignal(categoryId: 2, happenedAt: now), // danger(0.9)
        CategoryUsageSignal(categoryId: 3, happenedAt: now), // normal
      ];
      CategoryBudgetUsage usage(int categoryId, double used, double budget) =>
          CategoryBudgetUsage(
            budgetId: categoryId,
            categoryId: categoryId,
            categoryName: 'c$categoryId',
            usage: BudgetUsage(used: used, budget: budget),
          );

      final scores = CategorySuggestionService.computeScores(
        signals: signals,
        budgetUsages: [
          usage(1, 120, 100), // rate 1.2 → exceeded
          usage(2, 90, 100), // rate 0.9 → danger
          usage(3, 50, 100), // rate 0.5 → normal
        ],
        now: now,
      );
      final byId = {for (final s in scores) s.categoryId: s};

      expect(byId[1]!.budgetPenalty, 0.3);
      expect(byId[2]!.budgetPenalty, 0.6);
      expect(byId[3]!.budgetPenalty, 1.0);
      // 同樣的歷史訊號下,懲罰越重總分越低。
      expect(byId[3]!.score, greaterThan(byId[2]!.score));
      expect(byId[2]!.score, greaterThan(byId[1]!.score));
    });

    test('沒有對應預算紀錄的分類不受懲罰(預設 1.0)', () {
      final now = DateTime(2026, 1, 30, 3);
      final scores = CategorySuggestionService.computeScores(
        signals: [CategoryUsageSignal(categoryId: 1, happenedAt: now)],
        budgetUsages: const [],
        now: now,
      );
      expect(scores.single.budgetPenalty, 1.0);
    });
  });

  group('getSuggestedCategories', () {
    late BeeDatabase db;
    late LocalRepository repo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = BeeDatabase.forTesting(NativeDatabase.memory());
      repo = LocalRepository(db);
    });

    tearDown(() async => db.close());

    test('沒有任何歷史紀錄(冷啟動)時退回全部可記帳分類', () async {
      final lid = await repo.createLedger(name: 'L');
      await repo.createCategory(name: '餐饮', kind: 'expense');
      await repo.createCategory(name: '交通', kind: 'expense');

      final result = await CategorySuggestionService.getSuggestedCategories(
        repository: repo,
        ledgerId: lid,
        budgetUsages: const [],
        now: DateTime(2026, 1, 30, 12),
      );

      expect(result.map((c) => c.name).toSet(), {'餐饮', '交通'});
    });

    test('有歷史紀錄時依分數排序,反查出對應的 Category 物件', () async {
      final lid = await repo.createLedger(name: 'L');
      final dining = await repo.createCategory(name: '餐饮', kind: 'expense');
      final transport = await repo.createCategory(name: '交通', kind: 'expense');

      // 餐饮:最近且高頻;交通:很久以前只用過一次。
      for (var i = 0; i < 5; i++) {
        await repo.addTransaction(
          ledgerId: lid,
          type: 'expense',
          amount: 30,
          categoryId: dining,
          happenedAt: DateTime(2026, 1, 25 + i, 12),
        );
      }
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 10,
        categoryId: transport,
        happenedAt: DateTime(2025, 6, 1),
      );

      final result = await CategorySuggestionService.getSuggestedCategories(
        repository: repo,
        ledgerId: lid,
        budgetUsages: const [],
        now: DateTime(2026, 1, 30, 12),
      );

      expect(result.first.name, '餐饮');
    });

    test('可用分類超過 10 個時,不管冷啟動或有歷史紀錄都只回傳前 10 個', () async {
      final lid = await repo.createLedger(name: 'L');
      final categoryIds = <int>[];
      for (var i = 0; i < 15; i++) {
        categoryIds.add(await repo.createCategory(name: 'c$i', kind: 'expense'));
      }

      final cold = await CategorySuggestionService.getSuggestedCategories(
        repository: repo,
        ledgerId: lid,
        budgetUsages: const [],
        now: DateTime(2026, 1, 30, 12),
      );
      expect(cold.length, 10);

      for (final id in categoryIds) {
        await repo.addTransaction(
          ledgerId: lid,
          type: 'expense',
          amount: 10,
          categoryId: id,
          happenedAt: DateTime(2026, 1, 30, 12),
        );
      }

      final ranked = await CategorySuggestionService.getSuggestedCategories(
        repository: repo,
        ledgerId: lid,
        budgetUsages: const [],
        now: DateTime(2026, 1, 30, 12),
      );
      expect(ranked.length, 10);
    });
  });
}
