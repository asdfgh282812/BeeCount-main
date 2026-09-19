import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/ai/core/ai_extraction_context.dart';
import 'package:beecount/ai/core/ai_extraction_engine.dart';
import 'package:beecount/ai/core/bill_info.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/ai/ai_bookkeeper.dart';
import 'package:beecount/services/ai/ai_chat_service.dart';
import 'package:beecount/services/ai/free_chat_router.dart';
import 'package:beecount/services/billing/bill_creation_service.dart';

/// 本檔是本次修正的**端到端驗收測試**。
///
/// 回報的問題:「我復健科至今為止花了多少錢」答不出來。根因是
/// `AIChatService._isTransactionIntent` 用 `hasAmount || hasKeyword`,而關鍵字表
/// 含「花」,導致這句被判成記帳意圖送去做帳單提取,**完全沒走到查詢工具**。
/// 這裡從 `processMessage` 一路驗到查詢結果,確保整條鏈是通的。

class _NeverCalledEngine implements AiExtractionEngine {
  bool called = false;

  @override
  Future<List<BillInfo>> extractFromText(String text, AiExtractionContext ctx,
      {String billGuard = ''}) async {
    called = true;
    return const [];
  }

  @override
  Future<List<BillInfo>> extractFromImage(File image, AiExtractionContext ctx,
      {String billGuard = ''}) async {
    called = true;
    return const [];
  }

  @override
  Future<AudioExtractionResult> extractFromAudio(
    File audio,
    AiExtractionContext ctx,
  ) async {
    called = true;
    return const AudioExtractionResult();
  }

  @override
  Future<String?> speechToText(File audio) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;
  late int ledgerId;
  late int accountId;
  late int rehabCategoryId;
  late _NeverCalledEngine engine;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    ledgerId = await repo.createLedger(name: 'test');
    accountId = await repo.createAccount(ledgerId: ledgerId, name: '現金');
    rehabCategoryId = await repo.createCategory(name: '復健科', kind: 'expense');
    await repo.createCategory(name: '餐飲', kind: 'expense');
    engine = _NeverCalledEngine();

    // 跨越兩年多的 37 筆復健科支出,總額 18,400
    for (var i = 0; i < 36; i++) {
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: 500,
        categoryId: rehabCategoryId,
        accountId: accountId,
        happenedAt: DateTime(2024, 3, 2).add(Duration(days: i * 20)),
      );
    }
    await repo.addTransaction(
      ledgerId: ledgerId,
      type: 'expense',
      amount: 400,
      categoryId: rehabCategoryId,
      accountId: accountId,
      happenedAt: DateTime(2026, 9, 10),
    );
    // 一筆不相關的支出,確認沒有被算進去
    await repo.addTransaction(
      ledgerId: ledgerId,
      type: 'expense',
      amount: 99999,
      categoryId: await repo.createCategory(name: '房租', kind: 'expense'),
      accountId: accountId,
      happenedAt: DateTime(2026, 9, 11),
    );
  });

  tearDown(() async {
    await db.close();
  });

  AIChatService buildService(ChatFn chatFn) => AIChatService(
        repo: repo,
        bookkeeper: AiBookkeeper(
          repository: repo,
          engine: engine,
          persister: BillCreationService(repo),
        ),
        freeChatRouter: FreeChatRouter(
          repo: repo,
          chatFn: chatFn,
          now: () => DateTime(2026, 9, 18),
        ),
      );

  test('「我復健科至今為止花了多少錢」走到查詢工具,而不是記帳提取', () async {
    String? answerPrompt;
    final service = buildService((prompt, {systemPrompt}) async {
      if (answerPrompt == null && !prompt.contains('查到的資料')) {
        // 模型看到分類清單,選擇用 categoryName 精準查、且省略日期代表全部期間
        return '{"type":"tool_call","tool":"query_transactions",'
            '"params":{"categoryName":"復健科","limit":5}}';
      }
      answerPrompt = prompt;
      return '你從 2024 年 3 月到現在,在**復健科**總共花了 18,400 元,共 37 筆。';
    });

    final response = await service.processMessage(
      '我復健科至今為止花了多少錢',
      ledgerId: ledgerId,
    );

    expect(engine.called, isFalse, reason: '這句是查詢,絕不該走到帳單提取(這正是原本的 bug)');
    expect(response.type, 'text');
    expect(response.text, contains('18,400'));

    // 驗證餵給模型的資料本身是對的
    expect(answerPrompt, isNotNull);
    final json = jsonDecode(
      answerPrompt!.substring(
        answerPrompt!.indexOf('{'),
        answerPrompt!.lastIndexOf('}') + 1,
      ),
    ) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>;

    expect(data['matchedCount'], 37, reason: '總筆數必須涵蓋全部,不受 limit 影響');
    expect(data['totalExpense'], 18400.0, reason: '總額必須涵蓋全部,不受 limit 影響');
    expect((data['sample'] as Map)['transactions'], hasLength(5));
    expect((data['sample'] as Map)['isPartial'], isTrue);
    expect((data['range'] as Map)['allTime'], isTrue);
    expect((data['range'] as Map)['actualFirstDate'], '2024-03-02');
    expect((data['range'] as Map)['actualLastDate'], '2026-09-10');
  });

  test('用 keyword 問也能得到同樣的總額', () async {
    String? answerPrompt;
    final service = buildService((prompt, {systemPrompt}) async {
      if (answerPrompt == null && !prompt.contains('查到的資料')) {
        return '{"type":"tool_call","tool":"query_transactions",'
            '"params":{"keyword":["復健","复健"],"limit":0}}';
      }
      answerPrompt = prompt;
      return '總共 18,400 元';
    });

    await service.processMessage('復健總共花多少', ledgerId: ledgerId);

    expect(answerPrompt, contains('"totalExpense":18400.0'));
    expect(answerPrompt, contains('"matchedCount":37'));
  });

  test('記帳句仍然走記帳,沒有被新閘門弄壞', () async {
    final service = buildService((prompt, {systemPrompt}) async {
      fail('記帳句不該呼叫 LLM routing');
    });

    await service.processMessage('買了杯奶茶28塊', ledgerId: ledgerId);

    expect(engine.called, isTrue, reason: '記帳快路徑必須直接走提取');
  });
}
