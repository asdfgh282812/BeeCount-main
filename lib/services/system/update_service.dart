import 'dart:io';
import 'package:flutter/material.dart';
import 'logger_service.dart';
import '../../widgets/ui/ui.dart';
import '../../l10n/app_localizations.dart';

// 导入分离的模块
import '../update/update_result.dart';
import '../update/update_checker.dart';
import '../update/update_permissions.dart';
import '../update/update_dialogs.dart';
import '../update/update_downloader.dart';
import '../update/update_installer.dart';
import '../update/update_cache.dart';
import '../update/apk_update_snooze_store.dart';

/// 本地化UpdateResult消息的辅助函数
String _localizeUpdateMessage(BuildContext context, String? message) {
  if (message == null) return '';

  // 处理带参数的消息（格式："__KEY__:param"）
  if (message.contains(':')) {
    final parts = message.split(':');
    final key = parts[0];
    final param = parts.length > 1 ? parts[1] : '';

    switch (key) {
      case '__UPDATE_ALREADY_LATEST__':
        return '${AppLocalizations.of(context).updateAlreadyLatest} $param';
      case '__UPDATE_DOWNLOAD_FAILED__':
        return '${AppLocalizations.of(context).updateDownloadFailed}: $param';
      case '__UPDATE_INSTALL_FAILED__':
        return '${AppLocalizations.of(context).updateInstallFailed}: $param';
      case '__UPDATE_CHECK_FAILED__':
        return '${AppLocalizations.of(context).updateCheckFailed}: $param';
      case '__UPDATE_CHECK_HTTP_FAILED__':
        return '${AppLocalizations.of(context).updateCheckFailed}: HTTP $param';
      case '__UPDATE_CHECK_EXCEPTION__':
        return '${AppLocalizations.of(context).updateCheckFailed}: $param';
      default:
        return message;
    }
  }

  // 处理不带参数的消息
  switch (message) {
    case '__UPDATE_USER_CANCELLED__':
      return AppLocalizations.of(context).updateUserCancelled;
    case '__UPDATE_PERMISSION_DENIED__':
      return AppLocalizations.of(context).updatePermissionDenied;
    case '__UPDATE_NO_APK_FOUND__':
      return AppLocalizations.of(context).updateNoApkFound;
    case '__UPDATE_ALREADY_LATEST_SIMPLE__':
      return AppLocalizations.of(context).updateAlreadyLatest;
    case '__UPDATE_NOT_APPLICABLE__':
      return AppLocalizations.of(context).updateNotApplicableBuild;
    default:
      return message;
  }
}

class UpdateService {
  UpdateService._();

  /// 检查更新信息
  static Future<UpdateResult> checkUpdate() async {
    return UpdateChecker.checkUpdate();
  }

