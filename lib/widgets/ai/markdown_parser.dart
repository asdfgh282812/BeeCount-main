/// AI 回覆用的極簡 Markdown 解析器(純 Dart,不依賴 Flutter,方便單測)。
///
/// 刻意只支援 LLM 實際會產出的窄子集。**唯一的硬性要求:未知語法原樣輸出,
/// 絕不吞字** —— 渲染器再不完整,也不能讓使用者看到的字比原文少。
library;

/// 行內樣式片段。
class MdSpan {
  final String text;
  final bool bold;
  final bool italic;
  final bool code;

  const MdSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
  });

  MdSpan copyWith({String? text, bool? bold, bool? italic, bool? code}) =>
      MdSpan(
        text ?? this.text,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        code: code ?? this.code,
      );

  @override
  bool operator ==(Object other) =>
      other is MdSpan &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.code == code;

  @override
  int get hashCode => Object.hash(text, bold, italic, code);

  @override
  String toString() {
    final flags = [
      if (bold) 'b',
      if (italic) 'i',
      if (code) 'c',
    ].join();
    return flags.isEmpty ? '“$text”' : '“$text”($flags)';
  }
}

enum MdBlockType { paragraph, heading, bullet, ordered, codeBlock, rule, table }

/// 區塊。不同型別只會用到其中幾個欄位。
class MdBlock {
  final MdBlockType type;

  /// paragraph / heading / bullet / ordered 的內容。
  final List<MdSpan> spans;

  /// heading 的層級(1-6)。
  final int level;

  /// bullet / ordered 的縮排層級(0 起算)。
  final int indent;

  /// ordered 的顯示標記,例如 "1."。
  final String marker;

  /// codeBlock 的原始內容(不做任何 inline 解析)。
  final String code;

  /// table 的表頭與資料列。
  final List<List<MdSpan>> headerCells;
  final List<List<List<MdSpan>>> rows;

  const MdBlock({
    required this.type,
    this.spans = const [],
    this.level = 1,
    this.indent = 0,
    this.marker = '',
    this.code = '',
    this.headerCells = const [],
    this.rows = const [],
  });
}

final RegExp _headingRe = RegExp(r'^(#{1,6})\s+(.*)$');
final RegExp _bulletRe = RegExp(r'^(\s*)[-*+]\s+(.*)$');
final RegExp _orderedRe = RegExp(r'^(\s*)(\d{1,3})[.)]\s+(.*)$');
final RegExp _ruleRe = RegExp(r'^\s*([-*_])\s*(?:\1\s*){2,}$');
final RegExp _fenceRe = RegExp(r'^\s*```');
final RegExp _tableSepRe =
    RegExp(r'^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?\s*$');

/// 解析整段文字為區塊清單。
List<MdBlock> parseMarkdown(String source) {
  final blocks = <MdBlock>[];
  final lines = source.split('\n');
  final paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    final text = paragraph.join('\n');
    paragraph.clear();
    if (text.trim().isEmpty) return;
    blocks.add(MdBlock(type: MdBlockType.paragraph, spans: parseInline(text)));
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];

    // ``` 圍欄程式碼
    if (_fenceRe.hasMatch(line)) {
      flushParagraph();
      final body = <String>[];
      var closed = false;
      i++;
      while (i < lines.length) {
        if (_fenceRe.hasMatch(lines[i])) {
          closed = true;
          i++;
          break;
        }
        body.add(lines[i]);
        i++;
      }
      if (!closed && body.isEmpty) {
        // 只有一個孤兒 ```,原樣當文字輸出,不吞字
        paragraph.add(line);
        continue;
      }
      blocks.add(MdBlock(type: MdBlockType.codeBlock, code: body.join('\n')));
      continue;
    }

    // 表格:當前行像表格列,且下一行是分隔列
    if (line.contains('|') &&
        i + 1 < lines.length &&
        lines[i + 1].contains('-') &&
        _tableSepRe.hasMatch(lines[i + 1])) {
      flushParagraph();
      final header = _splitRow(line);
      i += 2;
      final rows = <List<List<MdSpan>>>[];
      while (i < lines.length &&
          lines[i].contains('|') &&
          lines[i].trim().isNotEmpty) {
        rows.add(_splitRow(lines[i]));
        i++;
      }
      blocks.add(MdBlock(
        type: MdBlockType.table,
        headerCells: header,
        rows: rows,
      ));
      continue;
    }

    if (_ruleRe.hasMatch(line)) {
      flushParagraph();
      blocks.add(const MdBlock(type: MdBlockType.rule));
      i++;
      continue;
    }

    final heading = _headingRe.firstMatch(line);
    if (heading != null) {
      flushParagraph();
      blocks.add(MdBlock(
        type: MdBlockType.heading,
        level: heading.group(1)!.length,
        spans: parseInline(heading.group(2)!),
      ));
      i++;
      continue;
    }

    final ordered = _orderedRe.firstMatch(line);
    if (ordered != null) {
      flushParagraph();
      blocks.add(MdBlock(
        type: MdBlockType.ordered,
        indent: _indentLevel(ordered.group(1)!),
        marker: '${ordered.group(2)!}.',
        spans: parseInline(ordered.group(3)!),
      ));
      i++;
      continue;
    }

    final bullet = _bulletRe.firstMatch(line);
    if (bullet != null) {
      flushParagraph();
      blocks.add(MdBlock(
        type: MdBlockType.bullet,
        indent: _indentLevel(bullet.group(1)!),
        spans: parseInline(bullet.group(2)!),
      ));
      i++;
      continue;
    }

    if (line.trim().isEmpty) {
      flushParagraph();
      i++;
      continue;
    }

    paragraph.add(line);
    i++;
  }
  flushParagraph();
  return blocks;
}

