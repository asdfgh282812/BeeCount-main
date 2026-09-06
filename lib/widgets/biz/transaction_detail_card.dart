import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/repositories/base_repository.dart';
import '../../data/repositories/debt_repository.dart';
import '../../data/repositories/installment_repository.dart'
    show kInstallmentPlanStatusActive;
import '../../data/repositories/local/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/budget_providers.dart';
import '../../services/attachment_service.dart';
import '../../services/billing/post_processor.dart';
import '../../services/data/category_service.dart';
import '../../styles/tokens.dart';
import '../../utils/account_type_utils.dart';
import '../../utils/card_reward_calc.dart';
import '../../utils/category_utils.dart';
import '../../utils/currencies.dart';
import '../../utils/transaction_edit_utils.dart';
import '../../utils/shared_ledger_picker_filter.dart';
import '../../pages/attachment/attachment_preview_page.dart';
import '../../pages/debt/debt_editor_page.dart';
import '../../pages/debt/debt_repayment_page.dart';
import '../category_icon.dart';
import '../ui/ui.dart';
import 'amount_text.dart';
import 'installment_action_sheets.dart';
import 'installment_edit_choice_dialog.dart';
import 'recurring_occurrence_dialogs.dart';

/// 点击交易时弹出的资讯卡:唯读展示,右上角退款/删除/复制/编辑四个动作,
/// 中间最大区块显示附图(没有图就显示分类图示+名称)。取代原本「点击直接进
/// 编辑页」的流程——编辑页现在只能从卡片的「编辑」按钮进入。
Future<void> showTransactionDetailCard(
  BuildContext context,
  WidgetRef ref,
  Transaction transaction,
  Category? category,
) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: BeeTokens.surfaceSheet(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => TransactionDetailCard(
      hostContext: context,
      hostRef: ref,
      transaction: transaction,
      category: category,
    ),
  );
}

class _AccountDisplay {
  final String name;
  final String type;
  const _AccountDisplay(this.name, this.type);
}

/// v38 拆帳:一筆拆分明細 + 反查到的分類物件(用來畫圖示/名稱;§7 共享
/// 帳本的 synthetic 分類也已經反查好,category==null 代表分類已被刪除
/// 等異常情況)。
typedef _ResolvedSplit = ({TransactionSplit row, Category? category});

class _DetailBundle {
  final _AccountDisplay? account;
  final List<Tag> tags;
  final List<TransactionAttachment> attachments;
  final List<Transaction> refunds;
  final List<CardRewardRule> rewardRules;
  final List<_ResolvedSplit> splits;
  final Project? project;

  /// 這筆交易關聯的欠款(不管是還款交易本身,還是某筆欠款的起點交易),
  /// null = 跟欠款無關。見 [_TransactionDetailCardState._loadBundle]。
  final DebtWithStatus? relatedDebt;

  const _DetailBundle({
    required this.account,
    required this.tags,
    required this.attachments,
    required this.refunds,
    required this.rewardRules,
    required this.splits,
    required this.project,
    required this.relatedDebt,
  });
}

class TransactionDetailCard extends ConsumerStatefulWidget {
  /// 打开卡片那个页面的 context——用来在卡片关闭"之后"继续 push 编辑器
  /// 页面(卡片自己的 context 在 pop 之后就失效了)。
  final BuildContext hostContext;

  /// 打开卡片那个页面的 ref——同 [hostContext],卡片自己的 `ref`(来自这个
  /// State 自己的 `ConsumerState`)在 `Navigator.pop()` 之后、State 被
  /// dispose 掉就不能再用了。`_handleEdit` 等方法 pop 卡片后还要
  /// `await` 一段可能很久的使用者互动(例如週期規則的選擇彈窗),如果那之後
  /// 才用卡片自己的 `ref` 去 `ref.read(...)`,dispose 早就跑完了,会直接
  /// 丟 Riverpod 的 "used after dispose" 例外——整段 await 链没有
  /// try/catch,例外会静默变成 unhandled Future error,表现成「彈窗關閉但
  /// 沒有跳轉」。改用呼叫端(卡片還沒開啟前)傳進來、生命週期比卡片長的
  /// [hostRef]。
  final WidgetRef hostRef;
  final Transaction transaction;
  final Category? category;

  const TransactionDetailCard({
    super.key,
    required this.hostContext,
    required this.hostRef,
    required this.transaction,
    required this.category,
  });

  @override
  ConsumerState<TransactionDetailCard> createState() =>
      _TransactionDetailCardState();
}

class _TransactionDetailCardState extends ConsumerState<TransactionDetailCard> {
  late final Future<_DetailBundle> _bundleFuture;

  @override
  void initState() {
    super.initState();
    _bundleFuture = _loadBundle();
  }

