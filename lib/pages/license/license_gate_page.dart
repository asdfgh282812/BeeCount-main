import 'package:flutter/material.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart' hide SyncStatus;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/license/beecount_cloud_server_setup.dart';
import '../../services/system/logger_service.dart';
import '../auth/login_page.dart';
import 'license_key_form.dart';

/// 全螢幕授權門(docs/changes/2026-09-25-license-key-and-min-sync-version.md)。
///
/// `MainApp._getHomePage` 在 [licenseGateProvider] 不是 valid 時整個取代 `BeeApp`,
/// 所以這一頁之外沒有任何功能可以用。依狀態顯示:
/// - checking:正在確認
/// - needsLogin:輸入伺服器位址 → SSO 登入(沿用歡迎頁同一份流程)
/// - needsKey:輸入金鑰
/// - needsNetwork:超過 7 天沒連網驗證,要求連網後重試
///
/// 樣式跟歡迎頁一致(主題色底 + 白字),因為兩者都是「進 App 之前」的畫面。
class LicenseGatePage extends ConsumerStatefulWidget {
  const LicenseGatePage({super.key});

  @override
  ConsumerState<LicenseGatePage> createState() => _LicenseGatePageState();
}

class _LicenseGatePageState extends ConsumerState<LicenseGatePage> {
  final TextEditingController _serverCtrl = TextEditingController();
  bool _serverBusy = false;
  String? _serverError;

  /// needsLogin 時:false = 先輸入伺服器位址,true = 已設定好伺服器,顯示登入。
  bool _serverReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillServer());
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    super.dispose();
  }

  Future<void> _prefillServer() async {
    try {
      final active = await ref.read(activeCloudConfigProvider.future);
      final saved = await ref.read(beecountCloudConfigProvider.future);
      final url = saved?.beecountCloudBaseUrl;
      if (!mounted) return;
      if (url != null && url.isNotEmpty) _serverCtrl.text = url;
      // 已經是 BeeCount Cloud 模式(只是沒登入/登出了)就直接顯示登入,不用
      // 再問一次伺服器位址。
      setState(() => _serverReady = active.type == CloudBackendType.beecountCloud &&
          active.valid);
    } catch (_) {}
  }

  Future<void> _confirmServer() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _serverBusy = true;
      _serverError = null;
    });
    try {
      await configureBeeCountCloudServer(ref, _serverCtrl.text);
      if (!mounted) return;
      setState(() {
        _serverBusy = false;
        _serverReady = true;
      });
    } on BeeCountCloudServerSetupException catch (e) {
      logger.warning('License', '伺服器位址校验失败: ${_serverCtrl.text} ($e)');
      if (!mounted) return;
      setState(() {
        _serverBusy = false;
        _serverError = e.invalidUrl
            ? l10n.welcomeServerAddressInvalid
            : l10n.welcomeServerAddressUnreachable;
      });
    }
  }

  Future<void> _onLoggedIn() async {
    await ref.read(licenseGateProvider.notifier).refresh();
    // 版本門檻也跟著重查一次(剛設定好伺服器,之前可能拿不到門檻)。
    await ref.read(appVersionGateProvider.notifier).refresh();
  }

  Future<void> _signOut() async {
    try {
      final cloud = await ref.read(beecountCloudProviderInstance.future);
      await cloud?.auth.signOut();
    } catch (e) {
      logger.warning('License', '登出失败: $e');
    }
    await ref.read(licenseGateProvider.notifier).clearLocal();
    ref.invalidate(beecountCloudProviderInstance);
    ref.invalidate(authServiceProvider);
    ref.invalidate(syncServiceProvider);
    if (mounted) setState(() => _serverReady = true);
    await ref.read(licenseGateProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final gate = ref.watch(licenseGateProvider);

    final Widget body;
    switch (gate.status) {
      case LicenseGateStatus.checking:
      case LicenseGateStatus.valid:
        body = _buildChecking(theme, l10n);
      case LicenseGateStatus.needsLogin:
        body = _serverReady
            ? _buildLogin(theme, l10n)
            : _buildServerAddress(theme, l10n);
      case LicenseGateStatus.needsKey:
        body = _buildNeedsKey(theme, l10n, gate);
      case LicenseGateStatus.needsNetwork:
        body = _buildNeedsNetwork(theme, l10n, gate);
    }

    return Scaffold(
      backgroundColor: theme.primaryColor,
      body: SafeArea(child: body),
    );
  }

  Widget _header(ThemeData theme, IconData icon, String title, String desc) {
    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 64, color: Colors.white),
        ),
        const SizedBox(height: 32),
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          desc,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.9),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildChecking(ThemeData theme, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 16),
          Text(
            l10n.licenseCheckingText,
            style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildServerAddress(ThemeData theme, AppLocalizations l10n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          _header(theme, Icons.dns_outlined, l10n.licenseGateLoginTitle,
              l10n.licenseGateLoginDescription),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _serverCtrl,
              keyboardType: TextInputType.url,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: l10n.welcomeServerAddressHint,
                hintStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onSubmitted: (_) => _confirmServer(),
            ),
          ),
          if (_serverError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _serverError!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _serverBusy ? null : _confirmServer,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: theme.primaryColor,
              ),
              child: _serverBusy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.welcomeServerAddressButton),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogin(ThemeData theme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
      child: Column(
        children: [
          _header(theme, Icons.login, l10n.licenseGateLoginTitle,
              l10n.licenseGateLoginDescription),
          const SizedBox(height: 16),
          // 跟歡迎頁一樣內嵌 AuthPage,登入成功後重新確認授權。
          Expanded(child: AuthPage(onLoggedIn: _onLoggedIn)),
          TextButton(
            onPressed: () => setState(() => _serverReady = false),
            child: Text(
              l10n.welcomeServerAddressTitle,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNeedsKey(
      ThemeData theme, AppLocalizations l10n, LicenseGateState gate) {
    final expired = gate.expiresAt;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(
            theme,
            Icons.vpn_key_outlined,
            l10n.licenseGateTitle,
            expired != null
                ? l10n.licenseGateExpiredOn(formatLicenseDate(expired))
                : l10n.licenseGateDescription,
          ),
          const SizedBox(height: 32),
          const LicenseKeyForm(),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _signOut,
            child: Text(
              l10n.licenseSwitchAccountButton,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNeedsNetwork(
      ThemeData theme, AppLocalizations l10n, LicenseGateState gate) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(theme, Icons.wifi_off_outlined, l10n.licenseGateNetworkTitle,
              l10n.licenseGateNetworkDescription),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: gate.busy
                ? null
                : () => ref.read(licenseGateProvider.notifier).refresh(),
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
                : Text(l10n.licenseRetryButton),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _signOut,
            child: Text(
              l10n.licenseSwitchAccountButton,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
