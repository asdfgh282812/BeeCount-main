import 'package:beecount/providers/license_providers.dart';
import 'package:beecount/services/license/license_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 25, 12);

  LicenseCache verify({
    DateTime? expiresAt,
    DateTime? serverTime,
    bool exempt = false,
    DateTime? at,
  }) =>
      LicenseCache.fromVerification(
        serverKey: 'https://s/api/v1',
        userId: 'u1',
        now: at ?? now,
        serverTime: serverTime ?? at ?? now,
        offlineGraceDays: 7,
        exempt: exempt,
        licenseExpiresAt: expiresAt,
      );

  group('LicenseCache offline grace', () {
    test('valid for 7 days after a successful check', () {
      final cache = verify(expiresAt: now.add(const Duration(days: 300)));
      expect(cache.verifiedUntil, now.add(const Duration(days: 7)));
      bool ok(DateTime t) =>
          cache.isValidAt(t, serverKey: 'https://s/api/v1', userId: 'u1');
      expect(ok(now.add(const Duration(days: 6, hours: 23))), isTrue);
      expect(ok(now.add(const Duration(days: 7, seconds: 1))), isFalse);
    });

    test('never extends past the key expiry', () {
      final cache = verify(expiresAt: now.add(const Duration(days: 2)));
      expect(cache.verifiedUntil, now.add(const Duration(days: 2)));
    });

    test('key expiry is measured against server time, not device clock', () {
      // 裝置時鐘快了 1 天,server 說還剩 3 天 → 本地仍然只給 3 天
      final device = now.add(const Duration(days: 1));
      final cache = verify(
        at: device,
        serverTime: now,
        expiresAt: now.add(const Duration(days: 3)),
      );
      expect(cache.verifiedUntil, device.add(const Duration(days: 3)));
    });

    test('exempt admin gets the full grace period', () {
      final cache = verify(exempt: true);
      expect(cache.verifiedUntil, now.add(const Duration(days: 7)));
    });

    test('bound to server and user', () {
      final cache = verify(expiresAt: now.add(const Duration(days: 300)));
      expect(cache.isValidAt(now, serverKey: 'https://other/api/v1', userId: 'u1'),
          isFalse);
      expect(cache.isValidAt(now, serverKey: 'https://s/api/v1', userId: 'u2'),
          isFalse);
    });

    test('clock rollback invalidates the cache', () {
      final cache = verify(expiresAt: now.add(const Duration(days: 300)))
          .copyWithSeen(now.add(const Duration(days: 6)));
      bool ok(DateTime t) =>
          cache.isValidAt(t, serverKey: 'https://s/api/v1', userId: 'u1');
      // 往回調 5 分鐘在容忍範圍內
      expect(ok(now.add(const Duration(days: 6)).subtract(const Duration(minutes: 5))),
          isTrue);
      // 往回調一天想延長離線期限 → 失效
      expect(ok(now.add(const Duration(days: 5))), isFalse);
    });

    test('json round trip', () {
      final cache = verify(expiresAt: now.add(const Duration(days: 30)));
      final back = LicenseCache.fromJson(cache.toJson())!;
      expect(back.verifiedUntil, cache.verifiedUntil);
      expect(back.licenseExpiresAt, cache.licenseExpiresAt);
      expect(back.userId, 'u1');
      expect(LicenseCache.fromJson({'userId': 'x'}), isNull);
    });
  });

  group('app version compare', () {
    test('parse', () {
      expect(parseAppVersion('3.6.0'), [3, 6, 0]);
      expect(parseAppVersion('3.6.0+2'), [3, 6, 0]);
      expect(parseAppVersion('v3.6'), isNull);
    });

    test('below', () {
      expect(isAppVersionBelow('3.5.7', '3.6.0'), isTrue);
      expect(isAppVersionBelow('3.6.0', '3.6.0'), isFalse);
      expect(isAppVersionBelow('3.6', '3.6.0'), isFalse);
      expect(isAppVersionBelow('3.10.0', '3.9.9'), isFalse);
      expect(isAppVersionBelow('garbage', '3.6.0'), isFalse);
    });

    test('gate state blocked', () {
      expect(
          const AppVersionGateState(currentVersion: '3.5.7', minSyncVersion: '3.6.0')
              .blocked,
          isTrue);
      expect(const AppVersionGateState(currentVersion: '3.5.7').blocked, isFalse);
    });
  });
}
