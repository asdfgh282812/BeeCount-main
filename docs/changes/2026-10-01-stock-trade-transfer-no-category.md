# 股票買賣綁定轉帳不帶分類

## 為什麼
同一種「定期定額買進」的綁定轉帳,在 Web 交易詳情一筆分類顯示「轉帳」、一筆顯示「—」。
- App 建立買賣(含定期定額補期、手動買賣)時,`createStockTrade` 把綁定轉帳的 `categoryId` 指向本機虛擬「轉帳」分類,推上 Cloud 就帶了分類。
- Cloud 排程執行定期定額(`recurring_materializer.py` `materialize_due_stock_rules`)與 Web 手動買賣(`snapshot_mutator._apply_stock_tx`)建立的轉帳,本來就沒有分類(Web 轉帳沒有分類概念)。

## 改了什麼
- `lib/data/repositories/local/local_repository.dart` `createStockTrade`:現金類買賣的綁定轉帳 `categoryId` 改為 null。App 自己顯示時轉帳由 UI 層特判名稱,且 pull 回來時 `sync_engine_apply.dart` 會對無分類轉帳補虛擬分類,所以 App 端畫面不受影響。
- `test/repositories/stock_trade_repository_test.dart`:買進後斷言綁定轉帳 `categoryId` 為 null。

## 沒做
- 已經推上 Cloud、帶著「轉帳」分類的舊交易不會自動改,需在 Web 編輯/重建,或之後另做一次性修正。
- 股利(income)的「股利」分類維持不變。

## 入口
無新入口;影響「投資理財帳戶 → 買進/賣出/定期定額」產生的轉帳交易。
