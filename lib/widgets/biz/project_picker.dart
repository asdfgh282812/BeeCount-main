import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/data/category_service.dart';
import '../../styles/tokens.dart';

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
  List<Project> _projects = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(repositoryProvider);
    final projects = await repo.getAllProjects(widget.ledgerId);
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
                                  color: BeeTokens.cardOuterBorderColor(
                                      context)),
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
                                    for (final entry
                                        in _projects.indexed) ...[
                                      if (entry.$1 > 0)
                                        Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: BeeTokens.cardInnerDividerColor(
                                              context),
                                        ),
                                      _ProjectRow(
                                        icon: CategoryService.getCategoryIcon(
                                            entry.$2.icon),
                                        label: entry.$2.name,
                                        isSelected: entry.$2.syncId != null &&
                                            entry.$2.syncId ==
                                                widget.selectedProjectSyncId,
                                        primaryColor: primaryColor,
                                        onTap: () => Navigator.pop(context,
                                            ProjectPickResult(entry.$2)),
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
}

class _ProjectRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final Color primaryColor;
  final VoidCallback onTap;

  const _ProjectRow({
    required this.icon,
    required this.label,
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
