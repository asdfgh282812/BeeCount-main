# 週期交易「修改連同未來週期」全欄位同步(App + Web)

**入口**:編輯任一筆週期性交易(明細頁鉛筆 / 網頁交易列表)→ 彈窗選「修改連同未來週期」。

## 問題
原本沒綁專案的週期交易,編輯時綁上專案並選「連同未來週期」,後面各期不會跟著改。
根因是兩端都只轉發一小部分欄位,而且「清空」沒被當成一種修改:

- **App**:`transaction_editor_page.dart` / `transfer_form.dart` 只把 type、金額、分類、帳戶、備註、商家
  轉給 `updateRuleAndFuture`;標籤、專案、回饋項目、手續費/折扣都沒帶。
  另外 `RecurringTransactions` 規則表根本沒有專案與手續費/折扣欄位,所以規則本身也存不下來,
  之後自動補生成的期數也不會有。
- **Web**:`update-from` 的 payload 用 `|| undefined` / `?? undefined` 組裝,值為空就省略該鍵,
  server 視為「不動」→ 移除專案/備註/商家後面各期仍保留舊值;手續費/折扣/回饋項目完全沒送。
  (server `WriteRecurringUpdateFromRequest` 其實早就支援這些欄位,且顯式 `null` 會清除。)

## 變更
### App
- `db.dart`:schema v65,`recurring_transactions` 新增 `project_sync_id`、`base_amount`、`fee_amount`、
  `fee_label`、`discount_amount`、`discount_label`(全 nullable,免回填)。
- `local_recurring_rule_repository.dart`:`createRule` / `updateRuleFields` 支援新欄位(更新用 tri-state `Value`,可清空)。
- `local_repository.dart`:
  - `updateRuleAndFuture` 新增 `clearNote`/`clearMerchant`、專案與手續費/折扣 tri-state;
    寫入規則,並套用到 anchor 之後未單獨編輯過的每一期(專案走 `setTransactionProjectLink`)。
  - 修正既有隱患:批次更新時 `rewardRuleIds` 未指定會被當成 null 洗掉,改為沿用該期原值。
  - `_createOccurrenceTransaction` 讓自動補生成的期數繼承專案與手續費/折扣。
- 編輯頁(一般 / 轉帳)把「表單最終狀態」整份轉發,含標籤 syncId、回饋項目、專案、手續費/折扣;空值=清除。
  新建週期規則時也一併帶入標籤/專案/手續費。
- 同步:`entity_serializer.dart` 規則 payload 恆發 `projectId`、`baseAmount`、`feeAmount`、`feeLabel`、
  `discountAmount`、`discountLabel`(含 null,Cloud merge 看「鍵有沒有出現」);`sync_engine_apply.dart`
  拉取時解析這些鍵(`containsKey` 保護,舊版 Cloud 缺鍵不沖掉本地值)。Cloud 端 `recurring_rule` merge spec 本來就有這些鍵,不需改。

### Web(BeeCount-Cloud)
- 新增 `frontend/apps/web/src/lib/recurringUpdateFrom.ts` 統一組裝 update-from payload:
  備註/商家/專案明確送 `null`、標籤/回饋送 `[]`、手續費/折扣未開啟時送 `null`;
  轉帳不送專案與手續費鍵(server 對轉帳規則送這些鍵會 400)。
  `GlobalEditDialogs.tsx` 與 `TransactionsPage.tsx` 兩處呼叫點改用它。

## 刻意不做
- 附件、匯率/幣別快照、帳單標記、拆帳、延後入帳:屬逐筆概念,維持不轉發(同原設計)。
- 規則列表頁自己的編輯頁(`recurring_rule_editor_page.dart`)沒有專案欄位,不傳新參數 = 不動既有值。
- 股票定期定額規則(`kind='stock_dca'`)已生成的期數一律不回頭改(同原設計)。

## 測試
- `test/repositories/recurring_rule_repository_test.dart`:新增專案/標籤/手續費/備註套用到規則與未來各期、以及清除的案例。
- Web `src/lib/recurringUpdateFrom.test.ts`。
