# AI 記帳:民國年換算 + 排除合併帳單主帳戶

## 背景

使用者回報兩個 AI 記帳問題:

1. 台灣發票/收據常用民國年格式(如 `115/09/20`),AI 記帳提示詞沒有教模型換算成西元年,容易解析錯誤或直接失敗。
2. 從通知截圖自動記帳時,AI 把交易掛到「星展信用卡」這個合併帳單的**主帳戶**上——主帳戶(`Account.type == 'account_group'`)是純管理容器,本來就不該被指定為交易的實際入帳帳戶(手動選擇器 `account_card_picker.dart` 已經排除,但 AI 記帳路徑漏掉了這道檢查)。

## 變更

### 1. 民國年換算(`lib/ai/core/prompt_builder.dart`)

在 `defaultTemplate` 的 `time` 欄位說明(item 2)新增一條規則:民國年 + 1911 = 西元年,並補一個發票範例(`115/09/20` → `2026-09-20`),讓 few-shot 範例覆蓋到這個少見但常見於台灣單據的格式。

### 2. 排除 `account_group` 帳戶,兩層防線

- **提示詞候選清單**(`lib/ai/core/ai_extraction_context.dart` `forLedger`):建構 `{{ACCOUNTS}}` 候選時,比照既有的 `hidden` 過濾,新增 `a.type == 'account_group'` 過濾——主帳戶不會出現在餵給 AI 的帳戶清單裡,從源頭降低命中機率。
- **落庫前的名稱比對**(`lib/services/billing/bill_creation_service.dart` `_matchAccountByName`):候選池 `pool` 新增 `a.type != 'account_group'` 過濾。這是最後一道防線——即使使用者自訂了提示詞模板(繞過上面的候選清單),或 AI 幻覺回傳了主帳戶名稱,也不會被比對命中;未命中則照既有邏輯落回預設帳戶或不掛帳戶。

兩處都沿用 `account_card_picker.dart:123` 既有的 `type != 'account_group'` 判斷慣例,行為與手動選擇器一致。

## 測試

- `test/ai/core/ai_extraction_context_test.dart` 新增:主帳戶不出現在 `ctx.accounts` 候選清單。
- `test/services/billing/bill_creation_service_test.dart` 新增:AI 回傳的帳戶名稱即使與主帳戶完全相等,也不會命中,交易的 `accountId` 為 `null`。

## Out of scope

- 使用者設定裡的「預設支出/收入帳戶」(`default_expense_account_id` 等)沒有加同樣的 `account_group` 檢查——這組設定本來就是透過既有的帳戶選擇器 UI 挑選,該 UI 早已排除主帳戶,不屬於本次回報的問題路徑。