  Future<_DetailBundle> _loadBundle() async {
    final repo = ref.read(repositoryProvider);
    final tx = widget.transaction;

    final Future<_AccountDisplay?> accountFuture;
    if (tx.accountId != null) {
      accountFuture = repo
          .getAccount(tx.accountId!)
          .then((a) => a == null ? null : _AccountDisplay(a.name, a.type));
    } else if (tx.accountSyncIdOverride != null && repo is LocalRepository) {
      // §7 共享账本:Editor 视角看 Owner 的交易,账户在 SharedLedgerAccounts
      // 镜像表,不在主表。
      accountFuture = (repo.db.select(repo.db.sharedLedgerAccounts)
            ..where((t) => t.syncId.equals(tx.accountSyncIdOverride!)))
          .getSingleOrNull()
          .then(
              (s) => s == null ? null : _AccountDisplay(s.name, s.accountType));
    } else {
      accountFuture = Future.value(null);
    }

    final tagsFuture = repo.getTagsForTransaction(tx.id);
    final attachmentsFuture = repo.getAttachmentsByTransaction(tx.id);
    final refundsFuture = tx.syncId != null
        ? repo.getRefundsOf(tx.syncId!)
        : Future.value(<Transaction>[]);
    final rewardRuleIds = tx.rewardRuleIds;
    final rewardRulesFuture = rewardRuleIds.isEmpty
        ? Future.value(<CardRewardRule>[])
        : Future.wait(rewardRuleIds.map(repo.getCardRewardRuleBySyncId))
            .then((rules) => rules.whereType<CardRewardRule>().toList());

    final projectFuture = tx.projectSyncId != null
        ? repo.getProjectBySyncId(tx.projectSyncId!)
        : Future.value(null);

    final account = await accountFuture;
    final tags = await tagsFuture;
    final attachments = await attachmentsFuture;
    final refunds = await refundsFuture;
    final rewardRules = await rewardRulesFuture;
    final splits = await _loadSplits(repo, tx);
    final project = await projectFuture;
    final relatedDebt = await _loadRelatedDebt(repo, tx);
    return _DetailBundle(
      account: account,
      tags: tags,
      attachments: attachments,
      refunds: refunds,
      rewardRules: rewardRules,
      splits: splits,
      project: project,
      relatedDebt: relatedDebt,
    );
  }

  /// 找出這筆交易關聯的欠款——還款交易帶 [Transaction.debtSyncId] 直連;
  /// 欠款建立時的起點交易故意不帶這個欄位(見 [DebtRepository]
  /// createDebtWithOriginTransaction 文檔,避免污染還款金額加總),要反查
  /// [Debt.originTransactionSyncId] 才找得到。
  Future<DebtWithStatus?> _loadRelatedDebt(
      BaseRepository repo, Transaction tx) async {
    Debt? debt;
    if (tx.debtSyncId != null) {
      debt = await repo.getDebtBySyncId(tx.debtSyncId!);
    } else if (tx.syncId != null) {
      debt = await repo.getDebtByOriginTransactionSyncId(tx.syncId!);
    }
    if (debt == null) return null;
    return repo.getDebtWithStatus(debt.id);
  }

  /// v38 拆帳:反查每筆明細的分類物件,跟 `transaction_entry_form.dart`
  /// 的 `_resolveInitialSplits` 同一套邏輯(本地 categoryId 優先,查無再看
  /// categorySyncIdOverride 共享帳本兜底)。
  Future<List<_ResolvedSplit>> _loadSplits(
      BaseRepository repo, Transaction tx) async {
    if (!tx.hasSplits) return const [];
    final rows = await repo.getTransactionSplits(tx.id);
    final result = <_ResolvedSplit>[];
    for (final s in rows) {
      Category? cat;
      final override = s.categorySyncIdOverride;
      if (override != null && override.isNotEmpty && repo is LocalRepository) {
        cat = await repo.db
            .findCategoryBySyntheticId(syntheticIdForSyncId(override));
      } else if (s.categoryId != null) {
        cat = await repo.getCategoryById(s.categoryId!);
      }
      result.add((row: s, category: cat));
    }
    return result;
  }

  Future<void> _jumpToTransactionBySyncId(String syncId) async {
    final repo = ref.read(repositoryProvider);
    final target = await repo.getTransactionBySyncId(syncId);
    if (target == null) return;
    Category? targetCategory;
    if (target.categoryId != null) {
      targetCategory = await repo.getCategoryById(target.categoryId!);
    }
    if (!mounted) return;
    final hostContext = widget.hostContext;
    Navigator.of(context).pop();
    if (!hostContext.mounted) return;
    await showTransactionDetailCard(
        hostContext, widget.hostRef, target, targetCategory);
  }

  Future<void> _handleDelete() async {
    final l10n = AppLocalizations.of(context);
    final tx = widget.transaction;
    final repo = ref.read(repositoryProvider);

    // 問題 A 修正(2026-09-03,見
    // docs/changes/2026-09-03-installment-tracking-delete-sync-fixes.md):
    // 原本這裡對 installmentPlanSyncId != null 一律硬擋、提示改到分期管理
    // 頁操作——但整筆刪除分期計畫後偶爾會殘留孤兒交易,導致使用者卡死
    // (分期頁找不到計畫可以整筆刪,單筆又刪不掉)。改成完全交給
    // `TransactionEditUtils.deleteTransactionGuarded` 處理(它會先查 plan
    // 是否還存在:孤兒直接放行;plan 還在則彈「只刪這一筆 / 刪除整個計畫」
    // 二選一,「整個計畫」選項內部自己有二次確認),這裡不用再疊一層通用的
    // 「確定刪除?」彈窗。
    if (tx.installmentPlanSyncId != null) {
      final deleted =
          await TransactionEditUtils.deleteTransactionGuarded(context, ref, tx);
      if (!deleted || !mounted) return;
    } else if (tx.recurringRuleId != null) {
      // v36:週期規則生成的 occurrence 走「此記錄/連同未來週期」二選一彈窗
      // (對齐 MOZE 截圖語意,§2.2),純本地一次性交易維持原本的單一確認彈窗。
      final scope = await showRecurringDeleteChoiceSheet(context);
      if (scope == null || !mounted) return;
      await repo.deleteOccurrence(tx.id);
      if (scope == RecurringDeleteScope.thisAndFuture) {
        final rule = await repo.getRuleBySyncId(tx.recurringRuleId!);
        if (rule != null) await repo.terminateFuture(rule.id);
      }
      if (!mounted) return;
    } else {
      final confirmed = await AppDialog.confirm<bool>(
            context,
            title: l10n.deleteConfirmTitle,
            message: l10n.deleteConfirmMessage,
          ) ??
          false;
      if (!confirmed || !mounted) return;

      // 分期交易已在上面分流、不會走到這裡;透過共用入口刪除是為了跟其他
      // 頁面(search/category/tag 詳情頁、交易列表)保持同一套邏輯,不各自
      // 重複判斷(見 TransactionEditUtils.deleteTransactionGuarded)。
      final deleted =
          await TransactionEditUtils.deleteTransactionGuarded(context, ref, tx);
      if (!deleted || !mounted) return;
    }

    final curLedger = ref.read(currentLedgerIdProvider);
    ref.invalidate(countsForLedgerProvider(curLedger));
    ref.read(statsRefreshProvider.notifier).state++;
    ref.read(budgetRefreshProvider.notifier).state++;
    ref.read(tagListRefreshProvider.notifier).state++;
    ref.read(debtsRefreshProvider.notifier).state++;
    PostProcessor.sync(ref, ledgerId: curLedger);

    final overlay = Overlay.of(context);
    Navigator.of(context).pop();
    showToastOnOverlay(overlay, l10n.ledgersDeleted);
  }

