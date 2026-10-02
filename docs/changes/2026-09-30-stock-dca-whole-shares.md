# 股票定期定額:台股只買整數股

接續 `2026-09-29-stock-dca-fixes.md` 最後留下的問題。使用者確認台股定期定額要
跟券商一樣只買整數股:台股不論定期定額或盤中零股都進證交所撮合,最小單位
1 股,券商沒辦法把 0.5 股放進集保戶頭;美股(含複委託)是券商吃下整股再切碎
分配,允許碎股。Cloud 端同一套改動見 BeeCount Cloud `docs/STOCK_HOLDINGS_SD.md`
§10.2。

## 算法(`lib/services/investment/stock_dca.dart::stockDcaOrder`)

依市場拆兩種,整數股市場清單 `kStockDcaWholeShareMarkets = {TW, TWO}`,必須跟
Cloud `trade_fees.STOCK_DCA_WHOLE_SHARE_MARKETS`、Web
`STOCK_DCA_WHOLE_SHARE_MARKETS` 一致:

- **整數股(台股)**:每期金額是**含手續費**的扣款上限。股數 = 使「成交價金 +
  手續費 ≤ 金額」的最大整數,手續費依實際價金計。起點用券商公式
  ⌊(金額 − 以整筆金額估的手續費) ÷ 股價⌋,再往上試(實際價金小、手續費也可能
  小,省下的錢可能夠多買 1 股)。轉帳金額 = 實際價金、feeAmount = 手續費,
  零頭留在交割帳戶。
- **碎股(其它市場)**:維持原本的「金額 = 成交價金、手續費另計、股數 = 金額 ÷
  股價」。

使用者給的券商例子(3,000/月、手續費 1 元;股價 150/100/200 → 19/29/14 股、
扣款 2,851/2,901/2,801)是三端共用的測試案例。

## 生成(`LocalRepository._materializeStockRule`)

- 改用 `stockDcaOrder`,餘額檢查用實際扣款(`order.total`)。
- 連 1 股都買不起 → 新的 `RecurringRuleStockSkipReason.amountTooSmall`:**略過
  這一期、推進進度**並發通知。跟「餘額不足」停在原期重試不同——價格不會因為
  重試變低,停住會讓後面每一期都卡死。Cloud 同名 `amount_too_small`。

## UI

- `recurring_stock_rule_editor_page.dart`:金額欄下方顯示整數股/碎股說明;本地
  有這檔標的的報價時,試算「可買 N 股、扣款 X(含手續費 Y)、Z 不扣款」(或買
  不起 1 股的提示),自訂手續費會即時套用。
- What's New 3.7.0 的定期定額說明補上整數股/碎股。

## 入口

同 `2026-09-29-stock-dca-fixes.md`:帳戶 → 投資理財帳戶 → 持股頁「定期定額」,
或新增交易 → 交易類型列最後的「定期定額」。

## 刻意沒做

- 港股/日股/陸股/韓股仍當碎股(有「一手」或券商碎股方案,各家不同),需要時把
  市場代碼加進三端清單即可。
- 台股定期定額常見最低手續費 1 元,但帳戶預設最低 20 元是給單筆交易用的;沒有
  另外做「定期定額預設費率」,要在規則打開「自訂手續費」改。
- 已經用碎股生成的舊交易不重算。

## 測試

- `test/services/investment/stock_dca_test.dart`:券商範例、預設費率、多買 1 股、
  買不起、美股碎股(跟 Cloud/Web 同一組數字)。
- `test/repositories/recurring_stock_dca_test.dart`:原本碎股的期望值改成整數股
  (3,000 @97.45 → 30 股、轉帳 2,923 + 手續費 20);新增買不起 1 股略過、美股
  碎股。
