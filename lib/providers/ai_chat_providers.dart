import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:collection/collection.dart';

import '../ai/core/ai_extraction_engine.dart';
import '../services/ai/ai_bookkeeper.dart';
import '../services/ai/ai_chat_service.dart';
import '../services/billing/bill_creation_service.dart';
import '../providers.dart';
import '../data/db.dart';

/// AI 多模态记账底座 (Layer 1)。无状态,可全局复用。
final aiExtractionEngineProvider = Provider<AiExtractionEngine>(
  (ref) => const DefaultAiExtractionEngine(),
);

/// AI 记账应用层 (Layer 2)。5 个调用渠道(对话/图片/语音/自动截图/自动文本)
/// 的统一入口。
final aiBookkeeperProvider = Provider<AiBookkeeper>((ref) {
  final repo = ref.watch(repositoryProvider);
  return AiBookkeeper(
    repository: repo,
    engine: ref.watch(aiExtractionEngineProvider),
    persister: BillCreationService(
      repo,
      // 多币种(.docs/multi-currency-ai A6):AI 识别出外币时,落库前把该币种
      // 的汇率拉到本地,否则 repo 只能按 1:1 折算。注入而非在渠道层预拉,是
      // 为了让**后台自动记账**(截图/通知,无 WidgetRef)也走同一条路径。
      ensureRate: (code) =>
          refreshExchangeRates(ref, force: true, extraQuotes: {code}),
      // 信用卡回饋規則自動比對(design 2026-09-18 §5.3):查 SwipeSmart 該帳戶
      // 的推薦規則名稱,注入而非在渠道層打,同樣是為了背景自動記账也能複用。
      recommendRewardRuleName: (
              {required ledgerId,
              required accountId,
              required amount,
              required merchant}) =>
          _recommendRewardRuleName(
        ref,
        ledgerId: ledgerId,
        accountId: accountId,
        amount: amount,
        merchant: merchant,
      ),
    ),
  );
});

/// [RecommendRewardRuleName] 的實作:查該帳本 SwipeSmart 建議清單,挑出「已
/// 對照到這次本地帳戶」的那一筆,回傳其規則名稱文字。任何例外(沒連 Key、
/// 逾時、網路錯誤)一律 catch 後回傳 null,跟手動表單
/// `_fetchRecommendation` 的降級哲學一致,不影響記帳本身。
Future<String?> _recommendRewardRuleName(
  Ref ref, {
  required int ledgerId,
  required int accountId,
  required double amount,
  required String merchant,
}) async {
  try {
    final cloud = await ref.read(beecountCloudProviderInstance.future);
    if (cloud == null) return null;

    final db = ref.read(databaseProvider);
    final ledger = await (db.select(db.ledgers)
          ..where((l) => l.id.equals(ledgerId)))
        .getSingleOrNull();
    final serverLedgerId = ledger?.syncId ?? ledgerId.toString();

    final account = await (db.select(db.accounts)
          ..where((a) => a.id.equals(accountId)))
        .getSingleOrNull();
    final accountSyncId = account?.syncId;
    if (accountSyncId == null) return null;

    final results = await cloud.getCardRecommendation(
      ledgerId: serverLedgerId,
      amount: amount,
      merchant: merchant,
    );
    final matched =
        results.firstWhereOrNull((r) => r.accountId == accountSyncId);
    return matched?.ruleName;
  } catch (_) {
    return null;
  }
}

/// AI 对话服务 Provider
final aiChatServiceProvider = Provider<AIChatService>((ref) {
  final repo = ref.watch(repositoryProvider);
  return AIChatService(
    repo: repo,
    bookkeeper: ref.watch(aiBookkeeperProvider),
  );
});

/// 当前对话 ID Provider
final currentConversationIdProvider = StateProvider<int?>((ref) => null);

/// 消息列表 Provider
final messagesProvider = StreamProvider.family<List<Message>, int>(
  (ref, conversationId) {
    final repo = ref.watch(repositoryProvider);
    return repo.watchMessages(conversationId);
  },
);
