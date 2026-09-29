// SyncEngine 端到端测试。
//
// 用 in-memory Drift + FakeBeeCountCloudProvider 跑完整 pull/push/apply
// 链路。Day 1:smoke test 验证 fake provider 能跟 SyncEngine 兜上,跑通空 pull
// 路径。Day 2 加更多场景(脏数据 / 单飞 / web 新建账本 / busy retry 等)。

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/cloud/sync/change_tracker.dart';
import 'package:beecount/cloud/sync/sync_engine.dart';
import 'package:beecount/cloud/sync_service.dart' show SyncDiff;
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

import '_fakes/fake_beecount_cloud_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late ChangeTracker changeTracker;
  late LocalRepository repo;
  late FakeBeeCountCloudProvider provider;
  late SyncEngine engine;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    changeTracker = ChangeTracker(db);
    repo = LocalRepository(db, changeTracker: changeTracker);
    provider = FakeBeeCountCloudProvider();
    engine = SyncEngine(
      db: db,
      provider: provider,
      changeTracker: changeTracker,
      repo: repo,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('smoke', () {
    test('空 server → pull 返 0,不 prime LookupCache', () async {
      final applied = await engine.pull('');
      expect(applied, 0);
      // pullChanges 只调一次(探针),没数据直接 return
      expect(provider.pullCalls, hasLength(1));
      expect(provider.pullCalls.first.since, 0); // 初始 cursor=0
      expect(provider.pullCalls.first.persistCursor, isFalse,
          reason: 'app 侧接管 cursor,不让 cloud-sync 包持久化');
    });

    test('cursor 在 SharedPreferences 持久化', () async {
      // 第一次空 pull 不推进 cursor
      await engine.pull('');
      final prefs = await SharedPreferences.getInstance();
      // 应该还没有 app cursor key
      final keys =
          prefs.getKeys().where((k) => k.startsWith('app_pull_cursor_'));
      expect(keys, isEmpty, reason: '空 pull 不应推进 cursor');
    });
  });

  group('apply 远端 change', () {
    test('server 推 transaction change → 本地 transactions 表 insert', () async {
      // 准备:本地建好 ledger 和 category(因为 transaction 引用它们)
      final ledgerId = await db.into(db.ledgers).insert(
            LedgersCompanion.insert(
              name: 'L1',
              syncId: const Value('ledger-1'),
            ),
          );
      final catId = await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              name: 'Food',
              kind: 'expense',
              syncId: const Value('cat-1'),
            ),
          );

      // server 推一条 transaction
      provider.pushFakeChange(
        entityType: 'transaction',
        entitySyncId: 'tx-A',
        ledgerId: 'ledger-1',
        payload: {
          'syncId': 'tx-A',
          'type': 'expense',
          'amount': 12.5,
          'happenedAt': '2026-05-01T10:00:00Z',
          'note': 'lunch',
          'categoryName': 'Food',
          'categoryKind': 'expense',
          'categoryId': 'cat-1',
        },
      );

      final applied = await engine.pull('1');
      expect(applied, 1);

      final txs = await db.select(db.transactions).get();
      expect(txs, hasLength(1));
      expect(txs.first.syncId, 'tx-A');
      expect(txs.first.amount, 12.5);
      expect(txs.first.ledgerId, ledgerId);
      expect(txs.first.categoryId, catId);
    });

    test('apply 成功后 cursor 推进到本页末尾', () async {
      await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));
      await db.into(db.categories).insert(CategoriesCompanion.insert(
          name: 'C', kind: 'expense', syncId: const Value('C1')));

      // 推 3 条 change
      for (var i = 0; i < 3; i++) {
        provider.pushFakeChange(
          entityType: 'transaction',
          entitySyncId: 'tx-$i',
          ledgerId: 'L1',
          payload: {
            'syncId': 'tx-$i',
            'type': 'expense',
            'amount': 10.0,
            'happenedAt': '2026-05-01T10:00:00Z',
            'categoryName': 'C',
            'categoryKind': 'expense',
            'categoryId': 'C1',
          },
        );
      }

      final applied = await engine.pull('1');
      expect(applied, 3);

      // 再次 pull 应该是空(cursor 已到末尾)
      final applied2 = await engine.pull('1');
      expect(applied2, 0);
    });
  });

  group('web 新建账本场景', () {
    test('server 推 ledger entity change → 本地 ledgers 表 insert', () async {
      // 本地没这账本
      expect((await db.select(db.ledgers).get()), isEmpty);

      // server 推一条 ledger:upsert change(模拟 web 新建账本)
      provider.pushFakeChange(
        entityType: 'ledger',
        entitySyncId: 'new-ledger-uuid',
        ledgerId: 'new-ledger-uuid',
        payload: {
          'ledgerName': 'My New Ledger',
          'currency': 'USD',
        },
      );

      await engine.pull('');

      final ledgers = await db.select(db.ledgers).get();
      expect(ledgers, hasLength(1));
      expect(ledgers.first.syncId, 'new-ledger-uuid');
      expect(ledgers.first.name, 'My New Ledger');
      expect(ledgers.first.currency, 'USD');
    });

    test('server 推 ledger change 但 payload 缺 ledgerName → 跳过', () async {
      provider.pushFakeChange(
        entityType: 'ledger',
        entitySyncId: 'broken-ledger',
        ledgerId: 'broken-ledger',
        payload: {}, // 没 ledgerName
      );

      await engine.pull('');

      // 本地仍空
      expect((await db.select(db.ledgers).get()), isEmpty);
    });
  });

  group('pull 单飞锁', () {
    test('同时 2 个 pull → server pullChanges 只调一次', () async {
      // 同时触发 2 个 pull,合并到同一个 in-flight Future
      final f1 = engine.pull('');
      final f2 = engine.pull('');
      await Future.wait([f1, f2]);

      expect(provider.pullCalls, hasLength(1),
          reason: '单飞锁应让第二个 caller 复用 in-flight 结果');
    });

    test('replay(sinceOverride 非空)等待 in-flight 完成后独立跑', () async {
      // 普通 pull
      final f1 = engine.pull('');
      // replay 等 in-flight 完后独立跑
      final f2 = engine.pull('', sinceOverride: 0);
      await Future.wait([f1, f2]);

      // 2 次 pullChanges 调用:普通 pull 1 次 + replay 1 次
      expect(provider.pullCalls, hasLength(2));
    });
  });

  group('错误恢复', () {
    test('pullChanges 抛错 → engine.pull 抛出,cursor 不推进', () async {
      provider.pullErrorInjector = (since) => Exception('network error');

      // sync 入口的 catch 会兜住错误,但底层 pull 应抛
      // 用 .pull() 直接调,期待抛
      await expectLater(engine.pull(''), throwsA(isA<Exception>()));

      // cursor 未推进 — read 仍是 0
      final cursor = await engine.appCursor.read();
      expect(cursor, 0);
    });

    test(
        'apply 时单条 change payload 异常 → 整页 rollback + 错误入 sync_pull_errors + cursor 不推进',
        () async {
      // 推 5 条 change,第 3 条 payload 用错误类型(categoryId 传 int 而不是 string)
      // 让 _applyTransactionChange 内 `payload['categoryId'] as String?` 抛 TypeError
      await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));

      for (var i = 0; i < 5; i++) {
        final payload = <String, dynamic>{
          'syncId': 'tx-$i',
          'type': 'expense',
          'amount': 10.0,
          'happenedAt': '2026-05-01T10:00:00Z',
        };
        if (i == 2) {
          // 故意脏数据:categoryId 应是 String,这里传 int
          payload['categoryId'] = 12345;
        }
        provider.pushFakeChange(
          entityType: 'transaction',
          entitySyncId: 'tx-$i',
          ledgerId: 'L1',
          payload: payload,
        );
      }

      final applied = await engine.pull('');
      // 整页 rollback,applied=0
      expect(applied, 0);

      // 本地 transactions 表应该是空(rollback 生效,不是只插了前两条)
      final txs = await db.select(db.transactions).get();
      expect(txs, isEmpty, reason: 'apply 抛错时整页 rollback,前面已 INSERT 的也应回滚');

      // cursor 不推进(读 0)
      expect(await engine.appCursor.read(), 0);

      // 错误入 sync_pull_errors 表
      final errors = await engine.pullErrors.watchUnresolved().first;
      expect(errors, hasLength(1));
      expect(errors.first.changeId, 3); // 第 3 条触发
      expect(errors.first.entityType, 'transaction');
      expect(errors.first.entitySyncId, 'tx-2');
      expect(errors.first.errorClass, contains('TypeError'));
    });

    test('修复后 server 推同 change_id 新版本 → markResolved', () async {
      await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));

      // 先推一条会抛错的
      provider.pushFakeChange(
        entityType: 'transaction',
        entitySyncId: 'tx-A',
        ledgerId: 'L1',
        payload: {
          'categoryId': 999, // 错误类型
          'amount': 10.0,
        },
      );
      await engine.pull('');
      expect((await engine.pullErrors.watchUnresolved().first), hasLength(1));

      // 通过 markResolved 模拟"server 修了 + app 拉到新版本":
      // 实际逻辑应该是 server push 新 change_id 触发 apply 成功后 markResolved
      // 这里直接调测试 marker
      await engine.pullErrors.markResolved(1);
      expect((await engine.pullErrors.watchUnresolved().first), isEmpty);
    });
  });

  group('cursor 持久化', () {
    test('apply 成功后 cursor 写入 SharedPreferences,跨 SyncEngine 实例可读', () async {
      await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));
      await db.into(db.categories).insert(CategoriesCompanion.insert(
          name: 'C', kind: 'expense', syncId: const Value('C1')));

      for (var i = 0; i < 3; i++) {
        provider.pushFakeChange(
          entityType: 'transaction',
          entitySyncId: 'tx-$i',
          ledgerId: 'L1',
          payload: {
            'syncId': 'tx-$i',
            'type': 'expense',
            'amount': 10.0,
            'happenedAt': '2026-05-01T10:00:00Z',
            'categoryId': 'C1',
            'categoryName': 'C',
            'categoryKind': 'expense',
          },
        );
      }

      await engine.pull('');
      final cursor1 = await engine.appCursor.read();
      expect(cursor1, 3, reason: '3 条 change 后 cursor 应到 changeId=3');

      // 模拟 app 重启:新建 SyncEngine,读 cursor 继续
      final engine2 = SyncEngine(
        db: db,
        provider: provider,
        changeTracker: changeTracker,
        repo: repo,
      );
      final cursor2 = await engine2.appCursor.read();
      expect(cursor2, 3,
          reason: '新 SyncEngine 实例应从 SharedPreferences 读到上次 cursor');

      // 第二个 engine pull 应该看到"无变更"(空 pull)
      final applied = await engine2.pull('');
      expect(applied, 0);
      // 验证 pullChanges 是从 since=3 开始,不是从 0 重拉
      expect(provider.pullCalls.last.since, 3);
    });
  });

  group('replay (sinceOverride=0)', () {
    test('replay 从头拉所有 change,即使 cursor 已推进', () async {
      await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));
      await db.into(db.categories).insert(CategoriesCompanion.insert(
          name: 'C', kind: 'expense', syncId: const Value('C1')));

      for (var i = 0; i < 3; i++) {
        provider.pushFakeChange(
          entityType: 'transaction',
          entitySyncId: 'tx-$i',
          ledgerId: 'L1',
          payload: {
            'syncId': 'tx-$i',
            'type': 'expense',
            'amount': 10.0,
            'happenedAt': '2026-05-01T10:00:00Z',
            'categoryId': 'C1',
            'categoryName': 'C',
            'categoryKind': 'expense',
          },
        );
      }

      // 第一次 pull,cursor 推到 3
      await engine.pull('');
      expect(await engine.appCursor.read(), 3);

      // replay 从 0 拉 — 由于 apply 是 syncId upsert 幂等,重拉不会重复插
      provider.pullCalls.clear();
      final applied = await engine.pull('', sinceOverride: 0);
      expect(applied, 3, reason: 'replay 应重新 apply 3 条');
      expect(provider.pullCalls.first.since, 0, reason: 'replay 必须从 since=0 拉');

      // 本地 transactions 仍是 3 条(没 dup)
      final txs = await db.select(db.transactions).get();
      expect(txs, hasLength(3));
    });
  });

  group('entity-type 一次性 backfill(v35 card_reward_rule)', () {
    test('首次 sync 用一次性 replayAllChanges 补齐,之后恢复增量 pull', () async {
      final ledgerId = await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));
      await db.into(db.categories).insert(CategoriesCompanion.insert(
          name: 'C', kind: 'expense', syncId: const Value('C1')));
      provider.pushFakeLedgerSnapshot(ledgerId: 'L1');

      for (var i = 0; i < 3; i++) {
        provider.pushFakeChange(
          entityType: 'transaction',
          entitySyncId: 'tx-$i',
          ledgerId: 'L1',
          payload: {
            'syncId': 'tx-$i',
            'type': 'expense',
            'amount': 10.0,
            'happenedAt': '2026-05-01T10:00:00Z',
            'categoryId': 'C1',
            'categoryName': 'C',
            'categoryKind': 'expense',
          },
        );
      }

      // 模拟"旧版本已经用一段时间,cursor 早就推进过"——直接调 pull(不经过
      // sync()/_pullWithOneTimeBackfills),cursor 推到 3,但 backfill 标记未写。
      await engine.pull('');
      expect(await engine.appCursor.read(), 3);
      expect(await engine.appCursor.hasBackfilled('card_reward_rule_v35'),
          isFalse);

      // 模拟升级后 server 端多了一条新变更
      provider.pushFakeChange(
        entityType: 'transaction',
        entitySyncId: 'tx-3',
        ledgerId: 'L1',
        payload: {
          'syncId': 'tx-3',
          'type': 'expense',
          'amount': 20.0,
          'happenedAt': '2026-05-02T10:00:00Z',
          'categoryId': 'C1',
          'categoryName': 'C',
          'categoryKind': 'expense',
        },
      );

      provider.pullCalls.clear();
      final result = await engine.sync(ledgerId: ledgerId.toString());
      expect(result.hasError, isFalse);
      expect(provider.pullCalls, isNotEmpty);
      expect(provider.pullCalls.first.since, 0,
          reason: '一次性 backfill 应从 change_id=0 重放,而不是从已推进的 cursor 继续');
      expect(
          await engine.appCursor.hasBackfilled('card_reward_rule_v35'), isTrue);
      expect(await engine.appCursor.read(), 4);

      final txs = await db.select(db.transactions).get();
      expect(txs, hasLength(4),
          reason: '4 条 tx 都应落地,前 3 条 replay 幂等 upsert 不重复插入');

      // 第二次 sync:backfill 已标记过,应该恢复正常增量 pull(since=当前 cursor,不是 0)
      provider.pullCalls.clear();
      final result2 = await engine.sync(ledgerId: ledgerId.toString());
      expect(result2.hasError, isFalse);
      if (provider.pullCalls.isNotEmpty) {
        expect(provider.pullCalls.first.since, isNot(0),
            reason: 'backfill 只应触发一次,第二次应是正常增量 pull');
      }
    });

    test('backfill replay 失败时不阻塞 sync(),也不标记完成(下次重试)', () async {
      final ledgerId = await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));
      provider.pushFakeLedgerSnapshot(ledgerId: 'L1');
      provider.pullErrorInjector = (since) => Exception('network error');

      final result = await engine.sync(ledgerId: ledgerId.toString());

      expect(result.hasError, isTrue);
      expect(
          await engine.appCursor.hasBackfilled('card_reward_rule_v35'), isFalse,
          reason: 'replay 失败不应标记完成,下次 sync 要重试');
    });
  });

  group('entity-type 一次性 backfill(v47 account.swipesmartCardId)', () {
    test('装了这版 App 前就在 server 端對照好的账户,首次 sync 补齐',
        () async {
      final ledgerId = await db.into(db.ledgers).insert(LedgersCompanion.insert(
          name: 'L', syncId: const Value('L1')));
      final accId = await db.into(db.accounts).insert(AccountsCompanion.insert(
            name: '大戶信用卡',
            ledgerId: ledgerId,
            type: const Value('credit_card'),
            syncId: const Value('acc-1'),
          ));
      provider.pushFakeLedgerSnapshot(ledgerId: 'L1');

      // 模拟:web 端(或 server 自動比對)在这版 App 装上 swipesmartCardId
      // 字段**之前**就已经写好了對照 —— 老版本 App 读到这个 change 时不认识
      // 这个 key,其它字段照常 apply,cursor 照常前进。这里不走
      // engine.pull(直接调用会用**当前**代码 apply,已经认得这个字段,没法
      // 复现"老版本不认得"),改成直接把 cursor commit 到 1,模拟老设备已经
      // 越过这条 change 而完全没落地 swipesmartCardId 的历史状态。
      provider.pushFakeChange(
        entityType: 'account',
        entitySyncId: 'acc-1',
        ledgerId: 'L1',
        payload: {
          'syncId': 'acc-1',
          'name': '大戶信用卡',
          'type': 'credit_card',
          'currency': 'CNY',
          'initialBalance': 0.0,
          'sortOrder': 0,
          'swipesmartCardId': 'sw-dawho',
        },
      );
      await engine.appCursor.commit(1);
      var a = await (db.select(db.accounts)..where((t) => t.id.equals(accId)))
          .getSingle();
      expect(a.swipesmartCardId, isNull,
          reason: '模拟老版本 App 不认识这个字段,读不到值(cursor 已越过)');

      // 升级到这版 App 后,第一次 sync 应该侦测到待补齐 tag,从 0 重放一次。
      provider.pullCalls.clear();
      final result = await engine.sync(ledgerId: ledgerId.toString());
      expect(result.hasError, isFalse);
      expect(provider.pullCalls.first.since, 0,
          reason: '一次性 backfill 应从 change_id=0 重放');
      expect(
          await engine.appCursor
              .hasBackfilled('account_swipesmart_card_id_v47'),
          isTrue);

      a = await (db.select(db.accounts)..where((t) => t.id.equals(accId)))
          .getSingle();
      expect(a.swipesmartCardId, 'sw-dawho',
          reason: 'replay 后应该補齊历史對照');
    });
  });

  group('push 路径', () {
    test('本地有 unpushed change → engine.push 推到 server', () async {
      // 本地通过 repo 写一条 tx(会触发 changeTracker.recordLedgerChange)
      final ledgerId = await db.into(db.ledgers).insert(
            LedgersCompanion.insert(
              name: 'L',
              syncId: const Value('L1'),
            ),
          );
      await repo.insertTransactionsBatch([
        TransactionsCompanion.insert(
          ledgerId: ledgerId,
          type: 'expense',
          amount: 99.5,
          syncId: const Value('tx-push-1'),
        ),
      ]);

      // 验证 local_changes 已登记
      final unpushed =
          await changeTracker.getUnpushedChangesForLedger(ledgerId);
      expect(unpushed, hasLength(1));
      expect(unpushed.first.entityType, 'transaction');

      // 触发 engine.push
      final pushed = await engine.push(ledgerId.toString());
      expect(pushed, 1);

      // fake provider 收到 1 个 batch,内含 1 条 change
      expect(provider.pushedBatches, hasLength(1));
      expect(provider.pushedBatches.first, hasLength(1));
      expect(provider.pushedBatches.first.first['entity_sync_id'], 'tx-push-1');
      expect(provider.pushedBatches.first.first['action'], 'upsert');

      // local_changes 已 markPushed
      final remaining =
          await changeTracker.getUnpushedChangesForLedger(ledgerId);
      expect(remaining, isEmpty);
    });

    test('push 后再调 → 无新变更 → 不发 batch', () async {
      final ledgerId = await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));
      await repo.insertTransactionsBatch([
        TransactionsCompanion.insert(
            ledgerId: ledgerId,
            type: 'expense',
            amount: 10.0,
            syncId: const Value('tx-1')),
      ]);
      await engine.push(ledgerId.toString());
      expect(provider.pushedBatches, hasLength(1));

      // 第二次 push 无变更
      final pushed2 = await engine.push(ledgerId.toString());
      expect(pushed2, 0);
      expect(provider.pushedBatches, hasLength(1), reason: '无变更不应发新 batch');
    });
  });

  group('v55 分类颜色 push backfill', () {
    // 模拟 db.dart v55 migration 2026-09-06 之前的 bug 场景:分类早就正常同步
    // 过一次(local_changes 里已经有一条记录、且已标记 pushed),后来 color
    // 字段被 customStatement 之类绕过 outbox 的路径直接改掉,没有产生任何新
    // local_changes 记录。_backfillLegacyUserGlobalChanges 的 knownSyncIds
    // 检查会命中这个 syncId(因为旧记录还在)而跳过,只有专门的
    // _backfillLegacyCategoryColorPush 才会补推。
    Future<int> insertLegacyColoredCategory({String syncId = 'cat-legacy-1'}) async {
      final catId = await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              name: 'Legacy',
              kind: 'expense',
              syncId: Value(syncId),
            ),
          );
      // 模拟"曾经正常同步过一次"——登记 + 标记为已推送。
      await changeTracker.recordUserGlobalChange(
        entityType: 'category',
        entityId: catId,
        entitySyncId: syncId,
        action: 'upsert',
      );
      final oldChange =
          await changeTracker.getUnpushedChangesForLedger(0);
      await changeTracker.markPushed(oldChange.map((c) => c.id).toList());
      // 模拟旧版 v55 migration 用 customStatement 绕过 outbox 直接改 color。
      await db.customStatement(
          'UPDATE categories SET color = ? WHERE id = ?', ['#FF5722', catId]);
      return catId;
    }

    test('legacy 分类(有色但 outbox 之外改的)→ 首次 push 时补推一次', () async {
      await insertLegacyColoredCategory();

      final pushed = await engine.pushUserGlobalEntities();
      expect(pushed, 1);

      expect(provider.pushedBatches, hasLength(1));
      final batch = provider.pushedBatches.first;
      expect(batch, hasLength(1));
      expect(batch.first['entity_type'], 'category');
      expect(batch.first['entity_sync_id'], 'cat-legacy-1');
      expect(batch.first['action'], 'upsert');
      expect((batch.first['payload'] as Map)['color'], '#FF5722');

      expect(await engine.appCursor.hasBackfilled('category_color_push_v55'),
          isTrue);
    });

    test('补推标记已存在 → 不重复补推(即使又有别的 legacy 分类)', () async {
      await insertLegacyColoredCategory();
      await engine.pushUserGlobalEntities();
      expect(provider.pushedBatches, hasLength(1));

      // 再插一个"legacy 有色"分类,但标记已经写过 → 不应该再被这套 backfill 捞到
      await insertLegacyColoredCategory(syncId: 'cat-legacy-2');
      final pushed2 = await engine.pushUserGlobalEntities();
      expect(pushed2, 0,
          reason: '补推标记已经落过一次,不会对新的 legacy 分类再跑一遍全量扫描');
      expect(provider.pushedBatches, hasLength(1));
    });

    test('没有颜色的分类不受影响', () async {
      // 走跟 insertLegacyColoredCategory 同样的"已知 syncId、已标记 pushed"
      // 前置状态,只是不碰 color——这样才是单独隔离验证 backfill 只挑有色的,
      // 而不是碰巧被 _backfillLegacyUserGlobalChanges(专门对付完全没有
      // local_changes 记录的实体)捞到。
      final catId = await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              name: 'NoColor',
              kind: 'expense',
              syncId: const Value('cat-no-color'),
            ),
          );
      await changeTracker.recordUserGlobalChange(
        entityType: 'category',
        entityId: catId,
        entitySyncId: 'cat-no-color',
        action: 'upsert',
      );
      final oldChange = await changeTracker.getUnpushedChangesForLedger(0);
      await changeTracker.markPushed(oldChange.map((c) => c.id).toList());

      final pushed = await engine.pushUserGlobalEntities();
      expect(pushed, 0);
      expect(provider.pushedBatches, isEmpty);
    });
  });

  group('recordChanges=false:fullPull 不反向回流', () {
    test(
        'LocalRepository.insertTransactionsBatch(recordChanges: false) → 不写 local_changes',
        () async {
      final ledgerId = await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));

      // 模拟 fullPull 路径:DataImportService 大批量插 + recordChanges=false
      await repo.insertTransactionsBatch(
        List.generate(
            50,
            (i) => TransactionsCompanion.insert(
                  ledgerId: ledgerId,
                  type: 'expense',
                  amount: i.toDouble(),
                  syncId: Value('fullpull-tx-$i'),
                )),
        recordChanges: false,
      );

      // 本地有 50 条 tx,但 local_changes 表为空(不会反向 push)
      final txs = await db.select(db.transactions).get();
      expect(txs, hasLength(50));
      final changes = await changeTracker.getUnpushedChangesForLedger(ledgerId);
      expect(changes, isEmpty,
          reason: 'fullPull 写入不应触发 changeTracker.recordLedgerChange');
    });

    test('默认 recordChanges=true 路径仍正常登记', () async {
      final ledgerId = await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));
      await repo.insertTransactionsBatch([
        TransactionsCompanion.insert(
            ledgerId: ledgerId,
            type: 'expense',
            amount: 1.0,
            syncId: const Value('normal-tx')),
      ]); // 不传 recordChanges,走默认 true
      final changes = await changeTracker.getUnpushedChangesForLedger(ledgerId);
      expect(changes, hasLength(1));
    });
  });

  group('附件 upload/download', () {
    test('uploadAttachments 上传未同步附件 → 回填 cloudFileId + 登记 update change',
        () async {
      final ledgerId = await db.into(db.ledgers).insert(
            LedgersCompanion.insert(name: 'L', syncId: const Value('L1')),
          );
      // 插一条 tx + 一个未上传的 attachment
      final txId = await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              ledgerId: ledgerId,
              type: 'expense',
              amount: 5.0,
              syncId: const Value('tx-with-att'),
            ),
          );
      await db.into(db.transactionAttachments).insert(
            TransactionAttachmentsCompanion.insert(
              transactionId: txId,
              fileName: 'never-existing-file.jpg',
            ),
          );

      // uploadAttachments 会跑(虽然本地文件不存在,会 skip,但不抛错)
      final uploaded = await engine.uploadAttachments(ledgerId: ledgerId);
      // 本地文件不存在 → uploaded=0,不抛
      expect(uploaded, 0);
      // 没真发 HTTP(因为没文件)
      expect(provider.uploadAttachmentCalls, isEmpty);
    });
  });

  group('共享账本 Editor 不 fullPush', () {
    test('isShared=true + myRole=editor → 不触发 fullPush', () async {
      // 本地标记此账本是共享 Editor
      final ledgerId = await db.into(db.ledgers).insert(
            LedgersCompanion.insert(
              name: 'Shared',
              syncId: const Value('shared-l1'),
              isShared: const Value(true),
              myRole: const Value('editor'),
            ),
          );
      // 远端不返此账本(模拟 owner 在,但 server list 路径下 Editor 角色看到的视角)
      // — 即使 storage.list 没返,Editor 也不应 fullPush(会覆盖 Owner 数据)
      final result = await engine.sync(ledgerId: ledgerId.toString());

      expect(provider.writeCreateLedgerCalls, isEmpty,
          reason: 'Editor 角色永不应触发 fullPush');
      expect(result.hasError, isFalse);
    });
  });

  group('apply 各种 entity type', () {
    test('account / category / tag insert', () async {
      provider.pushFakeChange(
        entityType: 'category',
        entitySyncId: 'cat-X',
        ledgerId: '',
        payload: {
          'name': 'NewCat',
          'kind': 'expense',
          'sortOrder': 0,
        },
      );
      provider.pushFakeChange(
        entityType: 'account',
        entitySyncId: 'acc-X',
        ledgerId: '0',
        payload: {
          'name': 'NewAcc',
          'type': 'cash',
          'currency': 'CNY',
        },
      );
      provider.pushFakeChange(
        entityType: 'tag',
        entitySyncId: 'tag-X',
        ledgerId: '0',
        payload: {'name': 'NewTag'},
      );

      final applied = await engine.pull('');
      expect(applied, 3);

      final cats = await db.select(db.categories).get();
      expect(cats.where((c) => c.syncId == 'cat-X'), hasLength(1));
      final accs = await db.select(db.accounts).get();
      expect(accs.where((a) => a.syncId == 'acc-X'), hasLength(1));
      final tags = await db.select(db.tags).get();
      expect(tags.where((t) => t.syncId == 'tag-X'), hasLength(1));
    });

    test('apply update 已存在的实体(按 syncId upsert,不重复 insert)', () async {
      // 本地先有
      final catId = await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              name: 'Original',
              kind: 'expense',
              syncId: const Value('cat-upd'),
            ),
          );
      // server 推 update,改名
      provider.pushFakeChange(
        entityType: 'category',
        entitySyncId: 'cat-upd',
        ledgerId: '',
        payload: {
          'name': 'Renamed',
          'kind': 'expense',
        },
      );

      await engine.pull('');

      final cats = await (db.select(db.categories)
            ..where((c) => c.id.equals(catId)))
          .get();
      expect(cats, hasLength(1)); // 没新增,只更新
      expect(cats.first.name, 'Renamed');
    });
  });

  group('apply delete change', () {
    test('server 推 transaction:delete → 本地行被删 + cache 同步移除', () async {
      // 准备:本地有一条 tx
      final ledgerId = await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              ledgerId: ledgerId,
              type: 'expense',
              amount: 8.0,
              syncId: const Value('tx-to-delete'),
            ),
          );

      // server 推一条 delete
      provider.pushFakeChange(
        entityType: 'transaction',
        entitySyncId: 'tx-to-delete',
        ledgerId: 'L1',
        action: 'delete',
      );

      await engine.pull('');

      // 本地被删
      final remaining = await db.select(db.transactions).get();
      expect(remaining, isEmpty);
    });
  });

  group('fullPush 路径', () {
    test('远端无此账本 → SyncEngine.sync 触发 fullPush 流程', () async {
      // 本地建账本 + 1 条 tx
      final ledgerId = await db.into(db.ledgers).insert(
            LedgersCompanion.insert(
              name: 'My Ledger',
              syncId: const Value('my-ledger-uuid'),
              currency: const Value('CNY'),
            ),
          );
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
                name: 'C', kind: 'expense', syncId: const Value('C1')),
          );
      await repo.insertTransactionsBatch([
        TransactionsCompanion.insert(
            ledgerId: ledgerId,
            type: 'expense',
            amount: 50.0,
            syncId: const Value('tx-full-1')),
      ]);

      // server storage.list 返空 → fullPush 决策触发
      // (provider 默认就是空)

      final result = await engine.sync(ledgerId: ledgerId.toString());

      // fullPush 路径:writeCreateLedger 被调
      expect(provider.writeCreateLedgerCalls, isNotEmpty,
          reason: 'fullPush 应调 writeCreateLedger 显式建 server 账本');
      // 不应有 error
      expect(result.hasError, isFalse);
    });

    test('远端有此账本 → 走增量 push,不 fullPush', () async {
      final ledgerId = await db.into(db.ledgers).insert(
            LedgersCompanion.insert(
              name: 'L',
              syncId: const Value('existing-uuid'),
            ),
          );
      // 标记 server 端已有此账本
      provider.pushFakeLedgerSnapshot(ledgerId: 'existing-uuid');

      // 加一条 unpushed change
      await repo.insertTransactionsBatch([
        TransactionsCompanion.insert(
            ledgerId: ledgerId,
            type: 'expense',
            amount: 5.0,
            syncId: const Value('tx-incr')),
      ]);

      final result = await engine.sync(ledgerId: ledgerId.toString());

      expect(provider.writeCreateLedgerCalls, isEmpty,
          reason: '远端已有账本时不应触发 fullPush');
      expect(result.hasError, isFalse);
      // 增量 push 应有 1 batch
      expect(provider.pushedBatches, hasLength(1));
    });
  });

  group('SyncEvent stream(PR 1 解耦改造)', () {
    test('WS pull 完成 emit PullCompleted 到 events stream', () async {
      await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));
      await db.into(db.categories).insert(CategoriesCompanion.insert(
          name: 'C', kind: 'expense', syncId: const Value('C1')));

      // 订阅 events
      final received = <SyncEvent>[];
      final sub = engine.events.listen(received.add);

      engine.startListeningRealtime();
      provider.pushFakeChange(
        entityType: 'transaction',
        entitySyncId: 'tx-event',
        ledgerId: 'L1',
        payload: {
          'syncId': 'tx-event',
          'type': 'expense',
          'amount': 1.0,
          'happenedAt': '2026-05-01T10:00:00Z',
          'categoryId': 'C1',
          'categoryName': 'C',
          'categoryKind': 'expense',
        },
      );
      provider.emitRealtimeEvent(BeeCountCloudRealtimeEvent(
        type: 'sync_change',
        ledgerId: 'L1',
        rawData: const {},
      ));

      await Future.delayed(const Duration(milliseconds: 1500));

      engine.stopListeningRealtime();
      await sub.cancel();

      // 至少有一个 PullCompleted 事件
      final pullEvents = received.whereType<PullCompleted>().toList();
      expect(pullEvents, isNotEmpty);
      expect(pullEvents.last.ledgerId, 'L1');
      expect(pullEvents.last.applied, greaterThan(0));
    });

    test(
        'sync push 后清缓存 + emit,getStatus 从 localNewer 刷新为 inSync'
        '(修复:同步完成后「我的」页状态自动更新,不用手动下拉)', () async {
      final ledgerId = await db.into(db.ledgers).insert(
            LedgersCompanion.insert(
              name: 'L',
              syncId: const Value('existing-uuid'),
            ),
          );
      // 远端已有此账本 → 走增量 push,避开 fullPush 复杂路径
      provider.pushFakeLedgerSnapshot(ledgerId: 'existing-uuid');
      // 本地写一条 tx → 产生 unpushed local_change
      await repo.insertTransactionsBatch([
        TransactionsCompanion.insert(
          ledgerId: ledgerId,
          type: 'expense',
          amount: 8.0,
          syncId: const Value('tx-push-event'),
        ),
      ]);

      // 同步前:有未推送变更 → getStatus = localNewer,并把结果写进 _statusCache
      final before = await engine.getStatus(ledgerId: ledgerId);
      expect(before.diff, SyncDiff.localNewer,
          reason: '本地有未推送变更,同步前应为 localNewer(并落入缓存)');

      final received = <SyncEvent>[];
      final sub = engine.events.listen(received.add);
      final result = await engine.sync(ledgerId: ledgerId.toString());
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(result.pushed, greaterThan(0));
      // 修复点 1:push 完成 emit PushCompleted,通知 UI 重新读同步状态
      expect(received.whereType<PushCompleted>(), isNotEmpty,
          reason: 'push 上传本地变更后必须 emit PushCompleted');
      // 修复点 2(真正根因):push 后清了 _statusCache,getStatus 不再吃旧缓存。
      // 若仍命中缓存返回 localNewer,「我的」页就得手动下拉才更新 —— 本 bug。
      final after = await engine.getStatus(ledgerId: ledgerId);
      expect(after.diff, SyncDiff.inSync,
          reason: 'push 成功后 getStatus 必须刷新为 inSync;'
              '命中旧缓存返回 localNewer 即是本 bug 复现');
    });

    test('多种事件类型 dispatch:PullCompleted / ProfileFieldApplied 等', () async {
      final received = <SyncEvent>[];
      final sub = engine.events.listen(received.add);

      // 直接调 _emit 不容易(私有),但 syncMyProfile / pull 路径会 emit。
      // 这里用 syncMyProfile 路径:fake provider 抛 UnimplementedError →
      // 整个流程进 catch 不 emit。我们改测 pull → PullCompleted
      await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));
      engine.startListeningRealtime();
      provider.emitRealtimeEvent(BeeCountCloudRealtimeEvent(
        type: 'sync_change',
        ledgerId: 'L1',
        rawData: const {},
      ));
      await Future.delayed(const Duration(milliseconds: 1500));
      engine.stopListeningRealtime();
      await sub.cancel();

      expect(received.whereType<PullCompleted>(), isNotEmpty);
    });
  });

  group('WS realtime', () {
    test('startListeningRealtime + 模拟 WS sync_change → 1s debounce 后触发 pull',
        () async {
      await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));
      await db.into(db.categories).insert(CategoriesCompanion.insert(
          name: 'C', kind: 'expense', syncId: const Value('C1')));

      // 启动 WS 监听
      engine.startListeningRealtime();

      // 推一条 change 到 server,然后模拟 WS event
      provider.pushFakeChange(
        entityType: 'transaction',
        entitySyncId: 'tx-ws',
        ledgerId: 'L1',
        payload: {
          'syncId': 'tx-ws',
          'type': 'expense',
          'amount': 7.0,
          'happenedAt': '2026-05-01T10:00:00Z',
          'categoryId': 'C1',
          'categoryName': 'C',
          'categoryKind': 'expense',
        },
      );
      provider.emitRealtimeEvent(BeeCountCloudRealtimeEvent(
        type: 'sync_change',
        ledgerId: 'L1',
        rawData: const {},
      ));

      // _schedulePull 内 1 秒 debounce + 兜底 syncLedgersFromServer
      // 等待足够时间让 debounce + pull 完成
      await Future.delayed(const Duration(milliseconds: 1500));

      // 验证 apply 成功
      final txs = await db.select(db.transactions).get();
      expect(txs.where((t) => t.syncId == 'tx-ws'), hasLength(1));

      engine.stopListeningRealtime();
    });
  });

  group('分类重复数据(全历史回放踩到历史脏数据)', () {
    // 模拟真实场景:两台设备在互相同步前各自离线建了同名顶层分类「投资」,
    // 云端历史上因此存在两笔同名 category(不同 syncId)。全新设备第一次
    // 同步做全历史回放时,本地会依序 insert 出这两笔重复数据——这里直接
    // 手动造出"已经重复"的本地状态,模拟回放走到这一步之后的样子。
    //
    // 2026-09-29 改版:同名不同 syncId 在 server 端是两个都合法存在的实体,
    // App 不能自作主张合并删除、更不能把 delete 推回 server(实测事故:新设备
    // 回放时把使用者云端 12 个一级分类删掉)。这里钉住「只挑一笔、不改资料、
    // 不推送」。
    Future<({int keeperId, int dupeId, int ledgerId})> seedDupes() async {
      final keeperId = await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              name: '投资',
              kind: 'expense',
              syncId: const Value('cat-dup-A'),
            ),
          );
      final dupeId = await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              name: '投资',
              kind: 'expense',
              syncId: const Value('cat-dup-B'),
            ),
          );
      final ledgerId = await db.into(db.ledgers).insert(
            LedgersCompanion.insert(name: 'L', syncId: const Value('L1')),
          );
      return (keeperId: keeperId, dupeId: dupeId, ledgerId: ledgerId);
    }

    test('parentName 反查命中 2 笔同名顶层分类 → 不抛例外、不合并、不推 delete',
        () async {
      final seeded = await seedDupes();
      final txOnDupe = await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              ledgerId: seeded.ledgerId,
              type: 'expense',
              amount: 100,
              happenedAt: Value(DateTime.utc(2026, 5, 1)),
              categoryId: Value(seeded.dupeId),
            ),
          );

      provider.pushFakeChange(
        entityType: 'category',
        entitySyncId: 'cat-sub-1',
        payload: {
          'syncId': 'cat-sub-1',
          'name': '股票',
          'kind': 'expense',
          'level': 2,
          'parentName': '投资',
        },
      );

      final applied = await engine.pull('1');
      expect(applied, 1);

      final topLevel = await (db.select(db.categories)
            ..where((c) => c.name.equals('投资'))
            ..where((c) => c.level.equals(1)))
          .get();
      expect(topLevel, hasLength(2), reason: '同名不同 syncId 的两笔都应保留');

      final sub = await (db.select(db.categories)
            ..where((c) => c.syncId.equals('cat-sub-1')))
          .getSingle();
      expect(sub.parentId, seeded.keeperId,
          reason: '子分类挂到确定性挑出的那笔(有 syncId、id 最小)');

      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(txOnDupe)))
          .getSingle();
      expect(tx.categoryId, seeded.dupeId, reason: '不应搬动既有交易的分类');

      final pending = await changeTracker.getUnpushedChangesForLedger(0);
      expect(
        pending.where((c) => c.entityType == 'category' && c.action == 'delete'),
        isEmpty,
        reason: '绝不能把同名分类的 delete 推回 server',
      );
    });

    test('parentSyncId 优先于 parentName → 同名重复时精准挂到指定父分类', () async {
      final seeded = await seedDupes();
      provider.pushFakeChange(
        entityType: 'category',
        entitySyncId: 'cat-sub-2',
        payload: {
          'syncId': 'cat-sub-2',
          'name': '基金',
          'kind': 'expense',
          'level': 2,
          'parentName': '投资',
          'parentSyncId': 'cat-dup-B',
        },
      );

      await engine.pull('1');

      final sub = await (db.select(db.categories)
            ..where((c) => c.syncId.equals('cat-sub-2')))
          .getSingle();
      expect(sub.parentId, seeded.dupeId);
    });

    test('交易 categoryName 命中 2 笔同名分类 → 不抛 Too many elements,pull 不卡死',
        () async {
      final seeded = await seedDupes();
      provider.pushFakeChange(
        entityType: 'transaction',
        entitySyncId: 'tx-dup-1',
        ledgerId: 'L1',
        payload: {
          'syncId': 'tx-dup-1',
          'type': 'expense',
          'amount': 50,
          'happenedAt': '2026-05-02T10:00:00Z',
          'categoryName': '投资',
          'categoryKind': 'expense',
          // 故意不带 categoryId:模拟老 payload 只能靠名字反查
        },
      );
      // 同一页后面再塞一笔,确认整页有 apply 完(cursor 不会卡在这页)
      provider.pushFakeChange(
        entityType: 'transaction',
        entitySyncId: 'tx-dup-2',
        ledgerId: 'L1',
        payload: {
          'syncId': 'tx-dup-2',
          'type': 'expense',
          'amount': 60,
          'happenedAt': '2026-05-03T10:00:00Z',
        },
      );

      final applied = await engine.pull('${seeded.ledgerId}');
      expect(applied, 2);

      final tx = await (db.select(db.transactions)
            ..where((t) => t.syncId.equals('tx-dup-1')))
          .getSingle();
      expect(tx.categoryId, seeded.keeperId);
    });

    test('server 删掉同名重复的其中一笔 → 子分类/交易改挂到存活的那笔,不跟着被删',
        () async {
      final seeded = await seedDupes();
      final childOfDupe = await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              name: '基金',
              kind: 'expense',
              level: const Value(2),
              parentId: Value(seeded.dupeId),
              syncId: const Value('cat-sub-3'),
            ),
          );
      final txOnDupe = await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              ledgerId: seeded.ledgerId,
              type: 'expense',
              amount: 100,
              happenedAt: Value(DateTime.utc(2026, 5, 1)),
              categoryId: Value(seeded.dupeId),
            ),
          );

      provider.pushFakeChange(
        entityType: 'category',
        entitySyncId: 'cat-dup-B',
        action: 'delete',
      );

      await engine.pull('1');

      final dupe = await (db.select(db.categories)
            ..where((c) => c.id.equals(seeded.dupeId)))
          .getSingleOrNull();
      expect(dupe, isNull);

      final child = await (db.select(db.categories)
            ..where((c) => c.id.equals(childOfDupe)))
          .getSingleOrNull();
      expect(child, isNotNull, reason: '子分类不应跟着同名重复的父分类一起被删');
      expect(child!.parentId, seeded.keeperId);

      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(txOnDupe)))
          .getSingle();
      expect(tx.categoryId, seeded.keeperId);
    });

    test('同一个 syncId 本机有 2 笔副本 → 本机合并,但不推 delete', () async {
      final a = await db.into(db.categories).insert(CategoriesCompanion.insert(
          name: '饮食', kind: 'expense', syncId: const Value('cat-same')));
      await db.into(db.categories).insert(CategoriesCompanion.insert(
          name: '饮食', kind: 'expense', syncId: const Value('cat-same')));

      provider.pushFakeChange(
        entityType: 'category',
        entitySyncId: 'cat-same',
        payload: {
          'syncId': 'cat-same',
          'name': '饮食',
          'kind': 'expense',
          'level': 1,
        },
      );
      await engine.pull('1');

      final rows = await (db.select(db.categories)
            ..where((c) => c.syncId.equals('cat-same')))
          .get();
      expect(rows.map((r) => r.id), [a]);
      final pending = await changeTracker.getUnpushedChangesForLedger(0);
      expect(
        pending.where((c) => c.entityType == 'category' && c.action == 'delete'),
        isEmpty,
      );
    });
  });

  group('分类颜色对账(restoreCategoryColorsFromServer)', () {
    BeeCountCloudReadCategory remoteCat(String id, String? color,
            {String name = 'X', int level = 1}) =>
        BeeCountCloudReadCategory(
          id: id,
          name: name,
          kind: 'expense',
          level: level,
          color: color,
          lastChangeId: 1,
        );

    test('本机一级分类缺色 → 按 syncId 从 server 补回,不产生 local_changes', () async {
      final ledgerId = await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));
      final missing = await db.into(db.categories).insert(
          CategoriesCompanion.insert(
              name: '生活', kind: 'expense', syncId: const Value('cat-a')));
      final localColored = await db.into(db.categories).insert(
          CategoriesCompanion.insert(
              name: '交通',
              kind: 'expense',
              syncId: const Value('cat-b'),
              color: const Value('#111111')));
      provider.serverCategories.addAll([
        remoteCat('cat-a', '#FF9800'),
        remoteCat('cat-b', '#222222'),
      ]);

      final restored =
          await engine.restoreCategoryColorsFromServer(ledgerId: ledgerId);
      expect(restored, 1);
      expect(provider.readCategoriesCalls, ['L1']);

      Future<String?> colorOf(int id) async => (await (db.select(db.categories)
                ..where((c) => c.id.equals(id)))
              .getSingle())
          .color;
      expect(await colorOf(missing), '#FF9800');
      expect(await colorOf(localColored), '#111111',
          reason: '本机已有颜色不覆盖');

      final pending = await changeTracker.getUnpushedChangesForLedger(0);
      expect(pending, isEmpty, reason: '补回 server 既有状态,不应推回去');
    });

    test('本机没有缺色的一级分类 → 不打 read API', () async {
      final ledgerId = await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));
      await db.into(db.categories).insert(CategoriesCompanion.insert(
          name: '生活',
          kind: 'expense',
          syncId: const Value('cat-a'),
          color: const Value('#123456')));

      final restored =
          await engine.restoreCategoryColorsFromServer(ledgerId: ledgerId);
      expect(restored, 0);
      expect(provider.readCategoriesCalls, isEmpty);
    });
  });

  group('分类色盘补指派(repairMissingCategoryColorsOnce)', () {
    // 2026-09-29 使用者实际资料:(name, kind, sortOrder, icon, color)。
    // 原本 web 截图上的颜色:生活 #FF5722、交通 #E91E63 … 其他 #FF9800,
    // 即 v55 按 sortOrder 循环取色盘的结果。
    const seed = <(String, String, int, String, String?)>[
      ('餘額調整', 'expense', 0, '', null),
      ('生活', 'expense', 1, 'weekend', null),
      ('交通', 'expense', 7, 'traffic', null),
      ('個人', 'expense', 19, 'face', null),
      ('娛樂', 'expense', 28, 'theater_comedy', null),
      ('家居', 'expense', 36, 'house', null),
      ('家庭', 'expense', 43, 'family_restroom', null),
      ('飲食', 'expense', 45, 'restaurant', null),
      ('學習', 'expense', 52, 'school', null),
      ('應收款項', 'expense', 56, 'request_quote', null),
      ('購物', 'expense', 60, 'shopping_cart', null),
      ('醫療', 'expense', 68, 'local_hospital', null),
      ('手續費', 'expense', 72, 'price_change', '#CDDC39'),
      ('手續費', 'expense', 72, 'price_change', null),
      ('利息支出', 'expense', 73, 'trending_down', '#FFC107'),
      ('利息支出', 'expense', 73, 'trending_down', null),
      ('其他', 'expense', 74, 'inventory_2', '#FF9800'),
      ('其他', 'expense', 74, 'inventory_2', null),
      ('退款', 'income', 0, '', '#FF5722'),
      ('餘額調整', 'income', 0, '', null),
      ('股利', 'income', 0, '', null),
      ('收入', 'income', 75, 'savings', null),
      ('折扣', 'income', 85, 'local_offer', '#9C27B0'),
      ('折扣', 'income', 85, 'local_offer', null),
      ('轉帳', 'transfer', -1, 'swap_horiz', null),
    ];

    Future<void> seedAll() async {
      var i = 0;
      for (final (name, kind, sort, icon, color) in seed) {
        await db.into(db.categories).insert(CategoriesCompanion.insert(
              name: name,
              kind: kind,
              sortOrder: Value(sort),
              icon: Value(icon),
              color: Value(color),
              syncId: Value('cat-${i++}'),
            ));
      }
    }

    Future<Map<String, Set<String?>>> colorsByName(String kind) async {
      final rows = await (db.select(db.categories)
            ..where((c) => c.kind.equals(kind)))
          .get();
      final out = <String, Set<String?>>{};
      for (final r in rows) {
        out.putIfAbsent(r.name, () => {}).add(r.color);
      }
      return out;
    }

    test('还原成原本的色盘顺序,同名重复沿用锚点色,系统分类/转帐不补', () async {
      await seedAll();
      final n = await engine.repairMissingCategoryColorsOnce();

      final exp = await colorsByName('expense');
      expect(exp['餘額調整'], {null});
      expect(exp['生活'], {'#FF5722'});
      expect(exp['交通'], {'#E91E63'});
      expect(exp['個人'], {'#9C27B0'});
      expect(exp['娛樂'], {'#673AB7'});
      expect(exp['家居'], {'#3F51B5'});
      expect(exp['家庭'], {'#2196F3'});
      expect(exp['飲食'], {'#03A9F4'});
      expect(exp['學習'], {'#00BCD4'});
      expect(exp['應收款項'], {'#009688'});
      expect(exp['購物'], {'#4CAF50'});
      expect(exp['醫療'], {'#8BC34A'});
      expect(exp['手續費'], {'#CDDC39'});
      expect(exp['利息支出'], {'#FFC107'});
      expect(exp['其他'], {'#FF9800'});

      final inc = await colorsByName('income');
      expect(inc['退款'], {'#FF5722'});
      expect(inc['餘額調整'], {null});
      expect(inc['股利'], {null});
      expect(inc['收入'], {'#E91E63'});
      expect(inc['折扣'], {'#9C27B0'});

      expect((await colorsByName('transfer'))['轉帳'], {null});

      // 11 个支出 + 3 个支出重复 + 收入 + 折扣重复 = 16
      expect(n, 16);
      final pending = await changeTracker.getUnpushedChangesForLedger(0);
      expect(pending.where((c) => c.entityType == 'category' && c.action == 'update'),
          hasLength(16),
          reason: '补指派的颜色要推回 server,web 端才会恢复');
      expect(pending.where((c) => c.action == 'delete'), isEmpty);
    });

    test('只跑一次', () async {
      await seedAll();
      await engine.repairMissingCategoryColorsOnce();
      await (db.update(db.categories)..where((c) => c.name.equals('生活')))
          .write(const CategoriesCompanion(color: Value(null)));
      final second = await engine.repairMissingCategoryColorsOnce();
      expect(second, 0);
    });

    test('还有 pull 错误时不执行(本机资料不完整,顺序会算错)', () async {
      await seedAll();
      await engine.pullErrors.record(
        change: BeeCountCloudSyncChange(
          changeId: 99,
          ledgerId: 'L1',
          entityType: 'transaction',
          entitySyncId: 'tx-x',
          action: 'upsert',
          updatedByDeviceId: 'd',
          updatedAt: '2026-09-29T00:00:00Z',
          payload: const {},
        ),
        error: StateError('boom'),
        stackTrace: StackTrace.current,
      );
      final n = await engine.repairMissingCategoryColorsOnce();
      expect(n, 0);
      final exp = await colorsByName('expense');
      expect(exp['生活'], {null});
    });
  });
}
