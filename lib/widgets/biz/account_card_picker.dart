import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/repositories/local/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../utils/account_type_utils.dart';
import '../../utils/lru_cache.dart';
import '../../utils/shared_ledger_picker_filter.dart';
import 'amount_text.dart';

/// 新增交易頁的「卡片選擇」介面——比照資產頁(`accounts_page.dart`)的分組
/// 清單視覺(圓形頭像 + 類型色、名稱、副標、金額),取代原本的橫滑
/// chips(`AccountSelector`)。`accounts_page.dart` 的實際渲染 class
/// (`_AccountCard`/`_AccountTypeGroup`)是私有的,這裡是仿照其視覺重新做的
/// 獨立元件,不是同一份程式碼(這樣才不會動到資產頁本身)。
///
/// 點一行直接選定並關閉(bottom sheet 慣用互動),不需要額外確認鍵。
///
/// [show] 回傳 `AccountPickResult?`——`null` 代表使用者取消/滑動關閉(呼叫端
/// 維持原本選擇不變),`AccountPickResult(<id>)` 代表選了一個真實帳戶。這個
/// picker 不再提供「不選擇帳戶」選項(交易必須有帳戶)。
class AccountPickResult {
  final int? accountId;
  const AccountPickResult(this.accountId);
}

class AccountCardPicker {
  static Future<AccountPickResult?> show(
    BuildContext context, {
    required int ledgerId,
    int? selectedAccountId,
    String? filterCurrency,
    int? pinnedAccountId,
    // 转账页排除对侧已选的账户(不能转出/转入同一个账户)。
    int? excludeAccountId,
    // 一般收支記帳表單:帳戶清單不再依「目前交易幣別」過濾,列出帳本下所有
    // 幣別的帳戶(跨幣別帳戶另外走換算流程)。轉帳/債務還款/信用卡還款/定期
    // 記帳規則維持預設 false,行為不變。
    bool allowAllCurrencies = false,
  }) {
    return showModalBottomSheet<AccountPickResult?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BeeTokens.surfaceSheet(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AccountCardPickerSheet(
        ledgerId: ledgerId,
        selectedAccountId: selectedAccountId,
        filterCurrency: filterCurrency,
        pinnedAccountId: pinnedAccountId,
        excludeAccountId: excludeAccountId,
        allowAllCurrencies: allowAllCurrencies,
      ),
    );
  }
}

class _AccountCardPickerSheet extends ConsumerStatefulWidget {
  final int ledgerId;
  final int? selectedAccountId;
  final String? filterCurrency;
  final int? pinnedAccountId;
  final int? excludeAccountId;
  final bool allowAllCurrencies;

  const _AccountCardPickerSheet({
    required this.ledgerId,
    this.selectedAccountId,
    this.filterCurrency,
    this.pinnedAccountId,
    this.excludeAccountId,
    this.allowAllCurrencies = false,
  });

  @override
  ConsumerState<_AccountCardPickerSheet> createState() =>
      _AccountCardPickerSheetState();
}

