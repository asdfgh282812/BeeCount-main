import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/repositories/local/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../widgets/ui/ui.dart';

/// 信用卡紅利回饋規則的「複製」/「刪除」共用邏輯,供列表頁 tile 選單與編輯頁
/// AppBar 選單共用,避免兩處各寫一份。
///
/// 刪除語意對齊 BeeCount Cloud web 專用 REST endpoint 的行為
/// (`routers/write/card_reward_rules.py::delete_card_reward_rule_api`):規則
/// 已有交易掛著時**不能真刪**,否則會讓那些交易的 `rewardRuleIds` 斷鏈引用一
/// 個不存在的規則;web 端遇到這種情況會軟刪(`enabled=false`)。但 App 走的
/// 是通用 sync engine(見 `docs/changes/2026-08-16-card-reward-rules.md`「決策
/// 1」),`generic /sync/push` 的 delete action 是無條件硬刪
/// (`projection.delete_card_reward_rule`),不會做這個歷史檢查。這裡在送出
/// delete change 之前,用跟編輯頁 `_checkLocked` 相同的本地代理判斷
/// (本地是否有交易的 rewardRuleIds 命中這條規則)複製 web 端的軟刪邏輯。

/// 本地代理判斷「是否已有交易掛著這條規則」,同
/// `card_reward_rule_editor_page.dart::_checkLocked`。
Future<bool> cardRewardRuleHasLocalHistory(
    WidgetRef ref, String? syncId) async {
  if (syncId == null || syncId.isEmpty) return false;
  final repo = ref.read(repositoryProvider);
  if (repo is! LocalRepository) return false;
  final needle = '"$syncId"';
  final hit = await (repo.db.select(repo.db.transactions)
        ..where((t) => t.rewardRuleIdsJson.like('%$needle%'))
        ..limit(1))
      .getSingleOrNull();
  return hit != null;
}

/// 複製一條規則:所有欄位原樣帶入新規則,名稱後綴「(複製)」,排在同帳戶
/// 現有規則之後。立即建立(不開編輯頁讓使用者先調整),建立後 toast 提示。
Future<void> duplicateCardRewardRule(
  BuildContext context,
  WidgetRef ref,
  CardRewardRule rule,
) async {
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(repositoryProvider);
  try {
    final siblings = await repo.getCardRewardRulesForAccount(rule.accountId);
    final maxSort =
        siblings.fold<int>(0, (m, r) => r.sortOrder > m ? r.sortOrder : m);
    final categoryIds = rule.categoryIds;

    await repo.createCardRewardRule(
      accountId: rule.accountId,
      label: l10n.cardRewardRuleCopyLabel(rule.label),
      categoryIds: categoryIds.isEmpty ? null : categoryIds,
      rateType: rule.rateType,
      rateValue: rule.rateValue,
      rounding: rule.rounding,
      totalRounding: rule.totalRounding,
      calcBasis: rule.calcBasis,
      interval: rule.interval,
      minSpendThreshold: rule.minSpendThreshold,
      minTxAmount: rule.minTxAmount,
      capAmount: rule.capAmount,
      capSharedKey: rule.capSharedKey,
      startsAt: rule.startsAt,
      endsAt: rule.endsAt,
      settlementType: rule.settlementType,
      settlementDays: rule.settlementDays,
      settlementMonthOffset: rule.settlementMonthOffset,
      settlementDayOfMonth: rule.settlementDayOfMonth,
      rewardAccountId: rule.rewardAccountId,
      note: rule.note,
      enabled: rule.enabled,
      sortOrder: maxSort + 1,
    );

    final activeLedgerId = ref.read(currentLedgerIdProvider);
    if (activeLedgerId > 0) {
      unawaited(PostProcessor.sync(ref, ledgerId: activeLedgerId));
    }
    if (context.mounted) showToast(context, l10n.cardRewardRuleCopied);
  } catch (e) {
    if (context.mounted) {
      showToast(context, l10n.cardRewardRuleSaveFailed(e.toString()));
    }
  }
}

/// 刪除一條規則,先跳二次確認彈窗。已有本地交易掛著時改成軟刪(disable),
/// 對話框文案會先說明這一點。回傳是否真的執行了刪除/停用(給呼叫方決定要
/// 不要順手關掉當前頁面)。
Future<bool> confirmAndDeleteCardRewardRule(
  BuildContext context,
  WidgetRef ref,
  CardRewardRule rule,
) async {
  final l10n = AppLocalizations.of(context);
  final locked = await cardRewardRuleHasLocalHistory(ref, rule.syncId);
  if (!context.mounted) return false;

  final confirm = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(locked
          ? l10n.cardRewardRuleDeleteLockedTitle
          : l10n.cardRewardRuleDeleteConfirmTitle),
      content: Text(locked
          ? l10n.cardRewardRuleDeleteLockedBody
          : l10n.cardRewardRuleDeleteConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text(l10n.commonDelete),
        ),
      ],
    ),
  );
  if (confirm != true) return false;

  final repo = ref.read(repositoryProvider);
  try {
    if (locked) {
      await repo.updateCardRewardRule(
        rule.id,
        const CardRewardRulesCompanion(enabled: Value(false)),
      );
    } else {
      await repo.deleteCardRewardRule(rule.id);
    }

    final activeLedgerId = ref.read(currentLedgerIdProvider);
    if (activeLedgerId > 0) {
      unawaited(PostProcessor.sync(ref, ledgerId: activeLedgerId));
    }
    if (context.mounted) {
      showToast(
        context,
        locked
            ? l10n.cardRewardRuleDisabledInsteadOfDeleted
            : l10n.cardRewardRuleDeleted,
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      showToast(context, l10n.cardRewardRuleSaveFailed(e.toString()));
    }
    return false;
  }
}
