import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart' hide SyncStatus;

import '../../l10n/app_localizations.dart';
import '../../pages/cloud/cloud_sync_page.dart';
import '../../providers.dart';
import '../../services/cloud_login_reminder_store.dart';
import '../../styles/tokens.dart';

/// App 冷啟動 / 回到前景時呼叫。若使用者曾設定過雲端同步(非 local)、目前
/// 處於未登入狀態,且尚未勾選「不再提示」,彈出提醒對話框。
///
/// 已勾選「不再提示」或從未設定雲端同步的情況都直接跳過,不打任何網路請求。
///
/// 回傳值代表「這次是否顯示了對話框」(不論使用者最後怎麼關閉),讓呼叫端
/// (`app.dart` 的 `_checkStartupReminders`)可以判斷要不要接著顯示「App 新
/// 版本提醒」——兩個提醒優先權不同,不該同時疊在畫面上,見該函式 docstring。
Future<bool> maybeShowCloudLoginReminder(
  BuildContext context,
  WidgetRef ref,
) async {
  if (await CloudLoginReminderStore.isDismissed()) return false;

  final config = await ref.read(activeCloudConfigProvider.future);
  if (!config.valid || config.type == CloudBackendType.local) return false;

  // authServiceProvider 内部会完整跑完对应 provider 的 initialize()(含 session
  // 从 SharedPreferences 还原 / 过期 refresh),这里 await 到底再读 currentUser,
  // 避免在还原过程中把「还没 settle」误判成「未登入」而闪现一次不必要的提醒。
  final auth = await ref.read(authServiceProvider.future);
  final user = await auth.currentUser;
  if (user != null) return false;

  if (!context.mounted) return false;
  final result = await showDialog<({bool dontShowAgain, bool goLogin})>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const CloudLoginReminderDialog(),
  );
  if (result == null) return true;

  if (result.dontShowAgain) {
    await CloudLoginReminderStore.setDismissed();
  }
  if (result.goLogin && context.mounted) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CloudSyncPage()),
    );
  }
  return true;
}

class CloudLoginReminderDialog extends ConsumerStatefulWidget {
  const CloudLoginReminderDialog({super.key});

  @override
  ConsumerState<CloudLoginReminderDialog> createState() =>
      _CloudLoginReminderDialogState();
}

class _CloudLoginReminderDialogState
    extends ConsumerState<CloudLoginReminderDialog> {
  bool _dontShowAgain = false;

  void _pop(bool goLogin) {
    Navigator.pop(
      context,
      (dontShowAgain: _dontShowAgain, goLogin: goLogin),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primary = ref.watch(primaryColorProvider);
    return AlertDialog(
      title: Text(l10n.cloudLoginReminderTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.cloudLoginReminderBody,
              style: TextStyle(
                height: 1.5,
                color: BeeTokens.textSecondary(context),
              ),
            ),
            CheckboxListTile(
              value: _dontShowAgain,
              onChanged: (v) => setState(() => _dontShowAgain = v ?? false),
              title: Text(l10n.cloudLoginReminderDontShowAgain),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _pop(false),
          child: Text(l10n.cloudLoginReminderDismiss),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: primary),
          onPressed: () => _pop(true),
          child: Text(l10n.cloudLoginReminderGoLogin),
        ),
      ],
    );
  }
}
