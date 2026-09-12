import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/widgets/cute_icons/pencil_underline_painter.dart';

void main() {
  testWidgets('CategoryColorUnderline renders without throwing',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CategoryColorUnderline(color: Colors.deepPurple),
        ),
      ),
    );

    expect(find.byType(CategoryColorUnderline), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  test('shouldRepaint is true only when color changes', () {
    const a = PencilUnderlinePainter(color: Colors.red);
    const b = PencilUnderlinePainter(color: Colors.red);
    const c = PencilUnderlinePainter(color: Colors.blue);

    expect(a.shouldRepaint(b), isFalse);
    expect(a.shouldRepaint(c), isTrue);
  });
}
