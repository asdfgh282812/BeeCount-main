/// 自由對話工具共用的純資料型別(metadata / 例外 / 日期格式化)。
///
/// 從 free_chat_tools.dart 抽出,讓股票工具檔(free_chat_stock_tools.dart)
/// 可以引用而不必跟 free_chat_tools.dart 互相 import。free_chat_tools.dart
/// 會 re-export 這裡的符號,既有呼叫端不用改。
library;

/// 單一工具參數的說明,純資料,用來拼進 routing systemPrompt。
class FreeChatToolParam {
  final String name;
  final String type; // 'date' | 'bool' | 'string' | 'int' | 'string|array'
  final bool required;
  final String description;

  const FreeChatToolParam({
    required this.name,
    required this.type,
    this.required = false,
    required this.description,
  });
}

/// 單一工具的 metadata。
class FreeChatToolSpec {
  final String name;
  final String description;
  final List<FreeChatToolParam> params;

  const FreeChatToolSpec({
    required this.name,
    required this.description,
    this.params = const [],
  });
}

/// `YYYY-MM-DD` 格式化,與 [PromptBuilder] 的 `{{CURRENT_DATE}}` 做法一致。
String formatIsoDate(DateTime date) {
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${pad(date.month)}-${pad(date.day)}';
}

/// 工具名不存在 / 參數格式錯誤時拋出,供 [FreeChatRouter] 捕捉並降級成固定文案,
/// 不是靜默回空結果。
class FreeChatToolException implements Exception {
  final String message;
  FreeChatToolException(this.message);

  @override
  String toString() => 'FreeChatToolException: $message';
}
