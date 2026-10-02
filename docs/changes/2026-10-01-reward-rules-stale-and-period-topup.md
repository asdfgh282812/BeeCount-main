# 信用卡回饋:殘留別張卡規則 + 整期結算後補綁回饋不入帳

## 問題(使用者回報)
一筆週期性交易用「修改此記錄」換了信用卡帳戶、忘了選回饋項目,事後補選後:
1. 明細卡的回饋項目比該卡的規則還多(5 條 vs 3 條),多的 2 條是原本那張卡的規則。
2. 補綁回饋後重跑「信用卡回饋入帳」排程,該期少算的兩筆沒補入帳。

## 原因與修法
### 1. 殘留別張卡的規則(App)
`CardRewardRuleSelector` 以傳入的既有選擇初始化並原樣回傳;記帳表單 chip/選單只列「所選卡」的規則,
殘留的別張卡規則 id 看不到也取消不掉,存檔時被原封寫回交易。
- `transaction_entry_form.dart`:送出前把回饋規則過濾成屬於所選帳戶的。
- `card_reward_rule_selector.dart`:確認時只回傳屬於該卡的規則。
- `transaction_detail_card.dart`:明細只顯示屬於交易所在帳戶的規則(舊資料立即不再顯示殘留項;
  重新編輯儲存一次即從資料中清除)。
- Cloud 結算本來就依 `account_sync_id` 過濾,殘留規則不會造成誤發,不需改。

### 2. 整期結算後補綁不入帳(Cloud)
`card_reward_payout.py::_materialize_period_end` 以「期末日期」為去重鍵,該期入帳過一次後,
事後補綁/補記的交易永遠不會再被結算。改為**補發差額**:重算該期 `capped_reward`,
比「該期已入帳總額」多時只補發差額(去重鍵 `期末日#N`,備註/通知為「補發」);
較少(退款等)不動。逐筆結算(`immediate_after_tx`)本來就會對新綁定的交易補發,不受影響。
重跑方式:`POST /internal/tasks/materialize-recurring`(admin)或等 15 分鐘排程。
測試:`tests/test_card_reward_payout.py::test_period_end_tops_up_when_reward_rule_bound_after_settlement`。

## 注意
`tests/test_card_reward_payout.py::test_analytics_nets_refund_and_reward_reversal` 在修改前就失敗(既有問題),與本次無關。
