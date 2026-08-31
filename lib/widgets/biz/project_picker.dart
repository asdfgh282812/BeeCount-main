import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/repositories/project_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/data/category_service.dart';
import '../../styles/tokens.dart';
import '../../utils/currencies.dart' show getCurrencySymbol;

/// 記帳表單「選擇專案」的結果。`project == null` 代表明確選了「不指定專案」
/// (清空),跟 [ProjectPicker.show] 回傳頂層 `null`(使用者取消/滑動關閉,
/// 維持原本選擇不變)是兩回事——同 `AccountCardPicker`/`AccountPickResult`
/// 的慣例(design doc §6)。
class ProjectPickResult {
  final Project? project;
  const ProjectPickResult(this.project);
}

/// 交易新增/編輯頁的「選擇專案」單選 bottom sheet,比照 `AccountCardPicker`
/// 的 tap-to-pop 互動,只是專案沒有分組概念,是一個扁平清單。只列出啟用中
/// 的專案(已封存的不該再被指定給新交易)。
class ProjectPicker {
  static Future<ProjectPickResult?> show(
    BuildContext context, {
    required int ledgerId,
    String? selectedProjectSyncId,
  }) {
    return showModalBottomSheet<ProjectPickResult?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BeeTokens.surfaceSheet(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ProjectPickerSheet(
        ledgerId: ledgerId,
        selectedProjectSyncId: selectedProjectSyncId,
      ),
    );
  }
}

class _ProjectPickerSheet extends ConsumerStatefulWidget {
  final int ledgerId;
  final String? selectedProjectSyncId;

  const _ProjectPickerSheet({
    required this.ledgerId,
    this.selectedProjectSyncId,
  });

  @override
  ConsumerState<_ProjectPickerSheet> createState() =>
      _ProjectPickerSheetState();
}

class _ProjectPickerSheetState extends ConsumerState<_ProjectPickerSheet> {
  bool _loading = true;
  List<ProjectWithUsage> _projects = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(repositoryProvider);
    // 帶上花費統計(比照 moze):清單裡每個專案要能看到剩餘額度,不能只有
    // 名稱——同 [ProjectOverviewPage] 用的 `getAllProjectUsages`。
    final projects =
        await repo.getAllProjectUsages(widget.ledgerId, DateTime.now());
    if (!mounted) return;
    setState(() {
      _projects = projects;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);
    final currencyCode =
        ref.watch(currentLedgerProvider).asData?.value?.currency ?? 'CNY';
    final currencySymbol = getCurrencySymbol(currencyCode);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Text(
                    l10n.projectSelectTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.commonCancel),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: BeeTokens.surfaceElevated(context),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color:
                                      BeeTokens.cardOuterBorderColor(context)),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Material(
                              color: Colors.transparent,
                              child: _ProjectRow(
                                icon: Icons.block_outlined,
                                label: l10n.projectPickerNone,
                                isSelected:
                                    widget.selectedProjectSyncId == null,
                                primaryColor: primaryColor,
                                onTap: () => Navigator.pop(
                                    context, const ProjectPickResult(null)),
                              ),
                            ),
                          ),
                          if (_projects.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              decoration: BoxDecoration(
                                color: BeeTokens.surfaceElevated(context),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: BeeTokens.cardOuterBorderColor(
                                        context)),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Material(
                                color: Colors.transparent,
                                child: Column(
                                  children: [
                                    for (final entry in _projects.indexed) ...[
                                      if (entry.$1 > 0)
                                        Divider(
                                          height: 1,
                                          thickness: 1,
                                          color:
                                              BeeTokens.cardInnerDividerColor(
                                                  context),
                                        ),
                                      _ProjectRow(
                                        icon: CategoryService.getCategoryIcon(
                                            entry.$2.project.icon),
                                        label: entry.$2.project.name,
                                        quotaText: _quotaText(l10n,
                                            entry.$2.usage, currencySymbol),
                                        quotaColor: entry.$2.usage.remaining ==
                                                null
                                            ? BeeTokens.textTertiary(context)
                                            : (entry.$2.usage.remaining! >= 0
                                                ? Colors.green
                                                : Colors.red),
                                        isSelected: entry.$2.project.syncId !=
                                                null &&
                                            entry.$2.project.syncId ==
                                                widget.selectedProjectSyncId,
                                        primaryColor: primaryColor,
                                        onTap: () => Navigator.pop(
                                            context,
                                            ProjectPickResult(
                                                entry.$2.project)),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 24),
                            Center(
                              child: Text(
                                l10n.projectPickerEmptyHint,
                                style: TextStyle(
                                    color: BeeTokens.textTertiary(context)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 比照 moze 的專案清單:純記錄型專案顯示「純記錄」,有預算的顯示剩餘額度
  /// (同 [ProjectOverviewPage] 卡片用的 `budgetRemaining` 措辭,不重新發明
  /// 一套文案)。
  String _quotaText(
      AppLocalizations l10n, ProjectUsage usage, String currencySymbol) {
    final remaining = usage.remaining;
    if (remaining == null) return l10n.projectCardPureTracking;
    return '${l10n.budgetRemaining} $currencySymbol${remaining.toStringAsFixed(2)}';
  }
}

class _ProjectRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? quotaText;
  final Color? quotaColor;
  final bool isSelected;
  final Color primaryColor;
  final VoidCallback onTap;

  const _ProjectRow({
    required this.icon,
    required this.label,
    this.quotaText,
    this.quotaColor,
    required this.isSelected,
    required this.primaryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withValues(alpha: 0.12),
              ),
              child: Center(
                child: Icon(icon, size: 16, color: primaryColor),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: BeeTokens.textPrimary(context),
                ),
              ),
            ),
            if (quotaText != null) ...[
              const SizedBox(width: 8),
              Text(
                quotaText!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: quotaColor,
                ),
              ),
            ],
            if (isSelected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check, color: primaryColor, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}
