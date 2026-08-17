# 延後入帳四修:時區日期偏移、結帳日邊界對齊、交易歷史清單改用入帳歸屬日

日期:2026-08-18
背景:延續同日稍早的[對帳模式](2026-08-18-reconciliation-mode.md)、
[對帳模式拆頁與週期連動修正](2026-08-18-reconciliation-page-and-sync-fix.md)、
[對帳模式三修](2026-08-18-reconciliation-deferred-grouping-unconfirm-sync.md)。
使用者這次報四個問題:(1) 在 App 設延後入帳為 8/5,web 端顯示 8/4(時區偏一
天);(2) 結帳日=5 號時,web 週期顯示 `8/05–9/05`(5 號算舊期),App 顯示
`8/05–9/04`(5 號算新期),兩端邊界定義相反;(3)「取消延後」;(4) 信用卡帳戶
「交易明細」tab 帳單彙總卡片下方的交易列表仍按 `happened_at` 查,延後入帳的
交易不會出現在延後目標那一期。排查後(3)在同日稍早的三修裡已經修完(App
push 端 + BeeCount Cloud `sync_applier.py::_merge_from_spec` 都已正確處理顯式
`null`),這次只動 (1)(2)(4)。

## 1. 時區偏移:`deferredPostingAt` 改成「純日期」語意,不再經過本地時區轉換

**根因**(對應
[card_reward_period.dart 修改前](2026-08-18-reconciliation-mode.md)):
`account_reconciliation_page.dart` 延後入帳的 `showDatePicker` 選完後,直接把
回傳的 `DateTime`(本地時區 flavor 的年月日,例如 UTC+8 裝置上的
`2026-08-05 00:00:00`「本地午夜」)傳給 `onDefer`,存進 Drift、push 時
`entity_serializer.dart` 對它呼叫 `.toUtc()`——UTC+8 裝置的本地午夜換算成 UTC
會變成前一天 16:00(`2026-08-04T16:00:00Z`),BeeCount Cloud web 端讀這個 ISO
字串一律用 `getUTCFullYear/Month/Date()`(`isoToDateInput` 系列 helper,理由見
`frontend/apps/web/src/components/dialogs/AccountReconciliationSection.tsx`
文件註解)取年月日,算出來就是 8/4,比使用者在 App 選的 8/5 早一天。

**改法**:
- `account_reconciliation_page.dart`:`showDatePicker` 選完後,不直接把回傳值
  傳給 `onDefer`,改成
  `DateTime.utc(picked.year, picked.month, picked.day)`——用選到的年月日重新
  構造成 UTC 午夜,跟 web 版 `dateInputToIso`(`` `${value}T00:00:00+00:00` ``)
  同一個表示法,序列化時 `.toUtc()` 是 no-op。
- `sync_engine_apply.dart`:pull 下來的 `deferredPostingAt` 不再 `.toLocal()`
  (`reconciledAt` 是真時刻,維持 `.toLocal()` 不動;只有 `deferredPostingAt`
  這個純日期欄位改)。UTC 午夜的 instant 經過本地時區轉換一律不會改變它「代表
  哪一天」的意圖,但直接把轉換後的本地 flavor 物件的 `.year/.month/.day` 拿去
  跟其它「本地時區構造」的日期比較(例如帳單週期邊界)還是有風險,所以乾脆
  不轉,讓它维持 UTC flavor。
- `lib/utils/reconciliation.dart`:新增 `deferredPostingCalendarDate(DateTime
  raw)` helper——`raw.toUtc()` 之後重新取年月日構造成本地 flavor 的
  `DateTime`,是讀出「這個 `deferredPostingAt` 代表哪一天」的唯一權威方法
  (不能直接讀 Drift 從 SQLite 讀回來的物件的 `.year/.month/.day`,那個是
  `fromMillisecondsSinceEpoch` 預設的本地 flavor,對西半球時區裝置會早一天)。
  `effectiveDate()` 改用這個 helper。

