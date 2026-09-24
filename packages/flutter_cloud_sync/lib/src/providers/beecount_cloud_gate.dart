import 'package:http/http.dart' as http;

/// BeeCount Cloud 授權金鑰 + 最低可同步版本的 HTTP 共用層
/// (docs/changes/2026-09-25-license-key-and-min-sync-version.md)。
///
/// - 每個打到 BeeCount Cloud 的 HTTP 請求都帶 `X-App-Version`(server 用來擋
///   低於「最低可同步版本」的 App;舊版 App 沒帶這個 header,一律被視為過舊)。
/// - 任何回應是 402(沒有有效授權)/ 426(版本過舊)時通知 App 層,讓 App
///   立刻切到授權頁 / 強制更新頁,不用每個呼叫點各自判斷。
///
/// 用靜態欄位而不是建構子參數:auth / storage / realtime 三個 service 各自
/// 建 http.Client,App 層只需要在啟動時設定一次(`main.dart`)。
class BeeCountCloudClientGate {
  BeeCountCloudClientGate._();

  static const String appVersionHeader = 'X-App-Version';

  /// WebSocket 被 server 以「沒有授權」關閉時的 close code(見 server `routers/ws.py`)。
  static const int wsCloseLicenseRequired = 4402;

  /// WebSocket 被 server 以「App 版本過舊」關閉時的 close code。
  static const int wsCloseAppVersionTooOld = 4426;

  /// App 版本名稱(`PackageInfo.version`,例如 `3.6.0`,不含 build number)。
  /// null = 尚未設定,此時不帶 header(server 會當成舊版)。
  static String? appVersion;

  /// server 回 402 時呼叫。
  static void Function()? onLicenseRequired;

  /// server 回 426 時呼叫。
  static void Function()? onAppVersionTooOld;

  static void notifyStatus(int statusCode) {
    if (statusCode == 402) {
      onLicenseRequired?.call();
    } else if (statusCode == 426) {
      onAppVersionTooOld?.call();
    }
  }

  static void notifyWebSocketClose(int? closeCode) {
    if (closeCode == wsCloseLicenseRequired) {
      onLicenseRequired?.call();
    } else if (closeCode == wsCloseAppVersionTooOld) {
      onAppVersionTooOld?.call();
    }
  }
}

/// 包一層 http.Client:送出前補 `X-App-Version`,收到回應後檢查 402/426。
class BeeCountCloudGateHttpClient extends http.BaseClient {
  BeeCountCloudGateHttpClient([http.Client? inner])
      : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final version = BeeCountCloudClientGate.appVersion;
    if (version != null && version.isNotEmpty) {
      request.headers[BeeCountCloudClientGate.appVersionHeader] = version;
    }
    final response = await _inner.send(request);
    BeeCountCloudClientGate.notifyStatus(response.statusCode);
    return response;
  }

  @override
  void close() => _inner.close();
}
