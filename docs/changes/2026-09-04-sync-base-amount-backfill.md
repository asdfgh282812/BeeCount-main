# 修补 base_amount 同步缺角(自愈,不需逐笔手动重推)

## 背景

延续 [2026-09-04-expense-income-fee-discount.md](./2026-09-04-expense-income-fee-discount.md)。
使用者回报:BeeCount Cloud 網頁端「更新交易」對話框顯示某筆支出手續費=40、
本金=2651、總額=2691,但同一筆交易在 App(macOS dev 版)上手續費/折扣顯示
都是 0,面板呈現「沒有啟用手續費/折扣」。

排查(見對話記錄的 forensics,未寫進程式碼註解——本地 sqlite 直接查
`transactions` 表)發現:App 本地資料庫這筆交易的 `fee_amount = 40.0`(已經
同步下來),但 `base_amount` 是真正的 SQL `NULL`(不是空字串)。App 的
`_buildFeeDiscountPanel` 顯示邏輯是用 `initialBaseAmount != null` 當「是否
啟用」的閘門(見 `transaction_entry_form.dart`),`base_amount` 缺了,面板
自然判定成「未啟用」,顯示 0/0——不是使用者少按了什麼,是**本地資料本身
不完整**。

根因:這筆交易是在 App 支援手續費/折扣(v51)之前建立的,某段歷史
`SyncChange` 的 payload 只帶了 `feeAmount`/`discountAmount` 卻漏了
`baseAmount` 鍵。`sync_engine_apply.dart` 的 `_applyTransactionChange` 對這
四個欄位是「缺鍵不覆蓋」語意(`hasBaseAmountKey ? d.Value(baseAmount) :
d.Value.absent()`)——這個語意本身是對的(保護老客戶端 partial payload 不
把本地已有值沖掉),但代價是:一旦某次歷史寫入就是漏了這個鍵,
`base_amount` 會永遠卡在 `null`,而且 App 的 pull cursor 早就越過那個
change_id,不會再重新收到——使用者只能一筆一筆在網頁端手動重新按「更新
交易」,逼出一次新的、欄位齊全的 `SyncChange`,才能把這筆交易修好。使用者
明確表示這不可接受(資料筆數多,不可能逐筆手動修):「同步的時候，應該要
自己判斷 app 本地資料庫是否有缺資料，不然這樣子就是會缺資料」。

## 解法:App 端自己算得出來,不依賴對端補鍵

`amount`(淨額)永遠是正確、必然存在的欄位(不管 payload 缺不缺
`baseAmount`,`amount` 都會照樣同步)。`baseAmount`/`feeAmount`/
`discountAmount`/`amount` 四者的關係是 [computeFeeDiscountNetAmount](../../lib/utils/amount_calculator.dart)
定義的一條線性公式,已知其中三個就能反推第四個——不需要對端重新推一次
`SyncChange`。

### `lib/utils/amount_calculator.dart`

新增 `computeBaseAmountFromNet`——`computeFeeDiscountNetAmount` 的反函數:
`amount`/`feeAmount`/`discountAmount` 已知,反推 `baseAmount`(expense:
`base = amount - fee + discount`;income:`base = amount + fee - discount`)。
跟正函數共用 `Decimal` 精度處理,不會有浮點漂移。

### `lib/cloud/sync/sync_engine_apply.dart`(future-proof:擋住未來新進的 pull)

`_applyTransactionChange` 的 update / insert 兩條路徑都加了同一段自愈判斷:
缺 `baseAmount` 鍵,但「有效的」`feeAmount`/`discountAmount`(payload 帶了就
用 payload 值,沒帶就退回本地既有值)非 0——代表這筆交易的手續費/折扣明顯
已啟用——且最終會落地的 `baseAmount` 仍是 `null`,就用
`computeBaseAmountFromNet` 從 `amount` 反推,不再讓它永遠停留在 `null`。
`type == 'transfer'` 不套用(轉帳手續費/折損是獨立的 delta 語意,見
`amount_calculator.dart` 頂部注釋)。

只在「反推結果」缺席時介入,對端如果哪天把 `baseAmount` 鍵補齊了,一樣直接
採用 payload 值,不會被這條自愈邏輯蓋掉。

### `lib/data/db.dart`(retroactive:修好已經卡在本地的舊資料)

上面兩處只能防住**以後**新進來的 pull——這筆使用者回報的交易已經在本地卡
住,沒有新的 `SyncChange` 會再次觸發 apply,單靠 sync 路徑的修補永遠碰不到
它。所以另外加了 v52 schema 版本 + 一次性 migration:直接對
`transactions` 表跑

```sql
UPDATE transactions
SET base_amount = CASE
  WHEN type = 'expense' THEN
    ROUND(amount - COALESCE(fee_amount, 0) + COALESCE(discount_amount, 0), 2)
  ELSE
    ROUND(amount + COALESCE(fee_amount, 0) - COALESCE(discount_amount, 0), 2)
END
WHERE base_amount IS NULL
  AND type IN ('expense', 'income')
  AND (COALESCE(fee_amount, 0) != 0 OR COALESCE(discount_amount, 0) != 0);
```

