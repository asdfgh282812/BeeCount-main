import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/license_providers.dart';

/// 強制更新頁(docs/changes/2026-09-25-license-key-and-min-sync-version.md)。
///
/// 目前 App 版本低於 BeeCount Cloud 後台設定的「最低可同步版本」時,
/// `MainApp._getHomePage` 整個改顯示這一頁,不能進入任何功能 —— 舊資料格式的
/// App 繼續寫本地資料、之後又同步不上去,只會讓資料更難收拾。
///
/// 這裡不提供下載連結:App 的安裝管道不只一種(App Store / TestFlight /
/// SideStore / APK),由使用者自行從原本的管道更新;更新完按「重新檢查」。
class ForceUpdatePage extends ConsumerWidget {
  const ForceUpdatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final gate = ref.watch(appVersionGateProvider);

    return Scaffold(
      backgroundColor: theme.primaryColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.system_update_outlined,
                      size: 64, color: Colors.white),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                l10n.forceUpdateTitle,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.forceUpdateDescription(
                    gate.currentVersion, gate.minSyncVersion ?? ''),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: gate.busy
                    ? null
                    : () => ref.read(appVersionGateProvider.notifier).refresh(),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: theme.primaryColor,
                ),
                child: gate.busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.forceUpdateRetryButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
