/// 账户隐藏(#240)E1 钉住 —— 转账表单编辑态(.docs/account-archive/01-product-design.md
/// §五 边界表第 5 行 + §4.2):
///   - 编辑历史转账(有 editingTransactionId)时,若转出账户当前已被隐藏,
///     页面直接把它当成已选中的「转出」卡片显示,并打「已隐藏」灰标,让
///     用户能原样保存(v2 单页式:账户不再是页面上的常驻网格,只有已选中
///     的账户会以卡片形式出现;候选清单改在 `AccountCardPicker` modal 里,
///     不在这个 widget 测试范围)
///   - 新建转账(无 editingTransactionId)不钉住,未选账户的卡片只显示佔位
///     文字,不会出现任何帳戶名稱
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
import 'package:beecount/services/attachment_service.dart';
import 'package:beecount/widgets/transaction/transfer_form.dart';

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
        "(id, ledger_id, name, currency, hidden) VALUES (1, 1, '现金', 'CNY', 0)");
    await db.customStatement("INSERT INTO accounts "
        "(id, ledger_id, name, currency, hidden) VALUES (2, 1, '旧钱包', 'CNY', 1)");
  });

  tearDown(() async => db.close());

  Ledger cnyLedger() => Ledger(
        id: 1,
        name: 'L',
        currency: 'CNY',
        type: 'personal',
        createdAt: DateTime(2026, 1, 1),
        myRole: 'owner',
        memberCount: 1,
        isShared: false,
        monthStartDay: 1,
      );

  Widget host({
    int? editingTransactionId,
    int? initialFromAccountId,
    int? initialToAccountId,
  }) {
    return ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentLedgerProvider
            .overrideWith((ref) => Stream<Ledger?>.value(cnyLedger())),
        // 真正的 provider 内部会调 logger.info(排它 2 秒防抖存档 timer,测试
        // 框架的严格 timer 检查会因此判失败),这里只关心隐藏账户钉住行为,
        // 不需要真实余额,直接给空表跳过(跟 account_card_picker_test.dart
        // 同款处理)。
        allAccountStatsProvider.overrideWith((ref) async => {}),
        // transactionAttachmentsProvider 是真实 Drift `.watch()` 的
        // StreamProvider.family——真的订阅在内存 db 上时,test 的 fake-async
        // 计时器在 widget 树 dispose 后还有一个未触发的取消订阅 Timer 没跑完,
        // 触发 flutter_test 的 `!timersPending` 断言失败。这里只关心隐藏账户
        // 钉住的静态显示,不需要真的监听附件表,直接给空流跳过。
        if (editingTransactionId != null)
          transactionAttachmentsProvider(editingTransactionId)
              .overrideWith((ref) => Stream.value(const [])),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: TransferForm(
            onTransferComplete: () {},
            editingTransactionId: editingTransactionId,
            initialFromAccountId: initialFromAccountId,
            initialToAccountId: initialToAccountId,
          ),
        ),
      ),
    );
  }

  testWidgets('编辑历史转账:转出账户已隐藏 → 钉住显示 + 已隐藏灰标', (tester) async {
    await tester.pumpWidget(host(
      editingTransactionId: 999,
      initialFromAccountId: 2, // 已隐藏账户
    ));
    await tester.pumpAndSettle();

    // 旧钱包(id=2)是初始转出账户,单页式设计下只会以「转出」卡片的名称
    // 形式出现一次;打了「已隐藏」灰标。
    expect(find.text('旧钱包'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    // 转入账户没有初始值,卡片显示佔位文字,现金(id=1)不会出现。
    expect(find.text('现金'), findsNothing);
  });

  testWidgets('新建转账:两侧都是佔位卡片,没有任何账户名称或已隐藏灰标', (tester) async {
    await tester.pumpWidget(host()); // 无 editingTransactionId → 不钉住

    await tester.pumpAndSettle();

    expect(find.text('旧钱包'), findsNothing);
    expect(find.text('现金'), findsNothing);
    expect(find.byIcon(Icons.visibility_off), findsNothing);
  });
}
