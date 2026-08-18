import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart' as db;
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../utils/reconciliation.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../utils/card_reward_period.dart';
import '../../widgets/biz/amount_text.dart';
import '../../widgets/biz/info_tag.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/biz/transaction_detail_card.dart';
import '../../widgets/ui/ui.dart';
import '../transaction/transaction_editor_page.dart';

/// 對帳模式(§2.10 MOZE_FEATURE_GAP_SD.md,對齊
/// doc.moze.app/reconciliation/statement-mode):信用卡帳戶詳情頁「交易明細」
/// tab 點入的獨立頁面,顯示「這期帳單」的交易清單,逐筆勾選確認/延後入帳。
///
/// 2026-08-18 改版:原本是掛在帳戶詳情頁裡的收合式 `ExpansionTile`,自己維護
/// 一份獨立的週期偏移([_AccountReconciliationSectionState]._cycleOffset,
/// 舊版),預設值跟頁面最上方帳單彙總卡片不同,兩處週期常常對不上。現在拆成
/// 獨立頁面,週期(`cycleOffset`)由呼叫端(`account_detail_page.dart`)的帳單
/// 彙總卡片目前選取的週期決定,這裡不再有自己的上一期/下一期切換——要換週期
/// 回上一頁在帳單彙總卡片切換,再重新點進來。
class AccountReconciliationPage extends ConsumerStatefulWidget {
  final db.Account account;
  final List<db.Account> children;
  final String currencyCode;

  /// 跟 `account_detail_page.dart` 帳單彙總卡片同一套 [billingCyclePeriod]
  /// offset 語意(offset=0 涵蓋今天的本期)——由呼叫端傳入,這裡固定不變。
  final int cycleOffset;

  const AccountReconciliationPage({
    super.key,
    required this.account,
    required this.children,
    required this.currencyCode,
    required this.cycleOffset,
  });

  @override
  ConsumerState<AccountReconciliationPage> createState() =>
      _AccountReconciliationPageState();
}

