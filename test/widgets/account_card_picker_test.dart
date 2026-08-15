/// 新增交易頁「卡片選擇」介面(`AccountCardPicker`)——比照資產頁視覺的帳戶
/// 挑選 sheet,取代原本橫滑 chips 版的 `AccountSelector`。
///
/// 覆蓋:
/// - 依帳本幣種 + 可交易類型過濾,分組顯示。
/// - 點一行直接回傳該帳戶 id 並關閉。
/// - allowNull=true 時「不選擇帳戶」回傳 `AccountPickResult(null)`。
/// - 取消(不透過任何選項關閉)回傳 `null`,不等於「明確選了不選擇帳戶」
///   ——呼叫端要能區分「使用者放棄操作」跟「使用者主動清空帳戶」。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/providers/statistics_providers.dart';
import 'package:beecount/widgets/biz/account_card_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    await db.customStatement("INSERT INTO accounts "
        "(id, ledger_id, name, currency, type, hidden) VALUES (1, 1, '现金', 'CNY', 'cash', 0)");
    await db.customStatement("INSERT INTO accounts "
        "(id, ledger_id, name, currency, type, hidden) VALUES (2, 1, '招行卡', 'CNY', 'bank_card', 0)");
    // 不同币种账户,不该出现在结果里。
    await db.customStatement("INSERT INTO accounts "
        "(id, ledger_id, name, currency, type, hidden) VALUES (3, 1, '美元户', 'USD', 'bank_card', 0)");
    // 主帳戶(合併帳單分組)容器帳戶——不是真實可入帳的帳戶,不該出現在
    // 交易的帳戶選擇器裡(v33 修正,見 CLAUDE.md「Change documentation」附近
    // 對 account_card_picker.dart 的說明)。
    await db.customStatement("INSERT INTO accounts "
        "(id, ledger_id, name, currency, type, hidden) VALUES (4, 1, '信用卡分组', 'CNY', 'account_group', 0)");
  });

  tearDown(() async => db.close());

  Widget host(Function(AccountPickResult? result) onPicked) {
    return ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        // 真正的 provider 内部会调 logger.info(排它 2 秒防抖存档 timer,测试
        // 框架的严格 timer 检查会因此判失败),这里只关心过滤/选择行为,不需要
        // 真实余额,直接给空表跳过。
        allAccountStatsProvider.overrideWith((ref) async => {}),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                final result =
                    await AccountCardPicker.show(context, ledgerId: 1);
                onPicked(result);
              },
              child: const Text('open'),
            );
          }),
        ),
      ),
    );
  }

  testWidgets('依幣種過濾 + 分組顯示,點一行回傳該帳戶 id', (tester) async {
    AccountPickResult? picked;
    var called = false;
    await tester.pumpWidget(host((r) {
      picked = r;
      called = true;
    }));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // "现金"类型的分类标签文字恰好也是「现金」，所以群组标题、帳戶名稱、
    // 帳戶副標(類型標籤)三處都会出现同样的文字。
    expect(find.text('现金'), findsNWidgets(3));
    expect(find.text('招行卡'), findsOneWidget);
    expect(find.text('美元户'), findsNothing); // 币种不符,过滤掉

    await tester.tap(find.text('招行卡'));
    await tester.pumpAndSettle();

    expect(called, true);
    expect(picked?.accountId, 2);
  });

  testWidgets('主帳戶(account_group 容器)不出現在候選清單裡', (tester) async {
    await tester.pumpWidget(host((_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('信用卡分组'), findsNothing);
  });

  testWidgets('點「不選擇帳戶」明確回傳 AccountPickResult(null)', (tester) async {
    AccountPickResult? picked;
    var called = false;
    await tester.pumpWidget(host((r) {
      picked = r;
      called = true;
    }));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('不选择账户'));
    await tester.pumpAndSettle();

    expect(called, true);
    expect(picked, isNotNull);
    expect(picked!.accountId, null);
  });

  testWidgets('點「取消」回傳 null(而不是 AccountPickResult(null))', (tester) async {
    AccountPickResult? picked = const AccountPickResult(999); // 哨兵初值
    var called = false;
    await tester.pumpWidget(host((r) {
      picked = r;
      called = true;
    }));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(called, true);
    // 关键区分:取消是 null,不是 AccountPickResult(null)——呼叫端据此判断
    // 「维持原选择不变」而不是「使用者主动清空帳戶」。
    expect(picked, isNull);
  });
}
