import 'package:beecount/utils/zh_variants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('繁簡摺疊後相等', () {
    expect(foldZh('復健科'), foldZh('复健科'));
    expect(foldZh('醫療'), foldZh('医疗'));
    expect(foldZh('餐飲'), foldZh('餐饮'));
    expect(foldZh('交通費'), foldZh('交通费'));
    expect(foldZh('購物'), foldZh('购物'));
  });

  test('不在表內的字原樣通過', () {
    expect(foldZh('牙科'), '牙科');
    expect(foldZh('咖啡'), '咖啡');
  });

  test('英文轉小寫', () {
    expect(foldZh('Coffee'), foldZh('coffee'));
  });

  test('忽略空白與常見分隔符', () {
    expect(foldZh('復 健 科'), foldZh('復健科'));
    expect(foldZh('food-drink'), foldZh('fooddrink'));
  });

  test('空字串', () {
    expect(foldZh(''), '');
  });

  test('不同的詞不會被摺疊成一樣', () {
    expect(foldZh('餐飲'), isNot(foldZh('交通')));
  });

  test('對照表沒有重複鍵、沒有恆等對映', () {
    for (final e in kTradToSimp.entries) {
      expect(e.key, isNot(e.value), reason: '${e.key} 是恆等對映,應該移除');
    }
  });
}
