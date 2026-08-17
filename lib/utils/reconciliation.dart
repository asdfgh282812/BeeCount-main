/// 對帳模式(§2.10 MOZE_FEATURE_GAP_SD.md,對齊
/// doc.moze.app/reconciliation/statement-mode)共用的歸屬日/正負號邏輯,跟
/// 信用卡帳單彙總卡片共用同一份 [billingCyclePeriod],確保週期算出來的區間
/// 一致。
///
/// 2026-08-18 改版:拿掉了原本的 `statementCyclePeriod`(內部多減 1、代表
/// 「最近一次已結束的週期」的獨立語意)。對帳模式不再維護自己的週期狀態,
/// 一律直接沿用 `account_detail_page.dart` 最上方帳單彙總卡片目前選取的
/// `cycleOffset`(跟 [billingCyclePeriod] 同一套 offset=0 是「涵蓋今天的本期」
/// 語意),避免兩處各自算出不同週期、畫面對不上。
library;

import '../data/db.dart' as db;
import 'card_reward_period.dart';

/// 交易的「入帳歸屬日」:有延後入帳日就用它,否則用實際發生日。對帳/信用卡
/// 帳單彙總等需要判斷交易落在哪一期帳單的地方一律呼叫這個函式,不要各自用
/// `happenedAt` 重寫——跟 BeeCount Cloud
/// `services/deferred_posting.py::attribution_date_expr()` 的 COALESCE
/// 語意一致。
DateTime effectiveDate(db.Transaction tx) =>
    tx.deferredPostingAt ?? tx.happenedAt;

/// 延後入帳的預設目標日:下一期帳單的第一天,比照 web 版行為(結帳日隔天)。
DateTime defaultDeferredPostingDate(int? billingDay, int cycleOffset) =>
    billingCyclePeriod(billingDay, cycleOffset + 1).start;

/// 對帳清單裡單筆交易的正負號口徑,跟 BeeCount Cloud
/// `compute_cycle_period_billing.new_spend`/`get_account_statement` 一致:
/// expense 記正(增加應繳)、income 記負(減少應繳)、轉入這張卡/群組視為
/// 還款/預繳,比照 income 記負值。呼叫方必須先篩選過「這筆交易屬於這期
/// 帳單清單」(expense/income 發生在成員帳戶,或 transfer 轉入成員帳戶)才
/// 呼叫這個函式——它不做篩選,只算正負號。
double signedStatementAmount(db.Transaction tx) {
  switch (tx.type) {
    case 'expense':
      return tx.amount;
    case 'income':
    case 'transfer':
      return -tx.amount;
    default:
      return tx.amount;
  }
}

/// BeeCount Cloud `services/card_rewards.py::REWARD_CATEGORY_NAME` 的字面值
/// 慣例——App 端沒有 `card_reward_rule` 實體,對帳模式的「回饋」徽章只做
/// 簡化版:分類名稱等於這個字串就標記,不做規則反查/多筆合併。
const String kRewardCategoryName = '回饋金';

bool isRewardCategoryName(String? categoryName) =>
    categoryName == kRewardCategoryName;
