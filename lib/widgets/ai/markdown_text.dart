import 'package:flutter/material.dart';

import '../../styles/tokens.dart';
import 'markdown_parser.dart';

/// 渲染 AI 回覆裡的極簡 Markdown。
///
/// 所有樣式都是從 [baseStyle] 衍生出來的(字級用倍率、顏色用 [BeeTokens]),
/// 呼叫端傳什麼就跟著什麼 —— 這樣才不會破壞暗色模式與全域字級縮放設定。
/// 本元件**不自己決定字級**,也不引入任何 markdown 套件。
///
/// 搭配 [TypewriterText] 使用:逐字動畫播放中會餵進半截的 markdown
/// (例如只打出 `**粗`),所以動畫期間由呼叫端改用純 [Text],播完再切到這裡。
/// 見 `ai_chat_page.dart` 的 `_buildMessageBubble`。
class MarkdownText extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;

  const MarkdownText({
    super.key,
    required this.text,
    required this.baseStyle,
  });

  double get _fontSize => baseStyle.fontSize ?? 14.0;

  @override
  Widget build(BuildContext context) {
    final blocks = parseMarkdown(text);
    if (blocks.isEmpty) {
      return Text(text, style: baseStyle);
    }

    final gap = _fontSize * 0.45;
    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      if (i > 0) children.add(SizedBox(height: gap));
      children.add(_buildBlock(context, blocks[i]));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildBlock(BuildContext context, MdBlock block) {
    switch (block.type) {
      case MdBlockType.paragraph:
        return _richText(block.spans);

      case MdBlockType.heading:
        // h1 1.35x、h2 1.2x、h3 以下 1.1x
        final scale = switch (block.level) { 1 => 1.35, 2 => 1.2, _ => 1.1 };
        return _richText(
          block.spans,
          style: baseStyle.copyWith(
            fontSize: _fontSize * scale,
            fontWeight: FontWeight.w700,
          ),
        );

      case MdBlockType.bullet:
        return _listRow(block, '•');

      case MdBlockType.ordered:
        return _listRow(block, block.marker);

      case MdBlockType.rule:
        return Padding(
          padding: EdgeInsets.symmetric(vertical: _fontSize * 0.25),
          child: Divider(
              height: 1, thickness: 1, color: BeeTokens.divider(context)),
        );

      case MdBlockType.codeBlock:
        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(_fontSize * 0.6),
          decoration: BoxDecoration(
            color: BeeTokens.surfaceSecondary(context),
            borderRadius: BorderRadius.circular(_fontSize * 0.5),
          ),
          child: Text(
            block.code,
            style: baseStyle.copyWith(
              fontFamily: 'monospace',
              fontSize: _fontSize * 0.92,
            ),
          ),
        );

      case MdBlockType.table:
        return _buildTable(context, block);
    }
  }

  Widget _listRow(MdBlock block, String marker) {
    return Padding(
      padding: EdgeInsets.only(left: _fontSize * 1.1 * block.indent),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _fontSize * 1.5,
            child: Text(marker, style: baseStyle),
          ),
          Expanded(child: _richText(block.spans)),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context, MdBlock block) {
    final border = BeeTokens.divider(context);
    final cellPad = EdgeInsets.symmetric(
      horizontal: _fontSize * 0.5,
      vertical: _fontSize * 0.35,
    );

    TableRow row(List<List<MdSpan>> cells, {required bool header}) => TableRow(
          decoration: header
              ? BoxDecoration(color: BeeTokens.surfaceSecondary(context))
              : null,
          children: [
            for (final cell in cells)
              Padding(
                padding: cellPad,
                child: _richText(
                  cell,
                  style: header
                      ? baseStyle.copyWith(fontWeight: FontWeight.w600)
                      : null,
                ),
              ),
          ],
        );

    final columnCount = block.headerCells.length;
    // 資料列的欄數可能跟表頭對不上,補齊/截斷避免 Table 拋例外
    List<List<MdSpan>> normalize(List<List<MdSpan>> cells) {
      if (cells.length == columnCount) return cells;
      if (cells.length > columnCount) return cells.sublist(0, columnCount);
      return [
        ...cells,
        for (var i = cells.length; i < columnCount; i++) <MdSpan>[],
      ];
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 0),
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: border, width: 1),
          children: [
            row(block.headerCells, header: true),
            for (final r in block.rows) row(normalize(r), header: false),
          ],
        ),
      ),
    );
  }

  Widget _richText(List<MdSpan> spans, {TextStyle? style}) {
    final base = style ?? baseStyle;
    return Text.rich(
      TextSpan(
        children: [
          for (final s in spans)
            TextSpan(
              text: s.text,
              style: base.copyWith(
                fontWeight: s.bold ? FontWeight.w700 : base.fontWeight,
                fontStyle: s.italic ? FontStyle.italic : base.fontStyle,
                fontFamily: s.code ? 'monospace' : base.fontFamily,
                fontSize: s.code
                    ? (base.fontSize ?? _fontSize) * 0.92
                    : base.fontSize,
              ),
            ),
        ],
      ),
      style: base,
    );
  }
}
