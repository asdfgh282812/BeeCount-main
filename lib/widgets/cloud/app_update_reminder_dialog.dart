import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/update/app_update_reminder_store.dart';
import '../../styles/tokens.dart';

/// App 冷啟動 / 回到前景時呼叫,只在「未登入雲端同步提醒」沒有顯示時才會被
/// [_checkStartupReminders]（`app.dart`）呼叫到。只有目前雲端同步後端是
/// `beecountCloud` 時才會發任何網路請求 —— 其他同步後端(Supabase/WebDAV/S3/
/// iCloud)或本機模式的使用者無從得知這台 server 在哪,直接跳過。
///
/// [beecountCloudProviderInstance] 內部已經處理好「非 beecountCloud 型別 /
/// 未設定 / 初始化失敗」都回傳 null,這裡不需要再重複判斷一次
/// `activeCloudConfigProvider`。
Future<void> maybeShowAppUpdateReminder(
  BuildContext context,
  WidgetRef ref,
) async {
  final cloud = await ref.read(beecountCloudProviderInstance.future);
  if (cloud == null) return;

  String? latestVersion;
  try {
    final latest = await cloud.fetchLatestAppVersion();
    latestVersion = latest.version;
  } catch (_) {
    // 网络失败/解析失败一律视同这次跳过检查,不影响 App 正常使用。
    return;
  }
  if (latestVersion == null) return;

  final info = await PackageInfo.fromPlatform();
  final currentVersion = info.version;
  if (!_isVersionNewer(latestVersion, currentVersion)) return;

  final dismissedVersion = await AppUpdateReminderStore.getDismissedVersion();
  if (dismissedVersion == latestVersion) return;

  if (!context.mounted) return;
  final result = await showDialog<({bool dontShowAgain})>(
    context: context,
    barrierDismissible: true,
    builder: (_) => AppUpdateReminderDialog(
      currentVersion: currentVersion,
      latestVersion: latestVersion!,
    ),
  );
  if (result == null) return;

  if (result.dontShowAgain) {
    await AppUpdateReminderStore.setDismissedVersion(latestVersion);
  }
}

/// 簡單三段式(x.y.z)數字比較,只看 [latestVersion] 是否嚴格大於
/// [currentVersion]。刻意獨立於 `UpdateChecker._isNewerVersion`
/// (`services/update/update_checker.dart`)——那個是 Android/APK 下載安裝
/// 流程的內部細節,語意上跟這個「純提醒、無下載動作」的功能無關,三、五行
/// 的版本比較邏輯沒有必要跨模組共用一個私有靜態方法。
bool _isVersionNewer(String latestVersion, String currentVersion) {
  final latestParts = _parseVersionParts(latestVersion);
  final currentParts = _parseVersionParts(currentVersion);
  final length = latestParts.length > currentParts.length
      ? latestParts.length
      : currentParts.length;
  for (var i = 0; i < length; i++) {
    final latest = i < latestParts.length ? latestParts[i] : 0;
    final current = i < currentParts.length ? currentParts[i] : 0;
    if (latest != current) return latest > current;
  }
  return false;
}

List<int> _parseVersionParts(String version) {
  return version.split('.').map((e) => int.tryParse(e) ?? 0).toList();
}

class AppUpdateReminderDialog extends ConsumerStatefulWidget {
  const AppUpdateReminderDialog({
    super.key,
    required this.currentVersion,
    required this.latestVersion,
  });

  final String currentVersion;
  final String latestVersion;

  @override
  ConsumerState<AppUpdateReminderDialog> createState() =>
      _AppUpdateReminderDialogState();
}

class _AppUpdateReminderDialogState
    extends ConsumerState<AppUpdateReminderDialog> {
  bool _dontShowAgain = false;

  void _pop() {
    Navigator.pop(context, (dontShowAgain: _dontShowAgain));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primary = ref.watch(primaryColorProvider);
    return AlertDialog(
      title: Text(l10n.appUpdateReminderTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.appUpdateReminderBody(
                widget.currentVersion,
                widget.latestVersion,
              ),
              style: TextStyle(
                height: 1.5,
                color: BeeTokens.textSecondary(context),
              ),
            ),
            CheckboxListTile(
              value: _dontShowAgain,
              onChanged: (v) => setState(() => _dontShowAgain = v ?? false),
              title: Text(l10n.appUpdateReminderDontShowAgain),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: primary),
          onPressed: _pop,
          child: Text(l10n.appUpdateReminderDismiss),
        ),
      ],
    );
  }
}
