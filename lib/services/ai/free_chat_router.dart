import 'dart:convert';

import '../../ai/providers/ai_provider_factory.dart';
import '../../data/db.dart' show Message;
import '../../data/repositories/base_repository.dart';
import '../system/logger_service.dart';
import 'free_chat_context.dart';
import 'free_chat_tools.dart';

const String _tag = 'FreeChatRouter';

/// 單輪對話呼叫,型別對齊 [AIProviderFactory.chat] 的 `(prompt, {systemPrompt})`
/// 子集,測試時可注入假實作。
typedef ChatFn = Future<String> Function(String prompt, {String? systemPrompt});

/// [FreeChatRouter.route] 的結果。
///
/// 不直接回 `String`,是為了讓 router 能把「這句其實是要記帳」回報給
/// [AIChatService] —— 記帳需要 `l10n` 與兩個會彈 UI 的 callback
/// (`resolveMissingAccount` / `resolveMissingProject`),那些都綁著 `BuildContext`,
/// 由一直握著它們的 service 來執行才合理。router 只做決策。
sealed class FreeChatOutcome {
  const FreeChatOutcome();
}

/// 一般對話回覆(含查詢結果整理出來的自然語言)。
class FreeChatAnswer extends FreeChatOutcome {
  final String text;
  const FreeChatAnswer(this.text);
}

/// 模型判斷這句其實是要記帳,請 service 走帳單提取流程。
class FreeChatBookkeepingRequest extends FreeChatOutcome {
  /// 要拿去提取的文字(通常等於使用者原句)。
  final String text;

  /// 提取失敗時的降級回覆。模型已經誤判過一次,再丟一段記帳教學給正在問問題的人
  /// 只會更糟,所以這裡用模型自己寫的自然語言。
  final String? fallbackText;

  const FreeChatBookkeepingRequest(this.text, {this.fallbackText});
}

/// 自由對話兩階段路由:
/// 1. 帶著工具說明 + 帳本分類 + 最近對話紀錄問模型「該直接回答、呼叫工具,還是記帳」
/// 2. 若要呼叫工具,執行後把結果餵回模型產生最終自然語言回覆
///
/// 單輪最多並行執行 [maxToolsPerTurn] 個工具呼叫。這些工具全部唯讀、彼此獨立、
/// 打的是行程內 SQLite,所以並行安全且幾乎免費 —— 重點是 **LLM 往返次數不變**
/// (routing 1 次 + answer 1 次),複合問題(「復健科跟牙科比呢」)因此零延遲代價。
/// 不做 observation loop(answer 階段再回頭呼叫工具),那會讓每則訊息的延遲上限
/// 不可預測,收益也遠不如工具陣列。
class FreeChatRouter {
  /// 單輪最多並行幾個工具呼叫。超過只取前幾個。
  static const maxToolsPerTurn = 3;

  final BaseRepository _repo;
  final ChatFn _chatFn;
  final FreeChatToolExecutor _executor;
  final DateTime Function() _now;

  FreeChatRouter({
    required BaseRepository repo,
    ChatFn? chatFn,
    FreeChatToolExecutor executor = const FreeChatToolExecutor(),
    DateTime Function()? now,
  })  : _repo = repo,
        _chatFn = chatFn ?? _defaultChatFn,
        _executor = executor,
        _now = now ?? DateTime.now;

  static Future<String> _defaultChatFn(String prompt, {String? systemPrompt}) {
    return AIProviderFactory.chat(prompt,
        systemPrompt: systemPrompt, logTag: _tag);
  }

  Future<FreeChatOutcome> route(
    String userInput, {
    required int ledgerId,
    int? conversationId,
    String? languageCode,
  }) async {
    final history = await _loadHistoryExcludingCurrentTurn(
      conversationId,
      userInput,
    );
    final historyText = _buildHistoryText(history);
    final routingPrompt =
        historyText.isEmpty ? '使用者：$userInput' : '$historyText\n使用者：$userInput';

    final context = await _loadContext();
    final routingSystemPrompt =
        _buildRoutingSystemPrompt(languageCode, context);
    final rawResponse =
        await _chatFn(routingPrompt, systemPrompt: routingSystemPrompt);

    final decision = _parseDecision(rawResponse);
    if (decision == null) {
      // 解析不出 JSON:整段模型輸出當作自由對話文字,等同今天的行為,不視為錯誤。
      return FreeChatAnswer(rawResponse);
    }

    switch (decision['type']) {
      case 'answer':
        return FreeChatAnswer((decision['text'] as String?) ?? rawResponse);

      case 'record_transaction':
        final text = (decision['text'] as String?)?.trim();
        return FreeChatBookkeepingRequest(
          (text == null || text.isEmpty) ? userInput : text,
          fallbackText: (decision['fallbackText'] as String?)?.trim(),
        );

      case 'tool_call':
        return _runToolCalls(decision, rawResponse, userInput,
            ledgerId: ledgerId, languageCode: languageCode);

      default:
        return FreeChatAnswer(rawResponse);
    }
  }

