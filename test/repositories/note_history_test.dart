/// 備註欄位「歷史備註」的 repository 查詢
/// (`getNoteHistory`)——尤其是系統自動產生備註(信用卡回饋入帳、信用卡
/// 繳款……)不該被使用者的歷史備註清單收錄,見
/// `kSystemGeneratedNotePrefixes`(lib/models/note_history.dart)。
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/models/note_history.dart';

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

  group('getNoteHistory', () {
    test('排除系統自動產生的備註(信用卡回饋入帳、信用卡繳款)', () async {
      final lid = await repo.createLedger(name: 'L');
      final cat = await repo.createCategory(name: '餐饮', kind: 'expense');

      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 30,
        categoryId: cat,
        note: '午餐',
        happenedAt: DateTime(2026, 1, 1),
      );
      await repo.addTransaction(
        ledgerId: lid,
        type: 'income',
        amount: 15,
        categoryId: cat,
        note: '信用卡回饋入帳：海外實體8%',
        happenedAt: DateTime(2026, 1, 2),
      );
      await repo.addTransaction(
        ledgerId: lid,
        type: 'transfer',
        amount: 100,
        note: '信用卡繳款(帳單 2026-07-11~2026-08-11)',
        happenedAt: DateTime(2026, 1, 3),
      );

      final result = await repo.getNoteHistory(
        ledgerId: lid,
        sort: NoteHistorySort.frequency,
      );

      expect(result.map((e) => e.note).toList(), ['午餐']);
    });

    test('沒有歷史備註時回傳空清單', () async {
      final lid = await repo.createLedger(name: 'L');

      final result = await repo.getNoteHistory(
        ledgerId: lid,
        sort: NoteHistorySort.frequency,
      );

      expect(result, isEmpty);
    });
  });
}
