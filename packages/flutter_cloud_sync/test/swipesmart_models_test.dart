import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';

void main() {
  group('SwipeSmartKeyStatus', () {
    test('fromJson 解析已連接狀態', () {
      final s = SwipeSmartKeyStatus.fromJson({
        'has_key': true,
        'masked': 'swp_abc12••••',
        'auto_mapped': 3,
      });
      expect(s.hasKey, isTrue);
      expect(s.masked, 'swp_abc12••••');
      expect(s.autoMapped, 3);
    });

    test('fromJson 解析未連接狀態(masked/auto_mapped 缺省)', () {
      final s = SwipeSmartKeyStatus.fromJson({'has_key': false});
      expect(s.hasKey, isFalse);
      expect(s.masked, isNull);
      expect(s.autoMapped, 0);
    });
  });

  group('SwipeSmartCard', () {
    test('fromJson 解析卡片目錄項目', () {
      final c = SwipeSmartCard.fromJson({
        'card_id': 'sw-card-123',
        'bank_name': '永豐銀行',
        'card_name': 'SPORT卡',
      });
      expect(c.cardId, 'sw-card-123');
      expect(c.bankName, '永豐銀行');
      expect(c.cardName, 'SPORT卡');
    });
  });

  group('SwipeSmartCardRecommendation', () {
    test('fromJson 解析已對照帳戶的推薦結果', () {
      final r = SwipeSmartCardRecommendation.fromJson({
        'card_id': 'sw-card-123',
        'bank_name': '永豐銀行',
        'card_name': 'SPORT卡',
        'rule_name': '運動獎勵',
        'estimated_reward': 30.0,
        'effective_rate': 0.05,
        'note': '指定通路上限300/月',
        'alert_messages': ['本月已使用 27%'],
        'account_id': 'acc-sync-1',
        'account_name': '永豐SPORT卡',
      });
      expect(r.cardId, 'sw-card-123');
      expect(r.estimatedReward, 30.0);
      expect(r.effectiveRate, 0.05);
      expect(r.alertMessages, ['本月已使用 27%']);
      expect(r.accountId, 'acc-sync-1');
      expect(r.accountName, '永豐SPORT卡');
    });

    test('fromJson 解析未對照帳戶的推薦結果(account_id/account_name 為 null)', () {
      final r = SwipeSmartCardRecommendation.fromJson({
        'card_id': 'sw-card-999',
        'bank_name': '玉山銀行',
        'card_name': '熊本熊卡',
        'estimated_reward': 12.0,
        'effective_rate': 0.02,
      });
      expect(r.accountId, isNull);
      expect(r.accountName, isNull);
      expect(r.ruleName, isNull);
      expect(r.note, isNull);
      expect(r.alertMessages, isEmpty);
    });
  });
}
