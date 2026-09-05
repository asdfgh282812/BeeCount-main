import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/styles/tokens.dart';

void main() {
  test('时长与曲线常量值符合设计', () {
    expect(BeeMotion.fast, const Duration(milliseconds: 150));
    expect(BeeMotion.medium, const Duration(milliseconds: 280));
    expect(BeeMotion.slow, const Duration(milliseconds: 380));
    expect(BeeMotion.standard, Curves.easeOutCubic);
    expect(BeeMotion.spring, Curves.easeOutBack);
  });

  testWidgets('durationOf 在 disableAnimations 时归零', (tester) async {
    late Duration normalResult;
    late Duration reducedResult;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: false),
        child: Builder(builder: (context) {
          normalResult = BeeMotion.durationOf(context, BeeMotion.medium);
          return const SizedBox();
        }),
      ),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(builder: (context) {
          reducedResult = BeeMotion.durationOf(context, BeeMotion.medium);
          return const SizedBox();
        }),
      ),
    );
    expect(normalResult, BeeMotion.medium);
    expect(reducedResult, Duration.zero);
  });
}
