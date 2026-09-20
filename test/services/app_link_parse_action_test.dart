// AppLinkService.parseAction 的 host 解析测试，重点覆盖「纯启动链接」：
// SideStore/AltStore 侧载商店点「打开」是直接开 App 注册的 URL scheme
// 本身（beecount://），系统会把这条没有 host 的 URL 投递给 uriLinkStream。
// 它必须被识别成 AppLinkAction.launch 静默忽略，否则每次从 SideStore
// 启动都会弹一个「未知的操作: 」的 toast。
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/services/platform/app_link_service.dart';

void main() {
  group('parseAction', () {
    test('纯启动链接 beecount:// 解析为 launch', () {
      expect(AppLinkService.parseAction(Uri.parse('beecount://')),
          AppLinkAction.launch);
      expect(AppLinkService.parseAction(Uri.parse('beecount:///')),
          AppLinkAction.launch);
    });

    test('已知 host 仍正常解析', () {
      expect(AppLinkService.parseAction(Uri.parse('beecount://voice')),
          AppLinkAction.voice);
      expect(AppLinkService.parseAction(Uri.parse('beecount://open?page=assets')),
          AppLinkAction.open);
      expect(AppLinkService.parseAction(Uri.parse('beecount://auth-callback')),
          AppLinkAction.ssoCallback);
    });

    test('无法辨识的 host 仍是 unknown', () {
      expect(AppLinkService.parseAction(Uri.parse('beecount://nope')),
          AppLinkAction.unknown);
    });
  });
}
