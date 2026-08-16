import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../styles/tokens.dart';
import '../settings/reminder_settings_page.dart';
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
