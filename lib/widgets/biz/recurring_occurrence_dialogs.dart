import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';

/// 編輯/刪除一筆「週期規則生成的 occurrence」時,MOZE 對標的二選一彈窗——
/// 「此記錄」vs「連同未來週期」。只在 `Transaction.recurringRuleId != null`
/// 時才需要呼叫;純本地一次性交易走原本的編輯/刪除流程,不受影響。
enum RecurringEditScope { thisOnly, thisAndFuture }

enum RecurringDeleteScope { thisOnly, thisAndFuture }

Future<RecurringEditScope?> showRecurringEditChoiceSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return _showChoiceSheet<RecurringEditScope>(
    context,
    title: l10n.recurringEditChoiceTitle,
    options: [
      (
        label: l10n.recurringEditChoiceThisOnly,
        value: RecurringEditScope.thisOnly,
        destructive: false,
      ),
      (
        label: l10n.recurringEditChoiceThisAndFuture,
        value: RecurringEditScope.thisAndFuture,
        destructive: false,
      ),
    ],
  );
}

Future<RecurringDeleteScope?> showRecurringDeleteChoiceSheet(
    BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return _showChoiceSheet<RecurringDeleteScope>(
    context,
    title: l10n.recurringDeleteChoiceTitle,
    options: [
      (
        label: l10n.recurringDeleteChoiceThisOnly,
        value: RecurringDeleteScope.thisOnly,
        destructive: true,
      ),
      (
        label: l10n.recurringDeleteChoiceThisAndFuture,
        value: RecurringDeleteScope.thisAndFuture,
        destructive: true,
      ),
    ],
  );
}

Future<T?> _showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<({String label, T value, bool destructive})> options,
}) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: BeeTokens.surfaceSheet(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: BeeTokens.divider(ctx),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: BeeTokens.textSecondary(ctx),
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final o in options)
            ListTile(
              title: Text(
                o.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: o.destructive
                      ? BeeTokens.error(ctx)
                      : BeeTokens.textPrimary(ctx),
                ),
              ),
              onTap: () => Navigator.pop(ctx, o.value),
            ),
          const Divider(height: 1),
          ListTile(
            title: Text(
              l10n.commonCancel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: BeeTokens.textSecondary(ctx),
              ),
            ),
            onTap: () => Navigator.pop(ctx),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}
