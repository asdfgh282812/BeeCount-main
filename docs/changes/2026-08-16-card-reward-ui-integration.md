# 紅利回饋 UI 整合:交易詳情顯示、規則編輯頁修正、帳戶頁明細、首頁底部遮擋修復

延續 [2026-08-16-card-reward-rules.md](2026-08-16-card-reward-rules.md) 的資料模型,補上使用者實際會碰到的四塊 UI。

## 1. 交易詳情彈窗顯示紅利回饋

`lib/widgets/biz/transaction_detail_card.dart`:`_DetailBundle` 新增 `rewardRules` 欄位,`_loadBundle` 依交易的 `rewardRuleIds`(JSON list of syncId)逐一 `getCardRewardRuleBySyncId` 查回規則物件。新增 `_buildRewardSection`,在日期/時間下方渲染每條規則的名稱、費率(`percentage` 才顯示 `%`)與這筆交易的估算回饋金;沒有勾選任何規則時整塊回傳 `SizedBox.shrink()`,不佔位。

估算公式抽成共用函式 `lib/utils/card_reward_calc.dart`(`estimateCardRewardForRule`/`estimateCardRewardTotal`),原本只存在於 `transaction_entry_form.dart` 的私有方法 `_estimatedReward`/`_applyRounding` 改成呼叫這個共用函式——同一份公式現在被記帳表單、交易詳情卡、帳戶紅利回饋頁三處共用,數字保證一致。

## 2. 規則編輯頁修正

`lib/pages/account/card_reward_rule_editor_page.dart`:

- **回饋入帳帳戶改為必填**:新增規則時 `_rewardAccountId` 預設為 `widget.accountId`(本卡自己),`AccountCardPicker.show` 呼叫改成 `allowNull: false`,結構上不再有「未選擇」這條路徑。編輯舊規則若剛好是 `rewardAccountId == null`(此需求之前建立的資料)一樣回退顯示本卡。
- **修正天數欄位誤用錯誤 label 的 bug**:`settlementType == 'after_posting_date'` 時顯示的天數輸入框,原本錯誤沿用 `cardRewardRuleSettlementDayOfMonthField`(「回饋日期(當月第幾號)」)當 label——這是 `period_end` 用的欄位,跟「消費後幾天」的語意不同。新增 `cardRewardRuleSettlementDaysField`(「天數」)並改用它,同時補上天數欄位的簡單驗證(非負整數)。

## 3. 帳戶頁紅利回饋分組卡片 + 明細頁

新頁面 `lib/pages/account/card_reward_detail_page.dart`(`CardRewardDetailPage`):單一規則的週期彙總 + 逐筆交易列表,週期可獨立前後翻頁(跟帳單彙總卡片的週期導覽互不影響,因為規則自己的 `interval` 可能是 `calendar_month` 而非 `billing_cycle`)。頂部顯示規則名稱、費率 chip、週期區間、累積回饋金額,以及「還差多少消費達到上限」投影(`rateType == 'percentage' && capAmount != null` 時反推 `capAmount / (rateValue/100) - totalSpend`;`capAmount == null` 顯示「回饋無上限」;`fixed_amount` 類型只顯示 cap 原始金額,不做投影,語意不同)。交易列表每筆顯示分類圖示、名稱、日期/金額、估算回饋金,以及入帳時程徽章(`estimateCardRewardSettlementDate` 依 `settlementType` 算:`immediate_after_tx` = 交易當天、`after_posting_date` = 交易日 + N 天、`period_end` = 週期結束日 + 月偏移後對到指定日期並 clamp 到當月天數上限、`manual` 沒有可預期日期,不顯示徽章)。