  Future<void> _handleCopy() async {
    final hostContext = widget.hostContext;
    Navigator.of(context).pop();
    if (!hostContext.mounted) return;
    await TransactionEditUtils.copyTransaction(
        hostContext, widget.hostRef, widget.transaction, widget.category);
  }

  Future<void> _handleEdit(DebtWithStatus? relatedDebt) async {
    final hostContext = widget.hostContext;
    final tx = widget.transaction;
    // v49 分期付款(子專案 3):金額/日期/帳戶由分期計畫管理,不進一般編輯
    // 表單——改彈出 InstallmentEditChoiceDialog(修改此記錄/連同未來/提前
    // 還本/提前繳清),取代子專案 1 的唯讀鎖定 banner(見
    // docs/changes/2026-09-03-installment-tracking-phase3.md)。這裡不
    // `Navigator.pop()` 關卡片——四個分支都是彈窗+repo呼叫,不需要離開卡片
    // 導頁,操作完成後才在各自的 _apply* 方法裡收尾關閉。
    if (tx.installmentPlanSyncId != null) {
      await _handleInstallmentEdit(tx);
      return;
    }
    Navigator.of(context).pop();
    if (!hostContext.mounted) return;
    // 欠款相關交易(起點交易或還款交易)不走一般交易編輯表單——改回原本
    // 建立/記錄它時用的欠款專用表單,才看得出跟欠款的關係、也才有欠款特有
    // 的欄位/限制(本金不可改、還款金額回顯等)。
    if (relatedDebt != null) {
      if (tx.debtSyncId != null) {
        await Navigator.of(hostContext).push(MaterialPageRoute(
          builder: (_) => DebtRepaymentPage(
            debt: relatedDebt.debt,
            suggestedAmount: relatedDebt.remainingAmount,
            editingTransaction: tx,
          ),
        ));
      } else {
        await Navigator.of(hostContext).push(MaterialPageRoute(
          builder: (_) => DebtEditorPage(debt: relatedDebt.debt),
        ));
      }
      return;
    }
    // 用 widget.hostRef(呼叫端、生命週期比這張卡片長的 ref),不要用這個
    // State 自己的 ref——上面这行 pop 之后卡片马上开始 dispose,
    // `editTransaction` 内部会先 `await showRecurringEditChoiceSheet(...)`
    // 等使用者选「此記錄/連同未來週期」,这段等待通常比卡片的 dispose 慢
    // 得多,等使用者选完,这个 State 早就 dispose 完了,自己的 ref 已失效。
    await TransactionEditUtils.editTransaction(
        hostContext, widget.hostRef, tx, widget.category);
  }

  Future<void> _handleRefund() async {
    final tx = widget.transaction;
    // v49 分期付款(子專案 3):分期交易複用同一個退款入口,但先彈出
    // InstallmentPeriodRefundChoiceDialog 問「只退這一期」還是「整筆退款」
    // (見設計文件 §5.3)——不能直接走一般交易的 refundTransaction(那個是
    // 開一個新建模式的編輯器讓使用者自己選類別,分期退款是 repo 直接建交易,
    // 不經過編輯表單)。
    if (tx.installmentPlanSyncId != null) {
      await _handleInstallmentRefund(tx);
      return;
    }
    final hostContext = widget.hostContext;
    Navigator.of(context).pop();
    if (!hostContext.mounted) return;
    await TransactionEditUtils.refundTransaction(
        hostContext, widget.hostRef, widget.transaction, widget.category);
  }

