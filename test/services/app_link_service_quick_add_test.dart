// SwipeSmart「一键记账」深链（beecount://quick-add?...）测试，见设计文档
// docs/superpowers/specs/2026-09-02-swipesmart-quickadd-deeplink-design.md §5：
// - 账户反查：swipesmartCardId 命中 / hidden 账户不参与 / 非 credit_card 类型不参与 /
//   cardId 空字符串不查
// - 分类模糊比对：单一命中 / 零命中 / 多笔命中降级 / 大小写与空白正规化
// - note 组装：账户对到时不加 note / 没对到时依序拼接 / reward、rate 为 0 或非数字时对应子句不出现
// - 无 currentLedger 时返回 failure，不调用 onNavigate
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/services/platform/app_link_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;
  late ProviderContainer container;
  late AppLinkService service;
  late int ledgerId;

  AppLinkAction? capturedAction;
  AddTransactionParams? capturedParams;

  Uri quickAddUri(Map<String, String> params) =>
      Uri(scheme: 'beecount', host: 'quick-add', queryParameters: params);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    ledgerId = await repo.createLedger(name: 'L');

    container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
    ]);
    container.read(currentLedgerIdProvider.notifier).state = ledgerId;

    capturedAction = null;
    capturedParams = null;
    service = AppLinkService(container);
    service.onNavigate = (action, {params}) {
      capturedAction = action;
      capturedParams = params;
    };
  });

  tearDown(() async {
    service.dispose();
    container.dispose();
    await db.close();
  });

  group('账户反查', () {
    test('swipesmartCardId 精确命中信用卡账户,note 不出现(账户已对到)', () async {
      final aid = await repo.createAccount(
          ledgerId: ledgerId, name: '卡A', type: 'credit_card');
      await repo.updateAccount(aid, swipesmartCardId: 'card-1');

      final result = await service.handleUrl(quickAddUri({'cardId': 'card-1'}));

      expect(result.success, true);
      expect(capturedAction, AppLinkAction.quickAdd);
      expect(capturedParams?.accountId, aid);
      expect(capturedParams?.note, isNull);
    });

    test('hidden 账户不参与匹配', () async {
      final aid = await repo.createAccount(
          ledgerId: ledgerId, name: '卡A', type: 'credit_card');
      await repo.updateAccount(aid, swipesmartCardId: 'card-1', hidden: true);

      final result = await service.handleUrl(quickAddUri({'cardId': 'card-1'}));

      expect(result.success, true);
      expect(capturedParams?.accountId, isNull);
      expect(capturedParams?.note, isNotNull);
    });

    test('非 credit_card 类型账户不参与匹配', () async {
      final aid =
          await repo.createAccount(ledgerId: ledgerId, name: '现金', type: 'cash');
      await repo.updateAccount(aid, swipesmartCardId: 'card-1');

      await service.handleUrl(quickAddUri({'cardId': 'card-1'}));

      expect(capturedParams?.accountId, isNull);
    });

    test('cardId 空字符串直接视为没对到,不触发查询', () async {
      await repo.createAccount(
          ledgerId: ledgerId, name: '卡A', type: 'credit_card');

      final result = await service.handleUrl(quickAddUri({'cardId': ''}));

      expect(result.success, true);
      expect(capturedParams?.accountId, isNull);
    });
  });

  group('分类模糊比对', () {
    test('单一命中才采用', () async {
      await repo.createCategory(name: '餐饮', kind: 'expense');

      await service.handleUrl(quickAddUri({'category': '餐饮美食'}));

      expect(capturedParams?.categoryId, isNotNull);
    });

    test('零命中当没对到,note 带原始文字提示', () async {
      await repo.createCategory(name: '交通', kind: 'expense');

      await service.handleUrl(quickAddUri({'category': '完全不相关'}));

      expect(capturedParams?.categoryId, isNull);
      expect(capturedParams?.note, contains('分类:完全不相关'));
    });

    test('多笔模糊命中降级为没对到', () async {
      await repo.createCategory(name: '餐', kind: 'expense');
      await repo.createCategory(name: '早餐店', kind: 'expense');

      await service.handleUrl(quickAddUri({'category': '餐'}));

      expect(capturedParams?.categoryId, isNull);
    });

    test('名称正规化:大小写与首尾空白不影响比对', () async {
      await repo.createCategory(name: ' ABC ', kind: 'expense');

      await service.handleUrl(quickAddUri({'category': 'abc'}));

      expect(capturedParams?.categoryId, isNotNull);
    });

    test('子分类(二层)也参与比对', () async {
      final topId = await repo.createCategory(name: '餐饮', kind: 'expense');
      final subId = await repo.createCategory(
          name: '早餐', kind: 'expense', level: 2, parentId: topId);

      await service.handleUrl(quickAddUri({'category': '早餐店'}));

      expect(capturedParams?.categoryId, subId);
    });
  });

  group('note 组装', () {
    test('账户对到时完全不加 note', () async {
      final aid = await repo.createAccount(
          ledgerId: ledgerId, name: '卡A', type: 'credit_card');
      await repo.updateAccount(aid, swipesmartCardId: 'card-1');

      await service.handleUrl(quickAddUri({
        'cardId': 'card-1',
        'bankName': '国泰',
        'cardName': 'CUBE卡',
        'reward': '99',
        'rate': '0.05',
      }));

      expect(capturedParams?.note, isNull);
    });

    test('reward/rate 为 0 或非数字时对应子句不出现', () async {
      await service.handleUrl(quickAddUri({
        'bankName': '国泰',
        'cardName': 'CUBE卡',
        'reward': '0',
        'rate': 'abc',
      }));

      final note = capturedParams!.note!;
      expect(note, isNot(contains('预估回馈')));
      expect(note, isNot(contains('回馈率')));
      expect(note, contains('尚未绑定 BeeCount 账户'));
    });

    test('账户没对到时依序拼接分类/回馈/回馈率/绑定引导', () async {
      await repo.createCategory(name: '娱乐', kind: 'expense');

      await service.handleUrl(quickAddUri({
        'bankName': '国泰',
        'cardName': 'CUBE卡',
        'category': '完全对不上的分类',
        'reward': '12.7',
        'rate': '0.035',
      }));

      final note = capturedParams!.note!;
      expect(note, startsWith('SwipeSmart 建议刷:国泰 CUBE卡（'));
      expect(note, contains('分类:完全对不上的分类'));
      expect(note, contains('预估回馈 13'));
      expect(note, contains('回馈率 3.5%'));
      expect(note, contains('尚未绑定 BeeCount 账户'));
      // 顺序:分类 → 预估回馈 → 回馈率 → 绑定引导
      final clauseText = note.substring(
          note.indexOf('（') + 1, note.lastIndexOf('）'));
      final parts = clauseText.split('，');
      expect(parts[0], contains('分类:'));
      expect(parts[1], contains('预估回馈'));
      expect(parts[2], contains('回馈率'));
      expect(parts[3], contains('尚未绑定'));
    });
  });

  test('无 currentLedger 时返回 failure,不调用 onNavigate', () async {
    container.read(currentLedgerIdProvider.notifier).state = 999999;

    final result = await service.handleUrl(quickAddUri({'merchant': 'x'}));

    expect(result.success, false);
    expect(capturedAction, isNull);
    expect(capturedParams, isNull);
  });

  test('金额可解析且为正才带入,否则留空不挡流程', () async {
    await service.handleUrl(quickAddUri({'amount': '128.5'}));
    expect(capturedParams?.amount, 128.5);

    await service.handleUrl(quickAddUri({'amount': '0'}));
    expect(capturedParams?.amount, isNull);

    await service.handleUrl(quickAddUri({'amount': 'not-a-number'}));
    expect(capturedParams?.amount, isNull);

    final result = await service.handleUrl(quickAddUri({}));
    expect(result.success, true);
    expect(capturedParams?.amount, isNull);
  });
}
