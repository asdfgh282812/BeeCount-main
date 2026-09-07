import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/section_card.dart';

/// 信用卡繳費提醒:**全域**設定,不分卡——這裡開了哪一種通知,就套用到目前
/// 及之後新增的每一張信用卡帳戶,不需要逐卡各自設定(2026-09-07 change doc
/// 的範圍調整:原本是逐卡列表 + 點進 `AccountEditPage` 個別設定,使用者反饋
/// 這樣既麻煩、又有卡片本身沒有可設定欄位的死路,改成本頁單一設定 + 立刻
/// 套用到所有卡)。實際排程仍是逐卡各自呼叫,見
/// `credit_card_reminder_reevaluation.dart` 的
/// `reevaluateAllCreditCardReminders`。
class CreditCardReminderOverviewPage extends ConsumerStatefulWidget {
  const CreditCardReminderOverviewPage({super.key});

  @override
  ConsumerState<CreditCardReminderOverviewPage> createState() =>
      _CreditCardReminderOverviewPageState();
}

class _CreditCardReminderOverviewPageState
    extends ConsumerState<CreditCardReminderOverviewPage> {
  bool _loaded = false;
  int _accountCount = 0;

  int _reminderHour = 10;
  int _reminderMinute = 0;
  bool _advanceEnabled = false;
  int _advanceDays = 3;
  bool _billingEnabled = false;
  bool _dueEnabled = false;
  int _dueMaxDays = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final repo = ref.read(repositoryProvider);
    final accounts = await repo.getCreditCardAccounts();
    if (!mounted) return;
    setState(() {
      _accountCount = accounts.length;
      _reminderHour = prefs.getInt('cc_reminder_hour') ?? 10;
      _reminderMinute = prefs.getInt('cc_reminder_minute') ?? 0;
      _advanceEnabled = prefs.getBool('cc_reminder_enabled') ?? false;
      _advanceDays = prefs.getInt('cc_reminder_days') ?? 3;
      _billingEnabled = prefs.getBool('cc_billing_reminder_enabled') ?? false;
      _dueEnabled = prefs.getBool('cc_due_reminder_enabled') ?? false;
      _dueMaxDays = prefs.getInt('cc_due_reminder_maxdays') ?? 3;
      _loaded = true;
    });
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminderHour, minute: _reminderMinute),
    );
    if (picked != null && mounted) {
      setState(() {
        _reminderHour = picked.hour;
        _reminderMinute = picked.minute;
      });
      await _save();
    }
  }

  /// 存 SharedPreferences 後立刻重新評估所有信用卡帳戶的排程,不用等下次
  /// App 啟動/回到前景。
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('cc_reminder_hour', _reminderHour);
    await prefs.setInt('cc_reminder_minute', _reminderMinute);
    await prefs.setBool('cc_reminder_enabled', _advanceEnabled);
    await prefs.setInt('cc_reminder_days', _advanceDays);
    await prefs.setBool('cc_billing_reminder_enabled', _billingEnabled);
    await prefs.setBool('cc_due_reminder_enabled', _dueEnabled);
    await prefs.setInt('cc_due_reminder_maxdays', _dueMaxDays);

    final repo = ref.read(repositoryProvider);
    final cloudActive =
        ref.read(beecountCloudProviderInstance).valueOrNull != null;
    await reevaluateAllCreditCardReminders(
      repo: repo,
      creditCardAccounts: await repo.getCreditCardAccounts(),
      skipIfCloudActive: cloudActive,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.creditCardReminderOverviewTitle,
            showBack: true,
          ),
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        _accountCount > 0
                            ? l10n
                                .creditCardReminderAppliesToCount(_accountCount)
                            : l10n.creditCardReminderOverviewEmpty,
                        style: TextStyle(
                          fontSize: 12,
                          color: BeeTokens.textTertiary(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SectionCard(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 提醒时间——①②③三种通知共用
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  l10n.creditCardReminderTimeTitle,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: BeeTokens.textPrimary(context),
                                  ),
                                ),
                                trailing: Text(
                                  '${_reminderHour.toString().padLeft(2, '0')}:'
                                  '${_reminderMinute.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: primaryColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onTap: _pickReminderTime,
                              ),
                              Divider(color: BeeTokens.divider(context)),
                              // ①提前提醒
                              SwitchListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  l10n.creditCardReminderTitle,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: BeeTokens.textPrimary(context),
                                  ),
                                ),
                                subtitle: Text(
                                  l10n.creditCardReminderDesc,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: BeeTokens.textTertiary(context),
                                  ),
                                ),
                                value: _advanceEnabled,
                                activeColor: primaryColor,
                                onChanged: (value) {
                                  setState(() => _advanceEnabled = value);
                                  _save();
                                },
                              ),
                              if (_advanceEnabled) ...[
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  children: [1, 3, 5, 7].map((days) {
                                    final isSelected = _advanceDays == days;
                                    return ChoiceChip(
                                      label: Text(l10n
                                          .creditCardReminderDaysBefore(days)),
                                      selected: isSelected,
                                      selectedColor:
                                          primaryColor.withValues(alpha: 0.15),
                                      labelStyle: TextStyle(
                                        fontSize: 12,
                                        color: isSelected
                                            ? primaryColor
                                            : BeeTokens.textSecondary(context),
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                      onSelected: (_) {
                                        setState(() => _advanceDays = days);
                                        _save();
                                      },
                                    );
                                  }).toList(),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Divider(color: BeeTokens.divider(context)),
                              // ②帳單結算提醒
                              SwitchListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  l10n.creditCardBillingReminderTitle,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: BeeTokens.textPrimary(context),
                                  ),
                                ),
                                subtitle: Text(
                                  l10n.creditCardBillingReminderDesc,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: BeeTokens.textTertiary(context),
                                  ),
                                ),
                                value: _billingEnabled,
                                activeColor: primaryColor,
                                onChanged: (value) {
                                  setState(() => _billingEnabled = value);
                                  _save();
                                },
                              ),
                              const SizedBox(height: 4),
                              Divider(color: BeeTokens.divider(context)),
                              // ③到期連續提醒
                              SwitchListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  l10n.creditCardDueReminderTitle,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: BeeTokens.textPrimary(context),
                                  ),
                                ),
                                subtitle: Text(
                                  l10n.creditCardDueReminderDesc,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: BeeTokens.textTertiary(context),
                                  ),
                                ),
                                value: _dueEnabled,
                                activeColor: primaryColor,
                                onChanged: (value) {
                                  setState(() => _dueEnabled = value);
                                  _save();
                                },
                              ),
                              if (_dueEnabled) ...[
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  children: [3, 5, 7, 10].map((days) {
                                    final isSelected = _dueMaxDays == days;
                                    return ChoiceChip(
                                      label: Text(l10n
                                          .creditCardDueReminderMaxDays(days)),
                                      selected: isSelected,
                                      selectedColor:
                                          primaryColor.withValues(alpha: 0.15),
                                      labelStyle: TextStyle(
                                        fontSize: 12,
                                        color: isSelected
                                            ? primaryColor
                                            : BeeTokens.textSecondary(context),
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                      onSelected: (_) {
                                        setState(() => _dueMaxDays = days);
                                        _save();
                                      },
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],
                          ),
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
