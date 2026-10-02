import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import 'theme_providers.dart' show pushAppearanceToCloud;

/// 帳戶總覽頁滑動快捷操作可選的動作。
enum AccountSwipeAction {
  none,
  adjustBalance,
  addTransaction,
  editAccount,
  // 投資理財(股票)帳戶專用:餘額是持股成本的帳面數,不能手動調整,滑動
  // 快捷改成買進/賣出/新增定期定額,直接開股票交易頁。
  stockBuy,
  stockSell,
  stockDca,
}

/// 一般帳戶滑動快捷操作可選的動作(股票專用動作不出現在這裡)。
const List<AccountSwipeAction> generalSwipeActionChoices = [
  AccountSwipeAction.none,
  AccountSwipeAction.adjustBalance,
  AccountSwipeAction.addTransaction,
  AccountSwipeAction.editAccount,
];

/// 投資理財帳戶滑動快捷操作可選的動作(沒有「調整餘額」/一般「新增交易」)。
const List<AccountSwipeAction> stockSwipeActionChoices = [
  AccountSwipeAction.none,
  AccountSwipeAction.stockBuy,
  AccountSwipeAction.stockSell,
  AccountSwipeAction.stockDca,
  AccountSwipeAction.editAccount,
];

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
    case AccountSwipeAction.stockBuy:
      return l10n.accountSwipeActionStockBuy;
    case AccountSwipeAction.stockSell:
      return l10n.accountSwipeActionStockSell;
    case AccountSwipeAction.stockDca:
      return l10n.accountSwipeActionStockDca;
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

  /// 投資理財帳戶預設:向右滑買進、向左滑賣出。
  factory AccountSwipeSettings.stockDefaultSettings() =>
      const AccountSwipeSettings(
        leftAction: AccountSwipeAction.stockSell,
        rightAction: AccountSwipeAction.stockBuy,
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

/// 帳戶總覽頁滑動快捷操作設定的 StateNotifier。
/// 會跟著帳號走:變更時透過 [onChanged] 推進 appearance 包(見
/// theme_providers.dart 的 `pushAppearanceToCloud`),其他裝置下行時走
/// [applyFromServer](只落本機,不回推,避免來回打架)。
class AccountSwipeSettingsNotifier extends StateNotifier<AccountSwipeSettings> {
  AccountSwipeSettingsNotifier({
    AccountSwipeSettings? defaults,
    String keyPrefix = 'account_swipe',
    List<AccountSwipeAction> allowed = generalSwipeActionChoices,
    void Function()? onChanged,
  })  : _onChanged = onChanged,
        _defaults = defaults ?? AccountSwipeSettings.defaultSettings(),
        _keyLeftAction = '${keyPrefix}_left_action',
        _keyRightAction = '${keyPrefix}_right_action',
        _allowed = allowed,
        super(defaults ?? AccountSwipeSettings.defaultSettings()) {
    _loadSettings();
  }

  final AccountSwipeSettings _defaults;
  final String _keyLeftAction;
  final String _keyRightAction;
  final List<AccountSwipeAction> _allowed;
  final void Function()? _onChanged;

  /// 雲端下行套用:只更新 state + 本機 prefs,不觸發回推。
  /// 不認得的動作名稱(另一組設定的動作/未來版本新增)視為沒收到。
  Future<void> applyFromServer({String? left, String? right}) async {
    AccountSwipeAction? parse(String? name) {
      if (name == null) return null;
      for (final a in _allowed) {
        if (a.name == name) return a;
      }
      return null;
    }

    final l = parse(left) ?? state.leftAction;
    final r = parse(right) ?? state.rightAction;
    if (l == state.leftAction && r == state.rightAction) return;
    state = AccountSwipeSettings(leftAction: l, rightAction: r);
    await _saveSettings();
  }

  AccountSwipeAction _parseAction(String? name, AccountSwipeAction fallback) {
    if (name == null) return fallback;
    // 只接受這組設定允許的動作(舊資料/另一組設定的動作一律退回預設)。
    return _allowed.firstWhere((a) => a.name == name, orElse: () => fallback);
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final defaults = _defaults;
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
    _onChanged?.call();
  }

  Future<void> updateRightAction(AccountSwipeAction action) async {
    state = state.copyWith(rightAction: action);
    await _saveSettings();
    _onChanged?.call();
  }
}

final accountSwipeSettingsProvider =
    StateNotifierProvider<AccountSwipeSettingsNotifier, AccountSwipeSettings>(
        (ref) {
  return AccountSwipeSettingsNotifier(
    onChanged: () => pushAppearanceToCloud(ref),
  );
});

/// 投資理財(股票)帳戶自己的滑動快捷操作設定,跟一般帳戶分開存。
final stockAccountSwipeSettingsProvider =
    StateNotifierProvider<AccountSwipeSettingsNotifier, AccountSwipeSettings>(
        (ref) {
  return AccountSwipeSettingsNotifier(
    defaults: AccountSwipeSettings.stockDefaultSettings(),
    keyPrefix: 'account_swipe_stock',
    allowed: stockSwipeActionChoices,
    onChanged: () => pushAppearanceToCloud(ref),
  );
});