公式跟上面 App 端的 `computeBaseAmountFromNet` 完全對齊(兩邊不能各自發
明)。只動 `base_amount IS NULL` 且 fee/discount 明顯已啟用的行,不碰其餘
資料,SQLite `UPDATE ... WHERE` 對空結果集是幾乎零成本的操作,不需要额外
的「只跑一次」旗標——升級到 v52 這一步本身就是只跑一次(Drift
`onUpgrade` 語意)。全新安裝走 `onCreate`,沒有存量資料,不需要這段。

## 刻意不做的事

- 沒有呼叫任何 Cloud API 去抓「目前的完整快照」來對比修正——`amount` 在
  本地已經是正確、必然存在的資料,純本地算術就能解掉這個特定缺角,不需要
  多一趟網路往返,也不用等對端修正歷史寫入路徑。
- 沒有觸碰 BeeCount Cloud(`../BeeCount-Cloud/`)側的程式碼——歷史寫入路徑
  為什麼會漏帶 `baseAmount` 鍵這件事本身沒有深入追查到底(牽涉另一個
  repo,且即使修好了 Cloud 端,已經寫進 `sync_changes` 表的歷史記錄本身也
  不會被改寫),this fix 選擇在 App 端做到「不管對端漏不漏這個鍵都能自己
  兜住」,比追一次性的歷史寫入 bug 更一般化、也更能直接解決使用者回報的
  症狀。
- 沒有做成 `AppCursorStore.hasBackfilled`/`replayAllChanges` 那套「一次性
  entity-type backfill」機制(`lib/cloud/sync/sync_engine.dart`
  `_entityTypeBackfillTags`)——那套是「App 舊版本不認識某個 entity type
  或欄位,直接丟棄,cursor 照常前進」的場景,重放歷史 `SyncChange` 就能把
  舊資料重新餵一次給*現在會讀這個欄位*的新版 apply 邏輯。這裡的根因不一
  樣:歷史 `SyncChange` 的 payload 本身就沒有這個鍵,重放同一份 payload
  結果還是一样缺,replay 沒有用——必須用本地既有的 `amount`/`feeAmount`/
  `discountAmount` 反推,而不是重新拉一份「還是缺鍵」的舊資料。

## 附帶:明細卡補上「(內含手續費 $X)」小字提示

使用者順帶提出另一個落差:BeeCount Cloud 網頁端「更新交易」對話框在金額
下方標了「(內含手續費 $40)」這種小字,App 端 `transaction_detail_card.dart`
的明細卡只顯示總額,看不出裡面含了多少手續費/折扣。

`lib/widgets/biz/transaction_detail_card.dart` 的 `_buildNoteAmountRow` 把
金額改成 `Column`,總額下面多一行 `_buildFeeDiscountSubtitle`——`type` 為
`expense`/`income` 且 `feeAmount`/`discountAmount` 非 0 時才顯示,轉帳/餘額
調整不套用。label 優先用使用者自訂的 `feeLabel`/`discountLabel`,沒有才退回
`transactionFeeLabelHint`/`transactionDiscountLabelHint` 的預設文案「手續費」
/「折扣」。金額本身仍然透過 [AmountText](../../lib/widgets/biz/amount_text.dart)
畫,不是手刻字串格式化——這樣才能繼承「隱藏金額」隱私開關跟既有的币种符號
/千分位格式化,不用自己重做一份。

新增 l10n key `txDetailFeeDiscountPrefix`(「內含」/"Includes")跟
`txDetailFeeDiscountSeparator`(「、」/", "),只寫進 `app_zh_TW.arb` +
`app_en.arb`(按 [[feedback_l10n_policy_change]] 的既有政策,`app_zh.arb`/
`app_ko.arb` 不再維護)。括號本身(`(`/`)`)沒有走 l10n,直接寫死在
Dart——中英文對括號的用法一致,沒有必要為兩個標點符號多開一組 ICU 訊息。

測試見 `test/widgets/transaction_detail_card_fee_discount_test.dart`(4
案例:顯示手續費金額、自訂 label 優先於預設文案、fee/discount 皆 0 時不顯示、
轉帳交易不套用)。

## 測試

- `test/sync/transaction_base_amount_backfill_apply_test.dart`(新增,4
  案例):update 缺鍵反推、insert 缺鍵反推、fee/discount 都是 0 時不強行
  反推(維持 `null`)、payload 顯式帶 `baseAmount` 鍵時優先採用 payload 值
  不走反推。
- `test/data/migration_v52_test.dart`(新增,5 案例):直接執行遷移用的同
  一段 SQL,驗證支出/收入公式方向、fee/discount 皆 0 時不動、既有
  `base_amount` 不被覆蓋、`transfer` 不套用。
- `test/widgets/transaction_detail_card_fee_discount_test.dart`(新增,4
  案例,見上面「附帶」小節)。
- 全套 `flutter test`(1103 案例)綠燈,無既有測試回歸。
