import 'package:drift/drift.dart' as d;
import 'package:uuid/uuid.dart';

import '../../db.dart';
import '../debt_repository.dart';

const _uuid = Uuid();

/// 借還款 Repository 本地實作,基於 Drift。
///
/// 這裡 NOT 直接調 changeTracker;changeTracker 的注入是通過
/// LocalRepository 包装层(lib/data/repositories/local/local_repository.dart)
/// 在 CRUD 前后统一 recordChange,保持跟 budget/transaction 的代码结构一致。
class LocalDebtRepository implements DebtRepository {
  final BeeDatabase db;

  LocalDebtRepository(this.db);

  @override
  Future<int> createDebt({
    required int ledgerId,
    required String direction,
    required String counterpartyName,
    required double principalAmount,
    DateTime? dueAt,
    String? note,
  }) async {
    assert(
      direction == kDebtDirectionPayable ||
          direction == kDebtDirectionReceivable,
      'direction 必须是 payable 或 receivable,实际传入 "$direction"',
    );
    return await db.into(db.debts).insert(
          DebtsCompanion.insert(
            ledgerId: ledgerId,
            direction: direction,
            counterpartyName: counterpartyName,
            principalAmount: principalAmount,
            dueAt: d.Value(dueAt),
            note: d.Value(note),
            syncId: d.Value(_uuid.v4()),
          ),
        );
  }

