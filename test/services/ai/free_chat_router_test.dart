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

    final result = _answerText(await router.route('哈囉', ledgerId: ledgerId));

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

    final result =
        _answerText(await router.route('這個月花多少', ledgerId: ledgerId));

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

    final result = _answerText(await router.route('嗨', ledgerId: ledgerId));

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

    final result = _answerText(await router.route('嗨', ledgerId: ledgerId));

    expect(result, rawResponse);
  });

  test('工具執行拋出例外時回傳固定文案,不再呼叫 LLM 第二次', () async {
    var callCount = 0;
    final router = FreeChatRouter(
      repo: repo,
      chatFn: (prompt, {systemPrompt}) async {
        callCount++;
        // 日期格式錯誤,executor 會拋 FreeChatToolException
        // (注意:空 params 現在代表「全部期間」,不再是錯誤)
        return '{"type":"tool_call","tool":"get_spending_summary",'
            '"params":{"startDate":"不是日期"}}';
      },
      now: () => DateTime(2026, 9, 8),
    );

    final result = _answerText(await router.route('花多少', ledgerId: ledgerId));

    expect(result, contains('暫時處理不了'));
    expect(callCount, 1);
  });

  test('tools 陣列:兩個工具都執行,兩份結果都進 answer prompt', () async {
    final prompts = <String>[];
    final router = FreeChatRouter(
      repo: repo,
      chatFn: (prompt, {systemPrompt}) async {
        prompts.add(prompt);
        if (prompts.length == 1) {
          return '{"type":"tool_call","tools":['
              '{"tool":"get_spending_summary","params":{"allTime":true}},'
              '{"tool":"get_recurring_transactions","params":{}}]}';
        }
        return '這是綜合回答';
      },
      now: () => DateTime(2026, 9, 8),
    );

    final result =
        _answerText(await router.route('復健科跟牙科比呢', ledgerId: ledgerId));

    expect(result, '這是綜合回答');
    expect(prompts, hasLength(2), reason: 'LLM 往返次數不應該因為多個工具而增加');
    expect(prompts[1], contains('get_spending_summary'));
    expect(prompts[1], contains('get_recurring_transactions'));
  });

  test('tools 陣列超過上限時只取前 maxToolsPerTurn 個', () async {
    final prompts = <String>[];
    final router = FreeChatRouter(
      repo: repo,
      chatFn: (prompt, {systemPrompt}) async {
        prompts.add(prompt);
        if (prompts.length == 1) {
          final one = '{"tool":"get_recurring_transactions","params":{}}';
          return '{"type":"tool_call","tools":[${List.filled(5, one).join(',')}]}';
        }
        return 'ok';
      },
      now: () => DateTime(2026, 9, 8),
    );

    await router.route('問題', ledgerId: ledgerId);

    final count = 'get_recurring_transactions'.allMatches(prompts[1]).length;
    expect(count, FreeChatRouter.maxToolsPerTurn);
  });

  test('部分工具失敗仍進 answer 階段,失敗那格帶 error', () async {
    final prompts = <String>[];
    final router = FreeChatRouter(
      repo: repo,
      chatFn: (prompt, {systemPrompt}) async {
        prompts.add(prompt);
        if (prompts.length == 1) {
          return '{"type":"tool_call","tools":['
              '{"tool":"get_spending_summary","params":{"startDate":"不是日期"}},'
              '{"tool":"get_recurring_transactions","params":{}}]}';
        }
        return '週期性交易有 0 筆,支出的部分我查不到';
      },
      now: () => DateTime(2026, 9, 8),
    );

    final result = _answerText(await router.route('問題', ledgerId: ledgerId));

    expect(prompts, hasLength(2), reason: '一個失敗不該讓整輪死掉');
    expect(prompts[1], contains('error'));
    expect(result, contains('查不到'));
  });

  test('全部工具都失敗才降級成固定文案', () async {
    var callCount = 0;
    final router = FreeChatRouter(
      repo: repo,
      chatFn: (prompt, {systemPrompt}) async {
        callCount++;
        return '{"type":"tool_call","tools":['
            '{"tool":"get_spending_summary","params":{"startDate":"壞日期"}},'
            '{"tool":"query_transactions","params":{"type":"transfer"}}]}';
      },
      now: () => DateTime(2026, 9, 8),
    );

    final result = _answerText(await router.route('問題', ledgerId: ledgerId));

    expect(result, contains('暫時處理不了'));
    expect(callCount, 1);
  });

  test('record_transaction:回傳記帳請求,不呼叫 answer 階段', () async {
    var callCount = 0;
    final router = FreeChatRouter(
      repo: repo,
      chatFn: (prompt, {systemPrompt}) async {
        callCount++;
        return '{"type":"record_transaction","text":"星巴克 150",'
            '"fallbackText":"我看不出金額"}';
      },
      now: () => DateTime(2026, 9, 8),
    );

    final outcome = await router.route('星巴克 150', ledgerId: ledgerId);

    expect(outcome, isA<FreeChatBookkeepingRequest>());
    final req = outcome as FreeChatBookkeepingRequest;
    expect(req.text, '星巴克 150');
    expect(req.fallbackText, '我看不出金額');
    expect(callCount, 1);
  });

  test('record_transaction 沒帶 text 時退回使用者原句', () async {
    final router = FreeChatRouter(
      repo: repo,
      chatFn: (prompt, {systemPrompt}) async => '{"type":"record_transaction"}',
      now: () => DateTime(2026, 9, 8),
    );

    final outcome = await router.route('拿鐵 90', ledgerId: ledgerId);

    expect((outcome as FreeChatBookkeepingRequest).text, '拿鐵 90');
  });

  test('routing prompt 帶入本帳本的分類名稱', () async {
    await repo.createCategory(name: '復健科', kind: 'expense');
    await repo.createCategory(name: '薪資', kind: 'income');

    String? captured;
    final router = FreeChatRouter(
      repo: repo,
      chatFn: (prompt, {systemPrompt}) async {
        captured ??= systemPrompt;
        return '{"type":"answer","text":"好"}';
      },
      now: () => DateTime(2026, 9, 8),
    );

    await router.route('嗨', ledgerId: ledgerId);

    expect(captured, isNotNull);
    expect(captured, contains('復健科'));
    expect(captured, contains('薪資'));
  });

  test('routing prompt 帶入今天日期與全期間規則', () async {
    String? captured;
    final router = FreeChatRouter(
      repo: repo,
      chatFn: (prompt, {systemPrompt}) async {
        captured ??= systemPrompt;
        return '{"type":"answer","text":"好"}';
      },
      now: () => DateTime(2026, 9, 8),
    );

    await router.route('嗨', ledgerId: ledgerId);

    expect(captured, contains('2026-09-08'));
    expect(captured, contains('省略 startDate'));
  });

  test('answer prompt 帶入反幻覺護欄', () async {
    final systemPrompts = <String?>[];
    final router = FreeChatRouter(
      repo: repo,
      chatFn: (prompt, {systemPrompt}) async {
        systemPrompts.add(systemPrompt);
        if (systemPrompts.length == 1) {
          return '{"type":"tool_call","tool":"get_recurring_transactions",'
              '"params":{}}';
        }
        return '沒有週期性交易';
      },
      now: () => DateTime(2026, 9, 8),
    );

    await router.route('我有哪些訂閱', ledgerId: ledgerId);

    expect(systemPrompts[1], contains('不要編造數字'));
    expect(systemPrompts[1], contains('Markdown'));
  });

  test('conversationId 為 null 時歷史為空陣列,流程仍可運作', () async {
    final router = FreeChatRouter(
      repo: repo,
      chatFn: (prompt, {systemPrompt}) async =>
          '{"type":"answer","text":"沒問題"}',
      now: () => DateTime(2026, 9, 8),
    );

    final result = _answerText(
        await router.route('哈囉', ledgerId: ledgerId, conversationId: null));

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

/// 既有測試大多只關心最終文字。route() 現在回 FreeChatOutcome,這裡統一解包。
String _answerText(FreeChatOutcome outcome) {
  expect(outcome, isA<FreeChatAnswer>(), reason: '預期是一般回覆,實際拿到 $outcome');
  return (outcome as FreeChatAnswer).text;
}
