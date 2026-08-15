import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db.dart';
import 'database_providers.dart';

/// 某信用卡帐户下的全部紅利回饋規則(含已停用),按 sortOrder 排序。
/// list 頁 + 記帳表單的回饋選單共用同一個 provider,底层 Drift watch 流,
/// 資料變動自動 rebuild,不需要额外的 refresh trigger。
final cardRewardRulesForAccountProvider =
    StreamProvider.family<List<CardRewardRule>, int>((ref, accountId) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchCardRewardRulesForAccount(accountId);
});

/// 單一紅利回饋規則詳情(编辑页回填用)。
final cardRewardRuleByIdProvider =
    FutureProvider.family<CardRewardRule?, int>((ref, id) async {
  final repo = ref.watch(repositoryProvider);
  return repo.getCardRewardRuleById(id);
});
