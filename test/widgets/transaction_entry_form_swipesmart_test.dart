import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/widgets/biz/transaction_entry_form.dart';

void main() {
  test('swipesmartUnmappedNoteAppend 組合銀行名與卡名', () {
    expect(swipesmartUnmappedNoteAppend('永豐銀行', 'SPORT卡'), '永豐銀行 SPORT卡');
  });

  test('swipesmartUnmappedNoteAppend 去除頭尾多餘空白', () {
    expect(swipesmartUnmappedNoteAppend(' 永豐銀行', 'SPORT卡 '), '永豐銀行 SPORT卡');
  });
}
