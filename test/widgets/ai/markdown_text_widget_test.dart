import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/widgets/ai/markdown_text.dart';

void main() {
  const baseStyle = TextStyle(fontSize: 14, height: 1.5);

  Future<void> pump(WidgetTester tester, String text,
      {Brightness brightness = Brightness.light}) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: SingleChildScrollView(
          child: MarkdownText(text: text, baseStyle: baseStyle),
        ),
      ),
    ));
  }

  testWidgets('AI 回覆的典型排版能正常繪製', (tester) async {
    await pump(tester, '''
你從 2024 年 3 月到現在，在**復健科**總共花了 18,400 元：

- 共 **37** 筆
- 平均每筆約 497 元

| 分類 | 金額 |
|---|---:|
| 復健科 | 18,400 |
| 牙科 | 3,200 |
''');

    expect(tester.takeException(), isNull);
    expect(find.byType(Table), findsOneWidget);
  });

  testWidgets('暗色模式不拋例外', (tester) async {
    await pump(tester, '### 標題\n\n`code`\n\n---\n\n1. 一\n2. 二',
        brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('程式碼區塊', (tester) async {
    await pump(tester, '```\nSELECT 1\n```');
    expect(tester.takeException(), isNull);
    expect(find.text('SELECT 1'), findsOneWidget);
  });

  testWidgets('純文字照樣顯示', (tester) async {
    await pump(tester, '這個月你還沒有任何交易紀錄。');
    expect(find.text('這個月你還沒有任何交易紀錄。'), findsOneWidget);
  });

  testWidgets('空字串不拋例外', (tester) async {
    await pump(tester, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('資料列欄數比表頭少也不拋例外', (tester) async {
    await pump(tester, '| a | b | c |\n|---|---|---|\n| 1 |\n| 1 | 2 | 3 | 4 |');
    expect(tester.takeException(), isNull);
  });
}
