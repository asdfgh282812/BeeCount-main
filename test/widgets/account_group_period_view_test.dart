/// 一般主帳戶群組(非信用卡合併帳單)明細頁「交易明細」tab:
/// `GeneralAccountPeriodView` 帶 `groupChildren` 時要聚合子帳戶的交易,
/// 不同幣種的子帳戶按有效匯率折算成群組幣種後加總,缺匯率時提示未納入。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/account/general_account_period_view.dart';
import 'package:beecount/providers.dart';
import 'package:beecount/services/currency/rate_math.dart';
import 'package:beecount/utils/account_group_utils.dart';

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
        "(id, ledger_id, name, currency, type, hidden, sync_id, parent_account_id) "
        "VALUES (11, 1, '中信台幣戶', 'TWD', 'bank_card', 0, 'c1', 'g1')");
    await db.customStatement("INSERT INTO accounts "
        "(id, ledger_id, name, currency, type, hidden, sync_id, parent_account_id) "
        "VALUES (12, 1, '中信日幣戶', 'JPY', 'bank_card', 0, 'c2', 'g1')");
    final now = DateTime.now();
    final ts =
        DateTime(now.year, now.month, now.day, 9).millisecondsSinceEpoch ~/
            1000;
    await db.customStatement("INSERT INTO transactions "
        "(ledger_id, type, amount, account_id, happened_at) "
        "VALUES (1, 'expense', 100, 11, $ts)");
    await db.customStatement("INSERT INTO transactions "
        "(ledger_id, type, amount, account_id, happened_at) "
        "VALUES (1, 'income', 1000, 12, $ts)");
  });

  tearDown(() async => db.close());

  Future<void> pump(
      WidgetTester tester, Map<String, EffectiveRate> rates) async {
    final all = await repo.getAllAccounts();
    final group = all.firstWhere((a) => a.id == 10);
    final children = accountGroupChildren(group, all);
    // 夠高才能讓 ListView 把最底下的交易清單也建出來。
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentLedgerProvider
            .overrideWith((ref) => Stream<Ledger?>.value(twdLedger())),
        allAccountStatsProvider.overrideWith((ref) async => {
              10: (balance: 0.0, expense: 0.0, income: 0.0),
              11: (balance: -100.0, expense: 100.0, income: 0.0),
              12: (balance: 1000.0, expense: 0.0, income: 1000.0),
            }),
        effectiveRatesProvider.overrideWith((ref) async => rates),
        baseCurrencyProvider.overrideWith((ref) => 'TWD'),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', 'TW'),
        home: Scaffold(
          body: GeneralAccountPeriodView(
            account: group,
            categories: const [],
            groupChildren: children,
          ),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  testWidgets('聚合子帳戶摘要並折算外幣,列出子帳戶', (tester) async {
    await pump(tester, {
      'JPY': const EffectiveRate(rate: '0.2', manual: true),
    });

    expect(find.text('子帳戶'), findsOneWidget);
    expect(find.text('中信日幣戶'), findsOneWidget);
    expect(find.text('JPY'), findsOneWidget);
    // 支出 100 TWD、收入 1000 JPY × 0.2 = 200 TWD,總計 +100。
    expect(find.textContaining('-100'), findsWidgets);
    expect(find.textContaining('+200'), findsOneWidget);
    expect(find.textContaining('缺少匯率'), findsNothing);
    // 子帳戶的交易(支出分頁)聚合進清單:子帳戶卡一次 + 交易列帳戶標籤一次。
    expect(find.text('中信台幣戶'), findsNWidgets(2));
    await _dispose(tester);
  });

  testWidgets('缺匯率的子帳戶不納入合計並提示', (tester) async {
    await pump(tester, const {});

    expect(find.textContaining('JPY 缺少匯率'), findsOneWidget);
    expect(find.textContaining('+200'), findsNothing);
    await _dispose(tester);
  });
}
