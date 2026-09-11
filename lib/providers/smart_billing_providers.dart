import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/core/ai_project_assign_mode.dart';

/// 智能记账自动关联标签开关（默认开启）
final smartBillingAutoTagsProvider = StateProvider<bool>((ref) => true);

/// 智能记账自动添加附件开关（默认开启）
final smartBillingAutoAttachmentProvider = StateProvider<bool>((ref) => true);

/// AI 記帳「專案指定」模式(design 2026-09-11)。預設 none,保證升級後行為
/// 不變(見 [AiProjectAssignMode])。
final smartBillingProjectAssignModeProvider =
    StateProvider<AiProjectAssignMode>((ref) => AiProjectAssignMode.none);

/// 智能记账自动关联标签持久化初始化
final smartBillingAutoTagsInitProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getBool('smartBillingAutoTags');
  if (saved != null) {
    ref.read(smartBillingAutoTagsProvider.notifier).state = saved;
  }
  ref.listen<bool>(smartBillingAutoTagsProvider, (prev, next) async {
    await prefs.setBool('smartBillingAutoTags', next);
  });
});

/// 智能记账自动添加附件持久化初始化
final smartBillingAutoAttachmentInitProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getBool('smartBillingAutoAttachment');
  if (saved != null) {
    ref.read(smartBillingAutoAttachmentProvider.notifier).state = saved;
  }
  ref.listen<bool>(smartBillingAutoAttachmentProvider, (prev, next) async {
    await prefs.setBool('smartBillingAutoAttachment', next);
  });
});

/// AI 記帳專案指定模式持久化初始化
final smartBillingProjectAssignModeInitProvider =
    FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(kAiProjectAssignModeKey);
  if (saved != null) {
    final mode = AiProjectAssignMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => AiProjectAssignMode.none,
    );
    ref.read(smartBillingProjectAssignModeProvider.notifier).state = mode;
  }
  ref.listen<AiProjectAssignMode>(smartBillingProjectAssignModeProvider,
      (prev, next) async {
    await prefs.setString(kAiProjectAssignModeKey, next.name);
  });
});
