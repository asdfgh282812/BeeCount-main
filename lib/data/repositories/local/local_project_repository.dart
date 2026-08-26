import 'package:drift/drift.dart' as d;
import 'package:uuid/uuid.dart';

import '../../db.dart';
import '../project_repository.dart';

const _uuid = Uuid();

/// 專案 Repository 本地實作,基於 Drift。跟 [LocalDebtRepository] 同款分工:
/// 這裡 NOT 直接調 changeTracker,changeTracker 的注入透過 LocalRepository
/// 包裝層(lib/data/repositories/local/local_repository.dart)在 CRUD 前後
/// 統一 recordChange。
class LocalProjectRepository implements ProjectRepository {
  final BeeDatabase db;

  LocalProjectRepository(this.db);

  @override
  Future<int> createProject({
    required int ledgerId,
    required String name,
    String? icon,
    double? budgetAmount,
    String periodType = 'monthly',
    DateTime? periodStart,
    DateTime? periodEnd,
    bool carryoverEnabled = false,
    bool visibleOnHome = true,
    int sortOrder = 0,
  }) async {
    assert(
      periodType == 'monthly' || periodType == 'yearly' || periodType == 'fixed',
      "periodType 必须是 'monthly'/'yearly'/'fixed',实际传入 \"$periodType\"",
    );
    return await db.into(db.projects).insert(
          ProjectsCompanion.insert(
            ledgerId: ledgerId,
            name: d.Value(name),
            icon: d.Value(icon),
            budgetAmount: d.Value(budgetAmount),
            periodType: d.Value(periodType),
            periodStart: d.Value(periodStart),
            periodEnd: d.Value(periodEnd),
            carryoverEnabled: d.Value(carryoverEnabled),
            visibleOnHome: d.Value(visibleOnHome),
            sortOrder: d.Value(sortOrder),
            syncId: d.Value(_uuid.v4()),
          ),
        );
  }

  @override
  Future<void> updateProject(
    int id, {
    String? name,
    String? icon,
    bool clearIcon = false,
    double? budgetAmount,
    bool clearBudgetAmount = false,
    String? periodType,
    DateTime? periodStart,
    bool clearPeriodStart = false,
    DateTime? periodEnd,
    bool clearPeriodEnd = false,
    bool? carryoverEnabled,
    bool? visibleOnHome,
    bool? enabled,
    int? sortOrder,
  }) async {
    await (db.update(db.projects)..where((t) => t.id.equals(id))).write(
      ProjectsCompanion(
        name: name != null ? d.Value(name) : const d.Value.absent(),
        icon: clearIcon
            ? const d.Value(null)
            : (icon != null ? d.Value(icon) : const d.Value.absent()),
        budgetAmount: clearBudgetAmount
            ? const d.Value(null)
            : (budgetAmount != null
                ? d.Value(budgetAmount)
                : const d.Value.absent()),
        periodType:
            periodType != null ? d.Value(periodType) : const d.Value.absent(),
        periodStart: clearPeriodStart
            ? const d.Value(null)
            : (periodStart != null
                ? d.Value(periodStart)
                : const d.Value.absent()),
        periodEnd: clearPeriodEnd
            ? const d.Value(null)
            : (periodEnd != null ? d.Value(periodEnd) : const d.Value.absent()),
        carryoverEnabled: carryoverEnabled != null
            ? d.Value(carryoverEnabled)
            : const d.Value.absent(),
        visibleOnHome: visibleOnHome != null
            ? d.Value(visibleOnHome)
            : const d.Value.absent(),
        enabled: enabled != null ? d.Value(enabled) : const d.Value.absent(),
        sortOrder:
            sortOrder != null ? d.Value(sortOrder) : const d.Value.absent(),
        updatedAt: d.Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> deleteProject(int id) async {
    final project = await getProject(id);
    if (project == null) return;
    final syncId = project.syncId;
    if (syncId != null && await projectHasTransactions(syncId)) {
      await (db.update(db.projects)..where((t) => t.id.equals(id))).write(
        ProjectsCompanion(
          enabled: const d.Value(false),
          updatedAt: d.Value(DateTime.now()),
        ),
      );
      return;
    }
    await (db.delete(db.projects)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<Project?> getProject(int id) =>
      (db.select(db.projects)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  @override
  Future<Project?> getProjectBySyncId(String syncId) =>
      (db.select(db.projects)..where((t) => t.syncId.equals(syncId)))
          .getSingleOrNull();

  @override
  Future<List<Project>> getAllProjects(int ledgerId,
      {bool includeDisabled = false}) async {
    final query = db.select(db.projects)
      ..where((t) => t.ledgerId.equals(ledgerId));
    if (!includeDisabled) {
      query.where((t) => t.enabled.equals(true));
    }
    query.orderBy([(t) => d.OrderingTerm.asc(t.sortOrder)]);
    return query.get();
  }

  @override
  Stream<List<Project>> watchProjects(int ledgerId,
      {bool includeDisabled = false}) {
    final query = db.select(db.projects)
      ..where((t) => t.ledgerId.equals(ledgerId));
    if (!includeDisabled) {
      query.where((t) => t.enabled.equals(true));
    }
    query.orderBy([(t) => d.OrderingTerm.asc(t.sortOrder)]);
    return query.watch();
  }

  @override
  Future<bool> projectHasTransactions(String projectSyncId) async {
    final rows = await (db.select(db.transactions)
          ..where((t) => t.projectSyncId.equals(projectSyncId))
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }
}
