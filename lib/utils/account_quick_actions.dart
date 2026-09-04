import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart' as db;
import '../providers.dart';
import '../styles/tokens.dart';
import '../l10n/app_localizations.dart';
import '../utils/currencies.dart';
import '../widgets/ui/ui.dart';
import '../pages/account/account_detail_page.dart'
    show accountTransactionsPaginatedProvider;

/// 調整餘額彈窗——比照 BeeCount Cloud 的「餘額調整」(`balance_adjustment_ep`):
/// 使用者輸入調整後應該的餘額,系統算出跟目前餘額的差額,自動建一筆
/// `type='adjustment'` 交易補上差額。跟估值帳戶的「更新估值」不是同一套
/// （那個直接改 initialBalance,不建交易、不同步),這裡走一般交易路徑,
/// 會被 ChangeTracker 記錄、正常同步上雲端。
///
/// 從 `account_detail_page.dart` 的 `_AccountDetailPageState
/// ._showBalanceAdjustmentDialog` 抽成頂層函式,供帳戶總覽頁滑動快捷操作
/// 共用（帳戶總覽頁滑動快捷操作設計文件）。
Future<void> showBalanceAdjustmentDialog(
  BuildContext context,
  WidgetRef ref,
  db.Account account,
  AppLocalizations l10n,
) async {
  final currentLedger = ref.read(currentLedgerProvider).asData?.value;
  if (currentLedger == null) return;

  final stats = await ref.read(accountStatsProvider(account.id).future);
  final currentBalance = stats.balance;
  if (!context.mounted) return;

  final targetController = TextEditingController(
    text: currentBalance.toStringAsFixed(2),
  );
  final noteController = TextEditingController();

  final result = await showDialog<double>(
    context: context,
    builder: (ctx) {
      final primaryColor = ref.watch(primaryColorProvider);
      return AlertDialog(
        title: Text(l10n.balanceAdjustmentDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.balanceAdjustmentCurrentBalanceLabel}: '
              '${getCurrencySymbol(account.currency)}${currentBalance.toStringAsFixed(2)}',
              style: TextStyle(color: BeeTokens.textSecondary(ctx)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: targetController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                prefixText: '${getCurrencySymbol(account.currency)} ',
                hintText: l10n.balanceAdjustmentTargetBalanceHint,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                hintText: l10n.balanceAdjustmentNoteHint,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              final value = double.tryParse(targetController.text.trim());
              if (value != null) {
                Navigator.pop(ctx, value);
              }
            },
            style: TextButton.styleFrom(foregroundColor: primaryColor),
            child: Text(l10n.commonOk),
          ),
        ],
      );
    },
  );

  final note = noteController.text.trim();
  targetController.dispose();
  noteController.dispose();

  if (result == null) return;
  final diff = double.parse((result - currentBalance).toStringAsFixed(2));

  final repo = ref.read(repositoryProvider);
  await repo.createAdjustmentTransaction(
    ledgerId: currentLedger.id,
    accountId: account.id,
    amount: diff,
    happenedAt: DateTime.now(),
    note: note.isNotEmpty
        ? note
        : l10n.balanceAdjustmentDefaultNote(currentBalance, result),
  );

  ref.invalidate(accountStatsProvider(account.id));
  ref.invalidate(accountTransactionsPaginatedProvider);
  if (account.type == 'credit_card' || account.type == 'account_group') {
    ref.invalidate(accountStatementTransactionsProvider);
    ref.invalidate(accountBalanceAsOfProvider);
    ref.invalidate(creditCardBillingBadgeProvider);
    ref.invalidate(defaultBillingPeriodOffsetProvider);
    ref.invalidate(creditCardPaymentPeriodRecordsProvider);
  }
  if (context.mounted) {
    showToast(context, l10n.commonSave);
  }
}
