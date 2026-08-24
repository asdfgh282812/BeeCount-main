import 'package:flutter/material.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/repositories/base_repository.dart';
import '../../data/repositories/debt_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../widgets/ui/ui.dart';
import '../account/account_detail_page.dart';
import '../debt/debt_list_page.dart';
import '../debt/debt_repayment_page.dart';
import '../transaction/recurring_rule_list_page.dart';

/// [_handleTap] 的 payload 解析結果。跟 Navigator 完全解耦,方便直接用真的
/// (記憶體)Drift db 單元測試,不用起 widget pump。
class NotificationJumpTarget {
  const NotificationJumpTarget._({
    this.account,
    this.hasRuleTarget = false,
    this.debt,
    this.hasCounterpartyTarget = false,
    this.notFound = false,
    this.ledgerNotSynced = false,
  });

  /// payload 沒有 accountId/recurringRuleId/debtId/counterpartyName(如
  /// budget_alert/system 或未知 category)——不用跳轉,只標已讀。
  static const none = NotificationJumpTarget._();

  /// payload 帶的 ledgerId 在本機找不到對應帳本(如共享帳本還沒同步下來)。
  static const ledgerNotSyncedResult = NotificationJumpTarget._(
    ledgerNotSynced: true,
  );

  /// payload 帶了 accountId/recurringRuleId/debtId,但本機查無此實體。
  static const notFoundResult = NotificationJumpTarget._(notFound: true);

  factory NotificationJumpTarget.account(Account account) =>
      NotificationJumpTarget._(account: account);

  static const rule = NotificationJumpTarget._(hasRuleTarget: true);

  factory NotificationJumpTarget.debt(DebtWithStatus debt) =>
      NotificationJumpTarget._(debt: debt);

  /// §5.5 通知中心「未結清對象清單」——payload 只帶 counterpartyName(對象
  /// 分組摘要,不是單一 debt),沒有可跳轉的單一欠款詳情,導去欠款清單頁
  /// 即可(見 [DebtListPage])。
  static const counterparty =
      NotificationJumpTarget._(hasCounterpartyTarget: true);

  final Account? account;
  final bool hasRuleTarget;
  final DebtWithStatus? debt;
  final bool hasCounterpartyTarget;
  final bool notFound;
  final bool ledgerNotSynced;
}

/// 依 web 端 `NotificationBell.tsx handleJumpToDetail` 的優先序:
/// accountId(涵蓋 card_due / card_reward)優先於 recurringRuleId(涵蓋一般
/// reminder)優先於 debtId(欠款到期提醒,同樣是 category='reminder' 但
/// payload 帶的是 debtId 不是 recurringRuleId,見 server 端
/// `debt_reminders.py`)優先於 counterpartyName(§5.5 未結清對象清單,
/// `category='debt_unsettled'`,對象分組摘要沒有單一 debtId)——四者互斥,
/// 靠 payload 帶哪個 key 判斷,不是靠 category)。跳轉前先把 payload 的
/// ledgerId(=server external_id/syncId)解回本機 ledger,和目前選中的帳本
/// 不同就先切過去,否則目標頁會查不到資料。
Future<NotificationJumpTarget> resolveNotificationJumpTarget(
  BaseRepository repo,
  Map<String, dynamic>? payload, {
  required int currentLedgerId,
  required void Function(int ledgerId) onSwitchLedger,
}) async {
  if (payload == null) return NotificationJumpTarget.none;
  final accountSyncId = payload['accountId'] as String?;
  final recurringRuleSyncId = payload['recurringRuleId'] as String?;
  final debtSyncId = payload['debtId'] as String?;
  final counterpartyName = payload['counterpartyName'] as String?;
  if (accountSyncId == null &&
      recurringRuleSyncId == null &&
      debtSyncId == null &&
      counterpartyName == null) {
    return NotificationJumpTarget.none;
  }

  final ledgerSyncId = payload['ledgerId'] as String?;
  if (ledgerSyncId != null && ledgerSyncId.isNotEmpty) {
    final ledger = await repo.getLedgerBySyncId(ledgerSyncId);
    if (ledger == null) return NotificationJumpTarget.ledgerNotSyncedResult;
    if (ledger.id != currentLedgerId) onSwitchLedger(ledger.id);
  }

  if (accountSyncId != null) {
    final account = await repo.getAccountBySyncId(accountSyncId);
    if (account == null) return NotificationJumpTarget.notFoundResult;
    return NotificationJumpTarget.account(account);
  }

  if (recurringRuleSyncId != null) {
    final rule = await repo.getRuleBySyncId(recurringRuleSyncId);
    if (rule == null) return NotificationJumpTarget.notFoundResult;
    return NotificationJumpTarget.rule;
  }

  if (debtSyncId != null) {
    final debt = await repo.getDebtBySyncId(debtSyncId);
    if (debt == null) return NotificationJumpTarget.notFoundResult;
    final withStatus = await repo.getDebtWithStatus(debt.id);
    if (withStatus == null) return NotificationJumpTarget.notFoundResult;
    return NotificationJumpTarget.debt(withStatus);
  }

  return NotificationJumpTarget.counterparty;
}

