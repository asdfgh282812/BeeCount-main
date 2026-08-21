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
    final result = await AccountCardPicker.show(context, ledgerId: ledgerId);
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