帳戶詳情頁 `lib/pages/account/account_detail_page.dart`:信用卡帳戶的「交易明細」tab 在帳單彙總卡片之後、交易列表之前,新增 `_buildRewardSummaryCard`——只在有「啟用中」規則時顯示,每條規則一行(名稱+費率、週期區間、累積回饋金額),點擊進 `CardRewardDetailPage`。彙總資料來源是新 provider `cardRewardAccountSummaryProvider`(`lib/providers/card_reward_rule_providers.dart`),固定看每條規則自己本期(offset 0);明細頁翻頁用另一個 family provider `cardRewardRulePeriodSummaryProvider` 傳入 `offset`。兩者都是「一次性拉整個週期的交易再本地依 `rewardRuleIds` 過濾加總」,跟既有的 `accountBillingPeriodTransactionsProvider` 是同樣的模式(單一週期筆數有限,不需要分頁)——**這是前端估算,不是 server 排程結果**,真正入帳金額仍以 Server 端為準。

新增共用週期計算 `lib/utils/card_reward_period.dart`(`billingCyclePeriod`/`calendarMonthPeriod`/`cardRewardRulePeriod`),`account_detail_page.dart` 原本內嵌的 `_billingPeriod` 私有方法改成委派給 `billingCyclePeriod`,避免跟新頁面各自維護一份月份進位/借位邏輯。

## 4. 首頁明細列表被底部 TabBar 遮擋

`lib/pages/calendar/calendar_body.dart`:選中日交易列表的 `SingleChildScrollView` 底部 padding 原本只有 `verticalPadding`(8dp 量級),沒有扣掉浮動 TabBar 的高度。改成額外加上 `56.0(barHeight) + MediaQuery.of(context).padding.bottom(安全區) + 12(浮動間距) + 16(視覺留白)`,算式跟 `lib/app.dart` `_BeeBottomBar` 的 `SizedBox` 高度公式(`barHeight + bottomPadding + 12`)對齊,確保最後一筆記錄能完整滾出、懸浮在 Bar 上方而不是貼著/被蓋住。

## 5. 帳戶頁點擊行為對齊首頁

`lib/pages/account/account_detail_page.dart`:「交易明細」tab 點擊一筆交易原本直接 `Navigator.push` 進編輯頁(`_editTransaction`),跟首頁明細「點擊彈詳情卡、卡片裡才有編輯按鈕」的互動不一致。改成 `_openTransactionDetail` 呼叫 `showTransactionDetailCard`(跟首頁共用同一顆 widget),關掉後才做原本 `_editTransaction` 那組 provider invalidate(`accountStatsProvider`/`accountTransactionsPaginatedProvider`/`accountBillingPeriodTransactionsProvider`/`accountCategoryStatsProvider`/`cardRewardAccountSummaryProvider`)——這頁的交易列表跟帳單彙總是非 Stream 的 `FutureProvider`/`StateNotifierProvider`,不會像首頁那樣資料庫一變就自動重繪,所以還是要手動 invalidate。`_TransactionTile.onTap` 的型別從 `VoidCallback` 改成 `void Function(Category?)`,把 tile 內部本來就算好的 `category`(含轉帳分類特判)直接帶給呼叫端,不用在外層重新查一次。

## 6. 紅利回饋資料遺失的根因:`getAccountTransactions` 手動拼欄位漏欄

真正的 bug 出在 `lib/data/repositories/local/local_account_repository.dart` 的 `getAccountTransactions`——它用 `customSelect('SELECT * FROM transactions ...')` 拿到原始 row 後,手動一個個欄位 new 出 `Transaction` 物件,但這份手動清單只列了 9 個早期欄位,漏掉了後來加的 `rewardRuleIdsJson`(以及 `currencyCode`/`nativeAmount`/`merchant`/`refundOfSyncId`/`categorySyncIdOverride` 等一整批)。信用卡帳戶頁的交易明細列表、紅利回饋彙總卡片(`cardRewardAccountSummaryProvider`)、明細頁全部經由這個方法查交易,結果都是「查到的 `Transaction.rewardRuleIdsJson` 恆為 null」——這解釋了兩個現象:①從帳戶頁點進交易詳情卡,紅利回饋規則資訊消失;②帳戶頁頂部紅利回饋卡片永遠算出 `+0`(`matched = txs.where((t) => t.rewardRuleIds.contains(rule.syncId))` 因為 `rewardRuleIds` 永遠是空 list,永遠匹配不到)。修法是把手動欄位列表換成 Drift 生成的 `db.transactions.map(row.data)`,用 schema 自己的欄位定義轉型,不會再漏新欄位。