class _AccountReconciliationPageState
    extends ConsumerState<AccountReconciliationPage> {
  bool _sortDesc = false;

  String get _extraIdsKey => widget.children.map((c) => c.id).join(',');

  // 帳戶詳情頁的帳單彙總卡片/交易列表現在也直接讀同一個
  // `accountStatementTransactionsProvider`(2026-08-18 改版,不再自己維護一份
  // 較寬鬆的查詢),失效這一個 provider 就會讓那幾處一起重算,不需要另外
  // 通知。
  void _invalidate() {
    ref.invalidate(accountStatementTransactionsProvider);
  }

  String _formatYmd(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  /// 這筆交易算在哪張卡底下:expense/income 看 accountId,transfer 看
  /// toAccountId(轉入才算這張卡的帳,對齊 [ReconciliationCycleParams] 查詢
  /// 口徑跟 `getAccountStatementTransactions` 的 belongs 邏輯)。
  int _groupAccountId(db.Transaction tx) =>
      (tx.type == 'transfer' ? tx.toAccountId : tx.accountId) ??
      widget.account.id;

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final l10n = AppLocalizations.of(context);
    final useCompact = ref.watch(compactAmountProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final categories = categoriesAsync.asData?.value ?? const <db.Category>[];

    final cycle = billingCyclePeriod(account.billingDay, widget.cycleOffset);
    final txAsync = ref.watch(accountStatementTransactionsProvider((
      accountId: account.id,
      extraIdsKey: _extraIdsKey,
      billingDay: account.billingDay,
      cycleOffset: widget.cycleOffset,
    )));

    final txs = List<db.Transaction>.from(txAsync.valueOrNull ?? const []);
    txs.sort((a, b) => _sortDesc
        ? b.happenedAt.compareTo(a.happenedAt)
        : a.happenedAt.compareTo(b.happenedAt));

    var statementCount = 0;
    var newSpend = 0.0;
    var confirmedCount = 0;
    var confirmedTotal = 0.0;
    for (final tx in txs) {
      statementCount++;
      final signed = signedStatementAmount(tx);
      if (tx.type != 'transfer') newSpend += signed;
      if (tx.reconciledAt != null) {
        confirmedCount++;
        confirmedTotal += signed;
      }
    }

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.reconciliationSectionTitle,
            // cycle.start 是查詢用的 inclusive-both 邊界(上次結帳日隔天),
            // 顯示文字要換算回結帳日本身,對齊帳戶詳情頁帳單彙總卡片的
            // label 格式(見 card_reward_period.dart::billingCyclePeriod
            // 文件註解)。
            subtitle:
                '${_formatYmd(cycle.start.subtract(const Duration(days: 1)))} – ${_formatYmd(cycle.end)}',
            showBack: true,
            compact: true,
            actions: [
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert,
                    color: BeeTokens.iconPrimary(context), size: 20),
                onSelected: (value) =>
                    _onMenuSelected(context, value, txs, cycle),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'add',
                    child: Text(l10n.reconciliationMenuAddMissing),
                  ),
                  PopupMenuItem(
                    value: 'sort',
                    child: Text(_sortDesc
                        ? l10n.reconciliationMenuSortOldest
                        : l10n.reconciliationMenuSortNewest),
                  ),
                  PopupMenuItem(
                    value: 'clear',
                    enabled: confirmedCount > 0,
                    child: Text(l10n.reconciliationMenuClearAll),
                  ),
                ],
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(12.0.scaled(context, ref)),
              children: [
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _statRow(context, l10n.reconciliationStatCount,
                          '$statementCount'),
                      _statAmountRow(context, l10n.reconciliationStatNewSpend,
                          newSpend, useCompact),
                      _statRow(context, l10n.reconciliationStatConfirmedCount,
                          '$confirmedCount'),
                      _statAmountRow(
                          context,
                          l10n.reconciliationStatConfirmedAmount,
                          confirmedTotal,
                          useCompact),
                    ],
                  ),
                ),
                SizedBox(height: 12.0.scaled(context, ref)),
                if (txAsync.isLoading && txs.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(
                        vertical: 32.0.scaled(context, ref)),
                    child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (txs.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(
                        vertical: 32.0.scaled(context, ref)),
                    child: Center(
                      child: Text(
                        l10n.reconciliationEmptyState,
                        style: TextStyle(
                          fontSize: 13,
                          color: BeeTokens.textTertiary(context),
                        ),
                      ),
                    ),
                  )
                else
                  SectionCard(
                    margin: EdgeInsets.zero,
                    padding: EdgeInsets.symmetric(
                        horizontal: 12.0.scaled(context, ref)),
                    child: Column(
                      children: _buildRowsOrGroups(
                          context, txs, categories, useCompact),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 信用卡群組(合併帳單,`widget.children` 非空)依子卡分組展示,每組上方
  /// 一行子卡名稱 + 這期筆數/小計(比照 web 端 `AccountReconciliationSection.tsx`
  /// 的分組樣式);單卡帳戶(沒有子帳戶)維持原本平鋪清單,不多一層分組標頭。
  List<Widget> _buildRowsOrGroups(
    BuildContext context,
    List<db.Transaction> txs,
    List<db.Category> categories,
    bool useCompact,
  ) {
    if (widget.children.isEmpty) {
      return [
        for (var i = 0; i < txs.length; i++) ...[
          if (i > 0) Divider(height: 1, color: BeeTokens.divider(context)),
          _buildStatementRow(context, txs[i], categories, useCompact),
        ],
      ];
    }

    final groupOrder = [widget.account, ...widget.children];
    final byGroup = <int, List<db.Transaction>>{
      for (final a in groupOrder) a.id: [],
    };
    // 理論上 _groupAccountId 只會回傳 groupOrder 裡的 id(belongs 篩選已保證
    // 這點),找不到對應分組時保底歸給主帳戶,不讓交易憑空消失。
    for (final tx in txs) {
      final gid = _groupAccountId(tx);
      (byGroup[gid] ?? byGroup[widget.account.id]!).add(tx);
    }

    final widgets = <Widget>[];
    var isFirstGroup = true;
    for (final acc in groupOrder) {
      final groupTxs = byGroup[acc.id] ?? const <db.Transaction>[];
      if (groupTxs.isEmpty) continue;
      if (!isFirstGroup) {
        widgets.add(Divider(height: 1, color: BeeTokens.divider(context)));
      }
      widgets.add(_buildGroupHeader(context, acc, groupTxs, useCompact));
      for (var i = 0; i < groupTxs.length; i++) {
        widgets.add(Divider(height: 1, color: BeeTokens.divider(context)));
        widgets.add(
            _buildStatementRow(context, groupTxs[i], categories, useCompact));
      }
      isFirstGroup = false;
    }
    return widgets;
  }

  Widget _buildGroupHeader(
    BuildContext context,
    db.Account acc,
    List<db.Transaction> groupTxs,
    bool useCompact,
  ) {
    final subtotal = groupTxs.fold<double>(0, (s, t) => s + t.amount);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.0.scaled(context, ref)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              acc.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: BeeTokens.textPrimary(context),
              ),
            ),
          ),
          Text('${groupTxs.length} · ',
              style: TextStyle(
                  fontSize: 12, color: BeeTokens.textTertiary(context))),
          AmountText(
            value: subtotal,
            signed: false,
            showCurrency: false,
            useCompactFormat: useCompact,
            currencyCode: widget.currencyCode,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: BeeTokens.textTertiary(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatementRow(
    BuildContext context,
    db.Transaction tx,
    List<db.Category> categories,
    bool useCompact,
  ) {
    return _StatementRow(
      tx: tx,
      category: tx.categoryId == null
          ? null
          : categories
              .cast<db.Category?>()
              .firstWhere((c) => c?.id == tx.categoryId, orElse: () => null),
      currencyCode: widget.currencyCode,
      useCompact: useCompact,
      cycleOffset: widget.cycleOffset,
      billingDay: widget.account.billingDay,
      onToggleConfirm: () async {
        await ref.read(repositoryProvider).setTransactionReconciled(
              id: tx.id,
              reconciled: tx.reconciledAt == null,
            );
        _invalidate();
      },
      onDefer: (date) async {
        await ref.read(repositoryProvider).setTransactionDeferredPosting(
              id: tx.id,
              deferredPostingAt: date,
            );
        _invalidate();
      },
      onEdit: () async {
        await showTransactionDetailCard(
            context,
            ref,
            tx,
            categories
                .cast<db.Category?>()
                .firstWhere((c) => c?.id == tx.categoryId, orElse: () => null));
        if (!context.mounted) return;
        _invalidate();
      },
    );
  }

  Widget _statRow(BuildContext context, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.0.scaled(context, ref)),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: BeeTokens.textSecondary(context))),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: BeeTokens.textPrimary(context))),
        ],
      ),
    );
  }

  Widget _statAmountRow(
      BuildContext context, String label, double value, bool useCompact) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.0.scaled(context, ref)),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: BeeTokens.textSecondary(context))),
          const Spacer(),
          AmountText(
            value: value,
            signed: true,
            showCurrency: false,
            useCompactFormat: useCompact,
            currencyCode: widget.currencyCode,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: BeeTokens.textPrimary(context)),
          ),
        ],
      ),
    );
  }

  Future<void> _onMenuSelected(
    BuildContext context,
    String value,
    List<db.Transaction> txs,
    ({DateTime start, DateTime end}) cycle,
  ) async {
    final l10n = AppLocalizations.of(context);
    switch (value) {
      case 'add':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TransactionEditorPage(
              initialKind: 'expense',
              initialAccountId: widget.account.id,
              initialDate: cycle.start,
            ),
          ),
        );
        if (!context.mounted) return;
        _invalidate();
        break;
      case 'sort':
        setState(() => _sortDesc = !_sortDesc);
        break;
      case 'clear':
        final confirmedIds =
            txs.where((t) => t.reconciledAt != null).map((t) => t.id).toList();
        if (confirmedIds.isEmpty) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.reconciliationClearAllConfirmTitle),
            content: Text(l10n.reconciliationClearAllConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.commonConfirm),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await ref
            .read(repositoryProvider)
            .clearReconciliationBatch(ids: confirmedIds);
        _invalidate();
        break;
    }
  }
}

