import 'dart:convert';

import '../../ai/providers/ai_provider_factory.dart';
import '../../data/db.dart' show Message;
import '../../data/repositories/base_repository.dart';
import '../system/logger_service.dart';
import 'free_chat_tools.dart';

const String _tag = 'FreeChatRouter';

/// 單輪對話呼叫,型別對齊 [AIProviderFactory.chat] 的 `(prompt, {systemPrompt})`
/// 子集,測試時可注入假實作。
typedef ChatFn = Future<String> Function(String prompt, {String? systemPrompt});

/// 自由對話兩階段路由:
/// 1. 帶著工具說明 + 最近對話紀錄問模型「該直接回答還是呼叫工具」
/// 2. 若要呼叫工具,執行後把結果餵回模型產生最終自然語言回覆
///
/// 單輪最多觸發 1 次工具呼叫,不做工具鏈式呼叫迴圈(見 design doc)。
class FreeChatRouter {
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

  Future<String> route(
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

    final routingSystemPrompt = _buildRoutingSystemPrompt(languageCode);
    final rawResponse =
        await _chatFn(routingPrompt, systemPrompt: routingSystemPrompt);

    final decision = _parseDecision(rawResponse);
    if (decision == null || decision['type'] != 'tool_call') {
      if (decision != null && decision['type'] == 'answer') {
        return (decision['text'] as String?) ?? rawResponse;
      }
      // 解析不出 JSON,或 type 既非 answer 也非 tool_call:整段模型輸出當作
      // 自由對話文字,等同今天的行為,不視為錯誤。
      return rawResponse;
    }

    final toolName = decision['tool'];
    final knownNames = freeChatTools.map((t) => t.name).toSet();
    if (toolName is! String || !knownNames.contains(toolName)) {
      // 未知工具名 = 解析失敗,同上降級。
      return rawResponse;
    }

    final rawParams = decision['params'];
    final params = rawParams is Map
        ? rawParams.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};

    Map<String, dynamic> toolResult;
    try {
      toolResult = await _executor.execute(
        toolName,
        params,
        repo: _repo,
        ledgerId: ledgerId,
      );
    } on FreeChatToolException catch (e) {
      logger.warning(_tag, '工具執行失敗: ${e.message}');
      return '抱歉,這個問題我暫時處理不了,請換個方式問';
    }

    final answerSystemPrompt = _buildAnswerSystemPrompt(languageCode);
    final answerPrompt = '使用者問題：$userInput\n\n'
        '查到的資料：${jsonEncode(toolResult)}\n\n'
        '請用自然語言回答,不要提到 JSON 或工具。';

    return await _chatFn(answerPrompt, systemPrompt: answerSystemPrompt);
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

  String _buildRoutingSystemPrompt(String? languageCode) {
    final isEn = languageCode == 'en';
    final persona = isEn
        ? "You are BeeCount's AI assistant, mainly helping users with "
            'bookkeeping and answering questions about their financial data.'
        : '你是蜜蜂記帳的AI助手,主要幫助使用者記帳,並回答關於使用者財務資料的問題。';
    final langInstruction = isEn ? 'Please respond in English.' : '請用繁體中文回覆。';
    final dateLine = isEn
        ? 'Today is ${formatIsoDate(_now())}.'
        : '今天是${formatIsoDate(_now())}。';
    final toolsSection = buildFreeChatToolsPromptSection();
    final formatInstruction = isEn
        ? 'Reply with exactly one JSON object, either '
            '{"type":"tool_call","tool":"<name>","params":{...}} or '
            '{"type":"answer","text":"<direct reply>"}. '
            'Do not include any text outside the JSON object.'
        : '只回覆一個 JSON 物件,格式為 '
            '{"type":"tool_call","tool":"<工具名>","params":{...}} 或 '
            '{"type":"answer","text":"<直接回覆內容>"}。'
            '不要在 JSON 物件之外附加任何文字。';

    return '$persona\n$langInstruction\n$dateLine\n\n'
        '可用工具：\n$toolsSection\n\n$formatInstruction';
  }

  String _buildAnswerSystemPrompt(String? languageCode) {
    final isEn = languageCode == 'en';
    final persona = isEn
        ? "You are BeeCount's AI assistant, mainly helping users with bookkeeping."
        : '你是蜜蜂記帳的AI助手,主要幫助使用者記帳。';
    final langInstruction = isEn ? 'Please respond in English.' : '請用繁體中文回覆。';
    return '$persona\n$langInstruction';
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
        if (type == 'answer' || type == 'tool_call') {
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
