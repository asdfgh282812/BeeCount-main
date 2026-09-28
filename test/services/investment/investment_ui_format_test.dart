// 股票持股 UI 格式化(lib/pages/investment/investment_ui.dart)。2026-09-28 實機
// 踩到:formatPrice 原本用 replaceFirst(…, r'$1'),Dart 不支援 $1 群組引用,
// 整數價格(2475.0)會產生沒有小數點的字串、取 parts[1] 直接 RangeError。
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/pages/investment/investment_ui.dart';

void main() {
  test('formatPrice 保留 2–4 位小數並加千分位', () {
    expect(formatPrice(2475), '2,475.00');
    expect(formatPrice(600.513), '600.513');
    expect(formatPrice(150.128), '150.128');
    expect(formatPrice(341.07), '341.07');
    expect(formatPrice(0.12345), '0.1235');
    expect(formatPrice(12.5), '12.50');
  });

  test('formatShares:整數不帶小數,零碎股最多 4 位', () {
    expect(formatShares(1000), '1,000');
    expect(formatShares(2.5), '2.5');
    expect(formatShares(0.12345), '0.1235');
  });

  test('formatStockMoney 依幣別小數位', () {
    expect(formatStockMoney(2204800, 'TWD'), 'NT\$2,204,800');
    expect(formatStockMoney(3410.7, 'USD'), '\$3,410.70');
    expect(formatStockMoney(-1850, 'TWD', signed: true), '-NT\$1,850');
    expect(formatStockMoney(905.7, 'USD', signed: true), '+\$905.70');
  });
}
