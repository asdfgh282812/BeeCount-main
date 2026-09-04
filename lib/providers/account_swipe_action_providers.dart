import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';

/// 帳戶總覽頁滑動快捷操作可選的動作。
enum AccountSwipeAction { none, adjustBalance, addTransaction, editAccount }

/// 滑動快捷操作名稱(個性化設定頁的選項清單、帳戶總覽頁滑動按鈕共用)。
String accountSwipeActionLabel(
    AppLocalizations l10n, AccountSwipeAction action) {
  switch (action) {
    case AccountSwipeAction.none:
      return l10n.accountSwipeActionNone;
    case AccountSwipeAction.adjustBalance:
      return l10n.balanceAdjustmentAction;
    case AccountSwipeAction.addTransaction:
      return l10n.accountSwipeActionAddTransaction;
    case AccountSwipeAction.editAccount:
      return l10n.commonEdit;
  }
}

/// 帳戶總覽頁滑動快捷操作設定：左滑/右滑各自露出哪個動作。
class AccountSwipeSettings {
  final AccountSwipeAction leftAction; // 向左滑露出的动作
  final AccountSwipeAction rightAction; // 向右滑露出的动作

  const AccountSwipeSettings({
    required this.leftAction,
    required this.rightAction,
  });

  factory AccountSwipeSettings.defaultSettings() => const AccountSwipeSettings(
        leftAction: AccountSwipeAction.addTransaction,
        rightAction: AccountSwipeAction.adjustBalance,
      );

  AccountSwipeSettings copyWith({
    AccountSwipeAction? leftAction,
    AccountSwipeAction? rightAction,
  }) {
    return AccountSwipeSettings(
      leftAction: leftAction ?? this.leftAction,
      rightAction: rightAction ?? this.rightAction,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountSwipeSettings &&
          runtimeType == other.runtimeType &&
          leftAction == other.leftAction &&
          rightAction == other.rightAction;

  @override
  int get hashCode => leftAction.hashCode ^ rightAction.hashCode;
}

/// 帳戶總覽頁滑動快捷操作設定的 StateNotifier。刻意不做雲端同步——这是纯
/// 本机 UI 手势偏好，跟 compactAmountProvider 那种外观设定不同，不透过
/// sync_engine_profile.dart 的外观/主题同步管线，跨装置不共用。
class AccountSwipeSettingsNotifier extends StateNotifier<AccountSwipeSettings> {
  AccountSwipeSettingsNotifier()
      : super(AccountSwipeSettings.defaultSettings()) {
    _loadSettings();
  }

  static const String _keyLeftAction = 'account_swipe_left_action';
  static const String _keyRightAction = 'account_swipe_right_action';

  AccountSwipeAction _parseAction(String? name, AccountSwipeAction fallback) {
    if (name == null) return fallback;
    return AccountSwipeAction.values
        .firstWhere((a) => a.name == name, orElse: () => fallback);
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final defaults = AccountSwipeSettings.defaultSettings();
      state = AccountSwipeSettings(
        leftAction:
            _parseAction(prefs.getString(_keyLeftAction), defaults.leftAction),
        rightAction: _parseAction(
            prefs.getString(_keyRightAction), defaults.rightAction),
      );
    } catch (e) {
      // 保持默认设置
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLeftAction, state.leftAction.name);
      await prefs.setString(_keyRightAction, state.rightAction.name);
    } catch (e) {
      // 忽略保存错误
    }
  }

  Future<void> updateLeftAction(AccountSwipeAction action) async {
    state = state.copyWith(leftAction: action);
    await _saveSettings();
  }

  Future<void> updateRightAction(AccountSwipeAction action) async {
    state = state.copyWith(rightAction: action);
    await _saveSettings();
  }
}

final accountSwipeSettingsProvider =
    StateNotifierProvider<AccountSwipeSettingsNotifier, AccountSwipeSettings>(
        (ref) {
  return AccountSwipeSettingsNotifier();
});
