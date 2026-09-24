import 'dart:convert';

import 'package:flutter_cloud_sync/flutter_cloud_sync.dart' hide SyncStatus;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../providers/sync_providers.dart';

/// 設定並啟用 BeeCount Cloud 伺服器位址的共用流程 —— 歡迎頁(新使用者引導)
/// 跟授權頁(既有使用者被要求改用 BeeCount Cloud 登入)都用這一份。

class BeeCountCloudServerSetupException implements Exception {
  const BeeCountCloudServerSetupException(this.invalidUrl, [this.cause]);

  /// true = 位址格式不對;false = 連不上 / server 沒開 SSO。
  final bool invalidUrl;
  final Object? cause;

  @override
  String toString() => 'BeeCountCloudServerSetupException(invalidUrl: $invalidUrl, cause: $cause)';
}

/// 歸一化使用者輸入的伺服器位址:沒帶 scheme 就補 https://,去掉結尾斜線。
String normalizeBeeCountCloudServerUrl(String raw) {
  var url = raw.trim();
  if (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'https://$url';
  }
  return url;
}

/// 探測 server 可達 + 確認有開 SSO,然後存檔並把同步後端切到 BeeCount Cloud。
/// 失敗抛 [BeeCountCloudServerSetupException]。
Future<void> configureBeeCountCloudServer(WidgetRef ref, String rawUrl) async {
  final url = normalizeBeeCountCloudServerUrl(rawUrl);
  if (url.isEmpty || Uri.tryParse(url)?.host.isEmpty != false) {
    throw const BeeCountCloudServerSetupException(true);
  }

  const apiPrefix = '/api/v1';
  try {
    // 探测可达性 + 确认 server 端真的开了 SSO（server 现成的
    // GET /auth/sso/status 端点，见 BeeCount-Cloud src/routers/auth.py）。
    final statusUri = Uri.parse('$url$apiPrefix/auth/sso/status');
    final resp = await http.get(statusUri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (body['sso_enabled'] != true) {
      throw Exception('sso_enabled=false');
    }
  } catch (e) {
    throw BeeCountCloudServerSetupException(false, e);
  }

  final cfg = CloudServiceConfig(
    type: CloudBackendType.beecountCloud,
    name: 'BeeCount Cloud',
    beecountCloudBaseUrl: url,
    beecountCloudApiPrefix: apiPrefix,
  );
  if (!cfg.valid) {
    throw const BeeCountCloudServerSetupException(true);
  }

  final store = ref.read(cloudServiceStoreProvider);
  await store.saveOnly(cfg);
  await store.activate(CloudBackendType.beecountCloud);
  ref.invalidate(beecountCloudConfigProvider);
  ref.invalidate(activeCloudConfigProvider);
  ref.invalidate(beecountCloudProviderInstance);
  ref.invalidate(authServiceProvider);
  ref.invalidate(syncServiceProvider);
}
