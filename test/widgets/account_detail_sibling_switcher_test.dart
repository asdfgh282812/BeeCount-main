/// 帳戶明細頁標題下拉:子帳戶(掛在主帳戶群組底下)標題旁有箭頭,點標題列
/// 展開同群組子帳戶清單,選另一個子帳戶就換成那個帳戶的明細頁;不是子帳戶
/// 的帳戶沒有箭頭。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/account/account_detail_page.dart';
import 'package:beecount/providers.dart';

/// 拆掉 widget tree 並讓 logger 的防抖存檔 timer 跑完,避免 timersPending。
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;

  Ledger twdLedger() => Ledger(
        id: 1,
        name: 'L',
        currency: 'TWD',
        type: 'personal',
        createdAt: DateTime(2026, 1, 1),
        myRole: 'owner',
        memberCount: 1,
        isShared: false,
        monthStartDay: 1,
      );

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'TWD')");
    await db.customStatement("INSERT INTO accounts "
        "(id, ledger_id, name, currency, type, hidden, sync_id) "
        "VALUES (10, 1, '中信帳戶', 'TWD', 'account_group', 0, 'g1')");
    await db.customStatement("INSERT INTO accounts "
        "(id, ledger_id, name, currency, type, hidden, sync_id, parent_account_id, sort_order) "
        "VALUES (11, 1, '中信台幣戶', 'TWD', 'bank_card', 0, 'c1', 'g1', 0)");
    await db.customStatement("INSERT INTO accounts "
        "(id, ledger_id, name, currency, type, hidden, sync_id, parent_account_id, sort_order) "
        "VALUES (12, 1, '中信日幣戶', 'JPY', 'bank_card', 0, 'c2', 'g1', 1)");
    await db.customStatement("INSERT INTO accounts "
        "(id, ledger_id, name, currency, type, hidden, sync_id) "
        "VALUES (13, 1, '現金', 'TWD', 'cash', 0, 'c3')");
  });

  tearDown(() async => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  Future<void> pumpDetail(WidgetTester tester, int accountId) async {
    final account = (await repo.getAccount(accountId))!;
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentLedgerProvider
            .overrideWith((ref) => Stream<Ledger?>.value(twdLedger())),
        allAccountStatsProvider.overrideWith((ref) async => {}),
        effectiveRatesProvider.overrideWith((ref) async => {}),
        baseCurrencyProvider.overrideWith((ref) => 'TWD'),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', 'TW'),
        home: AccountDetailPage(account: account),
      ),
    ));
    await settle(tester);
  }

  testWidgets('子帳戶:點標題展開同群組清單,選另一個就切換', (tester) async {
    await pumpDetail(tester, 11);

    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    // 收起時只有標題上的名稱。
    expect(find.text('中信日幣戶'), findsNothing);

    await tester.tap(find.text('中信台幣戶').first);
    await settle(tester);
    expect(find.byIcon(Icons.arrow_drop_up), findsOneWidget);
    expect(find.text('中信日幣戶'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    // 群組本身與非同群組帳戶不在清單裡。
    expect(find.text('中信帳戶'), findsNothing);
    expect(find.text('現金'), findsNothing);

    await tester.tap(find.text('中信日幣戶'));
    await settle(tester);
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    expect(find.text('中信日幣戶'), findsOneWidget);
    expect(find.text('中信台幣戶'), findsNothing);
    await _dispose(tester);
  });

  testWidgets('不是子帳戶的帳戶沒有下拉箭頭', (tester) async {
    await pumpDetail(tester, 13);

    expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
    await _dispose(tester);
  });
}
