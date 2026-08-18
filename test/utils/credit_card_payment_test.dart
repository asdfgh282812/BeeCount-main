import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/utils/card_reward_period.dart';
import 'package:beecount/utils/credit_card_payment.dart';

void main() {
  group('creditCardPaymentNote', () {
    String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    test('格式對齊 server 的「信用卡繳款(帳單 起~迄)」,週期取「最近一次已結帳」的那期', () {
      final offset = mostRecentlyClosedBillingOffset(11);
      final period = billingCyclePeriod(11, offset);
      final cycleStart = period.start.subtract(const Duration(days: 1));
      final expected = '信用卡繳款(帳單 ${iso(cycleStart)}~${iso(period.end)})';

      expect(creditCardPaymentNote(billingDay: 11), expected);
    });

    test('isOverflowToGroup 加註「(溢繳結轉)」後綴,對齊 card_payment_ep 的 tx_note', () {
      final withoutSuffix = creditCardPaymentNote(billingDay: 11);
      final withSuffix =
          creditCardPaymentNote(billingDay: 11, isOverflowToGroup: true);
      expect(withSuffix, '$withoutSuffix(溢繳結轉)');
    });

    test('billingDay 為 null 時退化成每月 1 號起算,不拋例外', () {
      expect(() => creditCardPaymentNote(billingDay: null), returnsNormally);
    });
  });

  group('creditCardDueAsOf', () {
    test('charged > paidTotal:回傳差額(仍欠款)', () {
      expect(creditCardDueAsOf(charged: 7477, paidTotal: 0), 7477);
    });

    test('charged == paidTotal:剛好清償,回傳 0', () {
      expect(creditCardDueAsOf(charged: 1000, paidTotal: 1000), 0);
    });

    test('paidTotal > charged(溢繳):floor 在 0,不回傳負值', () {
      expect(creditCardDueAsOf(charged: 500, paidTotal: 800), 0);
    });

    test('paidTotal 是終身加總,不受 charged 的 asOf cutoff 限制', () {
      // 模擬:某期結算時 charged=1000,但使用者在別期已經繳了 1200(FIFO
      // 也套用在這期上)——回傳 0,不是「這期沒收到錢」的字面判斷。
      expect(creditCardDueAsOf(charged: 1000, paidTotal: 1200), 0);
    });
  });

  group('allocateCardPayment', () {
    test('金額 >= 應繳總和:每個子帳戶付清,溢繳歸群組本身', () {
      final result = allocateCardPayment(
        remainingDueByChild: {1: 1000, 2: 500},
        amount: 2000,
        groupAccountId: 99,
      );
      expect(result[1], 1000);
      expect(result[2], 500);
      expect(result[99], 500);
    });

    test('金額 == 應繳總和:剛好付清,不產生溢繳項', () {
      final result = allocateCardPayment(
        remainingDueByChild: {1: 1000, 2: 500},
        amount: 1500,
        groupAccountId: 99,
      );
      expect(result[1], 1000);
      expect(result[2], 500);
      expect(result.containsKey(99), isFalse);
    });

    test('金額 < 應繳總和:按比例分攤,最後一筆用減法拿餘數', () {
      final result = allocateCardPayment(
        remainingDueByChild: {1: 1000, 2: 500},
        amount: 900,
        groupAccountId: 99,
      );
      // 1: 900 * (1000/1500) = 600, 2(最後一筆): 900 - 600 = 300
      expect(result[1], 600);
      expect(result[2], 300);
      expect(result[1]! + result[2]!, 900);
      expect(result.containsKey(99), isFalse);
    });

    test('沒有人欠錢:整筆金額記到群組自己身上', () {
      final result = allocateCardPayment(
        remainingDueByChild: {1: 0, 2: -50},
        amount: 300,
        groupAccountId: 99,
      );
      expect(result, {99: 300});
    });

    test('沒有人欠錢且金額 <= 0:回傳空 map', () {
      final result = allocateCardPayment(
        remainingDueByChild: {1: 0},
        amount: 0,
        groupAccountId: 99,
      );
      expect(result, isEmpty);
    });

    test('金額 <= 0 或不欠款的子帳戶不會出現在結果裡', () {
      final result = allocateCardPayment(
        remainingDueByChild: {1: 1000, 2: 0, 3: -20},
        amount: 1000,
        groupAccountId: 99,
      );
      expect(result.containsKey(2), isFalse);
      expect(result.containsKey(3), isFalse);
      expect(result[1], 1000);
    });

    test('三個子帳戶不足額分攤:四捨五入誤差不會讓總和跟輸入金額對不上', () {
      final result = allocateCardPayment(
        remainingDueByChild: {1: 100, 2: 100, 3: 100},
        amount: 100,
        groupAccountId: 99,
      );
      final sum = result.values.fold(0.0, (a, b) => a + b);
      expect(sum, 100);
    });
  });

  group('attributePaymentsToPeriods', () {
    test('單筆繳款不足以沖完一期:歸屬到那一期本身', () {
      final home = attributePaymentsToPeriods(
        periods: [(periodId: -1, newSpend: 1000), (periodId: 0, newSpend: 500)],
        payments: [(paymentId: 1, amount: 400)],
      );
      expect(home[1], -1);
    });

    test('剛好沖完一期:歸屬到被沖完的那一期,不會多跑到下一期', () {
      final home = attributePaymentsToPeriods(
        periods: [(periodId: -1, newSpend: 1000), (periodId: 0, newSpend: 500)],
        payments: [(paymentId: 1, amount: 1000)],
      );
      expect(home[1], -1);
    });

    test('一筆繳款橫跨兩期:歸屬到最後沖到的那一期,不是開始沖的那一期', () {
      final home = attributePaymentsToPeriods(
        periods: [(periodId: -1, newSpend: 1000), (periodId: 0, newSpend: 500)],
        payments: [(paymentId: 1, amount: 1200)],
      );
      expect(home[1], 0);
    });

    test('多筆繳款依序沖銷同一期,第二筆才把它沖完並溢到下一期', () {
      final home = attributePaymentsToPeriods(
        periods: [(periodId: -1, newSpend: 1000), (periodId: 0, newSpend: 500)],
        payments: [
          (paymentId: 1, amount: 600),
          (paymentId: 2, amount: 700),
        ],
      );
      expect(home[1], -1); // 600 沒沖完 1000,留在原期
      expect(home[2], 0); // 700 沖完剩下的 400,再沖掉下一期 300(還沒沖完下一期的 500)
    });

    test('星展信用卡真實場景:819 沖完期一有找零,819 留在期一;5744 沖掉期一剩餘+全部期二,歸屬期二', () {
      // 期一(offset -2)2304、期二(offset -1)4259、期三(offset 0,當期)先忽略
      // 不放進 periods(這個函式只需要「有欠款的舊帳期」)。819 先繳、5744 後繳,
      // 兩筆合計 6563 剛好等於 2304+4259,把期一、期二都繳清——跟
      // 2026-08-18 直接查 BeeCount Cloud 正式資料庫核對「星展信用卡」帳戶的
      // 真實金額一致。
      final home = attributePaymentsToPeriods(
        periods: [
          (periodId: -2, newSpend: 2304),
          (periodId: -1, newSpend: 4259)
        ],
        payments: [
          (paymentId: 819, amount: 819),
          (paymentId: 5744, amount: 5744),
        ],
      );
      expect(home[819], -2);
      expect(home[5744], -1);
    });

    test('periods 為空:回傳空 map', () {
      final home = attributePaymentsToPeriods(
        periods: const [],
        payments: [(paymentId: 1, amount: 100)],
      );
      expect(home, isEmpty);
    });

    test('繳款金額遠超過所有帳期的欠款總和:歸屬到最新一期(不會索引越界)', () {
      final home = attributePaymentsToPeriods(
        periods: [(periodId: -1, newSpend: 100), (periodId: 0, newSpend: 100)],
        payments: [(paymentId: 1, amount: 9999)],
      );
      expect(home[1], 0);
    });
  });

  group('findEarliestUnpaidPeriodOffset', () {
    test('當期(offset 0)已清償:回傳 0', () async {
      final offset = await findEarliestUnpaidPeriodOffset(
        balanceOwedAsOf: (offset) async => 0,
      );
      expect(offset, 0);
    });

    test('連續兩期未繳(offset 0、-1),更早已清償:回傳較舊的 -1', () async {
      final offset = await findEarliestUnpaidPeriodOffset(
        balanceOwedAsOf: (offset) async {
          if (offset == 0) return 500;
          if (offset == -1) return 300;
          return 0; // -2 及更早已清償
        },
      );
      expect(offset, -1);
    });

    test('只有當期未繳,上一期已清償:回傳 0', () async {
      final offset = await findEarliestUnpaidPeriodOffset(
        balanceOwedAsOf: (offset) async => offset == 0 ? 500 : 0,
      );
      expect(offset, 0);
    });

    test('maxLookback 到頂會停止,回傳掃到的最舊 offset', () async {
      final offset = await findEarliestUnpaidPeriodOffset(
        balanceOwedAsOf: (offset) async => 999, // 永遠未繳清
        maxLookback: 5,
      );
      expect(offset, -4);
    });
  });
}
