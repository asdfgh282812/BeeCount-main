import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db.dart';
import '../pages/transaction/transaction_editor_page.dart';
import '../data/repositories/local/local_repository.dart';
import '../providers/database_providers.dart';
import '../widgets/biz/recurring_occurrence_dialogs.dart';
import 'shared_ledger_picker_filter.dart' show syntheticIdForSyncId;

/// 解析交易的标签/类别/账户(含 §7 共享账本 override → synthetic id)三元组,
/// 供编辑/复制共用。
class _ResolvedTransactionRefs {
  final List<int> tagIds;
  final int? categoryId;
  final int? accountId;
  final int? toAccountId;

  const _ResolvedTransactionRefs({
    required this.tagIds,
    required this.categoryId,
    required this.accountId,
    required this.toAccountId,
  });
}

class TransactionEditUtils {
  static Future<_ResolvedTransactionRefs> _resolveRefs(
    WidgetRef ref,
    Transaction transaction,
  ) async {
    final repo = ref.read(repositoryProvider);
    final tags = await repo.getTagsForTransaction(transaction.id);
    final tagIds = <int>[for (final t in tags) t.id];

    // §7 共享账本:加 TransactionTagOverrides → synthetic id 加进列表,
    // picker 显示选中
    if (repo is LocalRepository && transaction.syncId != null) {
      final overrides = await (repo.db.select(repo.db.transactionTagOverrides)
            ..where((t) => t.transactionSyncId.equals(transaction.syncId!)))
          .get();
      for (final ov in overrides) {
        final synthetic = syntheticIdForSyncId(ov.tagSyncId);
        if (!tagIds.contains(synthetic)) tagIds.add(synthetic);
      }
    }

    // §7 v25 共享账本:Editor 视角下记的 tx,categoryId/accountId 为 null,
    // 真实引用在 *SyncIdOverride。编辑时用 syntheticIdForSyncId 转成 picker
    // 列表里的 synthetic id,让 editor 反查时能命中"已选"。
    final int? categoryId = transaction.categorySyncIdOverride != null
        ? syntheticIdForSyncId(transaction.categorySyncIdOverride!)
        : transaction.categoryId;
    final int? accountId = transaction.accountSyncIdOverride != null
        ? syntheticIdForSyncId(transaction.accountSyncIdOverride!)
        : transaction.accountId;
    final int? toAccountId = transaction.toAccountSyncIdOverride != null
        ? syntheticIdForSyncId(transaction.toAccountSyncIdOverride!)
        : transaction.toAccountId;

    return _ResolvedTransactionRefs(
      tagIds: tagIds,
      categoryId: categoryId,
      accountId: accountId,
      toAccountId: toAccountId,
    );
  }