  Future<FreeChatOutcome> _runToolCalls(
    Map<String, dynamic> decision,
    String rawResponse,
    String userInput, {
    required int ledgerId,
    String? languageCode,
  }) async {
    final calls = _extractToolCalls(decision);
    if (calls.isEmpty) {
      // 未知工具名 / 格式不對 = 解析失敗,降級成自由對話文字。
      return FreeChatAnswer(rawResponse);
    }

    // 全部唯讀且彼此獨立,並行執行。
    final results = await Future.wait(calls.map((c) async {
      try {
        final data = await _executor.execute(
          c.tool,
          c.params,
          repo: _repo,
          ledgerId: ledgerId,
        );
        return {'tool': c.tool, 'data': data};
      } on FreeChatToolException catch (e) {
        logger.warning(_tag, '工具 ${c.tool} 執行失敗: ${e.message}');
        return {'tool': c.tool, 'error': e.message};
      }
    }));

    // 部分失敗不中止整輪 —— 模型還是可以說「預算我查不到,但支出的部分是…」。
    // 只有**全部**失敗才降級成固定文案。
    if (results.every((r) => r.containsKey('error'))) {
      return const FreeChatAnswer('抱歉,這個問題我暫時處理不了,請換個方式問');
    }

    final payload = results.length == 1 ? results.first : results;
    final answerSystemPrompt = _buildAnswerSystemPrompt(languageCode);
    final answerPrompt = '使用者問題：$userInput\n\n'
        '查到的資料：${jsonEncode(payload)}\n\n'
        '請用自然語言回答,不要提到 JSON 或工具。';

    return FreeChatAnswer(
        await _chatFn(answerPrompt, systemPrompt: answerSystemPrompt));
  }

  /// 同時支援新的 `tools` 陣列與舊的單一 `tool` 欄位(向後相容)。
  List<({String tool, Map<String, dynamic> params})> _extractToolCalls(
    Map<String, dynamic> decision,
  ) {
    final knownNames = freeChatTools.map((t) => t.name).toSet();
    final out = <({String tool, Map<String, dynamic> params})>[];

    void add(dynamic tool, dynamic rawParams) {
      if (tool is! String || !knownNames.contains(tool)) return;
      final params = rawParams is Map
          ? rawParams.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
      out.add((tool: tool, params: params));
    }

    final tools = decision['tools'];
    if (tools is List) {
      for (final entry in tools) {
        if (out.length >= maxToolsPerTurn) {
          logger.warning(_tag, '工具呼叫超過 $maxToolsPerTurn 個,只取前面幾個');
          break;
        }
        if (entry is Map) add(entry['tool'], entry['params']);
      }
      return out;
    }

    add(decision['tool'], decision['params']);
    return out;
  }

  Future<FreeChatContext> _loadContext() async {
    try {
      return await FreeChatContext.forLedger(repo: _repo);
    } catch (e) {
      // 上下文只是幫模型選對參數的加分項,載入失敗不該讓整則訊息失敗。
      logger.warning(_tag, '載入分類上下文失敗,改用空上下文: $e');
      return FreeChatContext.empty;
    }
  }

  /// 取最近 8 則歷史訊息。頁面在呼叫 `processMessage` 前就已把當前這句使用者
  /// 輸入存進 Messages 表,所以查回來的最後一則多半就是 [userInput] 本身 ——
  /// 這裡把它濾掉,避免組 prompt 時「歷史紀錄」跟「使用者：$userInput」重複
  /// 出現同一句話兩次。
  Future<List<Message>> _loadHistoryExcludingCurrentTurn(
    int? conversationId,
    String userInput,
  ) async {
    if (conversationId == null) return const [];
    final recent = await _repo.getRecentMessages(conversationId, limit: 8);
    if (recent.isNotEmpty &&
        recent.last.role == 'user' &&
        recent.last.content == userInput) {
      return recent.sublist(0, recent.length - 1);
    }
    return recent;
  }