  /// 分期交易明細頁的「編輯」入口(子專案 3)——彈
  /// [showInstallmentEditChoiceSheet] 四選一,依選擇打開子專案 2 已經做好的
  /// 對應 sheet 並呼叫對應 repository 方法。不離開卡片導頁,操作完成/失敗
  /// 都在卡片自己的 context 上收尾(跟 [_handleDelete] 同款風格)。
  Future<void> _handleInstallmentEdit(Transaction tx) async {
    final repo = ref.read(repositoryProvider);
    final plan =
        await repo.getInstallmentPlanBySyncId(tx.installmentPlanSyncId!);
    if (plan == null || !mounted) return;
    final periods = await repo.getInstallmentPeriods(plan.id);
    InstallmentPeriod? period;
    for (final p in periods) {
      if (p.txId == tx.id) {
        period = p;
        break;
      }
    }
    if (period == null || !mounted) return;

    final isActive = plan.status == kInstallmentPlanStatusActive;
    if (!mounted) return;
    final choice =
        await showInstallmentEditChoiceSheet(context, planActive: isActive);
    if (choice == null || !mounted) return;

    switch (choice) {
      case InstallmentEditChoice.thisRecordOnly:
        await _applyPeriodOverride(period);
        break;
      case InstallmentEditChoice.rebalanceFromHere:
        await _applyRebalanceFromHere(plan, period);
        break;
      case InstallmentEditChoice.earlyRepayPrincipal:
        await _applyEarlyRepay(plan);
        break;
      case InstallmentEditChoice.payoff:
        await _applyPayoff(plan, periods);
        break;
    }
  }

  Future<void> _applyPeriodOverride(InstallmentPeriod period) async {
    final repo = ref.read(repositoryProvider);
    final currentNote = period.txId != null
        ? (await repo.getTransactionById(period.txId!))?.note
        : null;
    if (!mounted) return;
    final currencyCode =
        ref.read(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    final input = await PeriodOverrideSheet.show(
      context,
      period: period,
      currentNote: currentNote,
      currencySymbol: getCurrencySymbol(currencyCode),
    );
    if (input == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    try {
      await repo.updatePeriodOverride(
        period.id,
        amount: input.amount,
        dueAt: input.dueAt,
        note: input.note,
      );
      await _finishInstallmentChange(l10n.installmentPeriodEditSuccess);
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.installmentOperationFailed(e.toString()));
      }
    }
  }