  @override
  Future<void> updateDebt(
    int id, {
    String? counterpartyName,
    DateTime? dueAt,
    bool clearDueAt = false,
    String? note,
    bool clearNote = false,
  }) async {
    await (db.update(db.debts)..where((t) => t.id.equals(id))).write(
      DebtsCompanion(
        counterpartyName: counterpartyName != null
            ? d.Value(counterpartyName)
            : const d.Value.absent(),
        dueAt: clearDueAt
            ? const d.Value(null)
            : (dueAt != null ? d.Value(dueAt) : const d.Value.absent()),
        note: clearNote
            ? const d.Value(null)
            : (note != null ? d.Value(note) : const d.Value.absent()),
        updatedAt: d.Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> closeDebt(int id) async {
    await (db.update(db.debts)..where((t) => t.id.equals(id))).write(
      DebtsCompanion(
        closedAt: d.Value(DateTime.now()),
        updatedAt: d.Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> reopenDebt(int id) async {
    await (db.update(db.debts)..where((t) => t.id.equals(id))).write(
      DebtsCompanion(
        closedAt: const d.Value(null),
        updatedAt: d.Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> deleteDebt(int id) async {
    if (await hasRepayments(id)) {
      throw StateError('该欠款已有还款记录,不能删除');
    }
    await (db.delete(db.debts)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<Debt?> getDebt(int id) =>
      (db.select(db.debts)..where((t) => t.id.equals(id))).getSingleOrNull();

  @override
  Future<Debt?> getDebtBySyncId(String syncId) =>
      (db.select(db.debts)..where((t) => t.syncId.equals(syncId)))
          .getSingleOrNull();

  @override
  Future<bool> hasRepayments(int debtId) async {
    final debt = await getDebt(debtId);
    if (debt?.syncId == null) return false;
    final count = await (db.select(db.transactions)
          ..where((t) => t.debtSyncId.equals(debt!.syncId!))
          ..limit(1))
        .get();
    return count.isNotEmpty;
  }

  @override
  Future<List<Debt>> getAllDebts(int ledgerId) async {
    final rows = await (db.select(db.debts)
          ..where((t) => t.ledgerId.equals(ledgerId)))
        .get();
    rows.sort((a, b) {
      if (a.dueAt == null && b.dueAt == null) return 0;
      if (a.dueAt == null) return 1;
      if (b.dueAt == null) return -1;
      return a.dueAt!.compareTo(b.dueAt!);
    });
    return rows;
  }

  /// 依 [debt] 算出即時的還款進度/狀態。狀態推導對齐 BeeCount Cloud
  /// `routers/read/ledgers.py::list_debts`:closedAt 優先於金額判斷。
  Future<DebtWithStatus> _withStatus(Debt debt) async {
    double repaid = 0;
    if (debt.syncId != null) {
      final repayments = await (db.select(db.transactions)
            ..where((t) => t.debtSyncId.equals(debt.syncId!)))
          .get();
      for (final tx in repayments) {
        repaid += tx.amount.abs();
      }
    }
    final remaining = (debt.principalAmount - repaid).clamp(0, double.infinity).toDouble();
    final String status;
    if (debt.closedAt != null) {
      status = kDebtStatusClosed;
    } else if (remaining <= 0.01) {
      status = kDebtStatusSettled;
    } else if (repaid > 0) {
      status = kDebtStatusPartial;
    } else {
      status = kDebtStatusOpen;
    }
    return DebtWithStatus(
      debt: debt,
      repaidAmount: repaid,
      remainingAmount: remaining,
      status: status,
    );
  }

  @override
  Future<List<DebtWithStatus>> getDebtsWithStatus(int ledgerId) async {
    final debts = await getAllDebts(ledgerId);
    return [for (final debt in debts) await _withStatus(debt)];
  }

  @override
  Future<DebtWithStatus?> getDebtWithStatus(int id) async {
    final debt = await getDebt(id);
    if (debt == null) return null;
    return _withStatus(debt);
  }

  @override
  Future<List<Transaction>> getDebtRepaymentTransactions(int debtId) async {
    final debt = await getDebt(debtId);
    if (debt?.syncId == null) return [];
    return await (db.select(db.transactions)
          ..where((t) => t.debtSyncId.equals(debt!.syncId!))
          ..orderBy([(t) => d.OrderingTerm.desc(t.happenedAt)]))
        .get();
  }

  @override
  Future<double> getNetDebtBalance(int ledgerId) async {
    final withStatus = await getDebtsWithStatus(ledgerId);
    double net = 0;
    for (final entry in withStatus) {
      if (entry.status == kDebtStatusClosed) continue;
      if (entry.debt.direction == kDebtDirectionReceivable) {
        net += entry.remainingAmount;
      } else {
        net -= entry.remainingAmount;
      }
    }
    return net;
  }

  @override
  Future<List<({int ledgerId, double receivableRemaining, double payableRemaining})>>
      getDebtBalancesByLedgerForAllLedgers() async {
    final allDebts = await db.select(db.debts).get();
    final byLedger = <int, ({double receivable, double payable})>{};
    for (final debt in allDebts) {
      final withStatus = await _withStatus(debt);
      if (withStatus.status == kDebtStatusClosed) continue;
      final prev = byLedger[debt.ledgerId] ?? (receivable: 0.0, payable: 0.0);
      if (debt.direction == kDebtDirectionReceivable) {
        byLedger[debt.ledgerId] =
            (receivable: prev.receivable + withStatus.remainingAmount, payable: prev.payable);
      } else {
        byLedger[debt.ledgerId] =
            (receivable: prev.receivable, payable: prev.payable + withStatus.remainingAmount);
      }
    }
    return [
      for (final entry in byLedger.entries)
        (
          ledgerId: entry.key,
          receivableRemaining: entry.value.receivable,
          payableRemaining: entry.value.payable,
        ),
    ];
  }

  @override
  Stream<List<Debt>> watchDebts(int ledgerId) {
    return (db.select(db.debts)..where((t) => t.ledgerId.equals(ledgerId)))
        .watch()
        .map((rows) {
      rows.sort((a, b) {
        if (a.dueAt == null && b.dueAt == null) return 0;
        if (a.dueAt == null) return 1;
        if (b.dueAt == null) return -1;
        return a.dueAt!.compareTo(b.dueAt!);
      });
      return rows;
    });
  }
}
