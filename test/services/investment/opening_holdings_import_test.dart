import 'package:beecount/services/investment/opening_holdings_import.dart';
import 'package:flutter_test/flutter_test.dart';

// 同一組字串/數字也在 Cloud Web `investmentFees.test.ts`「期初持股匯入」。
void main() {
  group('parseOpeningHoldingsText', () {
    test('Tab 分隔(Excel 複製)可帶千分位與名稱,標題列略過', () {
      final r = parseOpeningHoldingsText(
          '代號\t名稱\t股數\t平均成本\n0050\t元大台灣50\t1,000\t120.5\n2330\t台積電\t50\t580\n');
      expect(r.skipped, 1);
      expect(r.lines.length, 2);
      expect(r.lines[0].symbol, '0050');
      expect(r.lines[0].name, '元大台灣50');
      expect(r.lines[0].shares, 1000);
      expect(r.lines[0].cost, 120.5);
      expect(r.lines[1].symbol, '2330');
      expect(r.lines[1].shares, 50);
      expect(r.lines[1].cost, 580);
    });

    test('空白分隔,逗號當千分位;CSV;小寫代號轉大寫', () {
      final r = parseOpeningHoldingsText(
          '0056 2,000 35.2\n2330,台積電,50,580\nvoo 3.5 412.3\n');
      expect(r.skipped, 0);
      expect(r.lines.map((l) => l.symbol), ['0056', '2330', 'VOO']);
      expect(r.lines[0].shares, 2000);
      expect(r.lines[0].cost, 35.2);
      expect(r.lines[1].name, '台積電');
      expect(r.lines[2].shares, 3.5);
      expect(r.lines[2].name, isNull);
    });

    test('名稱在代號前面、帶單位/貨幣符號也可以', () {
      final r = parseOpeningHoldingsText('元大高股息 0056 1000股 NT\$35.2');
      expect(r.lines.single.symbol, '0056');
      expect(r.lines.single.name, '元大高股息');
      expect(r.lines.single.shares, 1000);
      expect(r.lines.single.cost, 35.2);
    });

    test('缺成本或數字為 0 的行略過', () {
      final r = parseOpeningHoldingsText('0050 1000\n2330 0 580\n\n   \n');
      expect(r.lines, isEmpty);
      expect(r.skipped, 2);
    });
  });

  group('openingTradeFromCost', () {
    test('平均成本:價格 = 均價、手續費 0', () {
      final t = openingTradeFromCost(
          shares: 1000, cost: 120.5, costIsTotal: false, currency: 'TWD');
      expect(t.price, 120.5);
      expect(t.fee, 0);
      expect(
          openingTotalCost(
              shares: 1000, cost: 120.5, costIsTotal: false, currency: 'TWD'),
          120500);
    });

    test('總成本:存下來的成本剛好等於輸入(台幣價金捨去的零頭進手續費)', () {
      // 100 / 3 = 33.3333;價金 floor(99.9999) = 99 → 差額 1 放手續費。
      final t = openingTradeFromCost(
          shares: 3, cost: 100, costIsTotal: true, currency: 'TWD');
      expect(t.price, 33.3333);
      expect(t.fee, 1);
      expect(
          openingTotalCost(
              shares: 3, cost: 100, costIsTotal: true, currency: 'TWD'),
          100);
      // 56,357 / 1,234 → 45.6702,價金 floor(56357.03) = 56,357,不用補。
      expect(
          openingTradeFromCost(
                  shares: 1234, cost: 56357, costIsTotal: true, currency: 'TWD')
              .fee,
          0);
    });

    test('總成本(美元碎股)四捨五入到分', () {
      expect(
          openingTotalCost(
              shares: 3.5, cost: 1443.05, costIsTotal: true, currency: 'USD'),
          1443.05);
    });
  });
}
