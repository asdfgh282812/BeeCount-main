import 'package:flutter/material.dart';

/// 全局 navigator key — 给 service 层(没有 BuildContext)push 路由使用。
///
/// 独立成文件是为了打破 import 环:`main.dart` 透过
/// `services/platform/screenshot_monitor_service.dart` 等文件间接 import
/// `services/automation/auto_billing_service.dart`,若後者要用这个 key 又
/// import `main.dart`,会形成循环 import,故把这个 key 提出来单独放。
final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();