## 7. 自然月 vs. 帳單月跨月拆分

規則的檢視視窗統一改成帳戶的**帳單週期**(`billingCyclePeriod(billingDay, offset)`),不再讓 `interval == calendar_month` 的規則自己单独按自然月翻頁(舊版 `cardRewardRulePeriod`/`calendarMonthPeriod` 已刪除,見 `lib/utils/card_reward_period.dart`)。若規則以自然月算上限、而帳單週期橫跨兩個自然月(如 8/5~9/4),`lib/providers/card_reward_rule_providers.dart` 新增的 `_summarizeRuleWindow` 會用 `splitPeriodByCalendarMonth` 把視窗切成每個自然月各自查詢/加總,結果放進 `CardRewardRuleSummary.monthlyBreakdown`(`lib/models/card_reward_summary.dart`);`interval == billing_cycle` 或視窗沒跨自然月時 `monthlyBreakdown` 是 null,行為跟舊版一致。`CardRewardDetailPage._buildSummaryCard` 依 `monthlyBreakdown` 是否存在切換渲染:null 時維持原本「單一大數字 + 上限投影」;非 null 時逐月列出「M 月(起訖)」+「符合條件消費」+ 上限投影文案 + 該月回饋金額(對齊使用者提供的 Web 端參考設計)。逐筆交易列表的入帳時程徽章(`estimateCardRewardSettlementDate` 的 `period_end` 分支)也改成用交易自己所在自然月的 `periodEnd`,不是整顆帳單週期的 `periodEnd`,避免月初的交易被套用月底那個自然月的入帳日推算。

## 8. 「消費後立即入帳」支援天數

`immediate_after_tx` 現在也讀 `settlementDays`(語意:0 = 消費當天入帳、1 = 隔天、以此類推),沒設時退化成 0(等同舊行為)。`lib/utils/card_reward_calc.dart` 的 `estimateCardRewardSettlementDate` 把 `immediate_after_tx`/`after_posting_date` 合併成同一個 `case`,都套用 `happenedAt.add(Duration(days: rule.settlementDays ?? 0))`。編輯頁(`card_reward_rule_editor_page.dart`)天數輸入框的顯示條件從只有 `after_posting_date` 擴大到兩種 settlementType 都顯示;切到 `immediate_after_tx` 且欄位還空著時自動帶入 `'0'`。存檔邏輯本來就是「不管哪個 settlementType 都讀 `_settlementDaysCtrl.text`」,不用改;序列化(`EntitySerializer.serializeCardRewardRule`/`sync_engine_apply.dart` 的 `payload['settlementDays']`)本來就是欄位直通,不區分 settlementType,所以這次只是把 UI 補齊、沒有動 wire 格式。

## 未涵蓋範圍

- 交易詳情卡的回饋區塊、帳戶頁彙總卡片、明細頁三處都是**前端估算**(沿用既有 `docs/changes/2026-08-16-card-reward-rules.md` 就定調的原則),不會反映 `minSpendThreshold`/共同上限群組等只有 Server 端排程才看得到完整資料的邏輯。
- 明細頁的入帳時程徽章同樣是前端投影,不是查詢 Server 端真實入帳紀錄(本地資料模型本來就沒有這張表,見架構文件)。
- 使用者提供的 MOZE 參考截圖裡「消費後幾天(逐筆)」等下拉選項文字與本 app 既有的 `settlementType` 列舉(`immediate_after_tx`/`after_posting_date`/`period_end`/`manual`)用詞不完全一致——這次只修正既有列舉下「動態顯示天數欄位」的實作缺陷(見 §2),沒有改動列舉本身或新增列舉值,避免跟已對齊的 Server schema 產生分歧。
