import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/widgets/biz/transaction_entry_form.dart';

void main() {
  group('shouldQueueSwipesmartRecommendation', () {
    test('條件都滿足時應該觸發', () {
      expect(
        shouldQueueSwipesmartRecommendation(
          hasKey: true,
          kind: 'expense',
          amount: 600,
          merchant: '蝦皮',
          lastQuery: null,
        ),
        isTrue,
      );
    });

    test('沒有 Key 不觸發', () {
      expect(
        shouldQueueSwipesmartRecommendation(
          hasKey: false,
          kind: 'expense',
          amount: 600,
          merchant: '蝦皮',
          lastQuery: null,
        ),
        isFalse,
      );
    });

    test('收入交易不觸發', () {
      expect(
        shouldQueueSwipesmartRecommendation(
          hasKey: true,
          kind: 'income',
          amount: 600,
          merchant: '蝦皮',
          lastQuery: null,
        ),
        isFalse,
      );
    });

    test('金額為 0 不觸發', () {
      expect(
        shouldQueueSwipesmartRecommendation(
          hasKey: true,
          kind: 'expense',
          amount: 0,
          merchant: '蝦皮',
          lastQuery: null,
        ),
        isFalse,
      );
    });

    test('商家為空不觸發', () {
      expect(
        shouldQueueSwipesmartRecommendation(
          hasKey: true,
          kind: 'expense',
          amount: 600,
          merchant: '',
          lastQuery: null,
        ),
        isFalse,
      );
    });

    test('同一組(金額,商家)已查過不重打', () {
      expect(
        shouldQueueSwipesmartRecommendation(
          hasKey: true,
          kind: 'expense',
          amount: 600,
          merchant: '蝦皮',
          lastQuery: (amount: 600, merchant: '蝦皮'),
        ),
        isFalse,
      );
    });

    test('金額或商家其中一個變了要重打', () {
      expect(
        shouldQueueSwipesmartRecommendation(
          hasKey: true,
          kind: 'expense',
          amount: 601,
          merchant: '蝦皮',
          lastQuery: (amount: 600, merchant: '蝦皮'),
        ),
        isTrue,
      );
    });
  });
}