  String _buildHistoryText(List<Message> messages) {
    if (messages.isEmpty) return '';
    final buffer = StringBuffer();
    for (final m in messages) {
      final label = m.role == 'user' ? '使用者' : 'AI';
      buffer.writeln('$label：${m.content}');
    }
    return buffer.toString().trimRight();
  }

  String _buildRoutingSystemPrompt(
    String? languageCode,
    FreeChatContext context,
  ) {
    final isEn = languageCode == 'en';
    final persona = isEn
        ? "You are BeeCount's AI assistant, mainly helping users with "
            'bookkeeping and answering questions about their financial data.'
        : '你是蜜蜂記帳的AI助手,主要幫助使用者記帳,並回答關於使用者財務資料的問題。';
    final langInstruction = isEn ? 'Please respond in English.' : '請用繁體中文回覆。';
    final dateLine = isEn
        ? 'Today is ${formatIsoDate(_now())}.'
        : '今天是${formatIsoDate(_now())}。';

    final dateRules = isEn
        ? 'Date rules:\n'
            '- If the user names a period (this month / last week / March), '
            'convert it to concrete startDate and endDate.\n'
            '- If the user says "so far", "all along", "in total", "overall", '
            'or names no period at all, OMIT startDate (and endDate).\n'
            '- NEVER invent a startDate you are not sure about.'
        : '日期規則:\n'
            '- 使用者明確講了時間範圍(這個月/上週/今年/三月)→ 換算成具體日期'
            '填入 startDate 與 endDate。\n'
            '- 使用者說「至今為止 / 一直以來 / 總共 / 全部 / 到現在」,或完全沒提'
            '時間 → **省略 startDate**(需要時連 endDate 一起省略),代表全部期間。\n'
            '- 絕對不要編造一個你不確定的 startDate。';

    final categorySection = context.toPromptSection(isEn: isEn);
    final categoryBlock = categorySection.isEmpty
        ? ''
        : (isEn ? "\nThis ledger's categories:\n" : '\n這個帳本現有的分類:\n') +
            categorySection +
            (isEn
                ? '\nIf the user names one of these, use categoryName. '
                    'Otherwise use keyword. If the thing they ask about is not '
                    'a category here, you may answer directly and say so.\n'
                : '\n使用者提到的詞如果是上面的分類,就用 categoryName;'
                    '否則用 keyword。如果帳本裡根本沒有相關分類,可以直接回答並說明。\n');

    final formatInstruction = isEn
        ? 'Reply with exactly one JSON object:\n'
            '- {"type":"answer","text":"<direct reply>"}\n'
            '- {"type":"tool_call","tool":"<name>","params":{...}}\n'
            '- {"type":"tool_call","tools":[{"tool":"<name>","params":{...}}, ...]} '
            '(up to $maxToolsPerTurn, for questions that need several lookups)\n'
            '- {"type":"record_transaction","text":"<the sentence to record>",'
            '"fallbackText":"<what to say if it cannot be parsed>"} '
            'when the user is recording a transaction rather than asking\n'
            'Do not include any text outside the JSON object.'
        : '只回覆一個 JSON 物件,格式為下列其中一種:\n'
            '- {"type":"answer","text":"<直接回覆內容>"}\n'
            '- {"type":"tool_call","tool":"<工具名>","params":{...}}\n'
            '- {"type":"tool_call","tools":[{"tool":"<工具名>","params":{...}}, ...]}'
            '(最多 $maxToolsPerTurn 個,適合需要多次查詢才能回答的問題)\n'
            '- {"type":"record_transaction","text":"<要記錄的那句話>",'
            '"fallbackText":"<萬一解析不出來要說的話>"} '
            '—— 當使用者是在「記一筆帳」而不是在提問時用這個\n'
            '不要在 JSON 物件之外附加任何文字。';

    final examples = isEn
        ? 'Examples:\n'
            '使用者：hi → {"type":"answer","text":"Hi! How can I help?"}\n'
            '使用者：how much did I spend on rehab so far → '
            '{"type":"tool_call","tool":"query_transactions",'
            '"params":{"keyword":["rehab"],"limit":10}}\n'
            '使用者：bought coffee 150 → '
            '{"type":"record_transaction","text":"bought coffee 150",'
            '"fallbackText":"I could not read the amount, could you rephrase?"}'
        : '範例:\n'
            '使用者：哈囉 → {"type":"answer","text":"你好,有什麼可以幫你?"}\n'
            '使用者：我復健科至今為止花了多少錢 → '
            '{"type":"tool_call","tool":"query_transactions",'
            '"params":{"keyword":["復健","复健"],"limit":10}}\n'
            '使用者：復健科跟牙科哪個花比較多 → '
            '{"type":"tool_call","tools":['
            '{"tool":"query_transactions","params":{"keyword":["復健","复健"],"limit":0}},'
            '{"tool":"query_transactions","params":{"keyword":["牙科","牙醫"],"limit":0}}]}\n'
            '使用者：星巴克 150 → '
            '{"type":"record_transaction","text":"星巴克 150",'
            '"fallbackText":"我看不出金額,可以再說一次嗎?"}';

    return '$persona\n$langInstruction\n$dateLine\n'
        '$categoryBlock\n'
        '可用工具：\n${buildFreeChatToolsPromptSection()}\n\n'
        '$dateRules\n\n$formatInstruction\n\n$examples';
  }

