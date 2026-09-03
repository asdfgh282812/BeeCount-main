import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db.dart';
import '../pages/transaction/transaction_editor_page.dart';
import '../data/repositories/installment_repository.dart'
    show InstallmentManagedTransactionException;
import '../data/repositories/local/local_repository.dart';
import '../l10n/app_localizations.dart';
import '../providers/database_providers.dart';
import '../providers/installment_providers.dart'
    show installmentsRefreshProvider;
import '../services/billing/post_processor.dart';
import '../widgets/biz/installment_edit_choice_dialog.dart';
import '../widgets/biz/recurring_occurrence_dialogs.dart';
import '../widgets/ui/ui.dart' show showToast, AppDialog;
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
          initialToAmount: transaction.toAmount,
          initialFeeAmount: transaction.feeAmount,
          initialFeeLabel: transaction.feeLabel,
          initialDiscountAmount: transaction.discountAmount,
          initialDiscountLabel: transaction.discountLabel,
          initialBaseAmount: transaction.baseAmount,
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
          initialToAmount: transaction.toAmount,
          initialFeeAmount: transaction.feeAmount,
          initialFeeLabel: transaction.feeLabel,
          initialDiscountAmount: transaction.discountAmount,
          initialDiscountLabel: transaction.discountLabel,
          initialBaseAmount: transaction.baseAmount,
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

  /// 刪除交易的共用入口——集中處理「這筆交易屬於分期計畫」的分流,取代子
  /// 專案 1 只在 `transaction_detail_card.dart` 一個入口做檢查的暫時方案
  /// (已知缺口見 `docs/changes/2026-09-03-installment-tracking-phase1.md`)。
  /// `search_page.dart`/`category_detail_page.dart`/`tag_detail_page.dart`/
  /// `transaction_list.dart`/`transaction_detail_card.dart` 都改呼叫這個
  /// 方法,不用各自複製 `installmentPlanSyncId` 檢查。
  ///
  /// 問題 A 修正(2026-09-03,見
  /// docs/changes/2026-09-03-installment-tracking-delete-sync-fixes.md):
  /// 原本 `installmentPlanSyncId != null` 一律攔下、提示改到分期管理頁操作
  /// ——但實機發現整筆刪除分期計畫後,本地有時會殘留指向已刪計畫的孤兒
  /// transaction/period(見上述文件對根因的調查),這種情況下硬攔會讓使用者
  /// 卡死(分期頁找不到計畫可以整筆刪,單筆交易又刪不掉)。改成:
  /// 1. 先查一次 `getInstallmentPlanBySyncId`——查不到(孤兒,plan 已經不
  ///    存在)就直接放行走一般刪除流程,不再顯示任何「去別的頁面」的提示。
  ///    `LocalRepository.deleteTransaction` 本身也做了同樣的 plan-存在性
  ///    檢查(第二層防線,見 [InstallmentManagedTransactionException] 的
  ///    doc)。
  /// 2. plan 還存在時,彈出 [showInstallmentTransactionDeleteChoiceSheet]
  ///    問使用者要「只刪這一筆」(`InstallmentRepository.deletePeriod`)還是
  ///    「刪除整個分期計畫」(既有的 `deleteInstallmentPlan`,帶二次確認)。
  ///    這個互動式選擇只在 [showFeedback] 為 `true`(單筆刪除場景)時進行;
  ///    [showFeedback] 為 `false` 的靜默/批量場景(如 `search_page.dart` 的
  ///    批量刪除)維持舊行為——遇到 plan 還存在的分期交易直接跳過,不彈窗
  ///    打斷批量操作。
  ///
  /// 回傳 `true` = 已刪除(含「刪除整個計畫」導致這筆交易被連帶刪除的情況);
  /// `false` = 使用者取消 / 被攔截。呼叫端在 `false` 時應直接 return,不要
  /// 跑後續的刷新/同步邏輯(installment 分支內部已經自己做了對應的刷新)。
  static Future<bool> deleteTransactionGuarded(
    BuildContext context,
    WidgetRef ref,
    Transaction transaction, {
    bool showFeedback = true,
  }) async {
    if (transaction.installmentPlanSyncId != null) {
      final repo = ref.read(repositoryProvider);
      final plan = await repo
          .getInstallmentPlanBySyncId(transaction.installmentPlanSyncId!);
      if (!context.mounted) return false;

      if (plan == null) {
        // 孤兒:plan 已經不存在(整筆刪除計畫時偶發的同步 race,見上方
        // doc),直接放行走一般刪除,不再顯示任何提示。
        return _deleteOrphanInstallmentTransaction(context, ref, transaction,
            showFeedback: showFeedback);
      }

      if (!showFeedback) {
        // 靜默/批量場景不彈選擇對話框,維持舊行為——攔下、跳過。
        return false;
      }
      return _deleteManagedInstallmentTransaction(
          context, ref, transaction, plan);
    }
    final repo = ref.read(repositoryProvider);
    try {
      await repo.deleteTransaction(transaction.id);
      return true;
    } on InstallmentManagedTransactionException {
      if (showFeedback && context.mounted) {
        showToast(
          context,
          AppLocalizations.of(context)
              .transactionInstallmentLockedDeleteMessage,
        );
      }
      return false;
    }
  }

  /// `installmentPlanSyncId != null` 但對應計畫已經不存在(孤兒交易)——
  /// 直接刪這筆交易。`LocalRepository.deleteTransaction` 已經確認過
  /// plan 不存在時會放行(並順便清掉指向這筆交易的孤兒 period),這裡的
  /// try/catch 只是防禦性兜底(理論上不會走到 catch 分支)。
  static Future<bool> _deleteOrphanInstallmentTransaction(
    BuildContext context,
    WidgetRef ref,
    Transaction transaction, {
    required bool showFeedback,
  }) async {
    final repo = ref.read(repositoryProvider);
    try {
      await repo.deleteTransaction(transaction.id);
      ref.read(installmentsRefreshProvider.notifier).state++;
      unawaited(PostProcessor.sync(ref, ledgerId: transaction.ledgerId));
      return true;
    } on InstallmentManagedTransactionException {
      if (showFeedback && context.mounted) {
        showToast(
          context,
          AppLocalizations.of(context)
              .transactionInstallmentLockedDeleteMessage,
        );
      }
      return false;
    }
  }

  /// `installmentPlanSyncId != null` 且對應計畫仍存在——彈二選一對話框,
  /// 依選擇呼叫 `deletePeriod`(只刪這一筆)或 `deleteInstallmentPlan`
  /// (整個計畫,帶二次確認)。
  static Future<bool> _deleteManagedInstallmentTransaction(
    BuildContext context,
    WidgetRef ref,
    Transaction transaction,
    InstallmentPlan plan,
  ) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showInstallmentTransactionDeleteChoiceSheet(context);
    if (choice == null || !context.mounted) return false;

    final repo = ref.read(repositoryProvider);

    if (choice == InstallmentTransactionDeleteChoice.wholePlan) {
      final confirmed = await AppDialog.confirm<bool>(
            context,
            title: l10n.installmentDeleteWholePlanConfirmTitle,
            message: l10n.installmentDeleteWholePlanConfirmMessage,
          ) ??
          false;
      if (!confirmed || !context.mounted) return false;
      await repo.deleteInstallmentPlan(plan.id);
      ref.read(installmentsRefreshProvider.notifier).state++;
      unawaited(PostProcessor.sync(ref, ledgerId: plan.ledgerId));
      return true;
    }

    // thisRecordOnly:反查這筆交易對應的 period(用 txId,同
    // transaction_detail_card.dart 既有的找法)。
    final periods = await repo.getInstallmentPeriods(plan.id);
    InstallmentPeriod? period;
    for (final p in periods) {
      if (p.txId == transaction.id) {
        period = p;
        break;
      }
    }
    if (period == null) {
      // 理論上不會發生(period.txId 一定指回這筆交易)——防禦性兜底。
      if (context.mounted) {
        showToast(context, l10n.transactionInstallmentLockedDeleteMessage);
      }
      return false;
    }
    try {
      await repo.deletePeriod(plan.id, period.id);
      ref.read(installmentsRefreshProvider.notifier).state++;
      unawaited(PostProcessor.sync(ref, ledgerId: plan.ledgerId));
      return true;
    } catch (e) {
      if (context.mounted) {
        showToast(context, l10n.installmentOperationFailed(e.toString()));
      }
      return false;
    }
  }
}
