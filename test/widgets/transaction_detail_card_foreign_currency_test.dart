/// 交易明細卡(`TransactionDetailCard`,`showTransactionDetailCard` 打開的
/// 那張卡,也是搜尋頁點交易列後開的同一張卡)外幣交易的顯示——2026-09-14
/// 使用者反饋(接續帳戶明細頁/首頁清單的同一輪反饋):搜尋頁跟交易詳情卡
/// 也要一併改成幣別縮寫文字(不是貨幣符號 ¥),下面同樣要顯示折算後的金額。
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/data/repositories/transaction_repository.dart'
    show TransactionSplitInput;
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/widgets/biz/transaction_detail_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;
  late int ledgerId;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    ledgerId = await db.into(db.ledgers).insert(LedgersCompanion.insert(
          id: const d.Value(1),
          name: 'L',
          currency: const d.Value('TWD'),
        ));
  });

  tearDown(() async => db.close());

  Ledger twdLedger() => Ledger(
        id: ledgerId,
        name: 'L',
        currency: 'TWD',
        type: 'personal',
        createdAt: DateTime(2026, 1, 1),
        myRole: 'owner',
        memberCount: 1,
        isShared: false,
        monthStartDay: 1,
      );

  Widget host({required int txId}) {
    return ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentLedgerIdProvider.overrideWith((ref) => ledgerId),
        currentLedgerProvider
            .overrideWith((ref) => Stream<Ledger?>.value(twdLedger())),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', 'TW'),
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) {
            return ElevatedButton(
              onPressed: () async {
                final tx = await repo.getTransactionById(txId);
                await showTransactionDetailCard(context, ref, tx!, null);
              },
              child: const Text('open'),
            );
          }),
        ),
      ),
    );
  }

  testWidgets('幣別跟帳本本位幣不同(JPY 記在 TWD 帳本)→ 頭部金額顯示幣別縮寫文字(不是 ¥)+ ≈折算金額',
      (tester) async {
    final txId = await repo.addTransaction(
      ledgerId: ledgerId,
      type: 'expense',
      amount: 600,
      currencyCode: 'JPY',
      nativeAmount: 123.65,
      happenedAt: DateTime(2026, 9, 14),
      note: '手扶梯',
    );

    await tester.pumpWidget(host(txId: txId));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('JPY'), findsWidgets);
    expect(find.textContaining('¥'), findsNothing);
    expect(find.textContaining('600'), findsWidgets);
    expect(find.text('≈123.65'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('同幣別(TWD)交易 → 不顯示幣別縮寫文字,也不顯示 ≈ 折算小字', (tester) async {
    final txId = await repo.addTransaction(
      ledgerId: ledgerId,
      type: 'expense',
      amount: 150,
      currencyCode: 'TWD',
      nativeAmount: 150,
      happenedAt: DateTime(2026, 9, 14),
      note: '晚餐',
    );

    await tester.pumpWidget(host(txId: txId));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('TWD'), findsNothing);
    expect(find.textContaining('¥'), findsNothing);
    expect(find.textContaining('≈'), findsNothing);
    expect(find.textContaining('150'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('拆帳明細(JPY 母交易)→ 每筆分帳明細按比例折算,顯示幣別縮寫文字 + ≈ 折算金額', (tester) async {
    final txId = await repo.addTransaction(
      ledgerId: ledgerId,
      type: 'expense',
      amount: 1000,
      currencyCode: 'JPY',
      nativeAmount: 200,
      happenedAt: DateTime(2026, 9, 14),
      note: '超市',
      splits: [
        const TransactionSplitInput(amount: 600),
        const TransactionSplitInput(amount: 400),
      ],
    );

    await tester.pumpWidget(host(txId: txId));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 600/1000 * 200 = 120.00；400/1000 * 200 = 80.00。
    expect(find.text('≈120.00'), findsOneWidget);
    expect(find.text('≈80.00'), findsOneWidget);
    expect(find.textContaining('¥'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });
}
