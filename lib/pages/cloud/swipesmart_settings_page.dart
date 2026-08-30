import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/sync_providers.dart';
import '../../styles/tokens.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import 'swipesmart_card_mapping_page.dart';

/// SwipeSmart Personal API Key 連接設定頁(design doc 2026-08-30 §2)。
///
/// 不在本機持久化明文 Key —— server 端加密存放且 GET 永遠不回明文,這個頁面
/// 只是一個表單去呼叫 Cloud 現成的三支 REST 端點。
class SwipeSmartSettingsPage extends ConsumerStatefulWidget {
  const SwipeSmartSettingsPage({super.key});

  @override
  ConsumerState<SwipeSmartSettingsPage> createState() =>
      _SwipeSmartSettingsPageState();
}

class _SwipeSmartSettingsPageState
    extends ConsumerState<SwipeSmartSettingsPage> {
  final _apiKeyController = TextEditingController();
  bool _obscureApiKey = true;
  bool _loading = true;
  bool _saving = false;
  bool _hasKey = false;
  String? _masked;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() => _loading = true);
    try {
      final cloud = await ref.read(beecountCloudProviderInstance.future);
      if (cloud == null) {
        setState(() => _loading = false);
        return;
      }
      final status = await cloud.getSwipeSmartKeyStatus();
      if (!mounted) return;
      setState(() {
        _hasKey = status.hasKey;
        _masked = status.masked;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, '$e');
    }
  }

  Future<void> _connect() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) return;
    setState(() => _saving = true);
    try {
      final cloud = await ref.read(beecountCloudProviderInstance.future);
      if (cloud == null) {
        setState(() => _saving = false);
        return;
      }
      final status = await cloud.setSwipeSmartKey(apiKey);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() {
        _hasKey = status.hasKey;
        _masked = status.masked;
        _saving = false;
      });
      _apiKeyController.clear();
      if (status.autoMapped > 0) {
        showToast(context, l10n.swipesmartAutoMapped(status.autoMapped));
      } else {
        showToast(context, l10n.commonSaved);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, '$e');
    }
  }

  Future<void> _disconnect() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialog.confirm<bool>(
      context,
      title: l10n.swipesmartDisconnect,
      message: l10n.swipesmartDisconnectConfirm,
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final cloud = await ref.read(beecountCloudProviderInstance.future);
      if (cloud == null) {
        setState(() => _saving = false);
        return;
      }
      await cloud.deleteSwipeSmartKey();
      if (!mounted) return;
      setState(() {
        _hasKey = false;
        _masked = null;
        _saving = false;
      });
      showToast(context, l10n.commonSaved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.swipesmartSettingsTitle,
            subtitle: l10n.swipesmartSettingsSubtitle,
            showBack: true,
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _hasKey
                                  ? l10n.swipesmartConnected(_masked ?? '')
                                  : l10n.swipesmartNotConnected,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: BeeTokens.textPrimary(context),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _apiKeyController,
                              obscureText: _obscureApiKey,
                              decoration: InputDecoration(
                                hintText: l10n.swipesmartApiKeyHint,
                                border: const OutlineInputBorder(),
                                isDense: true,
                                suffixIcon: IconButton(
                                  icon: Icon(_obscureApiKey
                                      ? Icons.visibility_off
                                      : Icons.visibility),
                                  onPressed: () => setState(
                                      () => _obscureApiKey = !_obscureApiKey),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _saving ? null : _connect,
                                    child: Text(l10n.swipesmartConnect),
                                  ),
                                ),
                                if (_hasKey) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _saving ? null : _disconnect,
                                      child: Text(l10n.swipesmartDisconnect),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (_hasKey) ...[
                        const SizedBox(height: 8),
                        SectionCard(
                          child: AppListTile(
                            leading: Icons.credit_card,
                            title: l10n.swipesmartCardMapping,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const SwipeSmartCardMappingPage(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
