import 'package:beecount/widgets/ai/markdown_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('行內樣式', () {
    test('粗體', () {
      expect(parseInline('總共 **18,400** 元'), [
        const MdSpan('總共 '),
        const MdSpan('18,400', bold: true),
        const MdSpan(' 元'),
      ]);
    });

    test('斜體 *', () {
      expect(parseInline('這是 *重點*'), [
        const MdSpan('這是 '),
        const MdSpan('重點', italic: true),
      ]);
    });

    test('行內程式碼', () {
      expect(parseInline('欄位 `note` 是備註'), [
        const MdSpan('欄位 '),
        const MdSpan('note', code: true),
        const MdSpan(' 是備註'),
      ]);
    });

    test('粗斜體 ***', () {
      final spans = parseInline('***很重要***');
      expect(spans.single.bold, isTrue);
      expect(spans.single.italic, isTrue);
      expect(spans.single.text, '很重要');
    });

    test('連結只保留文字', () {
      expect(spansToPlainText(parseInline('見 [說明](https://a.b/c) 一節')),
          '見 說明 一節');
    });

    test('跳脫字元', () {
      expect(spansToPlainText(parseInline(r'\*不是斜體\*')), '*不是斜體*');
      expect(parseInline(r'\*不是斜體\*').single.italic, isFalse);
    });
  });

  group('絕不吞字', () {
    test('未閉合的 ** 原樣輸出', () {
      expect(spansToPlainText(parseInline('**沒有收尾')), '**沒有收尾');
    });

    test('未閉合的反引號原樣輸出', () {
      expect(spansToPlainText(parseInline('`沒有收尾')), '`沒有收尾');
    });

    test('未閉合的 [ 原樣輸出', () {
      expect(spansToPlainText(parseInline('[標題但沒有連結')), '[標題但沒有連結');
    });

    test('snake_case 不會被當成斜體', () {
      expect(spansToPlainText(parseInline('欄位 native_amount_value 是金額')),
          '欄位 native_amount_value 是金額');
      expect(parseInline('native_amount_value').single.italic, isFalse);
    });

    test('純文字完全等同原文', () {
      const plain = '你這個月在復健科總共花了 18,400 元，共 37 筆。';
      expect(spansToPlainText(parseInline(plain)), plain);
    });

    test('單獨的星號與百分比', () {
      expect(spansToPlainText(parseInline('折扣 95% * 2')), '折扣 95% * 2');
    });
  });

  group('區塊', () {
    test('標題', () {
      final b = parseMarkdown('## 本月支出').single;
      expect(b.type, MdBlockType.heading);
      expect(b.level, 2);
      expect(spansToPlainText(b.spans), '本月支出');
    });

    test('項目符號與巢狀縮排', () {
      final blocks = parseMarkdown('- 餐飲 3,200\n  - 早餐 800\n- 交通 1,100');
      expect(blocks.map((b) => b.type),
          everyElement(MdBlockType.bullet));
      expect(blocks[0].indent, 0);
      expect(blocks[1].indent, 1);
      expect(blocks[2].indent, 0);
      expect(spansToPlainText(blocks[1].spans), '早餐 800');
    });

    test('編號清單保留原編號', () {
      final blocks = parseMarkdown('1. 餐飲\n2. 交通');
      expect(blocks[0].type, MdBlockType.ordered);
      expect(blocks[0].marker, '1.');
      expect(blocks[1].marker, '2.');
    });

    test('圍欄程式碼不做行內解析', () {
      final b = parseMarkdown('```\na = **b**\n```').single;
      expect(b.type, MdBlockType.codeBlock);
      expect(b.code, 'a = **b**');
    });

    test('未閉合的圍欄仍收進 code block,不吞字', () {
      final b = parseMarkdown('```\nabc').single;
      expect(b.type, MdBlockType.codeBlock);
      expect(b.code, 'abc');
    });

    test('分隔線', () {
      expect(parseMarkdown('---').single.type, MdBlockType.rule);
      expect(parseMarkdown('***').single.type, MdBlockType.rule);
    });

    test('表格', () {
      final b = parseMarkdown(
        '| 分類 | 金額 |\n|---|---:|\n| 復健科 | 18,400 |\n| 牙科 | 3,200 |',
      ).single;
      expect(b.type, MdBlockType.table);
      expect(b.headerCells.map(spansToPlainText), ['分類', '金額']);
      expect(b.rows.length, 2);
      expect(b.rows[0].map(spansToPlainText), ['復健科', '18,400']);
    });

    test('像表格但沒有分隔列 → 當一般段落,不吞字', () {
      final blocks = parseMarkdown('| 不是 | 表格 |');
      expect(blocks.single.type, MdBlockType.paragraph);
      expect(spansToPlainText(blocks.single.spans), '| 不是 | 表格 |');
    });

    test('空字串', () {
      expect(parseMarkdown(''), isEmpty);
    });

    test('多段文字以空行分段', () {
      final blocks = parseMarkdown('第一段\n\n第二段');
      expect(blocks.length, 2);
      expect(spansToPlainText(blocks[1].spans), '第二段');
    });

    test('混合內容:段落 + 清單 + 粗體', () {
      final blocks = parseMarkdown(
        '你在**復健科**總共花了 18,400 元：\n\n- 2026-09-10 500 元\n- 2026-09-03 500 元',
      );
      expect(blocks[0].type, MdBlockType.paragraph);
      expect(blocks[0].spans.any((s) => s.bold && s.text == '復健科'), isTrue);
      expect(blocks[1].type, MdBlockType.bullet);
      expect(blocks[2].type, MdBlockType.bullet);
    });
  });
}
