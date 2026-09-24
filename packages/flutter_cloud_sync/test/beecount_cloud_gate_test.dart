import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(() {
    BeeCountCloudClientGate.appVersion = null;
    BeeCountCloudClientGate.onLicenseRequired = null;
    BeeCountCloudClientGate.onAppVersionTooOld = null;
  });

  test('adds X-App-Version to every request', () async {
    String? seen;
    final client = BeeCountCloudGateHttpClient(MockClient((req) async {
      seen = req.headers['X-App-Version'];
      return http.Response('{}', 200);
    }));
    BeeCountCloudClientGate.appVersion = '3.6.0';
    await client.get(Uri.parse('https://example.com/api/v1/sync/ledgers'));
    expect(seen, '3.6.0');
  });

  test('402 and 426 notify the app layer', () async {
    var license = 0;
    var version = 0;
    BeeCountCloudClientGate.onLicenseRequired = () => license++;
    BeeCountCloudClientGate.onAppVersionTooOld = () => version++;
    for (final code in [200, 401, 402, 426]) {
      final client = BeeCountCloudGateHttpClient(
          MockClient((_) async => http.Response('{}', code)));
      await client.get(Uri.parse('https://example.com/x'));
    }
    expect(license, 1);
    expect(version, 1);
    BeeCountCloudClientGate.notifyWebSocketClose(4402);
    BeeCountCloudClientGate.notifyWebSocketClose(4426);
    BeeCountCloudClientGate.notifyWebSocketClose(1000);
    expect(license, 2);
    expect(version, 2);
  });

  test('license status json', () {
    final s = BeeCountCloudLicenseStatus.fromJson({
      'user_id': 'u',
      'licensed': true,
      'exempt': false,
      'expires_at': '2027-09-25T00:00:00Z',
      'server_time': '2026-09-25T00:00:00Z',
      'offline_grace_days': 7,
    });
    expect(s.licensed, isTrue);
    expect(s.expiresAt, DateTime.utc(2027, 9, 25));
    expect(s.offlineGraceDays, 7);
    expect(
        BeeCountCloudLatestAppVersion.fromJson({'version': '3.6.0', 'min_sync_version': ''})
            .minSyncVersion,
        isNull);
  });
}