int _indentLevel(String leading) {
  final width = leading.replaceAll('\t', '  ').length;
  final level = width ~/ 2;
  return level > 3 ? 3 : level;
}

List<List<MdSpan>> _splitRow(String line) {
  var s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|')) s = s.substring(0, s.length - 1);
  return s.split('|').map((c) => parseInline(c.trim())).toList();
}

/// 解析行內樣式。找不到配對的標記一律原樣保留。
List<MdSpan> parseInline(String text) {
  final out = <MdSpan>[];
  final buf = StringBuffer();

  void flush({bool bold = false, bool italic = false, bool code = false}) {
    if (buf.isEmpty) return;
    out.add(MdSpan(buf.toString(), bold: bold, italic: italic, code: code));
    buf.clear();
  }

  void emit(String s,
      {bool bold = false, bool italic = false, bool code = false}) {
    if (s.isEmpty) return;
    flush();
    out.add(MdSpan(s, bold: bold, italic: italic, code: code));
  }

  var i = 0;
  while (i < text.length) {
    final c = text[i];

    // 跳脫字元
    if (c == '\\' && i + 1 < text.length) {
      buf.write(text[i + 1]);
      i += 2;
      continue;
    }

    // 行內程式碼
    if (c == '`') {
      final close = text.indexOf('`', i + 1);
      if (close > i + 1) {
        emit(text.substring(i + 1, close), code: true);
        i = close + 1;
        continue;
      }
    }

    // 粗斜體 ***…***(要先於 ** 判斷,否則 ** 會先咬掉兩顆星,
    // 把第三顆星留在內容裡變成 `*很重要`)
    if (c == '*' &&
        i + 2 < text.length &&
        text[i + 1] == '*' &&
        text[i + 2] == '*') {
      final close = text.indexOf('***', i + 3);
      if (close > i + 3) {
        emit(text.substring(i + 3, close), bold: true, italic: true);
        i = close + 3;
        continue;
      }
    }

    // 粗體 **…**
    if (c == '*' && i + 1 < text.length && text[i + 1] == '*') {
      final close = text.indexOf('**', i + 2);
      if (close > i + 2) {
        final inner = text.substring(i + 2, close);
        for (final s in parseInline(inner)) {
          flush();
          out.add(s.copyWith(bold: true));
        }
        i = close + 2;
        continue;
      }
    }

    // 斜體 *…*
    if (c == '*') {
      final close = text.indexOf('*', i + 1);
      if (close > i + 1 && !text.substring(i + 1, close).contains('\n')) {
        emit(text.substring(i + 1, close), italic: true);
        i = close + 1;
        continue;
      }
    }

    // 斜體 _…_ —— 只在兩側都是「非文字字元」時成立,避免拆壞 snake_case
    if (c == '_' && _isWordBoundaryBefore(text, i)) {
      final close = text.indexOf('_', i + 1);
      if (close > i + 1 && _isWordBoundaryAfter(text, close)) {
        emit(text.substring(i + 1, close), italic: true);
        i = close + 1;
        continue;
      }
    }

    // 連結 [文字](url) —— 只保留文字
    if (c == '[') {
      final closeBracket = text.indexOf(']', i + 1);
      if (closeBracket > i &&
          closeBracket + 1 < text.length &&
          text[closeBracket + 1] == '(') {
        final closeParen = text.indexOf(')', closeBracket + 2);
        if (closeParen > closeBracket) {
          final label = text.substring(i + 1, closeBracket);
          for (final s in parseInline(label)) {
            flush();
            out.add(s);
          }
          i = closeParen + 1;
          continue;
        }
      }
    }

    buf.write(c);
    i++;
  }
  flush();
  return out;
}

final RegExp _wordChar = RegExp(r'[A-Za-z0-9_]');

bool _isWordBoundaryBefore(String text, int i) =>
    i == 0 || !_wordChar.hasMatch(text[i - 1]);

bool _isWordBoundaryAfter(String text, int closeIndex) =>
    closeIndex + 1 >= text.length || !_wordChar.hasMatch(text[closeIndex + 1]);

/// 把解析結果還原成純文字,測試用來驗證「沒有吞字」。
String spansToPlainText(List<MdSpan> spans) => spans.map((s) => s.text).join();