**為什麼不索性把 `deferredPostingAt` 存成 SQLite 的純日期字串(而不是
epoch 時間戳)**:`Transactions.deferredPostingAt` 是既有的 `DateTimeColumn`
(schemaVersion 37 就定義了),改欄位型態要動 migration,風險跟成本遠大於
「約定俗成:這個 datetime 欄位的權威值永遠是 UTC 午夜,讀寫都不做本地時區
轉換」這種應用層慣例。web 端本來就是用同一招(`datetime` 欄位 + 前端
UTC-getter 慣例),兩端現在一致。

## 2. 結帳日邊界對齊:`billingCyclePeriod` 邊界語意從 inclusive-start 改成
   inclusive-end,對齊 BeeCount Cloud `services/credit_card.py`

**根因**:BeeCount Cloud `credit_card.py` docstring 明確定義「涵蓋『上次結帳日
(不含)~這次結帳日(含)』的消費」(`compute_cycle_period_billing`/
`compute_group_billing` 的查詢邊界也是 `_ATTR_DATE > cycle_start_end_of_day
AND _ATTR_DATE <= cycle_end_end_of_day`,下界排除結帳日當天、上界包含)。App
端 `lib/utils/card_reward_period.dart::billingCyclePeriod` 改版前反過來:
`start = DateTime(anchorYear, anchorMonth, day)`(結帳日當天本身,inclusive)、
`end = nextStart - 1 day`(下次結帳日前一天,把下次結帳日排除在外)——同一個
結帳日在 App 端被算進「以它為起點的新一期」,在 web 端被算進「以它為終點的
舊一期」,兩端對「結帳日當天算哪一期」的判斷完全相反。使用者在 App 設延後
入帳為結帳日當天,web 端看仍在舊期,App 端看已經進新期,對不上。

**改法**(`lib/utils/card_reward_period.dart`):
- 錨點月份的選法從「今天 < 結帳日就退回上個月」改成「今天 > 結帳日就推到下個
  月」,對齊 Cloud `billing_cycle_containing` 的 `cycle_end` 選法(今天剛好是
  結帳日時,今天算進今天結的這期)。
- 回傳的 `end` 直接是這次結帳日本身(不再 -1 天);`start` 是**上次**結帳日
  隔天(不是結帳日本身)——這樣 `start`/`end` 維持 inclusive-both 語意
  (`>= start && <= end`),所有既有呼叫端(`getAccountTransactions(startDate:,
  endDate:)`、`getAccountStatementTransactions(cycleStart:, cycleEnd:)`)完全
  不用改,因為它們原本就是拿 `start`/`end` 直接餵 inclusive-both 的查詢——現在
  值對了,查詢邏輯自動跟著對。
- 新增 `_clampDay` 月底夾斷(比照 Cloud `_clamp_day`/`_shift_billing_day`,每次
  平移都用原始 `billingDay` 重新夾斷,不拿已夾斷過的 `.day` 反推),
  `billingDay=31` 這種值在二月不再溢位成三月初(Dart `DateTime` 建構子預設不
  夾斷,`DateTime(2026,2,31)` 會變成 `2026-03-03`)。這是改版前就存在的獨立
  潛在 bug,順手一起修。

**顯示文字要換算**:`start` 現在是「上次結帳日隔天」,不是結帳日本身,所以
UI 顯示「結帳日 – 結帳日」這種 label 文字的地方(不是查詢用途)要手動
`start.subtract(const Duration(days: 1))` 換算回結帳日。改了 5 處:
`account_detail_page.dart`(帳單彙總卡片週期文字、帳戶資訊 tab 結帳日文字、
紅利回饋彙總卡片週期文字,新增 `_formatCycleLabel` helper 給前兩處共用)、
`card_reward_detail_page.dart`(規則明細頁週期文字)、
`account_reconciliation_page.dart`(對帳頁 header 副標題)。**沒有改**
`card_reward_detail_page.dart` monthly breakdown(`month.periodStart`,來自
`splitPeriodByCalendarMonth` 的自然月分段,本來就是真實日曆月邊界,不是結帳日
label)跟 `account_reconciliation_page.dart` 新增遺漏交易的 `initialDate:
cycle.start`(拿真實查詢邊界當預設值本來就對,不需要換算)。

