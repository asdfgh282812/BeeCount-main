import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/license_providers.dart';
import '../../services/system/update_service.dart';

/// 強制更新頁(docs/changes/2026-09-25-license-key-and-min-sync-version.md)。
///
/// 目前 App 版本低於 BeeCount Cloud 後台設定的「最低可同步版本」時,
/// `MainApp._getHomePage` 整個改顯示這一頁,不能進入任何功能 —— 舊資料格式的
/// App 繼續寫本地資料、之後又同步不上去,只會讓資料更難收拾。
///
/// iOS 不提供下載連結(SideStore 等管道由使用者自行更新),更新完按「重新檢查」。
/// Android 多一顆「立即更新」,直接走 R2 `version.json` 的 APK 下載安裝流程
/// ([UpdateService.checkUpdateWithUI],見
/// docs/changes/2026-09-26-android-apk-self-update.md)——這一頁取代了整個首頁,
/// 啟動時的自動更新檢查(`app.dart` 的 `_checkStartupReminders`)不會跑到,
/// 沒有這顆按鈕的話 Android 使用者只能自己去找 APK。
class ForceUpdatePage extends ConsumerStatefulWidget {
  const ForceUpdatePage({super.key});

  @override
  ConsumerState<ForceUpdatePage> createState() => _ForceUpdatePageState();
}

class _ForceUpdatePageState extends ConsumerState<ForceUpdatePage> {
  bool _updating = false;

  Future<void> _startApkUpdate() async {
    await UpdateService.checkUpdateWithUI(
      context,
      setLoading: (v) {
        if (mounted) setState(() => _updating = v);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final gate = ref.watch(appVersionGateProvider);
    final canSelfUpdate = Platform.isAndroid;
    final spinner = SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(
          strokeWidth: 2, color: canSelfUpdate ? Colors.white : null),
    );

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
              if (canSelfUpdate) ...[
                FilledButton(
                  onPressed: _updating || gate.busy ? null : _startApkUpdate,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: theme.primaryColor,
                  ),
                  child: _updating
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: theme.primaryColor),
                        )
                      : Text(l10n.updateNowButton),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: gate.busy || _updating
                      ? null
                      : () =>
                          ref.read(appVersionGateProvider.notifier).refresh(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                  ),
                  child:
                      gate.busy ? spinner : Text(l10n.forceUpdateRetryButton),
                ),
              ] else
                FilledButton(
                  onPressed: gate.busy
                      ? null
                      : () =>
                          ref.read(appVersionGateProvider.notifier).refresh(),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: theme.primaryColor,
                  ),
                  child:
                      gate.busy ? spinner : Text(l10n.forceUpdateRetryButton),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
