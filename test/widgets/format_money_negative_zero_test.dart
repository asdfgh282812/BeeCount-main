import 'package:beecount/utils/format_utils.dart';
import 'package:beecount/widgets/biz/format_money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('浮点残差的负数显示成 0,不是 -0', () {
    expect(formatMoneyCompact(-1.1e-13, signed: false), '0');
    expect(formatMoneyCompact(-0.004, signed: false), '0');
    expect(formatMoneyCompact(-0.004, signed: true), '+0');
    expect(formatMoneyCompact(-0.2, maxDecimals: 0, signed: false), '0');
  });

  test('真的负数照样带负号', () {
    expect(formatMoneyCompact(-0.01, signed: false), '-0.01');
    expect(formatMoneyCompact(-17934, signed: false), '-17,934');
  });

  test('formatBalance / formatBalanceFull 同样不出现 -0', () {
    expect(formatBalance(-1e-9, 'TWD').startsWith('-'), isFalse);
    expect(formatBalanceFull(-1e-9, 'TWD').startsWith('-'), isFalse);
    expect(formatBalanceFull(-12.5, 'TWD').startsWith('-'), isTrue);
  });
}