**跟 [對帳模式三修](2026-08-18-reconciliation-deferred-grouping-unconfirm-sync.md)
的關係**:`reconciliation.dart::defaultDeferredPostingDate` = 
`billingCyclePeriod(billingDay, cycleOffset + 1).start`,文件註解一直寫「下一
期帳單第一天(結帳日隔天)」——但改版前的 `billingCyclePeriod.start` 其實是
結帳日當天本身,不是隔天,這個函式的實際行為早就跟自己的文件註解對不上,是
同一個邊界 bug 的另一個症狀。這次改完 `billingCyclePeriod` 後
`defaultDeferredPostingDate` 不需要再改一行代碼,語意自動變正確。

## 3. 交易明細 tab 交易歷史清單:改用入帳歸屬日 COALESCE

**根因**:`account_detail_page.dart::accountBillingPeriodTransactionsProvider`
(信用卡帳戶「交易明細」tab 帳單彙總卡片 + 下方交易列表共用的資料源)呼叫
`getAccountTransactions(startDate:, endDate:)`,底層 SQL 一直只按
`happened_at` 過濾。[三修](2026-08-18-reconciliation-deferred-grouping-unconfirm-sync.md)
已經把「對帳模式」自己的查詢(`getAccountStatementTransactions`)改成
`COALESCE(deferred_posting_at, happened_at)`,但那是對帳頁專用的獨立方法,
沒有動到這個更常用的一般帳單彙總/交易列表查詢路徑,延後入帳的交易在這裡仍卡在
原始消費日所在的那一期。

**改法**:沒有直接把這個 provider 改接 `getAccountStatementTransactions`——
後者的 member 帳戶判斷收窄成對帳清單專用口徑(expense/income 只認
`account_id`,transfer 只認 `to_account_id`,其它 type 不收),跟這個一般交易
列表原本「`account_id OR to_account_id`,含轉出」的更寬口徑不一樣,直接換會
悄悄讓「轉出這張卡」之類的交易從列表消失。改成給既有
`getAccountTransactions`(interface 在 `account_repository.dart`,實作在
`local_account_repository.dart`,經 `local_repository.dart` 透傳)加一個
`bool byEffectiveDate = false` 參數,true 時把 SQL 的日期過濾欄位從
`happened_at` 換成 `COALESCE(deferred_posting_at, happened_at)`,其餘
type/flow 篩選邏輯不變。`accountBillingPeriodTransactionsProvider` 呼叫時傳
`byEffectiveDate: true`。

**UI**:`_TransactionTile`(`account_detail_page.dart`,交易列表逐行渲染,
這個一般交易明細 tab 跟对帐页共用類似結構但各自獨立元件)在既有的轉帳/帳本
標籤旁新增 `tx.deferredPostingAt != null` 時顯示 `InfoTag(l10n
.reconciliationDeferredBadge)`(「已延後」,沿用對帳頁已有的 l10n key,不用
新增翻譯)。

## Verification

- `flutter analyze`:0 error(改動的 11 個檔案本身 0 issue,既有 info 級雜訊
  跟本次改動無關)。
- `flutter test`:734 個測試全過(跟改動前基準一致,`billingCyclePeriod` 沒有
  既有的直接單元測試覆蓋,靠既有整合測試面沒有回歸)。
- 手動驗證待補:(a) 雙端(App + web)結帳日=5 號的帳戶,結帳日當天記一筆
  消費,兩端週期彙總卡片/對帳頁都要把這筆歸到同一期;(b) App 選延後入帳日期
  後,web 端讀到的日期要跟 App 選的完全一致(不差一天);(c) 延後到下一期的
  交易,在「交易明細」tab 帳單彙總卡片下方的交易列表裡要出現在延後目標那期,
  帶「已延後」標籤;(d) `billingDay=31` 的帳戶在二月的週期邊界正確夾斷到
  28/29 號,不溢位到三月。
