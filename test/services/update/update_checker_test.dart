import 'package:beecount/services/update/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _manifest({
  String version = '3.7.0',
  String? packageName = 'com.tntlikely.beecount',
  Map<String, dynamic>? apks,
}) =>
    {
      if (packageName != null) 'packageName': packageName,
      'version': version,
      'versionCode': 5,
      'releaseNotes': '1. 新功能\n',
      'apks': apks ??
          {
            'arm64-v8a': {
              'url': 'https://r2.example/beecount-3.7.0.apk',
              'sha256': 'aa',
            },
            'universal': {
              'url': 'https://r2.example/beecount-3.7.0-universal.apk',
              'sha256': 'bb',
            },
          },
    };

void main() {
  group('UpdateChecker.evaluateManifest', () {
    test('newer version on arm64 picks the arm64 APK', () {
      final r = UpdateChecker.evaluateManifest(
        _manifest(),
        currentVersion: '3.6.0',
        packageName: 'com.tntlikely.beecount',
        runtimeAbi: 'arm64-v8a',
      );
      expect(r.hasUpdate, isTrue);
      expect(r.version, '3.7.0');
      expect(r.downloadUrl, 'https://r2.example/beecount-3.7.0.apk');
      expect(r.sha256, 'aa');
      expect(r.releaseNotes, '1. 新功能');
    });

    test('non-arm64 or unknown ABI falls back to universal', () {
      for (final abi in ['armeabi-v7a', 'x86_64', null]) {
        final r = UpdateChecker.evaluateManifest(
          _manifest(),
          currentVersion: '3.6.0',
          packageName: 'com.tntlikely.beecount',
          runtimeAbi: abi,
        );
        expect(r.downloadUrl, 'https://r2.example/beecount-3.7.0-universal.apk',
            reason: 'abi=$abi');
      }
    });

    test('same or older version reports already latest', () {
      for (final current in ['3.7.0', '3.7.1', '4.0']) {
        final r = UpdateChecker.evaluateManifest(
          _manifest(),
          currentVersion: current,
          packageName: 'com.tntlikely.beecount',
          runtimeAbi: 'arm64-v8a',
        );
        expect(r.hasUpdate, isFalse, reason: current);
        expect(r.message, '__UPDATE_ALREADY_LATEST_SIMPLE__');
      }
    });

    test('dev / debug package names are not offered the prod APK', () {
      for (final pkg in [
        'com.tntlikely.beecount.dev',
        'com.tntlikely.beecount.debug'
      ]) {
        final r = UpdateChecker.evaluateManifest(
          _manifest(),
          currentVersion: '3.6.0',
          packageName: pkg,
          runtimeAbi: 'arm64-v8a',
        );
        expect(r.hasUpdate, isFalse);
        expect(r.message, '__UPDATE_NOT_APPLICABLE__');
      }
    });

    test('manifest without a usable APK reports no APK found', () {
      final r = UpdateChecker.evaluateManifest(
        _manifest(apks: {
          'armeabi-v7a': {'url': 'x'}
        }),
        currentVersion: '3.6.0',
        packageName: 'com.tntlikely.beecount',
        runtimeAbi: 'arm64-v8a',
      );
      expect(r.hasUpdate, isFalse);
      expect(r.message, '__UPDATE_NO_APK_FOUND__');
    });

    test('version strings with v prefix / build suffix are normalized', () {
      final r = UpdateChecker.evaluateManifest(
        _manifest(version: 'v3.7.0+12'),
        currentVersion: '3.6.9',
        packageName: 'com.tntlikely.beecount',
        runtimeAbi: 'arm64-v8a',
      );
      expect(r.hasUpdate, isTrue);
      expect(r.version, '3.7.0');
    });
  });
}
