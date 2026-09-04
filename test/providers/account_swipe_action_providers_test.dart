import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/providers/account_swipe_action_providers.dart';

/// 帳戶總覽頁滑動快捷操作:AccountSwipeSettingsNotifier 讀寫 SharedPreferences
/// 的預設值與變更後持久化行為(帳戶總覽頁滑動快捷操作設計文件)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AccountSwipeSettings 默认值', () {
    test('预设右滑=调整余额，左滑=新增交易', () {
      final s = AccountSwipeSettings.defaultSettings();
      expect(s.rightAction, AccountSwipeAction.adjustBalance);
      expect(s.leftAction, AccountSwipeAction.addTransaction);
    });
  });

  group('AccountSwipeSettingsNotifier', () {
    test('无本机存储时读到默认值', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await pumpEventQueue();
      final settings = container.read(accountSwipeSettingsProvider);
      expect(settings.rightAction, AccountSwipeAction.adjustBalance);
      expect(settings.leftAction, AccountSwipeAction.addTransaction);
    });

    test('更新后立即反映在 state 上，且持久化到 SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // 先讀一次觸發 provider 建構,並等初始的 _loadSettings() 跑完,避免它
      // 晚於下面的 update 呼叫才 resolve、把剛寫入的值蓋回預設值。
      final notifier = container.read(accountSwipeSettingsProvider.notifier);
      await pumpEventQueue();

      await notifier.updateRightAction(AccountSwipeAction.editAccount);
      await notifier.updateLeftAction(AccountSwipeAction.none);

      expect(
        container.read(accountSwipeSettingsProvider).rightAction,
        AccountSwipeAction.editAccount,
      );
      expect(
        container.read(accountSwipeSettingsProvider).leftAction,
        AccountSwipeAction.none,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('account_swipe_right_action'),
        AccountSwipeAction.editAccount.name,
      );
      expect(
        prefs.getString('account_swipe_left_action'),
        AccountSwipeAction.none.name,
      );
    });

    test('重建后可从本机存储读回变更后的设定', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(accountSwipeSettingsProvider.notifier);
      await pumpEventQueue();
      await notifier.updateRightAction(AccountSwipeAction.none);

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      container2.read(accountSwipeSettingsProvider.notifier);
      await pumpEventQueue();
      expect(
        container2.read(accountSwipeSettingsProvider).rightAction,
        AccountSwipeAction.none,
      );
      // 未变更的左滑维持默认值。
      expect(
        container2.read(accountSwipeSettingsProvider).leftAction,
        AccountSwipeAction.addTransaction,
      );
    });
  });
}