  Future<void> _applyRebalanceFromHere(
      InstallmentPlan plan, InstallmentPeriod period) async {
    final input = await RebalanceFromSheet.show(
      context,
      periodNo: period.periodNo,
      currentInterestRate: plan.interestRate,
      currentRepaymentMethod: plan.repaymentMethod,
    );
    if (input == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(repositoryProvider).rebalanceFrom(
            plan.id,
            period.periodNo,
            interestRate: input.interestRate,
            repaymentMethod: input.repaymentMethod,
          );
      await _finishInstallmentChange(l10n.installmentRebalanceSuccess);
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.installmentOperationFailed(e.toString()));
      }
    }
  }

  Future<void> _applyEarlyRepay(InstallmentPlan plan) async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    final currencyCode =
        ref.read(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    final input = await EarlyRepayPrincipalSheet.show(
      context,
      ledgerId: ledgerId,
      currencySymbol: getCurrencySymbol(currencyCode),
      initialAccountId: plan.accountId,
    );
    if (input == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(repositoryProvider).earlyRepayPrincipal(
            plan.id,
            paymentAmount: input.paymentAmount,
            accountId: input.accountId,
            happenedAt: input.happenedAt,
          );
      await _finishInstallmentChange(l10n.installmentEarlyRepaySuccess);
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.installmentOperationFailed(e.toString()));
      }
    }
  }

  Future<void> _applyPayoff(
      InstallmentPlan plan, List<InstallmentPeriod> periods) async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    final currencyCode =
        ref.read(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    // 預覽用的估算結清金額,算法跟 repo 內部 payoff() 一致(已過去期數以外
    // 的剩餘本金 + 下一個未到期期的原排程利息近似值)——跟
    // installment_list_page.dart `_openPayoff` 同款重複計算,純粹是 UI 給
    // 使用者的心理準備,不是權威值(權威計算永遠以 repo 實際執行時為準)。
    final now = DateTime.now();
    double happenedPrincipal = 0;
    for (final p in periods) {
      if (!p.dueAt.isAfter(now)) happenedPrincipal += p.principalAmount;
    }
    final futurePeriods = periods.where((p) => p.dueAt.isAfter(now)).toList();
    final accruedInterest =
        futurePeriods.isEmpty ? 0.0 : futurePeriods.first.interestAmount;
    final previewAmount = double.parse(
        (plan.totalAmount - happenedPrincipal + accruedInterest)
            .toStringAsFixed(2));

    if (!mounted) return;
    final input = await PayoffSheet.show(
      context,
      ledgerId: ledgerId,
      previewSettleAmount: previewAmount,
      currencySymbol: getCurrencySymbol(currencyCode),
      initialAccountId: plan.accountId,
    );
    if (input == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(repositoryProvider).payoff(
            plan.id,
            accountId: input.accountId,
            happenedAt: input.happenedAt,
          );
      await _finishInstallmentChange(l10n.installmentPayoffSuccess);
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.installmentOperationFailed(e.toString()));
      }
    }
  }

  /// 分期交易明細頁的「退款」入口(子專案 3)——彈
  /// [showInstallmentPeriodRefundChoiceSheet] 二選一:「只退這一期」呼叫
  /// [InstallmentRepository.refundPeriod];「整筆退款」直接呼叫既有的
  /// [InstallmentRepository.deleteInstallmentPlan](連已發生期交易一起刪),
  /// 走跟 `installment_list_page.dart` 刪除計畫一致的破壞性操作二次確認
  /// pattern([AppDialog.confirm])。
  Future<void> _handleInstallmentRefund(Transaction tx) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showInstallmentPeriodRefundChoiceSheet(context);
    if (choice == null || !mounted) return;

    final repo = ref.read(repositoryProvider);
    final plan =
        await repo.getInstallmentPlanBySyncId(tx.installmentPlanSyncId!);
    if (plan == null || !mounted) return;

    if (choice == InstallmentRefundChoice.wholePlan) {
      final confirmed = await AppDialog.confirm<bool>(
            context,
            title: l10n.installmentRefundWholePlanConfirmTitle,
            message: l10n.installmentRefundWholePlanConfirmMessage,
          ) ??
          false;
      if (!confirmed || !mounted) return;
      await repo.deleteInstallmentPlan(plan.id);
    } else {
      final periods = await repo.getInstallmentPeriods(plan.id);
      InstallmentPeriod? period;
      for (final p in periods) {
        if (p.txId == tx.id) {
          period = p;
          break;
        }
      }
      if (!mounted) return;
      final currencyCode =
          ref.read(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
      final input = await InstallmentPeriodRefundSheet.show(
        context,
        defaultAmount: period?.totalAmount ?? tx.amount,
        currencySymbol: getCurrencySymbol(currencyCode),
      );
      if (input == null || !mounted) return;
      try {
        await repo.refundPeriod(
          plan.id,
          tx.id,
          amount: input.amount,
          note: input.note,
          happenedAt: input.happenedAt,
        );
      } catch (e) {
        if (mounted) {
          showToast(context, l10n.installmentOperationFailed(e.toString()));
        }
        return;
      }
    }

    await _finishInstallmentChange(l10n.installmentRefundSuccess);
  }

  /// 分期狀態變更/退款操作成功後的共用收尾——刷新分期/統計/預算相關
  /// provider、觸發背景同步、關閉卡片並在 overlay 上顯示成功 toast(卡片
  /// pop 之後自己的 context 已經不能再用來 show toast,跟 [_handleDelete]
  /// 收尾時用 [showToastOnOverlay] 同一個理由)。
  Future<void> _finishInstallmentChange(String successMessage) async {
    if (!mounted) return;
    final curLedger = ref.read(currentLedgerIdProvider);
    ref.read(installmentsRefreshProvider.notifier).state++;
    ref.invalidate(countsForLedgerProvider(curLedger));
    ref.read(statsRefreshProvider.notifier).state++;
    ref.read(budgetRefreshProvider.notifier).state++;
    PostProcessor.sync(ref, ledgerId: curLedger);

    if (!mounted) return;
    final overlay = Overlay.of(context);
    Navigator.of(context).pop();
    showToastOnOverlay(overlay, successMessage);
  }

  Future<void> _handleRepay(DebtWithStatus relatedDebt) async {
    final hostContext = widget.hostContext;
    Navigator.of(context).pop();
    if (!hostContext.mounted) return;
    await Navigator.of(hostContext).push(MaterialPageRoute(
      builder: (_) => DebtRepaymentPage(
        debt: relatedDebt.debt,
        suggestedAmount: relatedDebt.remainingAmount,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tx = widget.transaction;
    final isTransfer = tx.type == 'transfer';
    final isAdjustment = tx.type == 'adjustment';
    final isExpense = tx.type == 'expense';
    final isRefundTx = tx.refundOfSyncId != null;

    return SafeArea(
      top: false,
      child: FutureBuilder<_DetailBundle>(
        future: _bundleFuture,
        builder: (context, snapshot) {
          final bundle = snapshot.data;
          final refunds = bundle?.refunds ?? const <Transaction>[];
          final alreadyRefunded = refunds.isNotEmpty;

          String? refundDisabledReason;
          if (isTransfer || isAdjustment) {
            refundDisabledReason = l10n.txDetailRefundDisabledType;
          } else if (isRefundTx) {
            refundDisabledReason = l10n.txDetailRefundDisabledIsRefund;
          } else if (alreadyRefunded) {
            refundDisabledReason = l10n.txDetailRefundDisabledAlreadyRefunded;
          }
          final canRefund = refundDisabledReason == null;

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context, l10n, canRefund, refundDisabledReason,
                      bundle?.relatedDebt),
                  _buildImageOrCategoryBlock(context, bundle),
                  _buildNoteAmountRow(context, l10n, isExpense, isTransfer,
                      isAdjustment, isRefundTx),
                  const SizedBox(height: 8),
                  _buildDetailRows(context, l10n, bundle),
                  _buildSplitSection(context, l10n, bundle),
                  _buildRewardSection(context, l10n, bundle),
                  if (alreadyRefunded)
                    _buildRefundedList(context, l10n, refunds),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context,
      AppLocalizations l10n,
      bool canRefund,
      String? refundDisabledReason,
      DebtWithStatus? relatedDebt) {
    final canRepay = relatedDebt != null &&
        relatedDebt.status != kDebtStatusSettled &&
        relatedDebt.status != kDebtStatusClosed;
    final isAdjustment = widget.transaction.type == 'adjustment';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            color: BeeTokens.iconSecondary(context),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          if (canRepay)
            IconButton(
              icon: const Icon(Icons.payments_outlined),
              color: BeeTokens.iconSecondary(context),
              tooltip: relatedDebt.debt.direction == kDebtDirectionPayable
                  ? l10n.debtRepayButtonPayable
                  : l10n.debtRepayButtonReceivable,
              onPressed: () => _handleRepay(relatedDebt),
            ),
          Tooltip(
            message: refundDisabledReason ?? l10n.txDetailRefund,
            child: IconButton(
              icon: const Icon(Icons.replay),
              color: canRefund
                  ? BeeTokens.iconSecondary(context)
                  : BeeTokens.iconTertiary(context),
              onPressed: canRefund ? _handleRefund : null,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: BeeTokens.iconSecondary(context),
            tooltip: l10n.commonDelete,
            onPressed: _handleDelete,
          ),
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            color: BeeTokens.iconSecondary(context),
            tooltip: l10n.txDetailCopy,
            onPressed: _handleCopy,
          ),
          Tooltip(
            message: isAdjustment
                ? l10n.txDetailEditDisabledAdjustment
                : l10n.commonEdit,
            child: IconButton(
              icon: const Icon(Icons.edit_outlined),
              color: isAdjustment
                  ? BeeTokens.iconTertiary(context)
                  : BeeTokens.iconSecondary(context),
              // v49 分期付款(子專案 3):分期交易的編輯圖示不再灰掉/鎖定——
              // _handleEdit 內部偵測到 installmentPlanSyncId != null 時改彈
              // InstallmentEditChoiceDialog(修改此記錄/連同未來/提前還本/
              // 提前繳清)四選一,取代子專案 1 的唯讀鎖定,見
              // docs/changes/2026-09-03-installment-tracking-phase3.md。
              onPressed: isAdjustment ? null : () => _handleEdit(relatedDebt),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageOrCategoryBlock(
      BuildContext context, _DetailBundle? bundle) {
    final attachments = bundle?.attachments ?? const <TransactionAttachment>[];
    if (attachments.isEmpty) {
      final categoryKind = widget.category?.kind ??
          (widget.transaction.type == 'income' ? 'income' : 'expense');
      // v38 拆帳:没有单一分类可显示,固定用「多類別」聚合图示+标签。
      final displayName = widget.transaction.hasSplits
          ? AppLocalizations.of(context).txSplitAggregateLabel
          : CategoryUtils.getDisplayName(widget.category?.name, context,
              kind: categoryKind);
      return Container(
        width: double.infinity,
        height: 220,
        alignment: Alignment.center,
        color: BeeTokens.surfaceElevated(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.transaction.hasSplits
                ? Icon(Icons.apps,
                    size: 88, color: BeeTokens.iconSecondary(context))
                : CategoryIconWidget(
                    category: widget.category,
                    categoryName: displayName,
                    size: 88,
                  ),
            const SizedBox(height: 12),
            Text(
              displayName,
              style: BeeTextTokens.title(context)
                  .copyWith(color: BeeTokens.textPrimary(context)),
            ),
          ],
        ),
      );
    }

    final first = attachments.first;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AttachmentPreviewPage.fromTransaction(
              transactionId: widget.transaction.id,
            ),
          ),
        );
      },
      child: SizedBox(
        width: double.infinity,
        height: 220,
        child: FutureBuilder<String>(
          future: ref
              .read(attachmentServiceProvider)
              .getAttachmentPath(first.fileName),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Container(color: BeeTokens.surfaceElevated(context));
            }
            return Image.file(
              File(snapshot.data!),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: BeeTokens.surfaceElevated(context),
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_outlined,
                    color: BeeTokens.iconTertiary(context), size: 48),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNoteAmountRow(BuildContext context, AppLocalizations l10n,
      bool isExpense, bool isTransfer, bool isAdjustment, bool isRefundTx) {
    final tx = widget.transaction;
    final categoryKind =
        widget.category?.kind ?? (tx.type == 'income' ? 'income' : 'expense');
    // v38 拆帳:没有单一分类可显示,固定用「多類別」聚合标签。
    final categoryDisplayName = tx.hasSplits
        ? l10n.txSplitAggregateLabel
        : CategoryUtils.getDisplayName(widget.category?.name, context,
            kind: categoryKind);
    final noteText = (tx.note != null && tx.note!.isNotEmpty)
        ? tx.note!
        : categoryDisplayName;

    Widget badge(String label, {VoidCallback? onTap}) {
      final content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: BeeTokens.iconSecondary(context).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: BeeTokens.textSecondary(context),
          ),
        ),
      );
      return onTap == null
          ? content
          : GestureDetector(onTap: onTap, child: content);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          tx.hasSplits
              ? Icon(Icons.apps,
                  size: 22, color: BeeTokens.iconSecondary(context))
              : CategoryIconWidget(
                  category: widget.category,
                  categoryName: categoryDisplayName,
                  size: 22,
                ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    noteText,
                    style: BeeTextTokens.title(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (tx.hasSplits) ...[
                  const SizedBox(width: 6),
                  badge(l10n.txSplitBadge),
                ],
                if (isRefundTx) ...[
                  const SizedBox(width: 6),
                  badge(l10n.txDetailRefundBadge, onTap: () {
                    final original = tx.refundOfSyncId;
                    if (original != null) _jumpToTransactionBySyncId(original);
                  }),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              AmountText(
                value: isAdjustment
                    ? tx.amount
                    : isExpense
                        ? -tx.amount
                        : tx.amount,
                signed: !isTransfer,
                currencyCode: tx.currencyCode,
                showCurrency: tx.currencyCode != null,
                decimals: 2,
                style: BeeTextTokens.title(context).copyWith(
                  color: isAdjustment
                      ? (tx.amount >= 0
                          ? BeeTokens.incomeColor(context, ref)
                          : BeeTokens.expenseColor(context, ref))
                      : isTransfer
                          ? BeeTokens.textPrimary(context)
                          : isExpense
                              ? BeeTokens.expenseColor(context, ref)
                              : BeeTokens.incomeColor(context, ref),
                ),
              ),
              if (!isTransfer && !isAdjustment)
                _buildFeeDiscountSubtitle(context, l10n),
            ],
          ),
        ],
      ),
    );
  }

  /// 手續費/折扣淨額分量提示——單看總額看不出來裡面含了多少手續費/折扣,
  /// 使用者反馈网页端「更新交易」對話框有標(內含手續費 $40)這種小字提示,
  /// App 這裡沒有,只能自己心算。跟金額本身一样走 [AmountText],既能繼承
  /// 隐藏金额(隱私模式)開關,也不用自己重做币种符号/千分位格式化。
  Widget _buildFeeDiscountSubtitle(
          BuildContext context, AppLocalizations l10n) =>
      buildFeeDiscountSubtitle(context, l10n, widget.transaction);

  Widget _detailItem(BuildContext context, IconData icon, String text) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 16, color: BeeTokens.iconTertiary(context)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: BeeTokens.textSecondary(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRows(
      BuildContext context, AppLocalizations l10n, _DetailBundle? bundle) {
    final tx = widget.transaction;
    final account = bundle?.account;
    final tags = bundle?.tags ?? const <Tag>[];
    final firstTagName = tags.isNotEmpty ? tags.first.name : '—';
    final merchant =
        (tx.merchant != null && tx.merchant!.isNotEmpty) ? tx.merchant! : '—';
    final repeatText =
        tx.recurringRuleId == null ? l10n.txDetailOnce : l10n.txDetailRecurring;
    final dateText =
        '${tx.happenedAt.year}/${tx.happenedAt.month.toString().padLeft(2, '0')}/${tx.happenedAt.day.toString().padLeft(2, '0')}';
    final timeText =
        '${tx.happenedAt.hour.toString().padLeft(2, '0')}:${tx.happenedAt.minute.toString().padLeft(2, '0')}';
    final project = bundle?.project;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              account != null
                  ? Expanded(
                      child: Row(
                        children: [
                          AccountTypeIcon(type: account.type, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              account.name,
                              style: TextStyle(
                                fontSize: 13,
                                color: BeeTokens.textSecondary(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _detailItem(
                      context, Icons.account_balance_wallet_outlined, '—'),
              _detailItem(context, Icons.sell_outlined, firstTagName),
            ],
          ),
          if (project != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _detailItem(
                  context,
                  CategoryService.getCategoryIcon(project.icon),
                  project.name,
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _detailItem(context, Icons.storefront_outlined, merchant),
              _detailItem(context, Icons.event_repeat, repeatText),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _detailItem(context, Icons.calendar_today_outlined, dateText),
              _detailItem(context, Icons.access_time, timeText),
            ],
          ),
        ],
      ),
    );
  }

  /// 若交易有勾選紅利回饋規則,在日期/時間下方顯示每條規則的名稱、費率與
  /// 該筆交易的預估回饋金——沒有套用任何規則時整塊不佔空間。每一列交給
  /// [_RewardRuleRow] 現場算「這筆交易所屬帳單週期」內、已跟同週期其他交易
  /// 共用 capAmount 扣減額度後的金額,不能直接用 [estimateCardRewardForRule]
  /// (那只算單筆、忽略同週期其他交易已經用掉多少額度,顯示金額可能超過
  /// capAmount,跟明細頁/帳戶頁彙總卡片對不上,見 2026-08-28 bugfix)。實際
  /// 入帳金額仍由 Server 端排程計算,這裡終究只是現場估算。
  Widget _buildRewardSection(
      BuildContext context, AppLocalizations l10n, _DetailBundle? bundle) {
    final rules = bundle?.rewardRules ?? const <CardRewardRule>[];
    if (rules.isEmpty) return const SizedBox.shrink();
    final tx = widget.transaction;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.txDetailRewardSectionTitle,
            style: TextStyle(
              fontSize: 13,
              color: BeeTokens.textSecondary(context),
            ),
          ),
          const SizedBox(height: 4),
          ...rules.map((rule) => _RewardRuleRow(rule: rule, tx: tx)),
        ],
      ),
    );
  }

  /// v38 拆帳:堆疊列出每筆拆分明細(圖示+分類名+備註+金額),排在附件/
  /// 分類主圖示區之後、其餘欄位卡片之前——比照截圖裡「主卡片 + 下方明細
  /// 列表」的排版。
  Widget _buildSplitSection(
      BuildContext context, AppLocalizations l10n, _DetailBundle? bundle) {
    final splits = bundle?.splits ?? const <_ResolvedSplit>[];
    if (splits.isEmpty) return const SizedBox.shrink();
    final tx = widget.transaction;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.txSplitDetailTitle,
            style: TextStyle(
              fontSize: 13,
              color: BeeTokens.textSecondary(context),
            ),
          ),
          const SizedBox(height: 4),
          ...splits.map((s) {
            final name = s.category != null
                ? CategoryUtils.getDisplayName(s.category!.name, context,
                    kind: s.category!.kind)
                : l10n.commonUncategorized;
            return Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Row(
                children: [
                  CategoryIconWidget(
                    category: s.category,
                    categoryName: name,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 14,
                            color: BeeTokens.textPrimary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (s.row.note != null && s.row.note!.isNotEmpty)
                          Text(
                            s.row.note!,
                            style: TextStyle(
                              fontSize: 12,
                              color: BeeTokens.textTertiary(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  AmountText(
                    value: tx.type == 'income' ? s.row.amount : -s.row.amount,
                    signed: true,
                    currencyCode: tx.currencyCode,
                    showCurrency: tx.currencyCode != null,
                    decimals: 2,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tx.type == 'income'
                          ? BeeTokens.incomeColor(context, ref)
                          : BeeTokens.expenseColor(context, ref),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRefundedList(
      BuildContext context, AppLocalizations l10n, List<Transaction> refunds) {
    final total = refunds.fold<double>(0, (sum, r) => sum + r.amount);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.replay,
                  size: 16, color: BeeTokens.iconTertiary(context)),
              const SizedBox(width: 6),
              Text(
                l10n.txDetailRefundedTotal,
                style: TextStyle(
                  fontSize: 13,
                  color: BeeTokens.textSecondary(context),
                ),
              ),
              const Spacer(),
              AmountText(
                value: total,
                signed: false,
                decimals: 2,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: BeeTokens.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...refunds.map((r) {
            final rDate =
                '${r.happenedAt.year}/${r.happenedAt.month.toString().padLeft(2, '0')}/${r.happenedAt.day.toString().padLeft(2, '0')}';
            return InkWell(
              onTap: () {
                final syncId = r.syncId;
                if (syncId != null) _jumpToTransactionBySyncId(syncId);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(rDate,
                        style: TextStyle(
                            fontSize: 12,
                            color: BeeTokens.textTertiary(context))),
                    const Spacer(),
                    AmountText(
                      value: r.amount,
                      signed: false,
                      decimals: 2,
                      style: TextStyle(
                          fontSize: 12,
                          color: BeeTokens.textSecondary(context)),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right,
                        size: 16, color: BeeTokens.iconTertiary(context)),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// 交易列表/對帳清單皆可共用的手續費/折扣小字提示,格式:「(內含 手續費
/// NT$36)」。抽成頂層函式讓 `account_reconciliation_page.dart` 的對帳
/// 清單列也能直接引用,不用重複這段組字邏輯。
Widget buildFeeDiscountSubtitle(
    BuildContext context, AppLocalizations l10n, Transaction tx) {
  final feeAmount = tx.feeAmount ?? 0;
  final discountAmount = tx.discountAmount ?? 0;
  if (feeAmount == 0 && discountAmount == 0) return const SizedBox.shrink();

  final subtitleStyle = TextStyle(
    fontSize: 12,
    color: BeeTokens.textTertiary(context),
  );

  final segments = <Widget>[];
  void addSegment(String label, double amount) {
    if (segments.isNotEmpty) {
      segments
          .add(Text(l10n.txDetailFeeDiscountSeparator, style: subtitleStyle));
    }
    segments.add(Text('$label ', style: subtitleStyle));
    segments.add(AmountText(
      value: amount,
      signed: false,
      currencyCode: tx.currencyCode,
      showCurrency: tx.currencyCode != null,
      decimals: 2,
      style: subtitleStyle,
    ));
  }

  if (feeAmount != 0) {
    addSegment(
      (tx.feeLabel != null && tx.feeLabel!.isNotEmpty)
          ? tx.feeLabel!
          : l10n.transactionFeeLabelHint,
      feeAmount,
    );
  }
  if (discountAmount != 0) {
    addSegment(
      (tx.discountLabel != null && tx.discountLabel!.isNotEmpty)
          ? tx.discountLabel!
          : l10n.transactionDiscountLabelHint,
      discountAmount,
    );
  }

  return Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('(${l10n.txDetailFeeDiscountPrefix} ', style: subtitleStyle),
        ...segments,
        Text(')', style: subtitleStyle),
      ],
    ),
  );
}

String _trimPercentZeros(double v) {
  final s = v.toStringAsFixed(2);
  return s.contains('.')
      ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : s;
}

/// [TransactionDetailCard._buildRewardSection] 的單一規則列——獨立成
/// ConsumerWidget 才能個別 watch [cardRewardForTransactionProvider](該筆
/// 交易所屬帳單週期的即時查詢,交易被新增/刪除/改期後重新打開這張卡片會拿到
/// 重算後的金額)。載入完成前先用 [estimateCardRewardForRule] 的單筆估算頂著
/// 顯示,避免整列閃爍空白;算出來的金額比單筆估算低,代表這筆交易的回饋被
/// 同週期其他交易吃掉的額度壓低了,加上「已達上限」提示,不然使用者會覺得
/// 金額對不上記帳表單當初顯示的預估值。
class _RewardRuleRow extends ConsumerWidget {
  final CardRewardRule rule;
  final Transaction tx;

  const _RewardRuleRow({required this.rule, required this.tx});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final singleTxEstimate = estimateCardRewardForRule(rule, tx.amount);
    final cappedAsync = ref
        .watch(cardRewardForTransactionProvider((rule: rule, transaction: tx)));
    final estimated = cappedAsync.valueOrNull ?? singleTxEstimate;
    final isCapped = estimated < singleTxEstimate - 0.005;
    final rateLabel = rule.rateType == 'percentage'
        ? '${rule.label} ${_trimPercentZeros(rule.rateValue)}%'
        : rule.label;

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        children: [
          Text(
            '➤ ',
            style:
                TextStyle(fontSize: 13, color: BeeTokens.textTertiary(context)),
          ),
          Expanded(
            child: Text(
              rateLabel,
              style: TextStyle(
                fontSize: 13,
                color: BeeTokens.textPrimary(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isCapped) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: BeeTokens.warning(context).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l10n.txDetailRewardCapped,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: BeeTokens.warning(context),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          AmountText(
            value: estimated,
            signed: false,
            currencyCode: tx.currencyCode,
            showCurrency: true,
            decimals: 2,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: BeeTokens.incomeColor(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}
