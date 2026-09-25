import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../ui/ui.dart';

/// v30 補折算橫幅(01 §六):currencyCode≠本位幣 且 nativeAmount==amount 的
/// 存量外幣交易 >0 時出現;確認後按當前有效匯率重算(逐筆記 change,L13)。
/// 從舊洞察頁(analytics_page.dart)原樣搬出,統計報表頁頂端使用。
class ForeignCurrencyRecalcBanner extends ConsumerWidget {
  const ForeignCurrencyRecalcBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count =
        ref.watch(ledgerUnconvertedForeignTxCountProvider).valueOrNull ?? 0;
    if (count <= 0) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Material(
        color: BeeTokens.surface(context),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.currency_exchange,
                  size: 16, color: ref.watch(primaryColorProvider)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.recalcForeignTxBanner,
                  style: BeeTextTokens.label(context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => _run(context, ref, count),
                child: Text(l10n.recalcForeignTxAction,
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref, int count) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(l10n.recalcForeignTxAction),
        content: Text(l10n.recalcSyncCountHint(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(AppLocalizations.of(dctx).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(AppLocalizations.of(dctx).commonConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final repo = ref.read(repositoryProvider);
    final ledgerId = ref.read(currentLedgerIdProvider);
    // 补折算前先确保本位币汇率组是新鲜的;extraQuotes 带上账本交易实际涉及的
    // 外币(无对应账户的币种不在 usedCurrencies 里,不带就永远补不上)。
    final foreign = await repo.getLedgerForeignCurrencies(ledgerId);
    await refreshExchangeRatesFromUi(ref, force: true, extraQuotes: foreign);
    final n = await repo.recomputeForeignTxForLedger(ledgerId);
    if (!context.mounted) return;
    showToast(context, l10n.recalcForeignTxDone(n));
    ref.read(statsRefreshProvider.notifier).state++;
  }
}

/// 折算腳注:帳本存在外幣交易(含已折算)時,提示統計數字已折本位幣。
class ConvertedStatsFootnote extends ConsumerWidget {
  const ConvertedStatsFootnote({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(ledgerForeignTxCountProvider).valueOrNull ?? 0;
    if (count <= 0) return const SizedBox.shrink();
    final base = ref.watch(currentLedgerCurrencyProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          AppLocalizations.of(context).statsConvertedFootnote(base),
          style:
              TextStyle(fontSize: 11, color: BeeTokens.textTertiary(context)),
        ),
      ),
    );
  }
}
