import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/pending_account_providers.dart';
import '../../services/billing/post_processor.dart';
import '../../styles/tokens.dart';
import '../../widgets/biz/account_card_picker.dart';
import '../../widgets/ui/ui.dart';

class PendingAccountTransactionsPage extends ConsumerWidget {
  const PendingAccountTransactionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final pendingAsync =
        ref.watch(pendingAccountTransactionsProvider(ledgerId));

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(title: l10n.pendingAccountPageTitle, showBack: true),
          Expanded(
            child: pendingAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text(e.toString())),
              data: (txs) {
                if (txs.isEmpty) {
                  return Center(
                    child: Text(
                      l10n.pendingAccountEmptyMessage,
                      style: TextStyle(color: BeeTokens.textSecondary(context)),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: txs.length,
                  itemBuilder: (context, index) {
                    final tx = txs[index];
                    return ListTile(
                      title: Text(tx.note ?? tx.merchant ?? tx.type),
                      subtitle: Text(
                          '${tx.happenedAt.year}-${tx.happenedAt.month.toString().padLeft(2, '0')}-${tx.happenedAt.day.toString().padLeft(2, '0')}  ${tx.amount}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _assignAccount(context, ref, tx, ledgerId),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _assignAccount(
      BuildContext context, WidgetRef ref, Transaction tx, int ledgerId) async {
    // 這筆交易的 currencyCode 已經定案(AI 記帳時決定,補選帳戶不會重算幣別
    // /金額換算,見 BillCreationService.createFromBill),所以候選帳戶要按
    // 「這筆交易的幣種」篩,而不是帳本本位幣——否則日圓記錄的待確認交易,補選
    // 帳戶時反而看不到日圓帳戶(同 AI 對話/照片/語音那三個 picker 曾經的 bug)。
    final result = await AccountCardPicker.show(context,
        ledgerId: ledgerId, filterCurrency: tx.currencyCode);
    if (result?.accountId == null || !context.mounted) return;
    final repo = ref.read(repositoryProvider);
    await repo.setTransactionAccountAssignment(
        id: tx.id, accountId: result!.accountId!);
    ref.read(pendingAccountRefreshProvider.notifier).state++;
    unawaited(PostProcessor.sync(ref, ledgerId: ledgerId));
    if (context.mounted) {
      showToast(context, AppLocalizations.of(context).pendingAccountAssignSuccess);
    }
  }
}
