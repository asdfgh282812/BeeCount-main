import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../system/logger_service.dart';
import 'update_result.dart';

/// Android APK 自我更新的版本描述檔。由發布腳本 `build_apps_json.py
/// --platform android` 產生,跟 APK 一起上傳到 Cloudflare R2 bucket 根目錄。
/// 格式見 `docs/changes/2026-09-26-android-apk-self-update.md`。
const String kApkUpdateManifestUrl =
    'https://pub-6fbd073a81084e04a716c50549e721b7.r2.dev/version.json';

/// 更新检查管理类
class UpdateChecker {
  UpdateChecker._();

  static final Dio _dio = Dio()
    ..options.connectTimeout = const Duration(seconds: 15)
    ..options.receiveTimeout = const Duration(seconds: 30);

  /// 检查更新信息
  static Future<UpdateResult> checkUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = _normalizeVersion(info.version);
      logger.info('UpdateChecker',
          '当前版本: $currentVersion, packageName: ${info.packageName}');

      // 加时间戳避开 CDN / HTTP 缓存,确保拿到刚上传的 version.json
      final resp = await _dio.get(
        kApkUpdateManifestUrl,
        queryParameters: {'t': DateTime.now().millisecondsSinceEpoch},
        options: Options(responseType: ResponseType.plain),
      );
      if (resp.statusCode != 200) {
        logger.error(
            'UpdateChecker', 'version.json 请求失败: HTTP ${resp.statusCode}');
        return UpdateResult(
          hasUpdate: false,
          message: '__UPDATE_CHECK_HTTP_FAILED__:${resp.statusCode}',
        );
      }

      final manifest = jsonDecode(resp.data as String) as Map<String, dynamic>;
      return evaluateManifest(
        manifest,
        currentVersion: currentVersion,
        packageName: info.packageName,
        runtimeAbi: currentRuntimeAbi(),
      );
    } catch (e) {
      logger.error('UpdateChecker', '检查更新异常', e);
      return UpdateResult(
        hasUpdate: false,
        message: '__UPDATE_CHECK_EXCEPTION__:$e',
      );
    }
  }

  /// 纯函数:依 version.json 内容 + 当前安装信息判断是否有更新、该下载哪个 APK。
  /// 独立出来方便单元测试。
  static UpdateResult evaluateManifest(
    Map<String, dynamic> manifest, {
    required String currentVersion,
    required String packageName,
    required String? runtimeAbi,
  }) {
    // dev / debug 变体的 applicationId 带 .dev / .debug 后缀,装正式版 APK 会变成
    // 另一个独立 App 而不是覆盖升级,所以只有 packageName 完全一致才提示更新。
    final manifestPackage = manifest['packageName'] as String?;
    if (manifestPackage != null && manifestPackage != packageName) {
      return UpdateResult(
        hasUpdate: false,
        message: '__UPDATE_NOT_APPLICABLE__',
      );
    }

    final latestVersion = _normalizeVersion('${manifest['version'] ?? ''}');
    if (latestVersion.isEmpty ||
        !isNewerVersion(latestVersion, currentVersion)) {
      return UpdateResult(
        hasUpdate: false,
        message: '__UPDATE_ALREADY_LATEST_SIMPLE__',
      );
    }

    final apk = pickApk(manifest['apks'], runtimeAbi);
    if (apk == null) {
      return UpdateResult(
        hasUpdate: false,
        message: '__UPDATE_NO_APK_FOUND__',
      );
    }

    return UpdateResult(
      hasUpdate: true,
      version: latestVersion,
      downloadUrl: apk['url'] as String,
      sha256: apk['sha256'] as String?,
      releaseNotes: '${manifest['releaseNotes'] ?? ''}'.trim(),
    );
  }

  /// 从 version.json 的 `apks`(ABI → {url, size, sha256})挑出适配当前设备的 APK:
  /// 当前进程跑在 arm64 上就用 arm64-v8a 主包(体积约 universal 的 40%),
  /// 其余(armv7 老设备、x86_64 模拟器、判断不出来)一律用 universal 兜底。
  ///
  /// 历史教训(v3.2.1):arm64 真机装到 armeabi-v7a 包会走 32-bit 兼容层严重卡顿,
  /// 所以绝不在 arm64 设备上回退到 armeabi-v7a。
  static Map<String, dynamic>? pickApk(dynamic apks, String? runtimeAbi) {
    if (apks is! Map) return null;
    Map<String, dynamic>? entry(String abi) {
      final e = apks[abi];
      if (e is Map && e['url'] is String) return e.cast<String, dynamic>();
      return null;
    }

    if (runtimeAbi != null) {
      final exact = entry(runtimeAbi);
      if (exact != null) return exact;
    }
    return entry('universal');
  }

  /// 当前 Dart VM 运行的 ABI。`Platform.version` 形如
  /// `3.5.0 (stable) ... on "android_arm64"`。
  static String? currentRuntimeAbi() {
    final v = Platform.version;
    if (v.contains('android_arm64')) return 'arm64-v8a';
    if (v.contains('android_x64')) return 'x86_64';
    if (v.contains('android_arm')) return 'armeabi-v7a';
    return null;
  }

  static String _normalizeVersion(String version) {
    String normalized = version.trim();
    if (normalized.startsWith('v')) {
      normalized = normalized.substring(1);
    }
    if (normalized.startsWith('dev-')) {
      normalized = normalized.substring(4);
    }
    final dashIndex = normalized.indexOf('-');
    if (dashIndex != -1) {
      normalized = normalized.substring(0, dashIndex);
    }
    final plusIndex = normalized.indexOf('+');
    if (plusIndex != -1) {
      normalized = normalized.substring(0, plusIndex);
    }
    return normalized;
  }

  static bool isNewerVersion(String newVersion, String currentVersion) {
    final newParts = newVersion
        .split('.')
        .map(int.tryParse)
        .where((e) => e != null)
        .cast<int>()
        .toList();
    final currentParts = currentVersion
        .split('.')
        .map(int.tryParse)
        .where((e) => e != null)
        .cast<int>()
        .toList();

    final maxLength =
        [newParts.length, currentParts.length].reduce((a, b) => a > b ? a : b);
    while (newParts.length < maxLength) {
      newParts.add(0);
    }
    while (currentParts.length < maxLength) {
      currentParts.add(0);
    }

    for (int i = 0; i < maxLength; i++) {
      if (newParts[i] > currentParts[i]) return true;
      if (newParts[i] < currentParts[i]) return false;
    }

    return false;
  }
}
