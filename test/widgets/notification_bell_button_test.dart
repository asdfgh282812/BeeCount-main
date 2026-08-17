/// `NotificationBellButton`(首頁頂部通知鈴鐺)——gate 在
/// `beecountCloudProviderInstance` 上(非 BeeCount Cloud 後端整顆隱藏)、
/// 未讀徽章顯示/隱藏、點擊導航到 `NotificationCenterPage`。獨立拆出來測試,
/// 不用揹 home_page.dart 整頁的重量級依賴。
import 'package:flutter/material.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/notifications/notification_center_page.dart';
import 'package:beecount/providers/notification_center_providers.dart';
import 'package:beecount/providers/sync_providers.dart';
import 'package:beecount/widgets/biz/notification_bell_button.dart';

class _TestNotifier extends NotificationCenterNotifier {
  _TestNotifier(NotificationCenterState initial) : super(null) {
    state = initial;
  }
}

void main() {
  Widget host({
    required bool cloudActive,
    int unreadCount = 0,
  }) {
    return ProviderScope(
      overrides: [
        // widget 只判斷 valueOrNull != null，不會呼叫任何成員，未初始化的
        // BeeCountCloudProvider()(所有欄位皆可空)已足夠當非 null 標記。
        beecountCloudProviderInstance.overrideWith(
          (ref) async => cloudActive ? BeeCountCloudProvider() : null,
        ),
        notificationCenterProvider.overrideWith(
          (ref) => _TestNotifier(NotificationCenterState(
            unreadCount: unreadCount,
          )),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('zh', 'TW'),
        home: Scaffold(body: NotificationBellButton()),
      ),
    );
  }

  testWidgets('非 BeeCount Cloud 後端：鈴鐺完全不顯示', (tester) async {
    await tester.pumpWidget(host(cloudActive: false));
    await tester.pump();

    expect(find.byIcon(Icons.notifications_outlined), findsNothing);
  });

  testWidgets('BeeCount Cloud 後端 + unreadCount=0：顯示鈴鐺，不顯示徽章', (tester) async {
    await tester.pumpWidget(host(cloudActive: true, unreadCount: 0));
    await tester.pump();

    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('BeeCount Cloud 後端 + unreadCount=3：顯示徽章數字', (tester) async {
    await tester.pumpWidget(host(cloudActive: true, unreadCount: 3));
    await tester.pump();

    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('未讀數超過 99：顯示 99+', (tester) async {
    await tester.pumpWidget(host(cloudActive: true, unreadCount: 150));
    await tester.pump();

    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('點擊鈴鐺導航到 NotificationCenterPage', (tester) async {
    await tester.pumpWidget(host(cloudActive: true, unreadCount: 1));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationCenterPage), findsOneWidget);
  });
}
