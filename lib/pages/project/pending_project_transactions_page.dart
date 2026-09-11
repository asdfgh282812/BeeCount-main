import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/pending_project_providers.dart';
import '../../services/billing/post_processor.dart';
import '../../styles/tokens.dart';
import '../../widgets/biz/project_picker.dart';
import '../../widgets/ui/ui.dart';

/// 「待確認專案」清單頁(design 2026-09-11,完整比照
/// [PendingAccountTransactionsPage] 的既有實作模式)。
class PendingProjectTransactionsPage extends ConsumerWidget {
  const PendingProjectTransactionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final pendingAsync =
        ref.watch(pendingProjectTransactionsProvider(ledgerId));

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(title: l10n.pendingProjectPageTitle, showBack: true),
          Expanded(
            child: pendingAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text(e.toString())),
              data: (txs) {
                if (txs.isEmpty) {
                  return Center(
                    child: Text(
                      l10n.pendingProjectEmptyMessage,
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
                      onTap: () => _assignProject(context, ref, tx, ledgerId),
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

  Future<void> _assignProject(
      BuildContext context, WidgetRef ref, Transaction tx, int ledgerId) async {
    final result = await ProjectPicker.show(context, ledgerId: ledgerId);
    // result == null:使用者滑動取消,維持待確認狀態;result.project == null
    // 是明確選擇「不指定專案」,同樣算完成補選(同 ProjectPickResult 的慣例)。
    if (result == null || !context.mounted) return;
    final repo = ref.read(repositoryProvider);
    await repo.setTransactionProjectAssignment(
        id: tx.id, projectSyncId: result.project?.syncId);
    ref.read(pendingProjectRefreshProvider.notifier).state++;
    unawaited(PostProcessor.sync(ref, ledgerId: ledgerId));
    if (context.mounted) {
      showToast(
          context, AppLocalizations.of(context).pendingProjectAssignSuccess);
    }
  }
}
