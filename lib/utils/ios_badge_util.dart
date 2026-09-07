import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../services/system/logger_service.dart';

const _badgeChannel = MethodChannel('com.beecount.app/badge');

/// 清除 iOS App 圖示右上角的通知徽章(小紅點)數字。
///
/// `flutter_local_notifications` 在本專案的用法裡沒有暴露「無通知情況下把
/// 徽章歸零」的 Dart API(只能在排程通知時設定 `badgeNumber`,見
/// `lib/utils/notification_ios.dart`),徽章數字完全靠系統累加各個已觸發通知
/// 的 `badgeNumber`,不會自動清零。清零只能靠原生端呼叫
/// `UIApplication.shared.applicationIconBadgeNumber = 0`,見
/// `ios/Runner/AppDelegate.swift` 的 `com.beecount.app/badge` method channel。
///
/// 非 iOS 平台直接 no-op(Android 沒有這個系統層徽章概念)。
Future<void> clearAppIconBadge() async {
  if (!Platform.isIOS) return;
  try {
    await _badgeChannel.invokeMethod<void>('clearBadge');
  } catch (e, stack) {
    logger.error('IosBadge', '清除通知徽章失败', e, stack);
  }
}
