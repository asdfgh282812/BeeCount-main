import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/widgets/biz/amount_calculator_keypad.dart';

void main() {
  Widget host({
    required ValueChanged<String> onDigit,
    required ValueChanged<String> onOp,
    required VoidCallback onBackspace,
    required VoidCallback onClear,
    required VoidCallback onEquals,
    required VoidCallback onSave,
    bool isInCalcMode = false,
    bool canSubmit = false,
    bool isSubmitting = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: AmountCalculatorKeypad(
          onDigit: onDigit,
          onOp: onOp,
          onBackspace: onBackspace,
          onClear: onClear,
          onEquals: onEquals,
          onSave: onSave,
          isInCalcMode: isInCalcMode,
          canSubmit: canSubmit,
          isSubmitting: isSubmitting,
        ),
      ),
    );
  }

  testWidgets('數字鍵/運算子鍵/⌫/C 都會觸發對應 callback', (tester) async {
    final digits = <String>[];
    final ops = <String>[];
    var backspaceCount = 0;
    var clearCount = 0;

    await tester.pumpWidget(host(
      onDigit: digits.add,
      onOp: ops.add,
      onBackspace: () => backspaceCount++,
      onClear: () => clearCount++,
      onEquals: () {},
      onSave: () {},
    ));

    await tester.tap(find.text('7'));
    await tester.tap(find.text('00'));
    await tester.tap(find.text('.'));
    expect(digits, ['7', '00', '.']);

    await tester.tap(find.text('÷'));
    await tester.tap(find.text('×'));
    await tester.tap(find.text('-'));
    await tester.tap(find.text('+'));
    expect(ops, ['÷', '×', '-', '+']);

    await tester.tap(find.byIcon(Icons.backspace_outlined));
    expect(backspaceCount, 1);

    await tester.tap(find.text('C'));
    expect(clearCount, 1);
  });

  testWidgets('非計算模式下,✓ 鍵 canSubmit=false 不可點,true 時觸發 onSave', (tester) async {
    var saveCount = 0;
    var equalsCount = 0;

    await tester.pumpWidget(host(
      onDigit: (_) {},
      onOp: (_) {},
      onBackspace: () {},
      onClear: () {},
      onEquals: () => equalsCount++,
      onSave: () => saveCount++,
      canSubmit: false,
    ));
    await tester.tap(find.byIcon(Icons.check));
    expect(saveCount, 0);

    await tester.pumpWidget(host(
      onDigit: (_) {},
      onOp: (_) {},
      onBackspace: () {},
      onClear: () {},
      onEquals: () => equalsCount++,
      onSave: () => saveCount++,
      canSubmit: true,
    ));
    await tester.tap(find.byIcon(Icons.check));
    expect(saveCount, 1);
    expect(equalsCount, 0);
  });

  testWidgets('計算模式下(isInCalcMode=true),✓ 鍵只觸發 onEquals 不觸發 onSave',
      (tester) async {
    var saveCount = 0;
    var equalsCount = 0;

    await tester.pumpWidget(host(
      onDigit: (_) {},
      onOp: (_) {},
      onBackspace: () {},
      onClear: () {},
      onEquals: () => equalsCount++,
      onSave: () => saveCount++,
      isInCalcMode: true,
      canSubmit: true,
    ));
    await tester.tap(find.byIcon(Icons.check));
    expect(equalsCount, 1);
    expect(saveCount, 0);

    // 專門的 ↵ 捷徑鍵一樣觸發 onEquals
    await tester.tap(find.byIcon(Icons.keyboard_return_rounded));
    expect(equalsCount, 2);
  });
}
