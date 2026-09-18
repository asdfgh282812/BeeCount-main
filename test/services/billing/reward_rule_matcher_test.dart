// matchUniqueRewardRuleByLabel 契约测试(design 2026-09-18 §2/§5.1)。
//
// 锁死:
// - 完全命中 / 模糊互相包含命中 → 唯一一条时采用
// - 零命中 / 多筆命中 → 一律降级 null,不猜、不取分数最高
// - 大小写 / 首尾空白正规化后再比对
// - effectiveRewardRules 的 enabled + 有效期间窗口过滤(同
//   card_reward_rule_selector.dart 的 _eligible)

import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/services/billing/reward_rule_matcher.dart';

CardRewardRule _rule({
  int id = 1,
  String? syncId = 'rule-1',
  required String label,
  bool enabled = true,
  DateTime? startsAt,
  DateTime? endsAt,
}) {
  return CardRewardRule(
    id: id,
    accountId: 1,
    syncId: syncId,
    label: label,
    rateType: 'percentage',
    rateValue: 5,
    rounding: 'round',
    totalRounding: 'round',
    calcBasis: 'transaction_date',
    interval: 'billing_cycle',
    settlementType: 'manual',
    enabled: enabled,
    sortOrder: 0,
    startsAt: startsAt,
    endsAt: endsAt,
  );
}

void main() {
  group('matchUniqueRewardRuleByLabel', () {
    test('完全命中(正规化后相等)', () {
      final rules = [_rule(label: '网购5%回饋')];
      final matched = matchUniqueRewardRuleByLabel('网购5%回饋', rules);
      expect(matched?.label, '网购5%回饋');
    });

    test('模糊互相包含命中:target 是 label 的子串', () {
      final rules = [_rule(label: '海外實體消費8%回饋')];
      final matched = matchUniqueRewardRuleByLabel('海外實體消費', rules);
      expect(matched?.label, '海外實體消費8%回饋');
    });

    test('模糊互相包含命中:label 是 target 的子串', () {
      final rules = [_rule(label: '網購')];
      final matched = matchUniqueRewardRuleByLabel('網購5%回饋活動', rules);
      expect(matched?.label, '網購');
    });

    test('零命中 → null(不猜)', () {
      final rules = [_rule(label: '一般消費')];
      final matched = matchUniqueRewardRuleByLabel('海外消費', rules);
      expect(matched, isNull);
    });

    test('多笔命中 → 降级 null(不取分数最高/回饋最多那条)', () {
      final rules = [
        _rule(id: 1, syncId: 'r1', label: '網購5%回饋'),
        _rule(id: 2, syncId: 'r2', label: '網購3%回饋'),
      ];
      final matched = matchUniqueRewardRuleByLabel('網購', rules);
      expect(matched, isNull);
    });

    test('大小写 / 首尾空白正规化', () {
      final rules = [_rule(label: '  Netflix Reward  ')];
      final matched = matchUniqueRewardRuleByLabel('netflix reward', rules);
      expect(matched?.label, '  Netflix Reward  ');
    });

    test('空字串 target → null', () {
      final rules = [_rule(label: '網購')];
      final matched = matchUniqueRewardRuleByLabel('   ', rules);
      expect(matched, isNull);
    });

    test('候选清单为空 → null', () {
      expect(matchUniqueRewardRuleByLabel('網購', []), isNull);
    });
  });

  group('effectiveRewardRules', () {
    test('停用规则被排除', () {
      final rules = [_rule(label: 'A', enabled: false)];
      expect(effectiveRewardRules(rules), isEmpty);
    });

    test('尚未生效(startsAt 在未来)被排除', () {
      final future = DateTime.now().add(const Duration(days: 1));
      final rules = [_rule(label: 'A', startsAt: future)];
      expect(effectiveRewardRules(rules), isEmpty);
    });

    test('已过期(endsAt 在过去)被排除', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      final rules = [_rule(label: 'A', endsAt: past)];
      expect(effectiveRewardRules(rules), isEmpty);
    });

    test('沒有 syncId 被排除(比对回传要用 syncId)', () {
      final rules = [_rule(label: 'A', syncId: null)];
      expect(effectiveRewardRules(rules), isEmpty);
    });

    test('在有效期间内且启用 → 保留', () {
      final rules = [_rule(label: 'A')];
      expect(effectiveRewardRules(rules), hasLength(1));
    });
  });
}
