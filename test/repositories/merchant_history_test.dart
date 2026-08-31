/// 商家欄位「依類別記住常用商家」的 repository 查詢
/// (`getMerchantHistory`)+ 上層服務 (`MerchantHistoryService`)。
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/data/merchant_history_service.dart';

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

  group('getMerchantHistory', () {
    test('依分類過濾,依使用次數由高到低排序', () async {
      final lid = await repo.createLedger(name: 'L');
      final dining = await repo.createCategory(name: '餐饮', kind: 'expense');
      final transport = await repo.createCategory(name: '交通', kind: 'expense');

      for (var i = 0; i < 3; i++) {
        await repo.addTransaction(
          ledgerId: lid,
          type: 'expense',
          amount: 30,
          categoryId: dining,
          merchant: '星巴克',
          happenedAt: DateTime(2026, 1, 1 + i),
        );
      }
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 30,
        categoryId: dining,
        merchant: '麥當勞',
        happenedAt: DateTime(2026, 1, 10),
      );
      // 不同分類,不该混进来。
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 30,
        categoryId: transport,
        merchant: '台鐵',
        happenedAt: DateTime(2026, 1, 10),
      );

      final result = await repo.getMerchantHistory(
        ledgerId: lid,
        categoryId: dining,
      );

      expect(result.map((e) => e.merchant).toList(), ['星巴克', '麥當勞']);
      expect(result.first.usageCount, 3);
    });

    test('沒有商家紀錄的分類回傳空清單', () async {
      final lid = await repo.createLedger(name: 'L');
      final cat = await repo.createCategory(name: '餐饮', kind: 'expense');

      final result = await repo.getMerchantHistory(
        ledgerId: lid,
        categoryId: cat,
      );

      expect(result, isEmpty);
    });

    test('空白商家不納入統計', () async {
      final lid = await repo.createLedger(name: 'L');
      final cat = await repo.createCategory(name: '餐饮', kind: 'expense');
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 30,
        categoryId: cat,
        merchant: '   ',
        happenedAt: DateTime(2026, 1, 1),
      );

      final result = await repo.getMerchantHistory(
        ledgerId: lid,
        categoryId: cat,
      );

      expect(result, isEmpty);
    });
  });

  group('MerchantHistoryService.getHistoryMerchants', () {
    test('沒有有效分類時退回帳本全部分類(不回傳空清單)', () async {
      final lid = await repo.createLedger(name: 'L');
      final cat = await repo.createCategory(name: '餐饮', kind: 'expense');
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 30,
        categoryId: cat,
        merchant: '星巴克',
        happenedAt: DateTime(2026, 1, 1),
      );

      final result = await MerchantHistoryService.getHistoryMerchants(
        repository: repo,
        ledgerId: lid,
        categoryId: null,
        categorySyncId: null,
      );

      expect(result.map((e) => e.merchant).toList(), ['星巴克']);
    });
  });
}