  String _buildAnswerSystemPrompt(String? languageCode) {
    final isEn = languageCode == 'en';
    final persona = isEn
        ? "You are BeeCount's AI assistant, mainly helping users with bookkeeping."
        : '你是蜜蜂記帳的AI助手,主要幫助使用者記帳。';
    final langInstruction = isEn ? 'Please respond in English.' : '請用繁體中文回覆。';
    // 反幻覺護欄。第二條最重要:空結果時編一個數字出來,比任何其他失敗模式都
    // 危險,因為使用者沒有任何線索知道它是假的。
    final guards = isEn
        ? '- matchedCount / totalExpense / totalIncome / byCategory already cover '
            'ALL matching records. sample.transactions is only a sample — never '
            'add up the sample yourself.\n'
            '- If matchedCount is 0, just say nothing was found. NEVER make up a number.\n'
            '- If range.allTime is true, say which dates the data actually spans '
            '(actualFirstDate / actualLastDate) instead of a bare total.'
        : '- matchedCount / totalExpense / totalIncome / byCategory 已經涵蓋全部'
            '符合條件的資料,可以直接引用;sample.transactions 只是樣本,'
            '**絕對不要自己加總樣本**。\n'
            '- matchedCount 為 0 就直接說找不到,**不要編造數字**。\n'
            '- range.allTime 是 true 時,請說明資料實際涵蓋的起訖'
            '(actualFirstDate / actualLastDate),不要只給一個沒有範圍的數字。';
    // 對話視窗會渲染 Markdown(lib/widgets/ai/markdown_text.dart)
    final markdown = isEn
        ? 'You may use simple Markdown (bold, lists, tables) to make the answer '
            'easier to read. Keep it light — no headings for a one-line answer.'
        : '可以使用簡單的 Markdown(粗體、清單、表格)讓回覆更好讀,'
            '但不要過度排版 —— 一句話就能說完的答案不需要標題。';

    return '$persona\n$langInstruction\n\n$guards\n\n$markdown';
  }

  /// 解析 routing 回應為 `{"type": ..., ...}`。回傳 null 代表沒解析出合法的
  /// JSON 物件(容錯策略同 [JsonResponseParser]:balanced-block 提取 + 清掉
  /// trailing comma),呼叫端把整段原始回應當作自由對話文字。
  Map<String, dynamic>? _parseDecision(String response) {
    final block = _extractBalancedObject(response);
    if (block == null) return null;
    try {
      final decoded = jsonDecode(_cleanupTrailingCommas(block));
      if (decoded is Map) {
        final type = decoded['type'];
        if (type == 'answer' ||
            type == 'tool_call' ||
            type == 'record_transaction') {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      }
    } catch (e) {
      logger.warning(_tag, 'routing JSON 解析失敗: $e');
    }
    return null;
  }

  String? _extractBalancedObject(String text) {
    const open = '{';
    const close = '}';
    final start = text.indexOf(open);
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == '\\') {
        escaped = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (c == open) {
        depth++;
      } else if (c == close) {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }

  String _cleanupTrailingCommas(String input) {
    final out = StringBuffer();
    var inString = false;
    var escaped = false;
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (inString) {
        out.write(c);
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
        out.write(c);
        continue;
      }
      if (c == ',') {
        var j = i + 1;
        while (j < input.length &&
            (input[j] == ' ' ||
                input[j] == '\t' ||
                input[j] == '\n' ||
                input[j] == '\r')) {
          j++;
        }
        if (j < input.length && (input[j] == '}' || input[j] == ']')) {
          continue;
        }
      }
      out.write(c);
    }
    return out.toString();
  }
}
