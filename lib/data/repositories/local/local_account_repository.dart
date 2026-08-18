import 'package:drift/drift.dart' as d;
import 'package:uuid/uuid.dart';

import '../../db.dart';
import '../../../services/system/logger_service.dart';
import '../../../utils/account_type_utils.dart';
import '../account_repository.dart';
import '../exceptions.dart';

/// 本地账户Repository实现
/// 基于 Drift 数据库实现
class LocalAccountRepository implements AccountRepository {
  static const _uuid = Uuid();
  final BeeDatabase db;

  LocalAccountRepository(this.db);

  @override
  Stream<List<Account>> watchAccountsForLedger(int ledgerId) {
    return (db.select(db.accounts)..where((a) => a.ledgerId.equals(ledgerId)))
        .watch();
  }

  @override
  Stream<List<Account>> watchAllAccounts() {
    return (db.select(db.accounts)
          ..orderBy([
            (a) => d.OrderingTerm(expression: a.type),
            (a) => d.OrderingTerm(expression: a.sortOrder),
          ]))
        .watch();
  }

  @override
  Future<List<Account>> getAllAccounts() async {
    return await (db.select(db.accounts)
          ..orderBy([
            (a) => d.OrderingTerm(expression: a.type),
            (a) => d.OrderingTerm(expression: a.sortOrder),
          ]))
        .get();
  }

  @override
  Future<Account?> getAccount(int accountId) async {
    return await (db.select(db.accounts)..where((a) => a.id.equals(accountId)))
        .getSingleOrNull();
  }

  @override
  Future<Account?> getAccountBySyncId(String syncId) {
    return (db.select(db.accounts)..where((a) => a.syncId.equals(syncId)))
        .getSingleOrNull();
  }

  @override
  Future<List<Account>> getAvailableAccountsForLedger(int ledgerId) async {
    // 获取账本信息
    final ledger = await (db.select(db.ledgers)
          ..where((l) => l.id.equals(ledgerId)))
        .getSingle();

    // 通过币种过滤账户
    return await (db.select(db.accounts)
          ..where((a) => a.currency.equals(ledger.currency)))
        .get();
  }

  @override
  Future<List<Account>> getAccountsByCurrency(String currency) async {
    return await (db.select(db.accounts)
          ..where((a) => a.currency.equals(currency)))
        .get();
  }

  @override
  Future<Map<String, List<Account>>> getAccountsGroupedByCurrency() async {
    final allAccounts = await getAllAccounts();
    final Map<String, List<Account>> grouped = {};

    for (final account in allAccounts) {
      grouped.putIfAbsent(account.currency, () => []).add(account);
    }

    return grouped;
  }

  @override
  Future<int> createAccount({
    required int ledgerId,
    required String name,
    String type = 'cash',
    String currency = 'CNY',
    double initialBalance = 0.0,
    double? creditLimit,
    int? billingDay,
    int? paymentDueDay,
    String? bankName,
    String? cardLastFour,
    String? note,
    String? syncId,
    String? parentAccountId,
    String? avatarPath,
  }) async {
    // 撞同名抛 DuplicateNameException(name 全局唯一)。静默路径(import /
    // app-link 等)请改用 [upsertAccount]。
    final existingByName =
        await (db.select(db.accounts)..where((a) => a.name.equals(name))).get();
    if (existingByName.isNotEmpty) {
      throw DuplicateNameException(
        entityType: 'account',
        name: name,
        existingId: existingByName.first.id,
      );
    }
    try {
      // 计算同类型最大 sortOrder + 1
      final maxSortOrderResult = await db.customSelect(
        'SELECT COALESCE(MAX(sort_order), -1) AS max_order FROM accounts WHERE type = ?1',
        variables: [d.Variable.withString(type)],
        readsFrom: {db.accounts},
      ).getSingle();
      final nextSortOrder = (maxSortOrderResult.data['max_order'] as int) + 1;

      final companion = AccountsCompanion.insert(
        ledgerId: ledgerId,
        name: name,
        type: d.Value(type),
        currency: d.Value(currency),
        initialBalance: d.Value(initialBalance),
        createdAt: d.Value(DateTime.now()),
        sortOrder: d.Value(nextSortOrder),
        creditLimit: d.Value(creditLimit),
        billingDay: d.Value(billingDay),
        paymentDueDay: d.Value(paymentDueDay),
        bankName: d.Value(bankName),
        cardLastFour: d.Value(cardLastFour),
        note: d.Value(note),
        syncId: d.Value(syncId ?? _uuid.v4()),
        parentAccountId: d.Value(parentAccountId),
        avatarPath: d.Value(avatarPath),
      );

      final id = await db.into(db.accounts).insert(companion);
      // 单条 INFO 日志(import 批量场景下 3 条/账户 会把 logger 队列冲爆,降级
      // 到 debug;只在出错时 error)
      logger.debug('AccountCreate', '账户创建: id=$id name=$name type=$type');
      return id;
    } catch (e, stack) {
      logger.error('AccountCreate', '创建账户失败 name=$name', e, stack);
      rethrow;
    }
  }

  @override
  Future<int> upsertAccount({
    required String name,
    int ledgerId = 0,
    String type = 'cash',
    String currency = 'CNY',
    double initialBalance = 0.0,
  }) async {
    final existing =
        await (db.select(db.accounts)..where((a) => a.name.equals(name))).get();
    if (existing.isNotEmpty) return existing.first.id;
    // 复用 createAccount(此时 name 不冲突,不会抛)
    return createAccount(
      ledgerId: ledgerId,
      name: name,
      type: type,
      currency: currency,
      initialBalance: initialBalance,
    );
  }

