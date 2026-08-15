import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/card_reward_rule_providers.dart';
import '../../styles/tokens.dart';
import 'tag_chip.dart';

/// 信用卡紅利回饋選單——記帳表單選了信用卡帳戶後,點擊回饋欄位喚起。只列出
/// 該信用卡目前「啟用中 + 在有效期間內」的規則,支援多選,回傳規則 syncId
/// 列表(不是本地 int id——見 `lib/data/db.dart` 的 [Transaction.rewardRuleIds]
/// 注释,存 syncId 是為了跨設備穩定)。
class CardRewardRuleSelector extends ConsumerStatefulWidget {
  final int accountId;
  final List<String> selectedSyncIds;

  const CardRewardRuleSelector({
    super.key,
    required this.accountId,
    this.selectedSyncIds = const [],
  });

  static Future<List<String>?> show(
    BuildContext context, {
    required int accountId,
    List<String> selectedSyncIds = const [],
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CardRewardRuleSelector(
        accountId: accountId,
        selectedSyncIds: selectedSyncIds,
      ),
    );
  }

  @override
  ConsumerState<CardRewardRuleSelector> createState() =>
      _CardRewardRuleSelectorState();
}

class _CardRewardRuleSelectorState
    extends ConsumerState<CardRewardRuleSelector> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.selectedSyncIds);
  }

  List<CardRewardRule> _eligible(List<CardRewardRule> all) {
    final now = DateTime.now();
    return all.where((r) {
      if (!r.enabled) return false;
      if (r.startsAt != null && r.startsAt!.isAfter(now)) return false;
      if (r.endsAt != null && r.endsAt!.isBefore(now)) return false;
      return r.syncId != null;
    }).toList();
  }

  String _chipLabel(CardRewardRule r) {
    final v = r.rateValue;
    final vs = v.toStringAsFixed(v == v.truncateToDouble() ? 0 : 2);
    return r.rateType == 'fixed_amount'
        ? '${r.label} ($vs)'
        : '${r.label} ($vs%)';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rulesAsync =
        ref.watch(cardRewardRulesForAccountProvider(widget.accountId));

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: BoxDecoration(
        color: BeeTokens.surfaceElevated(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: BeeTokens.divider(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                Text(
                  l10n.cardRewardRuleSelectorTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_selected.toList()),
                  child: Text(l10n.commonConfirm),
                ),
              ],
            ),
          ),
          Flexible(
            child: rulesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('$e'),
              ),
              data: (all) {
                final eligible = _eligible(all);
                if (eligible.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    child: Text(
                      l10n.cardRewardRuleSelectorEmpty,
                      style: TextStyle(color: BeeTokens.textSecondary(context)),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: eligible.map((r) {
                      final isSelected = _selected.contains(r.syncId);
                      return TagChip(
                        name: _chipLabel(r),
                        size: TagChipSize.medium,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selected.remove(r.syncId);
                            } else {
                              _selected.add(r.syncId!);
                            }
                          });
                        },
                      );
                    }).toList(),
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