class _AccountCardPickerSheetState
    extends ConsumerState<_AccountCardPickerSheet> {
  bool _loading = true;
  List<Account> _accounts = [];
  String _wantedCurrency = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(repositoryProvider);
    final ledger = await ref.read(ledgerByIdProvider(widget.ledgerId).future);
    if (ledger == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    var allAccounts = await repo.getAllAccounts();
    if (repo is LocalRepository) {
      final ctx = await repo.db.loadLedgerPickerContext(widget.ledgerId);
      allAccounts = await repo.db.filterAccountsForLedger(allAccounts, ctx);
    }

    final wanted = (widget.filterCurrency ?? ledger.currency).toUpperCase();
    var accounts = allAccounts
        .where((a) =>
            (widget.allowAllCurrencies || a.currency.toUpperCase() == wanted) &&
            isTradableType(a.type) &&
            // 主帳戶(合併帳單分組,type=='account_group')是純管理容器,不是
            // 真實可入帳的帳戶,不該出現在交易的帳戶選擇器裡——底下子帳戶各自
            // 有自己的真實 type,會照常出現在對應分組底下。
            a.type != 'account_group' &&
            a.id != widget.excludeAccountId)
        .toList();

    // 账户隐藏(#240)E1 钉住:编辑历史交易挂的账户若已被隐藏,补回候选并
    // 打灰标(跟 AccountSelector 同一套规则)。
    final pinnedId = widget.pinnedAccountId;
    if (pinnedId != null && !accounts.any((a) => a.id == pinnedId)) {
      final pinned = await repo.getAccount(pinnedId);
      if (pinned != null && pinned.hidden) {
        accounts = [...accounts, pinned];
      }
    }

    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _wantedCurrency = wanted;
      _loading = false;
    });
  }

  Map<String, List<Account>> _groupByType(List<Account> accounts) {
    final grouped = <String, List<Account>>{};
    for (final a in accounts) {
      grouped.putIfAbsent(a.type, () => []).add(a);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);
    final statsAsync = ref.watch(allAccountStatsProvider);
    final stats = statsAsync.valueOrNull;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Text(
                    l10n.accountSelectTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.commonCancel),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final entry in _groupByType(_accounts).entries)
                            _AccountTypeSection(
                              type: entry.key,
                              accounts: entry.value,
                              primaryColor: primaryColor,
                              stats: stats,
                              selectedAccountId: widget.selectedAccountId,
                              ledgerId: widget.ledgerId,
                              wantedCurrency: _wantedCurrency,
                              onSelected: (id) =>
                                  Navigator.pop(context, AccountPickResult(id)),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountTypeSection extends StatefulWidget {
  final String type;
  final List<Account> accounts;
  final Color primaryColor;
  final Map<int, ({double balance, double expense, double income})>? stats;
  final int? selectedAccountId;
  final int ledgerId;
  final String wantedCurrency;
  final ValueChanged<int> onSelected;

  const _AccountTypeSection({
    required this.type,
    required this.accounts,
    required this.primaryColor,
    required this.stats,
    required this.selectedAccountId,
    required this.ledgerId,
    required this.wantedCurrency,
    required this.onSelected,
  });

  @override
  State<_AccountTypeSection> createState() => _AccountTypeSectionState();
}

class _AccountTypeSectionState extends State<_AccountTypeSection> {
  List<int> _lruOrder = [];

  @override
  void initState() {
    super.initState();
    LRUCache(key: 'account_lru_${widget.ledgerId}', maxSize: 20)
        .getOrderedIds()
        .then((ids) {
      if (mounted) setState(() => _lruOrder = ids);
    });
  }

  List<Account> _sorted() {
    final list = [...widget.accounts];
    list.sort((a, b) {
      if (a.id == widget.selectedAccountId) return -1;
      if (b.id == widget.selectedAccountId) return 1;
      final ai = _lruOrder.indexOf(a.id);
      final bi = _lruOrder.indexOf(b.id);
      if (ai == -1 && bi == -1) return 0;
      if (ai == -1) return 1;
      if (bi == -1) return -1;
      return ai.compareTo(bi);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final typeColor = getColorForAccountType(widget.type, widget.primaryColor);
    final accounts = _sorted();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 4),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: AccountTypeIcon(
                        type: widget.type, size: 14, color: typeColor),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  getAccountTypeLabel(context, widget.type),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: BeeTokens.surfaceElevated(context),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: BeeTokens.cardOuterBorderColor(context)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Colors.transparent,
              child: Column(
                children: [
                  for (final entry in accounts.indexed) ...[
                    if (entry.$1 > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: BeeTokens.cardInnerDividerColor(context),
                      ),
                    _AccountRow(
                      account: entry.$2,
                      typeColor: typeColor,
                      primaryColor: widget.primaryColor,
                      balance: widget.stats?[entry.$2.id]?.balance,
                      isSelected: entry.$2.id == widget.selectedAccountId,
                      wantedCurrency: widget.wantedCurrency,
                      onTap: () => widget.onSelected(entry.$2.id),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends ConsumerWidget {
  final Account account;
  final Color typeColor;
  final Color primaryColor;
  final double? balance;
  final bool isSelected;
  final String wantedCurrency;
  final VoidCallback onTap;

  const _AccountRow({
    required this.account,
    required this.typeColor,
    required this.primaryColor,
    required this.balance,
    required this.isSelected,
    required this.wantedCurrency,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isLiability = isLiabilityType(account.type);
    final b = balance ?? 0;
    final used = b < 0 ? -b : 0.0;
    final primaryValue = isLiability ? used : b;
    final amountColor = isLiability
        ? (used > 0
            ? BeeTokens.expenseColor(context, ref)
            : BeeTokens.incomeColor(context, ref))
        : (b < 0
            ? BeeTokens.expenseColor(context, ref)
            : BeeTokens.textPrimary(context));

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: typeColor.withValues(alpha: 0.14),
                border: Border.all(color: typeColor.withValues(alpha: 0.35)),
              ),
              child: Center(
                child: AccountTypeIcon(
                    type: account.type, size: 18, color: typeColor),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: BeeTokens.textPrimary(context),
                          ),
                        ),
                      ),
                      if (account.hidden) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: BeeTokens.textTertiary(context)
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l10n.accountHiddenTag,
                            style: TextStyle(
                                fontSize: 10,
                                color: BeeTokens.textTertiary(context)),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    account.currency.toUpperCase() != wantedCurrency
                        ? '${getAccountTypeLabel(context, account.type)} · ${account.currency.toUpperCase()}'
                        : getAccountTypeLabel(context, account.type),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: BeeTokens.textTertiary(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AmountText(
              value: primaryValue,
              signed: false,
              showCurrency: false,
              currencyCode: account.currency,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: amountColor),
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check, color: primaryColor, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}
