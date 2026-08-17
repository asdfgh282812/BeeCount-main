import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../pages/notifications/notification_center_page.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';

/// 首頁頂部通知鈴鐺:僅 BeeCount Cloud 後端激活時顯示(通知中心資料源是
/// server 端生成的通知,見 [notificationCenterProvider]),未讀數 > 0 時疊一
/// 個手刻的圓角徽章(此 codebase 沒有用 Flutter 內建 `Badge()` widget)。
/// 拆成獨立 widget 是為了讓這塊邏輯能脫離 home_page.dart 整頁重量級依賴單獨
/// 測試,見 `test/widgets/notification_bell_button_test.dart`。
class NotificationBellButton extends ConsumerWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cloudActive =
        ref.watch(beecountCloudProviderInstance).valueOrNull != null;
    if (!cloudActive) return const SizedBox.shrink();

    final unreadCount =
        ref.watch(notificationCenterProvider.select((s) => s.unreadCount));

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: AppLocalizations.of(context).notificationsTitle,
          padding: const EdgeInsets.all(6),
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: Size.zero,
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationCenterPage(),
              ),
            );
          },
          icon: Icon(
            Icons.notifications_outlined,
            size: 20,
            color: Theme.of(context).iconTheme.color,
          ),
        ),
        if (unreadCount > 0)
          Positioned(
            right: 4,
            top: 4,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                decoration: BoxDecoration(
                  color: BeeTokens.error(context),
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: Alignment.center,
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
