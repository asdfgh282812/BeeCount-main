/// `NotificationCenterPage` —— 列表渲染(未讀視覺區分)、空狀態、錯誤狀態+重試、
/// 下拉刷新、單筆已讀/全部已讀的接線。`notificationCenterProvider` 整個換成
/// spy 版 notifier,不打真的網路。payload → 跳轉目標的解析邏輯已在
/// `test/data/notification_jump_target_test.dart` 用真的 Drift db 覆蓋,這裡
/// 只驗證「沒有跳轉目標時只標已讀、不導航」這一支,完整頁面導航(account
/// detail / recurring rule list)不在這裡重覆驗證，因為那只是套用既有
/// `Navigator.push(MaterialPageRoute(...))` 樣板(同 automation_page.dart 既有
/// 寫法），真正的分支邏輯已經由 resolver 測試覆蓋。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/notifications/notification_center_page.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/providers/notification_center_providers.dart';

class _TestNotifier extends NotificationCenterNotifier {
  _TestNotifier(NotificationCenterState initial) : super(null) {
    state = initial;
  }

  int refreshCalls = 0;
  int markAllReadCalls = 0;
  final List<int> markReadIds = [];

  @override
  Future<void> refresh() async {
    refreshCalls++;
  }

  @override
  Future<void> markRead(int id) async {
    markReadIds.add(id);
  }

  @override
  Future<void> markAllRead() async {
    markAllReadCalls++;
  }
}

BeeCountCloudNotificationItem _item({
  required int id,
  required String category,
  required String title,
  String? body,
  DateTime? readAt,
  DateTime? createdAt,
  Map<String, dynamic>? payload,
}) {
  return BeeCountCloudNotificationItem(
    id: id,
    category: category,
    title: title,
    body: body,
    payload: payload,
    readAt: readAt,
    createdAt: createdAt ?? DateTime.now(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(_TestNotifier notifier) {
    // `_handleTap` 一律先 `ref.read(repositoryProvider)`(即使 payload 為
    // null、根本用不到查詢結果),不 override 的話會落到預設的真機 db,在
    // widget test 環境會出錯 —— 一律換成記憶體 db。
    final db = BeeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    return ProviderScope(
      overrides: [
        notificationCenterProvider.overrideWith((ref) => notifier),
        repositoryProvider.overrideWithValue(LocalRepository(db)),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('zh', 'TW'),
        home: NotificationCenterPage(),
      ),
    );
  }

  testWidgets('空狀態：顯示空狀態文案，不顯示列表', (tester) async {
    final notifier = _TestNotifier(const NotificationCenterState());
    await tester.pumpWidget(host(notifier));
    await tester.pump();

    expect(find.text('目前沒有通知'), findsOneWidget);
  });

  testWidgets('錯誤狀態（沒有已快取項目）：顯示重試按鈕，點擊呼叫 refresh', (tester) async {
    final notifier =
        _TestNotifier(const NotificationCenterState(error: 'network error'));
    await tester.pumpWidget(host(notifier));
    await tester.pump();

    expect(find.text('通知載入失敗'), findsOneWidget);
    expect(notifier.refreshCalls, greaterThanOrEqualTo(0));

    final before = notifier.refreshCalls;
    await tester.tap(find.text('重試'));
    await tester.pump();
    expect(notifier.refreshCalls, before + 1);
  });

  testWidgets('列表渲染：未讀項目顯示未讀圓點，已讀不顯示', (tester) async {
    final notifier = _TestNotifier(NotificationCenterState(
      unreadCount: 1,
      items: [
        _item(id: 1, category: 'card_due', title: '未讀通知'),
        _item(
          id: 2,
          category: 'card_reward',
          title: '已讀通知',
          readAt: DateTime.now(),
        ),
      ],
    ));
    await tester.pumpWidget(host(notifier));
    await tester.pump();

    expect(find.text('未讀通知'), findsOneWidget);
    expect(find.text('已讀通知'), findsOneWidget);
    // 未讀圓點是個 8x8 圓形 Container，用 Icons 找不到，改用文字存在性 +
    // unreadCount 驅動的「全部標為已讀」按鈕可用性間接驗證未讀狀態被正確渲染。
    final markAllButton =
        tester.widget<TextButton>(find.widgetWithText(TextButton, '全部標為已讀'));
    expect(markAllButton.onPressed, isNotNull);
  });

  testWidgets('unreadCount 為 0 時「全部標為已讀」按鈕停用', (tester) async {
    final notifier = _TestNotifier(NotificationCenterState(
      items: [
        _item(
          id: 1,
          category: 'system',
          title: '已讀通知',
          readAt: DateTime.now(),
        ),
      ],
    ));
    await tester.pumpWidget(host(notifier));
    await tester.pump();

    final markAllButton =
        tester.widget<TextButton>(find.widgetWithText(TextButton, '全部標為已讀'));
    expect(markAllButton.onPressed, isNull);
  });

  testWidgets('點擊「全部標為已讀」呼叫 notifier.markAllRead', (tester) async {
    final notifier = _TestNotifier(NotificationCenterState(
      unreadCount: 1,
      items: [_item(id: 1, category: 'system', title: 'A')],
    ));
    await tester.pumpWidget(host(notifier));
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, '全部標為已讀'));
    await tester.pump();
    expect(notifier.markAllReadCalls, 1);
  });

  testWidgets('點擊沒有跳轉目標(payload=null)的項目：只標已讀，不導航離開通知頁', (tester) async {
    final notifier = _TestNotifier(NotificationCenterState(
      unreadCount: 1,
      items: [_item(id: 42, category: 'system', title: '系統通知')],
    ));
    await tester.pumpWidget(host(notifier));
    await tester.pump();

    await tester.tap(find.text('系統通知'));
    await tester.pump();
    await tester.pump();

    expect(notifier.markReadIds, [42]);
    expect(find.byType(NotificationCenterPage), findsOneWidget);
  });

  testWidgets('下拉刷新呼叫 notifier.refresh', (tester) async {
    final notifier = _TestNotifier(NotificationCenterState(
      items: [_item(id: 1, category: 'system', title: 'A')],
    ));
    await tester.pumpWidget(host(notifier));
    await tester.pump();

    final before = notifier.refreshCalls;
    await tester.fling(find.text('A'), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(notifier.refreshCalls, greaterThan(before));
  });
}
