# 股票收盤價改 Yahoo 優先、證交所備援(Cloud 端)

## 問題
2026-10-02 17:28 App 持股現價仍顯示 10/1。證交所 `STOCK_DAY_ALL` 當時還是 `1151001`,
Yahoo 已有 10/2 13:30 收盤。原流程對台股先抓證交所,拿到舊日期;`CLOSE_RETRY_WINDOW`
(3 小時)過後 `_close_done` 視為完成,而證交所有這檔所以不會走 Yahoo,快取就卡在前一天。

## 變更(BeeCount-Cloud `src/services/securities/quotes.py::_fetch_close`)
- 所有市場收盤價都先打 Yahoo(只抓有人持有的標的)。
- 台股/櫃買中 Yahoo 失敗的標的,才用證交所/櫃買全市場資料補;補寫時若官方
  `quote_time` 比快取舊就跳過,避免晚更新的舊資料蓋掉新價。
- 測試:`tests/test_stock_holdings.py`(Yahoo 優先、官方舊資料不覆蓋、Yahoo 失敗走官方)。

## 取捨
- Yahoo 為非官方 API,故保留官方備援。
- 台股清單同步(搜尋用)仍走證交所,不受影響;收盤價不再順便由該路徑更新。

## 入口 / 生效
無新 UI。Cloud 部署後,下一次排程(台股約 15:00 起每 5 分鐘)生效;
已卡住的快取在 App 持股頁下拉刷新(盤中才會補抓)或隔天排程時更新。
