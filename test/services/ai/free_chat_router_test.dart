import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/ai/free_chat_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;
  late int ledgerId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    ledgerId = await repo.createLedger(name: 'test');
  });

  tearDown(() async {
    await db.close();
  });

  test('type=answer 直接回傳,不呼叫工具', () async {
    var callCount = 0;
    final router = FreeChatRouter(
      repo: repo,
      chatFn: (prompt, {systemPrompt}) async {
        callCount++;
        return '{"type":"answer","text":"你好,有什麼可以幫你"}';
      },
      now: () => DateTime(2026, 9, 8),
    );

    final result = await router.route('哈囉', ledgerId: ledgerId);

    expect(result, '你好,有什麼可以幫你');
    expect(callCount, 1);
  });

  test('type=tool_call 完整跑完兩階段,工具結果帶進第二次呼叫的 prompt', () async {
    final prompts = <String>[];
    final router = FreeChatRouter(
      repo: repo,
      chatFn: (prompt, {systemPrompt}) async {
        prompts.add(prompt);
        if (prompts.length == 1) {
          return '{"type":"tool_call","tool":"get_spending_summary",'
              '"params":{"startDate":"2026-09-01","endDate":"2026-09-08"}}';
        }
        return '你這個月花了 0 元';
      },
      now: () => DateTime(2026, 9, 8),
    );

    final result = await router.route('這個月花多少', ledgerId: ledgerId);

    expect(result, '你這個月花了 0 元');
    expect(prompts, hasLength(2));
    expect(prompts[1], contains('查到的資料'));
    expect(prompts[1], contains('"income":0.0'));
  });

  test('routing 回應解析不出 JSON 時降級為原始文字,不視為錯誤', () async {
    final router = FreeChatRouter(
      repo: repo,
      chatFn: (prompt, {systemPrompt}) async => '這是一段沒有 JSON 的純文字回覆',
      now: () => DateTime(2026, 9, 8),
    );

    final result = await router.route('嗨', ledgerId: ledgerId);

    expect(result, '這是一段沒有 JSON 的純文字回覆');
  });

  test('tool 欄位不是已知工具名時降級為原始文字', () async {
    const rawResponse =
        '{"type":"tool_call","tool":"delete_everything","params":{}}';
    final router = FreeChatRouter(
      repo: repo,
      chatFn: (prompt, {systemPrompt}) async => rawResponse,
      now: () => DateTime(2026, 9, 8),
    );

    final result = await router.route('嗨', ledgerId: ledgerId);

    expect(result, rawResponse);
  });

  test('工具執行拋出例外時回傳固定文案,不再呼叫 LLM 第二次', () async {
    var callCount = 0;
    final router = FreeChatRouter(
      repo: repo,
      chatFn: (prompt, {systemPrompt}) async {
        callCount++;
        // 缺少必填的 startDate/endDate,executor 會拋 FreeChatToolException
        return '{"type":"tool_call","tool":"get_spending_summary","params":{}}';
      },
      now: () => DateTime(2026, 9, 8),
    );

    final result = await router.route('花多少', ledgerId: ledgerId);

    expect(result, contains('暫時處理不了'));
    expect(callCount, 1);
  });

  test('conversationId 為 null 時歷史為空陣列,流程仍可運作', () async {
    final router = FreeChatRouter(
      repo: repo,
      chatFn: (prompt, {systemPrompt}) async =>
          '{"type":"answer","text":"沒問題"}',
      now: () => DateTime(2026, 9, 8),
    );

    final result =
        await router.route('哈囉', ledgerId: ledgerId, conversationId: null);

    expect(result, '沒問題');
  });

  test('歷史紀錄會帶進 routing prompt,且不重複當前這句輸入', () async {
    final conversationId =
        await repo.createConversation(const ConversationsCompanion());
    // 顯式遞增 createdAt(同 ai_chat_page.dart 實際寫法:每次都帶
    // `Value(DateTime.now())`),避免表定義的 SQL 預設值(秒級精度)在同一秒
    // 內插入多筆時打平順序,讓「最後一則」判斷失真。
    await repo.createMessage(MessagesCompanion.insert(
      conversationId: conversationId,
      role: 'user',
      content: '這個月餐飲花多少',
      messageType: 'text',
      createdAt: Value(DateTime(2026, 9, 8, 10, 0, 0)),
    ));
    await repo.createMessage(MessagesCompanion.insert(
      conversationId: conversationId,
      role: 'assistant',
      content: '您這個月餐飲支出 100 元',
      messageType: 'text',
      createdAt: Value(DateTime(2026, 9, 8, 10, 0, 1)),
    ));
    // 頁面在呼叫 processMessage 前已把當前這句存進 Messages 表,
    // router 拿到歷史時這句已經在裡面了。
    await repo.createMessage(MessagesCompanion.insert(
      conversationId: conversationId,
      role: 'user',
      content: '那預算呢',
      messageType: 'text',
      createdAt: Value(DateTime(2026, 9, 8, 10, 0, 2)),
    ));

    String? capturedPrompt;
    final router = FreeChatRouter(
      repo: repo,
      chatFn: (prompt, {systemPrompt}) async {
        capturedPrompt ??= prompt;
        return '{"type":"answer","text":"預算還剩 500 元"}';
      },
      now: () => DateTime(2026, 9, 8),
    );

    await router.route('那預算呢',
        ledgerId: ledgerId, conversationId: conversationId);

    expect(capturedPrompt, isNotNull);
    expect(
      '那預算呢'.allMatches(capturedPrompt!).length,
      1,
      reason: '當前輸入不應該在歷史紀錄裡重複出現',
    );
    expect(capturedPrompt, contains('這個月餐飲花多少'));
    expect(capturedPrompt, contains('您這個月餐飲支出 100 元'));
  });
}
