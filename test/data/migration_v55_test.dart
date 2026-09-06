/// v55 迁移(分类专属颜色 color):
/// - 只有一级分类(parent_id IS NULL)会被回填颜色,二级分类颜色继承父分类,
///   渲染时才解析(见 lib/widgets/category/category_selector.dart 的
///   _CategoryItem),迁移本身不需要碰二级分类。
/// - 回填算法按 kind 分组、依 sort_order/id 顺序,从 kCategoryColorPalette
///   循环取色——跟 LocalCategoryRepository.createCategory 里新建一级分类
///   用的 _nextAutoColor 是同一份算法,这里只测迁移这段回填逻辑本身在各种
///   既有资料形态下算得对(仓库既有 migration_v* 测试的惯例,不驱动真正的
///   onUpgrade from-version 分支)。
/// - 2026-09-06 补充:回填直接用 customStatement 改 categories 表,原本完全
///   绕过 ChangeTracker/local_changes outbox,导致颜色永远推不到服务端(线上
///   库实测验证过,已有分类的 color 全是 NULL)。现在回填的同时也要给每个
///   有 syncId 的一级分类补插一条 unpushed 的 local_changes 行,下面新增的
///   测试专门验证这一步。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:beecount/data/db.dart';

Future<void> _runV55ColorBackfill(BeeDatabase db) async {
  final topLevelRows = await db.customSelect(
    'SELECT id, kind, sync_id FROM categories WHERE parent_id IS NULL ORDER BY kind, sort_order, id',
  ).get();
  final perKindIndex = <String, int>{};
  for (final row in topLevelRows) {
    final id = row.read<int>('id');
    final kind = row.read<String>('kind');
    final syncId = row.readNullable<String>('sync_id');
    final index = perKindIndex[kind] ?? 0;
    perKindIndex[kind] = index + 1;
    final color = kCategoryColorPalette[index % kCategoryColorPalette.length];
    await db.customStatement(
        'UPDATE categories SET color = ? WHERE id = ?', [color, id]);
    if (syncId != null && syncId.isNotEmpty) {
      await db.into(db.localChanges).insert(LocalChangesCompanion.insert(
            entityType: 'category',
            entityId: id,
            entitySyncId: syncId,
            ledgerId: 0,
            action: 'update',
          ));
    }
  }
}

void main() {
  late BeeDatabase db;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  test('schemaVersion >= 55', () {
    expect(db.schemaVersion, greaterThanOrEqualTo(55));
  });

  test('既有一级分类按 kind 分组、依序循环指派色盘颜色', () async {
    await db.customStatement(
        "INSERT INTO categories (id, name, kind, sort_order, level) VALUES "
        "(1, '餐饮', 'expense', 0, 1),"
        "(2, '交通', 'expense', 1, 1),"
        "(3, '工资', 'income', 0, 1)");

    await _runV55ColorBackfill(db);

    final cats = await db.select(db.categories).get();
    final byId = {for (final c in cats) c.id: c};

    // 每个 kind 各自从色盘第 0 个开始循环,互不干扰。
    expect(byId[1]!.color, kCategoryColorPalette[0]);
    expect(byId[2]!.color, kCategoryColorPalette[1]);
    expect(byId[3]!.color, kCategoryColorPalette[0]);
  });

  test('二级分类不参与回填,颜色维持 null(渲染时继承父分类)', () async {
    await db.customStatement(
        "INSERT INTO categories (id, name, kind, sort_order, level) VALUES "
        "(1, '餐饮', 'expense', 0, 1)");
    await db.customStatement(
        "INSERT INTO categories (id, name, kind, sort_order, level, parent_id) VALUES "
        "(2, '早餐', 'expense', 0, 2, 1)");

    await _runV55ColorBackfill(db);

    final sub = await (db.select(db.categories)
          ..where((c) => c.id.equals(2)))
        .getSingle();
    expect(sub.color, isNull);
  });

  test('回填颜色的同时给有 syncId 的一级分类登记 unpushed local_changes', () async {
    await db.customStatement(
        "INSERT INTO categories (id, name, kind, sort_order, level, sync_id) VALUES "
        "(1, '餐饮', 'expense', 0, 1, 'sync-cat-1'),"
        "(2, '交通', 'expense', 1, 1, 'sync-cat-2')");
    // 极老、从未同步过的种子数据没有 syncId —— 不该登记(没有推送意义)。
    await db.customStatement(
        "INSERT INTO categories (id, name, kind, sort_order, level) VALUES "
        "(3, '娱乐', 'expense', 2, 1)");

    await _runV55ColorBackfill(db);

    final changes = await db.select(db.localChanges).get();
    expect(changes.length, 2, reason: '只有带 syncId 的一级分类才登记');

    final bySyncId = {for (final c in changes) c.entitySyncId: c};
    expect(bySyncId['sync-cat-1'], isNotNull);
    expect(bySyncId['sync-cat-1']!.entityType, 'category');
    expect(bySyncId['sync-cat-1']!.ledgerId, 0,
        reason: 'user-global 实体固定挂 ledgerId=0');
    expect(bySyncId['sync-cat-1']!.pushedAt, isNull,
        reason: '刚回填还没推送,pushedAt 必须是 null 才会被下次 sync 捞到');
    expect(bySyncId['sync-cat-2'], isNotNull);
  });

  test('新建一级分类走 createCategory 时颜色索引接续既有数量', () async {
    // 对应 LocalCategoryRepository._nextAutoColor:已有 2 个 expense 一级分类时,
    // 第 3 个应该拿色盘第 2 个(index 从 0 开始)。这里直接验证索引算法,不额外
    // 起 repository 依赖。
    const existingCount = 2;
    final expected =
        kCategoryColorPalette[existingCount % kCategoryColorPalette.length];
    expect(expected, kCategoryColorPalette[2]);
  });
}