  /// 下载并安装APK更新
  static Future<UpdateResult> downloadAndInstallUpdate(
    BuildContext context,
    String downloadUrl, {
    Function(double progress, String status)? onProgress,
    String? expectedSha256,
  }) async {
    try {
      // 检查权限
      onProgress?.call(0.0, AppLocalizations.of(context).updateCheckingPermissions);
      final hasPermission = await UpdatePermissions.checkAndRequestPermissions();
      if (!hasPermission) {
        return UpdateResult(
          hasUpdate: false,
          message: AppLocalizations.of(context).updatePermissionDenied,
        );
      }

      // 如果通知权限被拒绝，显示用户指南
      if (UpdatePermissions.notificationPermissionDenied && context.mounted) {
        await UpdateDialogs.showNotificationGuideDialog(context);
        UpdatePermissions.resetNotificationPermissionDenied(); // 重置状态，避免重复显示
      }

      // 从URL中提取版本信息用于文件命名和缓存检查
      onProgress?.call(0.0, AppLocalizations.of(context).updateCheckingCache);
      final uri = Uri.parse(downloadUrl);
      final originalFileName = uri.pathSegments.last;
      String? version;
      final versionMatch = RegExp(r'beecount-([0-9]+\.[0-9]+\.[0-9]+)\.apk')
          .firstMatch(originalFileName);
      if (versionMatch != null) {
        version = versionMatch.group(1);
        logger.info('UpdateService', '从URL提取的版本号: $version');
      }

      var cachedApkPath = await UpdateCache.checkCachedApkForUrl(downloadUrl);

      // 同版本号重新打包过(或缓存文件损坏)时,缓存 APK 跟 version.json 的
      // SHA-256 对不上 —— 直接丢掉重下,不要把旧包装回去。
      if (cachedApkPath != null &&
          expectedSha256 != null &&
          !await UpdateCache.matchesSha256(cachedApkPath, expectedSha256)) {
        logger.info('UpdateService', '缓存APK与version.json的SHA-256不符,删除后重新下载');
        await UpdateCache.deleteApkFile(cachedApkPath);
        cachedApkPath = null;
      }

      if (cachedApkPath != null) {
        logger.info('UpdateService', '找到缓存的APK: $cachedApkPath');

        // 验证APK文件完整性
        final isValid = await UpdateCache.validateApkFile(cachedApkPath);

        if (!isValid) {
          // APK文件损坏，询问用户是否重新下载
          logger.warning('UpdateService', '缓存的APK文件损坏或不完整');

          if (context.mounted) {
            final shouldRedownload = await AppDialog.confirm<bool>(
              context,
              title: AppLocalizations.of(context).updateCorruptedFileTitle,
              message: AppLocalizations.of(context).updateCorruptedFileMessage,
            );

            if (shouldRedownload == true) {
              // 删除损坏的文件
              await UpdateCache.deleteApkFile(cachedApkPath);
              logger.info('UpdateService', '已删除损坏的APK文件，继续下载');
              // 继续执行下载流程（不return，让代码继续往下走）
            } else {
              // 用户取消
              return UpdateResult.userCancelled();
            }
          }
        } else {
          // APK文件验证通过，询问是否安装
          if (context.mounted) {
            final shouldInstall = await AppDialog.confirm<bool>(
              context,
              title: AppLocalizations.of(context).updateCachedVersionTitle,
              message: AppLocalizations.of(context).updateCachedVersionMessage,
            );

            if (shouldInstall == true) {
              // 安装缓存的APK
              await UpdateInstaller.installApk(cachedApkPath);
              return UpdateResult(
                hasUpdate: true,
                success: true,
                message: AppLocalizations.of(context).updateInstallingCachedApk,
                filePath: cachedApkPath,
              );
            } else {
              // 用户选择取消，直接返回
              return UpdateResult.userCancelled();
            }
          }
        }
      }

      // 开始下载
      onProgress?.call(0.0, AppLocalizations.of(context).updatePreparingDownload);
      if (!context.mounted) {
        return UpdateResult(
          hasUpdate: false,
          message: AppLocalizations.of(context).updateUserCancelledDownload,
        );
      }

      // 使用版本号作为文件名，如果没有提取到版本号则使用默认名称
      final fileName = version != null ? 'v$version' : 'BeeCount_Update';
      final downloadResult = await UpdateDownloader.downloadApk(
        context,
        downloadUrl,
        fileName,
        onProgress: onProgress,
      );

      if (downloadResult.success &&
          downloadResult.filePath != null &&
          expectedSha256 != null &&
          !await UpdateCache.matchesSha256(downloadResult.filePath!, expectedSha256)) {
        await UpdateCache.deleteApkFile(downloadResult.filePath!);
        return UpdateResult(
          hasUpdate: false,
          success: false,
          message: context.mounted
              ? AppLocalizations.of(context).updateChecksumMismatch
              : 'SHA-256 mismatch',
        );
      }

      if (downloadResult.success && downloadResult.filePath != null) {
        // 下载成功，询问是否立即安装
        logger.info('UpdateService', '下载成功，准备显示安装确认弹窗');
        logger.info('UpdateService', 'Context挂载状态: ${context.mounted}');

        if (context.mounted) {
          // 检查Context状态和Widget树
          logger.info('UpdateService', 'Context已挂载，正在检查Widget树状态...');

          try {
            // 简化对话框显示逻辑，减少等待时间
            logger.info('UpdateService', '准备显示安装确认弹窗');

            bool? shouldInstall;
            // 较短的等待时间，确保下载对话框完全关闭
            await Future.delayed(const Duration(milliseconds: 300));

            // 再次检查context状态
            if (context.mounted) {
              logger.info('UpdateService', 'Context仍然挂载，开始显示安装确认弹窗');

              // 使用分离的对话框模块
              shouldInstall = await UpdateDialogs.showInstallDialog(context);
              logger.info('UpdateService', '安装确认弹窗返回结果: $shouldInstall');
            } else {
              logger.warning('UpdateService', 'Context在延迟后变为未挂载状态');
              shouldInstall = false;
            }

            if (shouldInstall == true) {
              // 在安装前提供进度回调
              logger.info('UpdateService', 'UPDATE_CRASH: 🚀 用户确认安装，开始启动安装程序');
              logger.info('UpdateService', 'UPDATE_CRASH: 当前构建模式: ${const bool.fromEnvironment('dart.vm.product') ? "生产模式" : "开发模式"}');
              logger.info('UpdateService', 'UPDATE_CRASH: 当前flavor: ${const String.fromEnvironment('flavor', defaultValue: 'unknown')}');
              onProgress?.call(0.95, AppLocalizations.of(context).updateStartingInstaller);

              // 确保在启动安装器之前，界面状态是正确的
              await Future.delayed(const Duration(milliseconds: 300));

              logger.info('UpdateService',
                  'UPDATE_CRASH: 🔧 调用UpdateInstaller.installApk方法，文件路径: ${downloadResult.filePath}');

              // 在生产环境中添加额外的预检查
              if (const bool.fromEnvironment('dart.vm.product')) {
                logger.info('UpdateService', 'UPDATE_CRASH: 🏭 生产环境，执行额外预检查...');
                try {
                  final preCheck = File(downloadResult.filePath!);
                  final preCheckExists = await preCheck.exists();
                  final preCheckSize = preCheckExists ? await preCheck.length() : 0;
                  logger.info('UpdateService', 'UPDATE_CRASH: 生产环境预检查 - 文件存在: $preCheckExists, 大小: $preCheckSize');
                } catch (preCheckError) {
                  logger.error('UpdateService', 'UPDATE_CRASH: 生产环境预检查失败', preCheckError);
                }
              }

              final installed = await UpdateInstaller.installApk(downloadResult.filePath!);
              logger.info('UpdateService', 'UPDATE_CRASH: 🎯 UpdateInstaller.installApk返回结果: $installed');

              if (const bool.fromEnvironment('dart.vm.product')) {
                logger.info('UpdateService', 'UPDATE_CRASH: 🏭 生产环境安装调用完成，应用即将进入后台或退出');
              }

              if (installed) {
                onProgress?.call(1.0, AppLocalizations.of(context).updateInstallerStarted);
                return UpdateResult(
                  hasUpdate: true,
                  success: true,
                  message: AppLocalizations.of(context).updateInstallStarted,
                  filePath: downloadResult.filePath,
                );
              } else {
                onProgress?.call(1.0, AppLocalizations.of(context).updateInstallationFailed);
                return UpdateResult(
                  hasUpdate: true,
                  success: false,
                  message: AppLocalizations.of(context).updateInstallFailed,
                  filePath: downloadResult.filePath,
                );
              }
            } else {
              // 用户选择稍后安装或弹窗被取消
              logger.info('UpdateService', '用户选择稍后安装或操作被取消');
              onProgress?.call(1.0, AppLocalizations.of(context).updateDownloadCompleted);
              return UpdateResult(
                hasUpdate: true,
                success: true,
                message: AppLocalizations.of(context).updateDownloadCompletedManual,
                filePath: downloadResult.filePath,
              );
            }
          } catch (e) {
            logger.error('UpdateService', '显示安装确认弹窗过程中发生异常', e);
            onProgress?.call(1.0, AppLocalizations.of(context).updateDownloadCompleted);
            return UpdateResult(
              hasUpdate: true,
              success: true,
              message: AppLocalizations.of(context).updateDownloadCompletedDialog,
              filePath: downloadResult.filePath,
            );
          }
        } else {
          // context未挂载，无法显示对话框
          logger.warning('UpdateService', 'Context未挂载，无法显示安装确认弹窗');
          onProgress?.call(1.0, AppLocalizations.of(context).updateDownloadCompleted);
          return UpdateResult(
            hasUpdate: true,
            success: true,
            message: AppLocalizations.of(context).updateDownloadCompletedContext,
            filePath: downloadResult.filePath,
          );
        }
      } else {
        onProgress?.call(1.0, AppLocalizations.of(context).updateDownloadFailedGeneric);
        return UpdateResult(
          hasUpdate: false,
          success: false,
          message: _localizeUpdateMessage(context, downloadResult.message).isNotEmpty ?
              _localizeUpdateMessage(context, downloadResult.message) :
              AppLocalizations.of(context).updateDownloadFailedGeneric,
        );
      }
    } catch (e) {
      logger.error('UpdateService', '下载更新失败', e);
      onProgress?.call(1.0, AppLocalizations.of(context).updateDownloadFailedGeneric);
      return UpdateResult(
        hasUpdate: false,
        success: false,
        message: AppLocalizations.of(context).updateCheckingUpdateError('$e'),
      );
    }
  }

