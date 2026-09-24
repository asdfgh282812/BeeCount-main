import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/license_providers.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/biz.dart';
import '../../widgets/ui/ui.dart';
import 'license_key_form.dart';

/// 我的 → 授權金鑰:查看目前授權到期日、離線可用期限,輸入新金鑰延長授權
/// (docs/changes/2026-09-25-license-key-and-min-sync-version.md)。
class LicenseSettingsPage extends ConsumerStatefulWidget {
  const LicenseSettingsPage({super.key});

  @override
  ConsumerState<LicenseSettingsPage> createState() =>
      _LicenseSettingsPageState();
}

class _LicenseSettingsPageState extends ConsumerState<LicenseSettingsPage> {
  @override
  void initState() {
    super.initState();
    // 進來就跟 server 對一次,顯示最新到期日。
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(licenseGateProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gate = ref.watch(licenseGateProvider);
    final textStyle = TextStyle(color: BeeTokens.textPrimary(context));
    final secondaryStyle = TextStyle(
      color: BeeTokens.textSecondary(context),
      fontSize: 13,
    );

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(title: l10n.licenseSettingsTitle, showBack: true),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(
                top: 8.0.scaled(context, ref),
                bottom: 16.0.scaled(context, ref),
              ),
              children: [
                SectionCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (gate.exempt)
                          Text(l10n.licenseSettingsExempt, style: textStyle)
                        else if (gate.expiresAt != null)
                          Text(
                            l10n.licenseSettingsExpiresAt(
                                formatLicenseDate(gate.expiresAt!)),
                            style: textStyle,
                          ),
                        if (gate.verifiedUntil != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            l10n.licenseSettingsOfflineUntil(
                                formatLicenseDate(gate.verifiedUntil!)),
                            style: secondaryStyle,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (!gate.exempt) ...[
                  SizedBox(height: 8.0.scaled(context, ref)),
                  SectionCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(l10n.licenseSettingsExtendHint,
                              style: secondaryStyle),
                          const SizedBox(height: 12),
                          const LicenseKeyForm(onPrimaryBackground: false),
                        ],
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
