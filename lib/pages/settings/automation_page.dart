import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../styles/tokens.dart';
import '../settings/reminder_settings_page.dart';
import '../settings/credit_card_reminder_overview_page.dart';
import '../transaction/recurring_rule_list_page.dart';
import '../../l10n/app_localizations.dart';

/// 自动化功能二级页面
class AutomationPage extends ConsumerWidget {
  const AutomationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: AppLocalizations.of(context).automationPageTitle,
            subtitle: AppLocalizations.of(context).automationPageSubtitle,
            showBack: true,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      // v36:週期記帳對齐 BeeCount Cloud recurring_rule 後的新入
                      // 口,見 docs/changes/2026-08-17-recurring-transactions-cloud-sync.md。
                      AppListTile(
                        leading: Icons.repeat,
                        title: AppLocalizations.of(context)
                            .automationRecurringTile,
                        subtitle: AppLocalizations.of(context)
                            .automationRecurringTileSubtitle,
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const RecurringRuleListPage()),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    AppLocalizations.of(context)
                        .automationNotificationSectionTitle,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                ),
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      // 记账提醒
                      AppListTile(
                        leading: Icons.notifications_outlined,
                        title:
                            AppLocalizations.of(context).mineReminderSettings,
                        subtitle: AppLocalizations.of(context)
                            .mineReminderSettingsSubtitle,
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const ReminderSettingsPage()),
                          );
                        },
                      ),
                      // 信用卡繳費提醒(②帳單結算/③到期連續/①提前提醒三合一,
                      // 見 docs/superpowers/specs/2026-09-07-credit-card-notifications-badge-fix-design.md)
                      AppListTile(
                        leading: Icons.credit_card_outlined,
                        title: AppLocalizations.of(context)
                            .automationCreditCardReminderTile,
                        subtitle: AppLocalizations.of(context)
                            .automationCreditCardReminderTileSubtitle,
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    const CreditCardReminderOverviewPage()),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
