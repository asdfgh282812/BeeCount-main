import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart' hide SyncStatus;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/license_providers.dart';
import '../../widgets/ui/ui.dart';

String formatLicenseDate(DateTime date) =>
    DateFormat('yyyy-MM-dd').format(date.toLocal());

/// 授權金鑰輸入表單 —— 授權頁、歡迎頁引導、「我的 → 授權金鑰」共用。
///
/// [onPrimaryBackground] = true 時用白字白框(授權頁/歡迎頁的主題色底),
/// false 時用一般表單樣式(設定頁)。
class LicenseKeyForm extends ConsumerStatefulWidget {
  const LicenseKeyForm({
    super.key,
    this.onActivated,
    this.onPrimaryBackground = true,
  });

  final VoidCallback? onActivated;
  final bool onPrimaryBackground;

  @override
  ConsumerState<LicenseKeyForm> createState() => _LicenseKeyFormState();
}

class _LicenseKeyFormState extends ConsumerState<LicenseKeyForm> {
  final TextEditingController _keyCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  String _messageFor(Object error, AppLocalizations l10n) {
    if (error is BeeCountCloudLicenseException) {
      switch (error.errorCode) {
        case 'LICENSE_KEY_INVALID':
          return l10n.licenseErrorInvalid;
        case 'LICENSE_KEY_NOT_FOUND':
          return l10n.licenseErrorNotFound;
        case 'LICENSE_KEY_ALREADY_REDEEMED':
          return l10n.licenseErrorAlreadyRedeemed;
        case 'LICENSE_KEY_REVOKED':
          return l10n.licenseErrorRevoked;
        case 'RATE_LIMITED':
          return l10n.licenseErrorRateLimited;
      }
      return l10n.licenseErrorGeneric(error.message);
    }
    if (error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException) {
      return l10n.licenseErrorNetwork;
    }
    return l10n.licenseErrorGeneric('$error');
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() => _error = l10n.licenseErrorEmpty);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(licenseGateProvider.notifier).activate(key);
      if (!mounted) return;
      final expiresAt = ref.read(licenseGateProvider).expiresAt;
      setState(() => _busy = false);
      _keyCtrl.clear();
      if (expiresAt != null) {
        showToast(context, l10n.licenseActivatedToast(formatLicenseDate(expiresAt)));
      }
      widget.onActivated?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(e, l10n);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final onPrimary = widget.onPrimaryBackground;

    final field = TextField(
      controller: _keyCtrl,
      enabled: !_busy,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.characters,
      style: TextStyle(
        color: onPrimary ? Colors.white : null,
        fontFamily: 'monospace',
        letterSpacing: 1,
      ),
      decoration: InputDecoration(
        labelText: onPrimary ? null : l10n.licenseKeyLabel,
        hintText: l10n.licenseKeyHint,
        hintStyle: onPrimary
            ? TextStyle(color: Colors.white.withValues(alpha: 0.5))
            : null,
        border: onPrimary ? InputBorder.none : const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      onSubmitted: (_) => _submit(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onPrimary)
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: field,
          )
        else
          field,
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: onPrimary
                  ? const TextStyle(color: Colors.white)
                  : TextStyle(color: theme.colorScheme.error),
              textAlign: onPrimary ? TextAlign.center : TextAlign.start,
            ),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: onPrimary
              ? FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: theme.primaryColor,
                )
              : null,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.licenseActivateButton),
        ),
      ],
    );
  }
}
