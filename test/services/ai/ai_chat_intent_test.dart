import 'package:beecount/services/ai/ai_chat_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Layer 0 查詢否決 —— 這些一律不能被判成記帳', () {
    const queries = [
      // 本次回報的原始案例:舊版因為句中有「花」而被判成記帳
      '我復健科至今為止花了多少錢',
      '這個月餐飲花了多少?',
      '2026年總共花多少',
      '上個月付了多少保費',
      '上個月收入多少',
      '幫我查詢一下牙科的支出',
      '今年哪個分類花最多',
      '我的預算還剩多少',
      '列出這個月的交易明細',
      '餐飲跟交通比較起來哪個多',
      '我一直以來在醫療上花了多少',
      '這個月有沒有超支',
      'how much did I spend on rehab',
      'show me my total spending this year',
    ];
    for (final q in queries) {
      test('「$q」→ 自由對話', () {
        expect(isTransactionIntent(q), isFalse, reason: q);
      });
    }
  });

  group('Layer 1 記帳快路徑 —— 這些不能退化', () {
    const bookkeeping = [
      // 既有文案 ai_chat_service.dart 提示使用者的三個範例
      '買了杯奶茶28塊',
      '今天午餐花了50',
      '打車回家花了35',
      // 繁體(舊版關鍵字表只有簡體,這幾句以前只靠 hasAmount 才勉強中)
      '買了咖啡120',
      '薪水收入50000',
      '繳了電費1200',
      '儲值悠遊卡500',
      '午餐吃了120',
      'bought coffee 150',
      'paid rent 12000',
    ];
    for (final b in bookkeeping) {
      test('「$b」→ 記帳', () {
        expect(isTransactionIntent(b), isTrue, reason: b);
      });
    }
  });

  group('AND 條件(舊版是 OR)', () {
    test('只有動詞沒有金額 → 不走快路徑,交給 router 判斷', () {
      expect(isTransactionIntent('剛剛買了東西'), isFalse);
    });

    test('只有數字沒有動詞 → 不走快路徑', () {
      expect(isTransactionIntent('2026'), isFalse);
      expect(isTransactionIntent('星巴克 150'), isFalse);
    });

    test('金額 + 動詞 → 走快路徑', () {
      expect(isTransactionIntent('買了東西300'), isTrue);
    });
  });

  group('刻意不收的單字,避免誤攔記帳句', () {
    test('「檢查」含「查」但仍是記帳', () {
      expect(isTransactionIntent('健康檢查花了2000'), isTrue);
    });

    test('「幾」不是否決字', () {
      expect(isTransactionIntent('買飲料花了65'), isTrue);
    });
  });

  group('輔助函式', () {
    test('hasAmountToken 認得小數', () {
      expect(hasAmountToken('咖啡 89.5'), isTrue);
      expect(hasAmountToken('咖啡'), isFalse);
    });

    test('英文動詞比對不分大小寫', () {
      expect(hasBookkeepingVerb('Bought lunch'), isTrue);
    });

    test('英文查詢片語比對不分大小寫', () {
      expect(isQueryIntent('How Much did I spend'), isTrue);
    });

    test('空字串不是記帳', () {
      expect(isTransactionIntent(''), isFalse);
    });
  });
}
