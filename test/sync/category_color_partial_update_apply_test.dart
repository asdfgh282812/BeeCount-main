// 分类颜色 apply 的 partial-update 保留语义回归测试。
//
// 背景(2026-09-29 实测):Categories.color(v55)是 App 单方面加的字段,
// BeeCount Cloud 还没把它接进自己的 projection/wire contract(见
// docs/changes/2026-09-29-category-color-pull-overwrite-fix.md)。server 回传的
// 分类 payload 里因此通常没有 'color' 这个 key。`_applyCategoryChange` 曾经对
// color 用 `payload['color'] as String?` 无条件覆盖——没有这个 key 时
// 等同于收到显式的 null,把本机刚指派好的颜色(新建一级分类时从
// kCategoryColorPalette 自动取色)冲成 null,导致「cute 图标」主题下分类
// 图标下方的颜色底线全部退化成中性灰兜底色(肉眼看起来像变白了)。本测试
// 钉住修复:跟 account 的 type/currency 同款用 containsKey 保护。

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/cloud/sync/change_tracker.dart';
import 'package:beecount/cloud/sync/sync_engine.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

import '../cloud/sync/_fakes/fake_beecount_cloud_provider.dart';

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

  tearDown(() async => db.close());

  test('远端 upsert 不带 color 键(Cloud 尚未支持该字段) → 本地已有颜色应保留',
      () async {
    const categorySyncId = 'cat-color-1';

    final cid = await repo.createCategory(
      name: '餐饮',
      kind: 'expense',
      color: '#FF9800',
      syncId: categorySyncId,
    );
    expect(
        (await (db.select(db.categories)..where((c) => c.id.equals(cid)))
                .getSingle())
            .color,
        '#FF9800');

    // 模拟 Cloud 广播回来的分类变更(例如改了排序/名称),payload 里完全
    // 不带 color 键 —— server 端目前不认得这个字段。
    provider.pushFakeChange(
      entityType: 'category',
      entitySyncId: categorySyncId,
      ledgerId: '0',
      payload: {
        'syncId': categorySyncId,
        'name': '餐饮',
        'kind': 'expense',
        'level': 1,
        'sortOrder': 1,
        'icon': 'restaurant',
        'iconType': 'material',
      },
    );

    await engine.pull('');

    final c = await (db.select(db.categories)
          ..where((t) => t.syncId.equals(categorySyncId)))
        .getSingle();
    expect(c.color, '#FF9800', reason: '缺 color 键不应把本地已有颜色冲成 null');
    expect(c.sortOrder, 1, reason: 'sortOrder 应正常被更新');
  });

  test('远端 upsert 显式带 color 键 → 正常覆盖本地值', () async {
    const categorySyncId = 'cat-color-2';

    await repo.createCategory(
      name: '交通',
      kind: 'expense',
      color: '#FF9800',
      syncId: categorySyncId,
    );

    provider.pushFakeChange(
      entityType: 'category',
      entitySyncId: categorySyncId,
      ledgerId: '0',
      payload: {
        'syncId': categorySyncId,
        'name': '交通',
        'kind': 'expense',
        'level': 1,
        'sortOrder': 0,
        'icon': 'directions_car',
        'iconType': 'material',
        'color': '#2196F3',
      },
    );

    await engine.pull('');

    final c = await (db.select(db.categories)
          ..where((t) => t.syncId.equals(categorySyncId)))
        .getSingle();
    expect(c.color, '#2196F3', reason: '显式带键应正常覆盖');
  });
}
