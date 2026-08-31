import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../models/merchant_history.dart';
import '../../services/data/merchant_history_service.dart';
import '../../styles/tokens.dart';
import '../../providers.dart';

/// 商家選擇彈窗——跟 [NotePickerDialog](note_picker_dialog.dart) 同款版面,
/// 但沒有 scope/sort 設定(商家歷史恆依分類過濾、恆按使用次數排序)。
class MerchantPickerDialog extends ConsumerStatefulWidget {
  final int ledgerId;
  final int? categoryId;
  final String? categorySyncId;
  final ValueChanged<String> onMerchantPicked;

  const MerchantPickerDialog({
    super.key,
    required this.ledgerId,
    this.categoryId,
    this.categorySyncId,
    required this.onMerchantPicked,
  });

  @override
  ConsumerState<MerchantPickerDialog> createState() =>
      _MerchantPickerDialogState();
}

class _MerchantPickerDialogState extends ConsumerState<MerchantPickerDialog> {
  List<MerchantHistoryEntry> _merchants = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMerchants();
  }

  Future<void> _loadMerchants() async {
    try {
      final repo = ref.read(repositoryProvider);
      final merchants = await MerchantHistoryService.getHistoryMerchants(
        repository: repo,
        ledgerId: widget.ledgerId,
        categoryId: widget.categoryId,
        categorySyncId: widget.categorySyncId,
      );
      if (!mounted) return;
      setState(() {
        _merchants = merchants;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      backgroundColor: BeeTokens.surfaceElevated(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.appearanceMerchantHistory,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: BeeTokens.textPrimary(context)),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              )
            else if (_merchants.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.commonEmpty,
                  style: TextStyle(color: BeeTokens.textSecondary(context)),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _merchants.map((item) {
                      return InkWell(
                        onTap: () {
                          widget.onMerchantPicked(item.merchant);
                          Navigator.pop(context);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: BeeTokens.surfaceChip(context),
                            borderRadius: BorderRadius.circular(16),
                            border: BeeTokens.isDark(context)
                                ? Border.all(color: BeeTokens.border(context))
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.merchant,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: BeeTokens.textSecondary(context),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${item.usageCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(l10n.commonClose),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