  @override
  Future<void> updateAccount(
    int id, {
    String? name,
    String? type,
    String? currency,
    double? initialBalance,
    double? creditLimit,
    int? billingDay,
    int? paymentDueDay,
    bool clearCreditCardFields = false,
    String? bankName,
    String? cardLastFour,
    String? note,
    bool clearMetadataFields = false,
    bool? hidden,
    String? parentAccountId,
    bool clearParentAccount = false,
    String? avatarPath,
    bool clearAvatar = false,
  }) async {
    await (db.update(db.accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(
        name: name != null ? d.Value(name) : const d.Value.absent(),
        type: type != null ? d.Value(type) : const d.Value.absent(),
        currency: currency != null ? d.Value(currency) : const d.Value.absent(),
        initialBalance: initialBalance != null
            ? d.Value(initialBalance)
            : const d.Value.absent(),
        creditLimit: clearCreditCardFields
            ? const d.Value(null)
            : (creditLimit != null
                ? d.Value(creditLimit)
                : const d.Value.absent()),
        billingDay: clearCreditCardFields
            ? const d.Value(null)
            : (billingDay != null
                ? d.Value(billingDay)
                : const d.Value.absent()),
        paymentDueDay: clearCreditCardFields
            ? const d.Value(null)
            : (paymentDueDay != null
                ? d.Value(paymentDueDay)
                : const d.Value.absent()),
        bankName: clearMetadataFields
            ? const d.Value(null)
            : (bankName != null ? d.Value(bankName) : const d.Value.absent()),
        cardLastFour: clearMetadataFields
            ? const d.Value(null)
            : (cardLastFour != null
                ? d.Value(cardLastFour)
                : const d.Value.absent()),
        note: clearMetadataFields
            ? const d.Value(null)
            : (note != null ? d.Value(note) : const d.Value.absent()),
        hidden: hidden == null ? const d.Value.absent() : d.Value(hidden),
        parentAccountId: clearParentAccount
            ? const d.Value(null)
            : (parentAccountId != null
                ? d.Value(parentAccountId)
                : const d.Value.absent()),
        avatarPath: clearAvatar
            ? const d.Value(null)
            : (avatarPath != null
                ? d.Value(avatarPath)
                : const d.Value.absent()),
      ),
    );
  }

  @override
  Future<void> setAccountHidden(int id, bool hidden) =>
      updateAccount(id, hidden: hidden);

  @override
  Future<List<Account>> getCreditCardAccounts() async {
    return await (db.select(db.accounts)
          ..where((a) => a.type.equals('credit_card'))
          ..orderBy([(a) => d.OrderingTerm(expression: a.sortOrder)]))
        .get();
  }

  @override
  Future<double> getCreditCardUsedAmount(int accountId,
      {DateTime? asOf}) async {
    // 已用额度 = -balance（余额为负表示欠款）
    final balance = await getAccountBalance(accountId, asOf: asOf);
    return balance < 0 ? -balance : 0.0;
  }

  @override
  Future<double> getCreditCardChargedAsOf(int accountId,
      {DateTime? asOf}) async {
    final now = DateTime.now();
    // clamp 到「现在」——即使调用方显式传了未来时间点,也不该把还没发生的
    // 周期性交易预先计入(对齐 Cloud `min(cycle_end_dt, now)`)。
    final cutoff = (asOf == null || asOf.isAfter(now)) ? now : asOf;
    // 入帳歸屬日 = COALESCE(deferred_posting_at, happened_at)——延後入帳的
    // 交易要用延後後的日期做帳期截斷,對齊 Cloud `_ATTR_DATE`、以及 App 既有
    // `getAccountStatementTransactions` 同一套口徑。原本這裡用 happened_at
    // 直接截斷,會出現「一般明細已經把這筆排除到下一期,但這裡的 charged
    // 仍把它算進這期」的不一致(2026-08-18 使用者實測回報:一筆 140 元已
    // 標記延後入帳的交易,讓「已繳金額」倒推出 -140 的異常負數)。
    final results = await db.customSelect(
      '''
      SELECT type, amount FROM transactions
      WHERE account_id = ?1 AND type IN ('expense', 'income')
        AND $_kExcludeJoinedSharedLedgerSql
        AND COALESCE(deferred_posting_at, happened_at) <= ?2
      ''',
      variables: [
        d.Variable.withInt(accountId),
        d.Variable.withInt(cutoff.millisecondsSinceEpoch ~/ 1000),
      ],
      readsFrom: {db.transactions},
    ).get();
    var charged = 0.0;
    for (final row in results) {
      final type = row.data['type'] as String;
      final amount = (row.data['amount'] as num).toDouble();
      charged += type == 'expense' ? amount : -amount;
    }
    return charged;
  }

  @override
  Future<double> getCreditCardPaidTotal(int accountId) async {
    final sharedIds = await _sharedLedgerIds();
    final txs = await (db.select(db.transactions)
          ..where((t) =>
              t.toAccountId.equals(accountId) &
              t.type.equals('transfer') &
              t.ledgerId.isNotIn(sharedIds)))
        .get();
    var paid = 0.0;
    for (final t in txs) {
      paid += t.amount;
    }
    return paid;
  }

  @override
  Future<List<Transaction>> getCreditCardPaymentTransactions(
      int accountId) async {
    // 跟 [getCreditCardPaidTotal] 同一個查詢範圍(type='transfer'、
    // toAccountId=accountId、排除共享帳本、真·終身不設 cutoff),只是回傳
    // 明細列而非加總——「繳款記錄」清單依 [attributePaymentsToPeriods] 做
    // FIFO 期別歸屬用,依入帳歸屬日由舊到新排序。
    final sharedIds = await _sharedLedgerIds();
    final txs = await (db.select(db.transactions)
          ..where((t) =>
              t.toAccountId.equals(accountId) &
              t.type.equals('transfer') &
              t.ledgerId.isNotIn(sharedIds)))
        .get();
    txs.sort((a, b) => (a.deferredPostingAt ?? a.happenedAt)
        .compareTo(b.deferredPostingAt ?? b.happenedAt));
    return txs;
  }

  @override
  Future<DateTime?> getCreditCardFirstActivityAt(int accountId) async {
    // 這張卡「有史以來」第一筆會影響帳單口徑的交易(expense/income/轉入的
    // transfer)入帳歸屬日——用來當 [attributePaymentsToPeriods] 模擬展開的
    // 起點,必須是跟「查詢哪個 targetOffset」「呼叫當下是哪一天」都無關的
    // 穩定值,不能用聚合快照代替(2026-08-18 開發過程中踩過這個重複計算陷阱,
    // 見 docs/changes/2026-08-18-credit-card-payment-period-attribution-fix.md)。
    final results = await db.customSelect(
      '''
      SELECT MIN(COALESCE(deferred_posting_at, happened_at)) AS first_at
      FROM transactions
      WHERE $_kExcludeJoinedSharedLedgerSql
        AND (
          (type IN ('expense', 'income') AND account_id = ?1)
          OR (type = 'transfer' AND to_account_id = ?1)
        )
      ''',
      variables: [d.Variable.withInt(accountId)],
      readsFrom: {db.transactions},
    ).get();
    final epochSeconds = results.first.data['first_at'] as int?;
    if (epochSeconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  }

  @override
  Future<void> deleteAccount(int id) async {
    await (db.delete(db.accounts)..where((a) => a.id.equals(id))).go();
  }

  /// 「以成员身份加入的共享账本」ledger id 集合 —— **个人资产统计一律排除
  /// 这些账本的交易**。加入他人共享账本时,Owner 的历史流水会同步到本机并
  /// 挂在本地账户行上,若计入会把别人账本的收支算进自己的净资产,且与
  /// Web/服务端口径(成员侧不计共享账本)永久不一致。
  /// 注意:**自己 Own 的共享账本不排除** —— 那是自己的账本分享给别人,
  /// 服务端也记在 Owner 名下。SQL 版条件见 _kExcludeJoinedSharedLedgerSql。
  Future<Set<int>> _sharedLedgerIds() async {
    final rows = await (db.selectOnly(db.ledgers)
          ..addColumns([db.ledgers.id])
          ..where(db.ledgers.isShared.equals(true) &
              db.ledgers.myRole.equals('owner').not()))
        .get();
    return rows.map((r) => r.read(db.ledgers.id)!).toSet();
  }

  /// customSelect 用的排除条件(语义同 [_sharedLedgerIds])
  static const String _kExcludeJoinedSharedLedgerSql =
      "ledger_id NOT IN (SELECT id FROM ledgers WHERE is_shared = 1 AND my_role != 'owner')";

  @override
  Future<double> getAccountBalance(int accountId, {DateTime? asOf}) async {
    // 获取账户初始资金
    final account = await (db.select(db.accounts)
          ..where((a) => a.id.equals(accountId)))
        .getSingleOrNull();

    if (account == null) return 0.0;

    // 估值账户直接返回 initialBalance 作为当前估值
    if (isValuationOnlyType(account.type)) {
      return account.initialBalance;
    }

    double balance = account.initialBalance;
    final sharedIds = await _sharedLedgerIds();
    // 账户余额只该反映「已经发生」的交易——周期性交易可以预先生成未来日期
    // 的记录(例如下个月才扣款的订阅),在它真正发生前不该计入当前余额/
    // 信用卡欠款,否则资产页金额会比实际偏高。跟 server 端
    // routers/read/workspace.py 的 `happened_at <= now` 口径对齐(该处注释
    // 记录了同一个使用者反馈:信用卡显示的消费金额不该连未来的都算进去)。
    // [asOf] 传入时把这个截止时间从「现在」换成指定时间点——信用卡帳單彙總
    // 卡片用它算「截至某个帳期结束日」的终身跑动余额快照。
    final cutoff = asOf ?? DateTime.now();

    // 收入和支出(排除共享账本)
    final normalTxs = await (db.select(db.transactions)
          ..where((t) =>
              t.accountId.equals(accountId) &
              t.ledgerId.isNotIn(sharedIds) &
              t.happenedAt.isSmallerOrEqualValue(cutoff)))
        .get();

    for (final t in normalTxs) {
      if (t.type == 'income') {
        balance += t.amount;
      } else if (t.type == 'expense') {
        balance -= t.amount;
      } else if (t.type == 'transfer') {
        // 作为转出账户
        balance -= t.amount;
      } else if (t.type == 'adjustment') {
        balance += t.amount;
      }
    }

    // 作为转入账户的转账(排除共享账本)
    final transfersIn = await (db.select(db.transactions)
          ..where((t) =>
              t.toAccountId.equals(accountId) &
              t.type.equals('transfer') &
              t.ledgerId.isNotIn(sharedIds) &
              t.happenedAt.isSmallerOrEqualValue(cutoff)))
        .get();

    for (final t in transfersIn) {
      balance += t.amount;
    }

    return balance;
  }

  @override
  Future<double> getAccountGlobalBalance(int accountId) async {
    final account = await (db.select(db.accounts)
          ..where((a) => a.id.equals(accountId)))
        .getSingle();

    // 估值账户直接返回 initialBalance
    if (isValuationOnlyType(account.type)) {
      return account.initialBalance;
    }

    // 获取所有交易(排除共享账本)。happenedAt <= now:同 [getAccountBalance]
    // 注释,不把未来才发生的周期性交易算进当前余额。
    final sharedIds = await _sharedLedgerIds();
    final now = DateTime.now();
    final transactions = await (db.select(db.transactions)
          ..where((t) =>
              (t.accountId.equals(accountId) |
                  t.toAccountId.equals(accountId)) &
              t.ledgerId.isNotIn(sharedIds) &
              t.happenedAt.isSmallerOrEqualValue(now)))
        .get();

    double balance = account.initialBalance;

    for (final tx in transactions) {
      if (tx.accountId == accountId) {
        // 作为主账户
        if (tx.type == 'income') {
          balance += tx.amount;
        } else if (tx.type == 'expense') {
          balance -= tx.amount;
        } else if (tx.type == 'transfer') {
          balance -= tx.amount;
        } else if (tx.type == 'adjustment') {
          balance += tx.amount;
        }
      } else if (tx.toAccountId == accountId) {
        // 作为转入账户（转账）
        balance += tx.amount;
      }
    }

    return balance;
  }

  @override
  Future<double> getAccountBalanceInLedger(int accountId, int ledgerId) async {
    // happenedAt <= now:同 [getAccountBalance] 注释,不把未来才发生的周期
    // 性交易算进当前余额。
    final now = DateTime.now();
    final transactions = await (db.select(db.transactions)
          ..where((t) =>
              (t.accountId.equals(accountId) |
                  t.toAccountId.equals(accountId)) &
              t.ledgerId.equals(ledgerId) &
              t.happenedAt.isSmallerOrEqualValue(now)))
        .get();

    double balance = 0.0;

    for (final tx in transactions) {
      if (tx.accountId == accountId) {
        // 作为主账户
        if (tx.type == 'income') {
          balance += tx.amount;
        } else if (tx.type == 'expense') {
          balance -= tx.amount;
        } else if (tx.type == 'transfer') {
          balance -= tx.amount;
        } else if (tx.type == 'adjustment') {
          balance += tx.amount;
        }
      } else if (tx.toAccountId == accountId) {
        // 作为转入账户（转账）
        balance += tx.amount;
      }
    }

    return balance;
  }

  @override
  Future<Map<int, double>> getAllAccountBalances(int ledgerId) async {
    final accounts = await (db.select(db.accounts)
          ..where((a) => a.ledgerId.equals(ledgerId)))
        .get();

    final Map<int, double> balances = {};
    for (final account in accounts) {
      balances[account.id] = await getAccountBalance(account.id);
    }

    return balances;
  }

  @override
  Future<int> getTransactionCountByAccount(int accountId) async {
    // 统计作为主账户的交易数
    final mainCount = await db.customSelect(
      'SELECT COUNT(*) AS count FROM transactions WHERE account_id = ?1',
      variables: [d.Variable.withInt(accountId)],
      readsFrom: {db.transactions},
    ).getSingle();

    // 统计作为转入账户的交易数
    final toCount = await db.customSelect(
      'SELECT COUNT(*) AS count FROM transactions WHERE to_account_id = ?1',
      variables: [d.Variable.withInt(accountId)],
      readsFrom: {db.transactions},
    ).getSingle();

    int parseCount(dynamic v) {
      if (v is int) return v;
      if (v is BigInt) return v.toInt();
      if (v is num) return v.toInt();
      return 0;
    }

    return parseCount(mainCount.data['count']) +
        parseCount(toCount.data['count']);
  }

  @override
  Future<double> getAccountExpense(int accountId) async {
    double expense = 0.0;

    // 获取作为主账户的支出和转出(排除共享账本;不计入收支的交易也排除)
    final sharedIds = await _sharedLedgerIds();
    final normalTxs = await (db.select(db.transactions)
          ..where((t) =>
              t.accountId.equals(accountId) &
              t.ledgerId.isNotIn(sharedIds) &
              t.excludeFromStats.equals(false)))
        .get();

    for (final t in normalTxs) {
      if (t.type == 'expense') {
        expense += t.amount;
      } else if (t.type == 'transfer') {
        // 作为转出账户
        expense += t.amount;
      }
    }

    return expense;
  }

  @override
  Future<double> getAccountIncome(int accountId) async {
    double income = 0.0;

    // 获取作为主账户的收入(排除共享账本;不计入收支的交易也排除)
    final sharedIds = await _sharedLedgerIds();
    final normalTxs = await (db.select(db.transactions)
          ..where((t) =>
              t.accountId.equals(accountId) &
              t.ledgerId.isNotIn(sharedIds) &
              t.excludeFromStats.equals(false)))
        .get();

    for (final t in normalTxs) {
      if (t.type == 'income') {
        income += t.amount;
      }
    }

    // 作为转入账户的转账(排除共享账本;不计入收支的交易也排除)
    final transfersIn = await (db.select(db.transactions)
          ..where((t) =>
              t.toAccountId.equals(accountId) &
              t.type.equals('transfer') &
              t.ledgerId.isNotIn(sharedIds) &
              t.excludeFromStats.equals(false)))
        .get();

    for (final t in transfersIn) {
      income += t.amount;
    }

    return income;
  }

  @override
  Future<({double balance, double expense, double income})> getAccountStats(
      int accountId) async {
    final balance = await getAccountBalance(accountId);
    final expense = await getAccountExpense(accountId);
    final income = await getAccountIncome(accountId);
    return (balance: balance, expense: expense, income: income);
  }

  @override
  Future<Map<int, ({double balance, double expense, double income})>>
      getAllAccountStats() async {
    final accounts = await db.select(db.accounts).get();

    final Map<int, ({double balance, double expense, double income})> stats =
        {};
    for (final account in accounts) {
      stats[account.id] = await getAccountStats(account.id);
    }

    return stats;
  }

  @override

  /// ⚠️ 多币种口径未处理:本方法跨所有账本/账户按 type 裸加 amount。当前
  /// 无 UI 消费(allAccountsTotalStatsProvider 是死代码),故不影响任何界面。
  /// 若将来接「全局总收支」卡片:这是跨账本汇总,正确口径是按各账户币种
  /// rate 折算到用户主币种(同净值卡 convertedNetWorth),**不是** nativeAmount
  /// (各账本本位币可能不同,nativeAmount 相加无意义)。届时须重写,勿直接
  /// 套账本维度的 nativeAmount 折算。
  Future<({double totalBalance, double totalExpense, double totalIncome})>
      getAllAccountsTotalStats() async {
    final accounts = await db.select(db.accounts).get();

    // 总余额 = 所有账户余额之和（转账不影响总余额）
    double totalBalance = 0.0;
    for (final account in accounts) {
      final balance = await getAccountBalance(account.id);
      totalBalance += balance;
    }

    // 总收入/支出：直接从交易表查询，排除转账类型
    final accountIds = accounts.map((a) => a.id).toSet();

    // 收入/支出排除不计入收支的交易(余额不受影响,见上方 totalBalance)
    final sharedIds = await _sharedLedgerIds();
    final allTxs = await (db.select(db.transactions)
          ..where((t) =>
              t.accountId.isNotNull() &
              t.ledgerId.isNotIn(sharedIds) &
              t.excludeFromStats.equals(false)))
        .get();

    double totalIncome = 0.0;
    double totalExpense = 0.0;

    for (final t in allTxs) {
      // 只统计属于已有账户的交易
      if (t.accountId != null && accountIds.contains(t.accountId)) {
        if (t.type == 'income') {
          totalIncome += t.amount;
        } else if (t.type == 'expense') {
          totalExpense += t.amount;
        }
        // 转账类型不计入总收入/支出
      }
    }

    return (
      totalBalance: totalBalance,
      totalExpense: totalExpense,
      totalIncome: totalIncome
    );
  }

  @override
  Future<Map<int, int>> getAccountUsageInLedgers(int accountId) async {
    final result = await db.customSelect(
      '''
      SELECT ledger_id, COUNT(*) as count
      FROM transactions
      WHERE account_id = ? OR to_account_id = ?
      GROUP BY ledger_id
      ''',
      variables: [d.Variable.withInt(accountId), d.Variable.withInt(accountId)],
      readsFrom: {db.transactions},
    ).get();

    final Map<int, int> usage = {};
    for (final row in result) {
      final ledgerId = row.data['ledger_id'] as int;
      final count = row.data['count'];

      int countInt = 0;
      if (count is int) {
        countInt = count;
      } else if (count is BigInt) {
        countInt = count.toInt();
      } else if (count is num) {
        countInt = count.toInt();
      }

      usage[ledgerId] = countInt;
    }

    return usage;
  }

  @override
  Future<int> migrateAccount({
    required int fromAccountId,
    required int toAccountId,
  }) async {
    final beforeCount = await getTransactionCountByAccount(fromAccountId);

    // 迁移作为主账户的交易
    await (db.update(db.transactions)
          ..where((t) => t.accountId.equals(fromAccountId)))
        .write(TransactionsCompanion(accountId: d.Value(toAccountId)));

    // 迁移作为转入账户的交易
    await (db.update(db.transactions)
          ..where((t) => t.toAccountId.equals(fromAccountId)))
        .write(TransactionsCompanion(toAccountId: d.Value(toAccountId)));

    return beforeCount;
  }

  @override
  Future<bool> hasTransactions(int accountId) async {
    final count = await db.customSelect(
      'SELECT COUNT(*) as count FROM transactions WHERE account_id = ? OR to_account_id = ?',
      variables: [d.Variable.withInt(accountId), d.Variable.withInt(accountId)],
      readsFrom: {db.transactions},
    ).getSingle();

    final c = count.data['count'];
    if (c is int) return c > 0;
    if (c is BigInt) return c > BigInt.zero;
    if (c is num) return c > 0;
    return false;
  }

  @override
  Stream<Account?> watchAccount(int accountId) {
    return (db.select(db.accounts)..where((a) => a.id.equals(accountId)))
        .watchSingleOrNull();
  }

  @override
  Stream<List<Transaction>> watchAccountTransactions(int accountId) {
    return (db.select(db.transactions)
          ..where((t) =>
              t.accountId.equals(accountId) | t.toAccountId.equals(accountId))
          ..orderBy([
            (t) => d.OrderingTerm(
                expression: t.happenedAt, mode: d.OrderingMode.desc)
          ]))
        .watch();
  }

  @override
  Future<void> batchInsertAccounts(List<AccountsCompanion> accounts) async {
    await db.batch((batch) {
      batch.insertAll(db.accounts, accounts);
    });
  }

  @override
  Future<List<Account>> getAccountsByIds(List<int> accountIds) async {
    if (accountIds.isEmpty) return [];
    return await (db.select(db.accounts)..where((a) => a.id.isIn(accountIds)))
        .get();
  }

  @override
  Future<void> updateAccountSortOrders(
      List<({int id, int sortOrder})> updates) async {
    await db.transaction(() async {
      for (final update in updates) {
        await (db.update(db.accounts)..where((a) => a.id.equals(update.id)))
            .write(AccountsCompanion(sortOrder: d.Value(update.sortOrder)));
      }
    });
  }

  @override
  Future<List<Transaction>> getAccountTransactions(
    int accountId, {
    int limit = 50,
    int offset = 0,
    String? flow,
    List<int>? extraAccountIds,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // 主帳戶(合併帳單分組)聚合視圖:accountId + extraAccountIds 一起按
    // IN (...) 查,跟单账户走同一条 SQL,只是集合大小不同。
    final ids = [accountId, ...?extraAccountIds];
    final idPlaceholders =
        List.generate(ids.length, (i) => '?${i + 1}').join(', ');
    // flow 过滤按资金流向:支出视图含转出,收入视图含转入,null 为全部
    final where = switch (flow) {
      'expense' =>
        "account_id IN ($idPlaceholders) AND type IN ('expense', 'transfer')",
      'income' =>
        "(type = 'income' AND account_id IN ($idPlaceholders)) OR (type = 'transfer' AND to_account_id IN ($idPlaceholders))",
      _ =>
        'account_id IN ($idPlaceholders) OR to_account_id IN ($idPlaceholders)',
    };
    // numbered ?N 占位符可以在同一条 SQL 里重复出现(account_id IN 一次、
    // to_account_id IN 一次),两处都复用同一批变量,不用重复绑定。
    final idVariables = ids.map((id) => d.Variable.withInt(id)).toList();

    // 帳單週期篩選(信用卡「交易明細」tab):happened_at 落库是 epoch 秒。
    const dateColumn = 'happened_at';
    var nextIndex = ids.length + 1;
    final dateVariables = <d.Variable>[];
    var dateWhere = '';
    if (startDate != null) {
      dateWhere += ' AND $dateColumn >= ?$nextIndex';
      dateVariables
          .add(d.Variable.withInt(startDate.millisecondsSinceEpoch ~/ 1000));
      nextIndex++;
    }
    if (endDate != null) {
      // endDate 视为「含整个自然日」,不管调用方传的是不是当天 00:00:00,
      // 都补到 23:59:59 再比较,避免当天下午的交易被判成「週期外」。
      final endOfDay =
          DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
      dateWhere += ' AND $dateColumn <= ?$nextIndex';
      dateVariables
          .add(d.Variable.withInt(endOfDay.millisecondsSinceEpoch ~/ 1000));
      nextIndex++;
    }
    final limitIndex = nextIndex;
    final offsetIndex = nextIndex + 1;

    final results = await db.customSelect(
      '''
      SELECT * FROM transactions
      WHERE ($where) AND $_kExcludeJoinedSharedLedgerSql$dateWhere
      ORDER BY happened_at DESC
      LIMIT ?$limitIndex OFFSET ?$offsetIndex
      ''',
      variables: [
        ...idVariables,
        ...dateVariables,
        d.Variable.withInt(limit),
        d.Variable.withInt(offset),
      ],
      readsFrom: {db.transactions},
    ).get();

    // 用 Drift 生成的 map(而非手动挑字段)转回 Transaction——手动列字段
    // 之前漏掉了 rewardRuleIdsJson/currencyCode/nativeAmount 等后加的列,
    // 导致信用卡帐户页从这里查出来的交易丢失红利回饋规则等资料。
    return results.map((row) => db.transactions.map(row.data)).toList();
  }

  @override
  Future<List<Transaction>> getAccountStatementTransactions({
    required int accountId,
    List<int>? extraAccountIds,
    required DateTime cycleStart,
    required DateTime cycleEnd,
  }) async {
    final ids = [accountId, ...?extraAccountIds];
    final idPlaceholders =
        List.generate(ids.length, (i) => '?${i + 1}').join(', ');
    final idVariables = ids.map((id) => d.Variable.withInt(id)).toList();

    // 對帳清單口徑:expense/income 只認 account_id,transfer 只認
    // to_account_id(轉出視角不算消費),其它 type 不收——跟
    // reconciliation_providers.dart 舊版 Dart 端 belongs 判斷語意一致。
    final where =
        "(type IN ('expense', 'income') AND account_id IN ($idPlaceholders)) "
        "OR (type = 'transfer' AND to_account_id IN ($idPlaceholders))";

    // 入帳歸屬日 = COALESCE(deferred_posting_at, happened_at),兩個時間戳
    // 落库都是 epoch 秒。cycleEnd 視為「含整個自然日」,補到 23:59:59。
    final endOfDay =
        DateTime(cycleEnd.year, cycleEnd.month, cycleEnd.day, 23, 59, 59);
    final startIndex = ids.length + 1;
    final endIndex = startIndex + 1;

    final results = await db.customSelect(
      '''
      SELECT * FROM transactions
      WHERE ($where) AND $_kExcludeJoinedSharedLedgerSql
        AND COALESCE(deferred_posting_at, happened_at) >= ?$startIndex
        AND COALESCE(deferred_posting_at, happened_at) <= ?$endIndex
      ORDER BY happened_at DESC
      LIMIT 5000
      ''',
      variables: [
        ...idVariables,
        d.Variable.withInt(cycleStart.millisecondsSinceEpoch ~/ 1000),
        d.Variable.withInt(endOfDay.millisecondsSinceEpoch ~/ 1000),
      ],
      readsFrom: {db.transactions},
    ).get();

    return results.map((row) => db.transactions.map(row.data)).toList();
  }

  @override
  Future<List<({DateTime date, double balance})>> getAccountDailyBalances(
      int accountId,
      {required DateTime startDate,
      required DateTime endDate}) async {
    final account = await getAccount(accountId);
    if (account == null) return [];

    // 估值账户：每天返回固定估值
    if (isValuationOnlyType(account.type)) {
      final result = <({DateTime date, double balance})>[];
      var currentDate =
          DateTime(startDate.year, startDate.month, startDate.day);
      final end = DateTime(endDate.year, endDate.month, endDate.day);
      while (!currentDate.isAfter(end)) {
        result.add((date: currentDate, balance: account.initialBalance));
        currentDate = currentDate.add(const Duration(days: 1));
      }
      return result;
    }

    // 获取 endDate **当天结束**之前的所有交易(按日期升序,排除共享账本)。
    // endDate 语义是「含当天」:调用方(trendTodayAnchor)传当天 0 点,若用
    // <= endDate 会把当天发生的交易全部截掉 —— 趋势终点永远停在"昨晚为止",
    // 今天记的账不进趋势线。
    final endExclusive = DateTime(endDate.year, endDate.month, endDate.day)
        .add(const Duration(days: 1));
    final sharedIds = await _sharedLedgerIds();
    final allTxs = await (db.select(db.transactions)
          ..where((t) =>
              t.accountId.equals(accountId) | t.toAccountId.equals(accountId))
          ..where((t) => t.happenedAt.isSmallerThanValue(endExclusive))
          ..where((t) => t.ledgerId.isNotIn(sharedIds))
          ..orderBy([(t) => d.OrderingTerm(expression: t.happenedAt)]))
        .get();

    // 计算 startDate 之前的余额
    double runningBalance = account.initialBalance;
    int txIndex = 0;

    // 先累加 startDate 之前的交易
    while (txIndex < allTxs.length &&
        allTxs[txIndex].happenedAt.isBefore(startDate)) {
      final tx = allTxs[txIndex];
      if (tx.accountId == accountId) {
        if (tx.type == 'income') {
          runningBalance += tx.amount;
        } else if (tx.type == 'expense') {
          runningBalance -= tx.amount;
        } else if (tx.type == 'transfer') {
          runningBalance -= tx.amount;
        } else if (tx.type == 'adjustment') {
          runningBalance += tx.amount;
        }
      }
      if (tx.toAccountId == accountId && tx.type == 'transfer') {
        runningBalance += tx.amount;
      }
      txIndex++;
    }

    // 按天填充
    final result = <({DateTime date, double balance})>[];
    var currentDate = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);

    while (!currentDate.isAfter(end)) {
      final nextDate = currentDate.add(const Duration(days: 1));

      // 累加当天的交易
      while (txIndex < allTxs.length &&
          allTxs[txIndex].happenedAt.isBefore(nextDate)) {
        final tx = allTxs[txIndex];
        if (tx.accountId == accountId) {
          if (tx.type == 'income') {
            runningBalance += tx.amount;
          } else if (tx.type == 'expense') {
            runningBalance -= tx.amount;
          } else if (tx.type == 'transfer') {
            runningBalance -= tx.amount;
          } else if (tx.type == 'adjustment') {
            runningBalance += tx.amount;
          }
        }
        if (tx.toAccountId == accountId && tx.type == 'transfer') {
          runningBalance += tx.amount;
        }
        txIndex++;
      }

      result.add((date: currentDate, balance: runningBalance));
      currentDate = nextDate;
    }

    return result;
  }

  @override
  Future<List<({int? id, String name, String? icon, double total})>>
      getAccountCategoryStats(int accountId, {required String type}) async {
    final results = await db.customSelect(
      '''
      SELECT c.id, c.name, c.icon, SUM(t.amount) as total
      FROM transactions t
      LEFT JOIN categories c ON t.category_id = c.id
      WHERE t.account_id = ?1 AND t.type = ?2
        AND t.$_kExcludeJoinedSharedLedgerSql
      GROUP BY c.id
      ORDER BY total DESC
      ''',
      variables: [
        d.Variable.withInt(accountId),
        d.Variable.withString(type),
      ],
      readsFrom: {db.transactions, db.categories},
    ).get();

    return results.map((row) {
      return (
        id: row.data['id'] as int?,
        name: (row.data['name'] as String?) ?? '未分类',
        icon: row.data['icon'] as String?,
        total: (row.data['total'] as num).toDouble(),
      );
    }).toList();
  }

  @override
  Future<({double totalAssets, double totalLiabilities, double netWorth})>
      getNetWorthBreakdown() async {
    final accounts = await getAllAccounts();
    double totalAssets = 0.0;
    double totalLiabilities = 0.0;

    for (final account in accounts) {
      final balance = await getAccountBalance(account.id);
      if (isAssetType(account.type)) {
        totalAssets += balance;
      } else {
        totalLiabilities += balance;
      }
    }

    return (
      totalAssets: totalAssets,
      totalLiabilities: totalLiabilities,
      netWorth: totalAssets + totalLiabilities,
    );
  }

  @override
  Future<
          Map<String,
              ({double totalAssets, double totalLiabilities, double netWorth})>>
      getNetWorthBreakdownByCurrency() async {
    final accounts = await getAllAccounts();
    final Map<String,
            ({double totalAssets, double totalLiabilities, double netWorth})>
        result = {};

    for (final account in accounts) {
      final balance = await getAccountBalance(account.id);
      final currency = account.currency.toUpperCase();
      final prev = result[currency] ??
          (totalAssets: 0.0, totalLiabilities: 0.0, netWorth: 0.0);

      if (isAssetType(account.type)) {
        result[currency] = (
          totalAssets: prev.totalAssets + balance,
          totalLiabilities: prev.totalLiabilities,
          netWorth: prev.netWorth + balance,
        );
      } else {
        result[currency] = (
          totalAssets: prev.totalAssets,
          totalLiabilities: prev.totalLiabilities + balance,
          netWorth: prev.netWorth + balance,
        );
      }
    }

    return result;
  }

  @override
  Future<List<({DateTime date, double balance})>> getNetWorthDailyBalances({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final accounts = await getAllAccounts();
    if (accounts.isEmpty) return [];

    // 获取每个账户的每日余额
    final allBalances = <int, List<({DateTime date, double balance})>>{};
    for (final account in accounts) {
      allBalances[account.id] = await getAccountDailyBalances(
        account.id,
        startDate: startDate,
        endDate: endDate,
      );
    }

    // 按日聚合
    final result = <({DateTime date, double balance})>[];
    var currentDate = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    int dayIndex = 0;

    while (!currentDate.isAfter(end)) {
      double dayTotal = 0.0;
      for (final account in accounts) {
        final balances = allBalances[account.id]!;
        if (dayIndex < balances.length) {
          dayTotal += balances[dayIndex].balance;
        }
      }
      result.add((date: currentDate, balance: dayTotal));
      currentDate = currentDate.add(const Duration(days: 1));
      dayIndex++;
    }

    return result;
  }

  @override
  Future<List<({DateTime date, double assets, double liabilities, double net})>>
      getNetWorthTrendSeries({
    required DateTime startDate,
    required DateTime endDate,
    required Map<String, double> ratesToBase,
  }) async {
    final accounts = await getAllAccounts();
    if (accounts.isEmpty) return [];

    final allBalances = <int, List<({DateTime date, double balance})>>{};
    for (final account in accounts) {
      allBalances[account.id] = await getAccountDailyBalances(account.id,
          startDate: startDate, endDate: endDate);
    }

    final result =
        <({DateTime date, double assets, double liabilities, double net})>[];
    var currentDate = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    int dayIndex = 0;
    while (!currentDate.isAfter(end)) {
      double assets = 0.0, liabilities = 0.0;
      for (final account in accounts) {
        final balances = allBalances[account.id]!;
        if (dayIndex < balances.length) {
          // 折算到主币种:缺汇率的币种整条剔除(与净资产卡同口径,绝不按 1.0 裸加)。
          final rate = ratesToBase[account.currency.toUpperCase()];
          if (rate == null) continue;
          final bal = balances[dayIndex].balance * rate;
          if (isAssetType(account.type)) {
            assets += bal;
          } else {
            liabilities += bal;
          }
        }
      }
      result.add((
        date: currentDate,
        assets: assets,
        liabilities: liabilities,
        net: assets + liabilities
      ));
      currentDate = currentDate.add(const Duration(days: 1));
      dayIndex++;
    }
    return result;
  }

  @override
  Future<List<({String type, double totalBalance})>>
      getAssetCompositionByType() async {
    final accounts = await getAllAccounts();
    final Map<String, double> typeBalances = {};

    for (final account in accounts) {
      final balance = await getAccountBalance(account.id);
      typeBalances.update(account.type, (v) => v + balance,
          ifAbsent: () => balance);
    }

    return typeBalances.entries
        .map((e) => (type: e.key, totalBalance: e.value))
        .toList();
  }

  @override
  Future<List<({String type, String currency, double totalBalance})>>
      getAssetCompositionByTypeAndCurrency() async {
    final accounts = await getAllAccounts();
    // (type, currency 大写) -> 余额累加
    final Map<({String type, String currency}), double> balances = {};

    for (final account in accounts) {
      final balance = await getAccountBalance(account.id);
      final key =
          (type: account.type, currency: account.currency.toUpperCase());
      balances.update(key, (v) => v + balance, ifAbsent: () => balance);
    }

    return balances.entries
        .map((e) => (
              type: e.key.type,
              currency: e.key.currency,
              totalBalance: e.value,
            ))
        .toList();
  }

  @override
  Future<void> updateAccountValuation(int accountId, double newValue) async {
    await (db.update(db.accounts)..where((a) => a.id.equals(accountId))).write(
      AccountsCompanion(
        initialBalance: d.Value(newValue),
        updatedAt: d.Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<SharedLedgerAccount?> getSharedAccountBySyncId(String syncId) {
    return (db.select(db.sharedLedgerAccounts)
          ..where((t) => t.syncId.equals(syncId)))
        .getSingleOrNull();
  }

  @override
  Future<Set<String>> getUsedCurrencies() async {
    final rows =
        await db.customSelect('SELECT DISTINCT currency FROM accounts').get();
    return rows.map((r) => (r.read<String>('currency')).toUpperCase()).toSet();
  }
}
