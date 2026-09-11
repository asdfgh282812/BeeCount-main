import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';
import '../../whats_new/whats_new_content.dart';
import '../../whats_new/whats_new_store.dart';

/// 目前 App 版本號(不含 build number)。用 Provider 包一層是為了讓 Riverpod
/// 快取結果,「我的」頁面每次 rebuild 判斷是否顯示「新功能！」入口時
/// 不用重複打一次 PackageInfo platform channel。
final currentAppVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

/// 「新功能！」公告彈窗。純展示型元件,只接收已經算好的 [items],不依賴任何
/// domain model / Riverpod,符合 `lib/widgets/ui/` 通用元件的分類。
class WhatsNewDialog extends StatelessWidget {
  const WhatsNewDialog({super.key, required this.items});

  final List<WhatsNewItem> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.whatsNewDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              Text(
                items[i].title(l10n),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: BeeTokens.textPrimary(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                items[i].description(l10n),
                style: TextStyle(
                  height: 1.4,
                  color: BeeTokens.textSecondary(context),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.whatsNewDialogGotIt),
        ),
      ],
    );
  }
}

/// App 冷啟動時呼叫(接在 `_checkStartupReminders`〔`app.dart`〕的登入提醒、
/// App 更新提醒之後),依 [decideWhatsNewAction] 的四種分支決定是否彈窗。
Future<void> maybeShowWhatsNewOnStartup(
  BuildContext context,
  WidgetRef ref,
) async {
  final currentVersion = await ref.read(currentAppVersionProvider.future);
  final lastSeenVersion = await WhatsNewStore.getLastSeenVersion();
  final items = kWhatsNewContent[currentVersion] ?? const <WhatsNewItem>[];

  final action = decideWhatsNewAction(
    lastSeenVersion: lastSeenVersion,
    currentVersion: currentVersion,
    hasContent: items.isNotEmpty,
  );

  switch (action) {
    case WhatsNewAction.alreadySeen:
      return;
    case WhatsNewAction.silentFirstRun:
    case WhatsNewAction.markOnlyNoContent:
      await WhatsNewStore.setLastSeenVersion(currentVersion);
      return;
    case WhatsNewAction.show:
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => WhatsNewDialog(items: items),
      );
      await WhatsNewStore.setLastSeenVersion(currentVersion);
  }
}

/// 「我的」頁面「新功能！」入口的手動查看:只顯示目前版本內容,不讀寫已讀
/// 狀態——手動查看不影響自動彈窗邏輯。
Future<void> showWhatsNewForCurrentVersion(
  BuildContext context,
  WidgetRef ref,
) async {
  final currentVersion = await ref.read(currentAppVersionProvider.future);
  final items = kWhatsNewContent[currentVersion];
  if (items == null || items.isEmpty) return;

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => WhatsNewDialog(items: items),
  );
}
