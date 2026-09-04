/// 交易明細卡「(內含手續費 $X)」小字提示測試。
///
/// 使用者反馈:BeeCount Cloud 網頁端「更新交易」對話框在金額下方標了
/// (內含手續費 $40)這種小字提示,App 端明細卡只顯示總額,看不出裡面含了
/// 多少手續費/折扣。見 transaction_detail_card.dart::_buildFeeDiscountSubtitle。
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
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

  testWidgets(r'支出帶手續費 → 顯示「(內含手續費 $40)」', (tester) async {
    final txId = await repo.addTransaction(
      ledgerId: ledgerId,
      type: 'expense',
      amount: 2691,
      happenedAt: DateTime(2026, 8, 27),
      note: '任天堂',
      baseAmount: 2651,
      feeAmount: 40,
      discountAmount: 0,
    );

    await tester.pumpWidget(host(txId: txId));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 「(內含 」「手續費 」「$40」「)」目前是各自獨立的 Text/AmountText
    // widget(AmountText 才能繼承隱藏金額開關+币种格式化),所以分開斷言,
    // 不找連在一起的完整字串。
    expect(find.textContaining('內含'), findsOneWidget);
    expect(find.textContaining('手續費'), findsWidgets);
    expect(find.textContaining('40'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('自訂手續費名稱 → 小字提示改用自訂名稱', (tester) async {
    final txId = await repo.addTransaction(
      ledgerId: ledgerId,
      type: 'expense',
      amount: 2691,
      happenedAt: DateTime(2026, 8, 27),
      note: '任天堂',
      baseAmount: 2651,
      feeAmount: 40,
      feeLabel: '海外手續費',
      discountAmount: 0,
    );

    await tester.pumpWidget(host(txId: txId));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('海外手續費'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('手續費/折扣皆為 0(未啟用)→ 不顯示小字提示', (tester) async {
    final txId = await repo.addTransaction(
      ledgerId: ledgerId,
      type: 'expense',
      amount: 100,
      happenedAt: DateTime(2026, 8, 27),
      note: '一般支出',
    );

    await tester.pumpWidget(host(txId: txId));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('內含'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('轉帳交易即使帶 feeAmount 也不顯示小字提示', (tester) async {
    final fromId =
        await repo.createAccount(ledgerId: ledgerId, name: 'A', type: 'cash');
    final toId =
        await repo.createAccount(ledgerId: ledgerId, name: 'B', type: 'cash');
    final txId = await repo.addTransaction(
      ledgerId: ledgerId,
      type: 'transfer',
      amount: 500,
      accountId: fromId,
      toAccountId: toId,
      happenedAt: DateTime(2026, 8, 27),
      feeAmount: 5,
    );

    await tester.pumpWidget(host(txId: txId));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('內含'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });
}