  static Future<void> editTransaction(
    BuildContext context,
    WidgetRef ref,
    Transaction transaction,
    Category? category, {
    // 規則列表頁展開明細後的「編輯」按鈕跟「連同以後」是兩顆分開的按鈕,
    // 呼叫端已經替使用者決定好範圍(單筆),不該再跳一次「此記錄/連同未來
    // 週期」選擇彈窗問一次已經問過的問題。非 null 時直接沿用,跳過下面的
    // `showRecurringEditChoiceSheet`。
    RecurringEditScope? forcedScope,
  }) async {
    // v36 修正:週期規則生成的 occurrence 要在「進入編輯頁之前」就先問
    // 「修改此記錄 / 修改連同未來週期」——原本這個彈窗只在存檔那一刻才跳
    // (transaction_editor_page.dart `_handleSubmit` / transfer_form.dart
    // `_submit`),使用者從明細頁點編輯鉛筆會直接看到表單,體感上像是
    // 「完全沒有彈窗」。此處先問清楚,選擇結果透過
    // `initialRecurringEditScope` 帶進編輯頁,存檔時直接沿用,不再重問。
    RecurringEditScope? recurringScope = forcedScope;
    if (recurringScope == null && transaction.recurringRuleId != null) {
      recurringScope = await showRecurringEditChoiceSheet(context);
      if (recurringScope == null || !context.mounted) return;
    }

    final refs = await _resolveRefs(ref, transaction);
    if (!context.mounted) return;

    // 所有类型（收入/支出/转账）都使用交易编辑器页面
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionEditorPage(
          initialKind: transaction.type, // 'expense', 'income', 或 'transfer'
          initialCategoryId: refs.categoryId,
          initialAmount: transaction.amount,
          initialDate: transaction.happenedAt,
          initialNote: transaction.note,
          initialMerchant: transaction.merchant,
          editingTransactionId: transaction.id,
          initialAccountId: refs.accountId,
          // 转账特有的参数
          initialToAccountId: refs.toAccountId,
          // 标签
          initialTagIds: refs.tagIds,
          // v44:專案只存 syncId,直接透传,不走 _resolveRefs 的 synthetic 反查
          // (專案不參與 §7 共享帳本 override 機制)。
          initialProjectSyncId: transaction.projectSyncId,
          // 账单标记（不计入收支/预算）回显
          initialExcludeFromStats: transaction.excludeFromStats,
          initialExcludeFromBudget: transaction.excludeFromBudget,
          // v30 多币种:编辑外币交易时汇率行按隐含汇率回显
          initialCurrencyCode: transaction.currencyCode,
          initialNativeAmount: transaction.nativeAmount,
          initialRewardRuleIds: transaction.rewardRuleIds,
          initialRecurringEditScope: recurringScope,
        ),
      ),
    );
  }

  /// 复制交易——比照 BeeCount Cloud 网页版的「複製」:开一个新建模式的编辑器,
  /// 带入除日期(重设为现在)、附件、退款关联以外的所有字段。复制出来是全新
  /// 独立记录,不写任何数据库关联。
  static Future<void> copyTransaction(
    BuildContext context,
    WidgetRef ref,
    Transaction transaction,
    Category? category,
  ) async {
    final refs = await _resolveRefs(ref, transaction);
    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionEditorPage(
          initialKind: transaction.type,
          initialCategoryId: refs.categoryId,
          initialAmount: transaction.amount,
          initialDate: DateTime.now(), // 网页版复制不带日期,重设为现在
          initialNote: transaction.note,
          initialMerchant: transaction.merchant,
          editingTransactionId: null, // 新建模式
          initialAccountId: refs.accountId,
          initialToAccountId: refs.toAccountId,
          initialTagIds: refs.tagIds,
          initialProjectSyncId: transaction.projectSyncId,
          initialExcludeFromStats: transaction.excludeFromStats,
          initialExcludeFromBudget: transaction.excludeFromBudget,
          initialCurrencyCode: transaction.currencyCode,
          initialNativeAmount: transaction.nativeAmount,
          initialRewardRuleIds: transaction.rewardRuleIds,
          // 不传 initialRefundOfSyncId:复制出来的是独立新记录
        ),
      ),
    );
  }

  /// 退款——比照 BeeCount Cloud 网页版的「退款」:开一个新建模式的编辑器,
  /// 类型对调(expense↔income)、金额/备注/账户带入原交易(金额可改,天然支持
  /// 部分退款),类别留空让用户自己选。呼叫方需先确认 transaction.type 是
  /// expense/income(transfer/adjustment 不可退款),且这笔交易本身不是退款单、
  /// 也还没被退过款。
  static Future<void> refundTransaction(
    BuildContext context,
    WidgetRef ref,
    Transaction transaction,
    Category? category,
  ) async {
    final refs = await _resolveRefs(ref, transaction);
    if (!context.mounted) return;

    final reversedKind = transaction.type == 'expense' ? 'income' : 'expense';

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionEditorPage(
          initialKind: reversedKind,
          initialCategoryId: null, // 留空让用户自己选
          initialAmount: transaction.amount,
          initialDate: DateTime.now(),
          initialNote: transaction.note,
          editingTransactionId: null, // 新建模式
          initialAccountId: refs.accountId,
          initialCurrencyCode: transaction.currencyCode,
          initialRefundOfSyncId: transaction.syncId,
        ),
      ),
    );
  }
}
