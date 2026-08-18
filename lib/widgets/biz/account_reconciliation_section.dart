import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart' as db;
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../pages/account/account_reconciliation_page.dart';
import 'section_card.dart';

/// 對帳模式(§2.10 MOZE_FEATURE_GAP_SD.md,對齊
/// doc.moze.app/reconciliation/statement-mode)的入口列:信用卡帳戶詳情頁
/// 「交易明細」tab 專用,顯示「這期帳單」已確認/總筆數的小標籤,點擊開
/// [AccountReconciliationPage] 看逐筆勾選確認/延後入帳的完整清單。只在信用卡
/// (或信用卡合併帳單群組)且已設定 billingDay/paymentDueDay 時由呼叫端掛載
/// ——這裡也做一次同樣的防呆判斷,避免被誤用在不支援的帳戶上。
///
/// 2026-08-18 改版:原本是收合式 `ExpansionTile`,自己維護一份獨立的
/// `_cycleOffset` 狀態(預設「最近一次已結束的週期」),跟頁面最上方帳單彙總
/// 卡片的週期(預設「涵蓋今天的本期」)常常對不上,兩張卡看到的數字不一致。
/// 現在拆成「入口列(這裡)+ 獨立頁面([AccountReconciliationPage])」:不再有
/// 自己的週期狀態,[cycleOffset] 一律由呼叫端(`account_detail_page.dart`)
/// 傳入目前帳單彙總卡片選取的週期,單一資料來源,使用者切換帳單彙總卡片的
/// 週期時這裡的已確認/總筆數徽章會跟著即時重算。
class AccountReconciliationSection extends ConsumerWidget {
  final db.Account account;
  final List<db.Account> children;
  final String currencyCode;

  /// 跟 `account_detail_page.dart` 帳單彙總卡片同一套 `billingCyclePeriod`
  /// offset 語意——由呼叫端傳入,不在這裡另外維護。
  final int cycleOffset;

  const AccountReconciliationSection({
    super.key,
    required this.account,
    required this.children,
    required this.currencyCode,
    required this.cycleOffset,
  });

  String get _extraIdsKey => children.map((c) => c.id).join(',');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (account.billingDay == null || account.paymentDueDay == null) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);
    final txAsync = ref.watch(accountStatementTransactionsProvider((
      accountId: account.id,
      extraIdsKey: _extraIdsKey,
      billingDay: account.billingDay,
      cycleOffset: cycleOffset,
    )));
    final txs = txAsync.valueOrNull ?? const <db.Transaction>[];
    final statementCount = txs.length;
    final confirmedCount = txs.where((t) => t.reconciledAt != null).length;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.0.scaled(context, ref)),
      child: SectionCard(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12.0.scaled(context, ref)),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AccountReconciliationPage(
                  account: account,
                  children: children,
                  currencyCode: currencyCode,
                  cycleOffset: cycleOffset,
                ),
              ),
            );
            if (!context.mounted) return;
            // 從對帳頁回來後,使用者可能確認/延後入帳了幾筆交易——這裡的入口
            // 徽章、`account_detail_page.dart` 的帳單彙總卡片跟交易列表都
            // 讀同一個 family provider,傳裸 provider(不帶參數)給
            // `invalidate` 會讓所有現存實例一起失效重算,不需要逐一通知。
            ref.invalidate(accountStatementTransactionsProvider);
          },
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 12.0.scaled(context, ref),
              vertical: 12.0.scaled(context, ref),
            ),
            child: Row(
              children: [
                Text(
                  l10n.reconciliationSectionTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
                SizedBox(width: 8.0.scaled(context, ref)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8.0.scaled(context, ref),
                    vertical: 2.0.scaled(context, ref),
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(10.0.scaled(context, ref)),
                  ),
                  child: Text(
                    '$confirmedCount/$statementCount',
                    style: TextStyle(
                      fontSize: 11,
                      color: primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(Icons.chevron_right,
                    size: 20, color: BeeTokens.iconSecondary(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
