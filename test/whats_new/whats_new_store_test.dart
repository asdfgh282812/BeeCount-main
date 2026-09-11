import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:beecount/whats_new/whats_new_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WhatsNewStore', () {
    test('从未写入过:getLastSeenVersion 回传 null', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await WhatsNewStore.getLastSeenVersion(), isNull);
    });

    test('setLastSeenVersion 后:getLastSeenVersion 回传同一版本', () async {
      SharedPreferences.setMockInitialValues({});
      await WhatsNewStore.setLastSeenVersion('3.3.0');
      expect(await WhatsNewStore.getLastSeenVersion(), '3.3.0');
    });
  });

  group('decideWhatsNewAction', () {
    test('全新安装(lastSeenVersion 为 null):silentFirstRun,不管有没有内容', () {
      expect(
        decideWhatsNewAction(
          lastSeenVersion: null,
          currentVersion: '3.3.0',
          hasContent: true,
        ),
        WhatsNewAction.silentFirstRun,
      );
      expect(
        decideWhatsNewAction(
          lastSeenVersion: null,
          currentVersion: '3.3.0',
          hasContent: false,
        ),
        WhatsNewAction.silentFirstRun,
      );
    });

    test('已读版本等于目前版本:alreadySeen,不管有没有内容', () {
      expect(
        decideWhatsNewAction(
          lastSeenVersion: '3.3.0',
          currentVersion: '3.3.0',
          hasContent: true,
        ),
        WhatsNewAction.alreadySeen,
      );
    });

    test('已读版本不同且目前版本有内容:show', () {
      expect(
        decideWhatsNewAction(
          lastSeenVersion: '3.2.0',
          currentVersion: '3.3.0',
          hasContent: true,
        ),
        WhatsNewAction.show,
      );
    });

    test('已读版本不同但目前版本没有内容:markOnlyNoContent', () {
      expect(
        decideWhatsNewAction(
          lastSeenVersion: '3.2.0',
          currentVersion: '3.3.0',
          hasContent: false,
        ),
        WhatsNewAction.markOnlyNoContent,
      );
    });
  });
}