/// 對帳清單單筆列:左側確認勾選按鈕、分類/備註、日期、金額、轉帳/回饋/
/// 已延後徽章、編輯/延後按鈕。
class _StatementRow extends ConsumerWidget {
  final db.Transaction tx;
  final db.Category? category;
  final String currencyCode;
  final bool useCompact;
  final int cycleOffset;
  final int? billingDay;
  final VoidCallback onToggleConfirm;
  final ValueChanged<DateTime?> onDefer;
  final VoidCallback onEdit;

  const _StatementRow({
    required this.tx,
    required this.category,
    required this.currencyCode,
    required this.useCompact,
    required this.cycleOffset,
    required this.billingDay,
    required this.onToggleConfirm,
    required this.onDefer,
    required this.onEdit,
  });

  String _formatYmd(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final reconciled = tx.reconciledAt != null;
    final isTransfer = tx.type == 'transfer';
    final isReward = isRewardCategoryName(category?.name);
    final title = isTransfer
        ? l10n.transferTitle
        : (category?.name ?? (tx.note?.isNotEmpty == true ? tx.note! : '-'));
    final signed = signedStatementAmount(tx);
    final amountColor = signed >= 0
        ? BeeTokens.expenseColor(context, ref)
        : BeeTokens.incomeColor(context, ref);

    return Container(
      padding: EdgeInsets.symmetric(vertical: 8.0.scaled(context, ref)),
      decoration: BoxDecoration(
        color: reconciled
            ? BeeTokens.incomeColor(context, ref).withValues(alpha: 0.06)
            : null,
        borderRadius: BorderRadius.circular(8.0.scaled(context, ref)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          InkWell(
            onTap: onToggleConfirm,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                reconciled ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 22,
                color: reconciled
                    ? BeeTokens.incomeColor(context, ref)
                    : BeeTokens.iconSecondary(context),
              ),
            ),
          ),
          SizedBox(width: 8.0.scaled(context, ref)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: BeeTokens.textPrimary(context),
                        ),
                      ),
                    ),
                    if (isTransfer) ...[
                      SizedBox(width: 6.0.scaled(context, ref)),
                      InfoTag(l10n.reconciliationTransferBadge),
                    ],
                    if (isReward) ...[
                      SizedBox(width: 6.0.scaled(context, ref)),
                      InfoTag(l10n.reconciliationRewardBadge),
                    ],
                    if (tx.deferredPostingAt != null) ...[
                      SizedBox(width: 6.0.scaled(context, ref)),
                      InfoTag(l10n.reconciliationDeferredBadge),
                    ],
                  ],
                ),
                SizedBox(height: 2.0.scaled(context, ref)),
                Text(
                  _formatYmd(tx.happenedAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: BeeTokens.textTertiary(context),
                  ),
                ),
              ],
            ),
          ),
          AmountText(
            value: signed,
            signed: true,
            showCurrency: false,
            useCompactFormat: useCompact,
            currencyCode: currencyCode,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: amountColor),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.edit_outlined,
                size: 18, color: BeeTokens.iconSecondary(context)),
            onPressed: onEdit,
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding:
                  EdgeInsets.symmetric(horizontal: 6.0.scaled(context, ref)),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            // 已延後的交易再點一次直接取消(清空 deferredPostingAt),不用二次
            // 選日期——跟左側確認勾選按鈕「再點一次取消」同一種低摩擦互動,
            // 也是使用者能從對帳清單本身檢視/清除這個欄位的唯一入口(比照
            // PH5 測試計畫「兩個入口寫同一個欄位,行為應該一致」的要求,這裡
            // 用單一入口涵蓋設定/檢視/清除三種操作,不用額外去一般記帳表單)。
            onPressed: tx.deferredPostingAt != null
                ? () => onDefer(null)
                : () async {
                    final defaultDate =
                        defaultDeferredPostingDate(billingDay, cycleOffset);
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: defaultDate,
                      firstDate: DateTime(2000),
                      lastDate:
                          DateTime.now().add(const Duration(days: 365 * 3)),
                    );
                    // 延後入帳是「純日期」欄位:showDatePicker 回傳的
                    // DateTime 帶的是機器本地時區 flavor 的年月日,直接
                    // `.toUtc()` 序列化會依裝置時區把日期往前/後推一天
                    // (UTC+8 裝置在 App 選 8/5,序列化後變成 UTC 8/4)。
                    // 這裡改成用選到的年月日重新構造成 UTC 午夜,跟 web 版
                    // dateInputToIso(`${value}T00:00:00+00:00`)同一個表示法。
                    if (picked != null) {
                      onDefer(
                          DateTime.utc(picked.year, picked.month, picked.day));
                    }
                  },
            child: Text(tx.deferredPostingAt != null
                ? l10n.reconciliationUndeferButton
                : l10n.reconciliationDeferButton),
          ),
        ],
      ),
    );
  }
}