  /// 完整的更新检查流程，包含UI交互（仅 Android;iOS 直接返回）
  ///
  /// [silent] = true 用于 App 启动 / 回到前景的自动检查:没有新版本、检查失败、
  /// 或同一版本 24 小时内按过「稍后」([ApkUpdateSnoozeStore])时都静默返回,
  /// 不打扰使用者。手动检查([silent] = false,「关于 → 检查更新」)则会把
  /// 「已是最新版本」或错误信息显示出来。
  static Future<void> checkUpdateWithUI(
    BuildContext context, {
    bool silent = false,
    Function(bool loading)? setLoading,
    Function(double progress, String status)? setProgress,
  }) async {
    if (!Platform.isAndroid) return;

    void loading(bool v) => setLoading?.call(v);
    void progress(double p, String s) => setProgress?.call(p, s);

    loading(true);
    progress(0.0, AppLocalizations.of(context).updateCheckingUpdate);

    try {
      final checkResult = await checkUpdate();

      if (!context.mounted) return;

      if (!checkResult.hasUpdate) {
        if (silent) return;
        final localizedMessage = _localizeUpdateMessage(context, checkResult.message);
        final message = localizedMessage.isEmpty
            ? AppLocalizations.of(context).updateCurrentLatestVersion
            : localizedMessage;
        if (checkResult.message?.startsWith('__UPDATE_CHECK') == true) {
          await UpdateDialogs.showUpdateErrorWithFallback(context, message);
        } else {
          await AppDialog.info(
            context,
            title: AppLocalizations.of(context).updateCheckTitle,
            message: message,
          );
        }
        return;
      }

      final version = checkResult.version ?? '';
      if (silent && await ApkUpdateSnoozeStore.isSnoozed(version)) {
        logger.info('UpdateService', '版本 $version 在暂缓期内,跳过自动提示');
        return;
      }
      if (!context.mounted) return;

      loading(false);
      progress(0.0, '');

      final shouldDownload = await UpdateDialogs.showDownloadConfirmDialog(
        context,
        version,
        checkResult.releaseNotes ?? '',
      );

      if (!shouldDownload) {
        await ApkUpdateSnoozeStore.snooze(version);
        return;
      }
      if (!context.mounted) return;

      final downloadResult = await downloadAndInstallUpdate(
        context,
        checkResult.downloadUrl!,
        onProgress: setProgress,
        expectedSha256: checkResult.sha256,
      );

      if (!context.mounted) return;

      logger.info('UpdateService', 'UPDATE_CRASH: 📊 downloadResult检查 - success: ${downloadResult.success}, message: ${downloadResult.message}, type: ${downloadResult.type}');

      if (!downloadResult.success && downloadResult.message != null) {
        // 用户取消下载,静默返回
        if (downloadResult.type == UpdateResultType.userCancelled) return;

        // 等待一段时间确保下载对话框完全关闭，避免黑屏
        await Future.delayed(const Duration(milliseconds: 500));
        if (!context.mounted) return;

        final localizedError = _localizeUpdateMessage(context, downloadResult.message!);
        await UpdateDialogs.showDownloadErrorWithFallback(
          context,
          localizedError.isNotEmpty ? localizedError : downloadResult.message!,
          browserUrl: checkResult.downloadUrl,
        );
      }
      // 成功下载的情况不需要额外提示，downloadAndInstallUpdate 内部已处理
    } catch (e) {
      if (!silent && context.mounted) {
        await UpdateDialogs.showUpdateErrorWithFallback(
            context, AppLocalizations.of(context).updateCheckingUpdateError('$e'));
      }
    } finally {
      loading(false);
      progress(0.0, '');
    }
  }

  /// 获取缓存的APK路径
  static Future<String?> getCachedApkPath() async {
    return UpdateCache.getCachedApkPath();
  }

  /// 手动查找并安装本地APK
  static Future<bool> showLocalApkInstallOption(BuildContext context) async {
    return UpdateInstaller.showLocalApkInstallOption(context);
  }

  /// 检查是否有可用的缓存APK并提供安装选项
  static Future<bool> showCachedApkInstallOption(BuildContext context) async {
    return UpdateInstaller.showCachedApkInstallOption(context);
  }
}