/// 通知中心 —— 展示 BeeCount Cloud 服务端已生成的通知(週期性到期/信用卡
/// 繳款日/紅利回饋等),App 只拉取/已讀標記,不做任何本地通知規則計算。
/// 資料源見 [notificationCenterProvider]。
class NotificationCenterPage extends ConsumerStatefulWidget {
  const NotificationCenterPage({super.key});

  @override
  ConsumerState<NotificationCenterPage> createState() =>
      _NotificationCenterPageState();
}

class _NotificationCenterPageState
    extends ConsumerState<NotificationCenterPage> {
  @override
  void initState() {
    super.initState();
    // 打开页面时立即刷新一次，60s 轮询只是下限（跟 web 端 bell 打开时刷新一致）。
    Future.microtask(
        () => ref.read(notificationCenterProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(notificationCenterProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.notificationsTitle,
            showBack: true,
            actions: [
              TextButton(
                onPressed: state.unreadCount > 0
                    ? () => ref
                        .read(notificationCenterProvider.notifier)
                        .markAllRead()
                    : null,
                child: Text(l10n.notificationsMarkAllRead),
              ),
            ],
          ),
          Expanded(child: _buildBody(context, l10n, state)),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    NotificationCenterState state,
  ) {
    if (state.error != null && state.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off,
                size: 64, color: BeeTokens.textTertiary(context)),
            const SizedBox(height: 16),
            Text(
              l10n.notificationsLoadError,
              style: TextStyle(color: BeeTokens.textSecondary(context)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () =>
                  ref.read(notificationCenterProvider.notifier).refresh(),
              child: Text(l10n.notificationsRetry),
            ),
          ],
        ),
      );
    }

    if (state.items.isEmpty && !state.loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none,
                size: 64, color: BeeTokens.textTertiary(context)),
            const SizedBox(height: 16),
            Text(
              l10n.notificationsEmpty,
              style: TextStyle(color: BeeTokens.textTertiary(context)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(notificationCenterProvider.notifier).refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) =>
            _NotificationTile(item: state.items[index], onTap: _handleTap),
      ),
    );
  }

  Future<void> _handleTap(BeeCountCloudNotificationItem item) async {
    final l10n = AppLocalizations.of(context);
    await ref.read(notificationCenterProvider.notifier).markRead(item.id);

    final target = await resolveNotificationJumpTarget(
      ref.read(repositoryProvider),
      item.payload,
      currentLedgerId: ref.read(currentLedgerIdProvider),
      onSwitchLedger: (ledgerId) =>
          ref.read(currentLedgerIdProvider.notifier).state = ledgerId,
    );
    if (!mounted) return;

    if (target.account != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AccountDetailPage(account: target.account!),
        ),
      );
    } else if (target.hasRuleTarget) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RecurringRuleListPage()),
      );
    } else if (target.debt != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DebtRepaymentPage(
            debt: target.debt!.debt,
            suggestedAmount: target.debt!.remainingAmount,
          ),
        ),
      );
    } else if (target.hasCounterpartyTarget) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DebtListPage()),
      );
    } else if (target.notFound) {
      showToast(context, l10n.notificationTargetNotFound);
    } else if (target.ledgerNotSynced) {
      showToast(context, l10n.notificationLedgerNotSynced);
    }
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final BeeCountCloudNotificationItem item;
  final void Function(BeeCountCloudNotificationItem item) onTap;

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'reminder':
        return Icons.repeat;
      case 'card_due':
        return Icons.credit_card;
      case 'card_reward':
        return Icons.card_giftcard;
      case 'debt_unsettled':
        return Icons.groups_outlined;
      default:
        return Icons.info_outline;
    }
  }

  String _relativeTime(BuildContext context, DateTime time) {
    final l10n = AppLocalizations.of(context);
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return l10n.notificationTimeJustNow;
    if (diff.inMinutes < 60) {
      return l10n.notificationTimeMinutesAgo(diff.inMinutes);
    }
    if (diff.inHours < 24) return l10n.notificationTimeHoursAgo(diff.inHours);
    if (diff.inDays < 30) return l10n.notificationTimeDaysAgo(diff.inDays);
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final unread = !item.isRead;
    return InkWell(
      onTap: () => onTap(item),
      child: Container(
        color:
            unread ? BeeTokens.primary(context).withValues(alpha: 0.05) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_categoryIcon(item.category),
                size: 20, color: BeeTokens.textSecondary(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontWeight:
                                unread ? FontWeight.w600 : FontWeight.normal,
                            color: BeeTokens.textPrimary(context),
                          ),
                        ),
                      ),
                      if (unread)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 8, top: 2),
                          decoration: BoxDecoration(
                            color: BeeTokens.error(context),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if (item.body != null && item.body!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.body!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: BeeTokens.textSecondary(context),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _relativeTime(context, item.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: BeeTokens.textTertiary(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
