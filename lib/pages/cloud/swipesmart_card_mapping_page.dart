import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cloud/sync/sync_providers.dart' as cloud_sync;
import '../../data/db.dart' show Account;
import '../../l10n/app_localizations.dart';
import '../../providers/database_providers.dart';
import '../../providers/sync_providers.dart';
import '../../styles/tokens.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';

/// SwipeSmart 卡片對照頁(design doc 2026-08-30 §3.3)。
///
/// 打開這頁會呼叫 `GET /profile/swipesmart/cards`,server 端會順便重跑一次
/// 自動比對(§3.2)——因此本頁在拿到卡片目錄後必須主動觸發一次 pull,才能
/// 顯示比對後的最新狀態,不能只憑本地既有資料渲染。
class SwipeSmartCardMappingPage extends ConsumerStatefulWidget {
  const SwipeSmartCardMappingPage({super.key});

  @override
  ConsumerState<SwipeSmartCardMappingPage> createState() =>
      _SwipeSmartCardMappingPageState();
}

class _SwipeSmartCardMappingPageState
    extends ConsumerState<SwipeSmartCardMappingPage> {
  bool _loading = true;
  String? _loadError;
  List<Account> _creditCardAccounts = [];
  List<({String cardId, String label})> _cardOptions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final cloud = await ref.read(beecountCloudProviderInstance.future);
      if (cloud == null) {
        setState(() => _loading = false);
        return;
      }

      // 打開這頁就查一次目錄 → server 端順便跑自動比對。
      final cards = await cloud.getSwipeSmartCards();

      // 自動比對的結果是 server 端寫入的 SyncChange,裝置 id 不是本機——
      // 必須主動觸發一次 pull 才能看到最新狀態,不能假設 WebSocket 一定會
      // 即時推播到(design doc §3.2)。
      final engine = ref.read(cloud_sync.syncEngineProvider(cloud));
      final ledgerId = ref.read(currentLedgerIdProvider);
      await engine.pull('$ledgerId');

      final repo = ref.read(repositoryProvider);
      final allAccounts = await repo.getAllAccounts();
      final creditCardAccounts =
          allAccounts.where((a) => a.type == 'credit_card').toList();

      if (!mounted) return;
      setState(() {
        _creditCardAccounts = creditCardAccounts;
        _cardOptions = cards
            .map((c) => (cardId: c.cardId, label: '${c.bankName} ${c.cardName}'))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _onCardSelected(Account account, String? cardId) async {
    final repo = ref.read(repositoryProvider);
    if (cardId == null) {
      await repo.updateAccount(account.id, clearSwipesmartCardId: true);
    } else {
      await repo.updateAccount(account.id, swipesmartCardId: cardId);
    }
    if (!mounted) return;
    showToast(context, AppLocalizations.of(context).commonSaved);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.swipesmartMappingTitle,
            subtitle: l10n.swipesmartMappingSubtitle,
            showBack: true,
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? Center(child: Text(l10n.swipesmartMappingNoCards))
                    : _creditCardAccounts.isEmpty
                        ? Center(child: Text(l10n.swipesmartMappingNoAccounts))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _creditCardAccounts.length,
                            itemBuilder: (context, index) {
                              final account = _creditCardAccounts[index];
                              return SectionCard(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              account.name,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              account.bankName ??
                                                  account.note ??
                                                  '',
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: BeeTokens.textSecondary(
                                                    context),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      SizedBox(
                                        width: 140,
                                        child: DropdownButton<String?>(
                                          value: account.swipesmartCardId,
                                          isExpanded: true,
                                          hint: Text(
                                            l10n.swipesmartMappingUnmapped,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          items: [
                                            DropdownMenuItem<String?>(
                                              value: null,
                                              child: Text(
                                                l10n.swipesmartMappingUnmapped,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                            ..._cardOptions.map(
                                              (o) => DropdownMenuItem<String?>(
                                                value: o.cardId,
                                                child: Text(o.label,
                                                    overflow:
                                                        TextOverflow.ellipsis),
                                              ),
                                            ),
                                          ],
                                          onChanged: (cardId) =>
                                              _onCardSelected(account, cardId),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
