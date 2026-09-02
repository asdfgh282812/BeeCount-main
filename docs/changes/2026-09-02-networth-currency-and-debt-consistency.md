# 帳戶頁淨資產與 server 端不一致(外幣匯率 + 欠款/應收)

用戶回報帳戶頁「淨資產(折TWD)」與 BeeCount Cloud web 端算出的數字對不上,
拆解出兩個獨立根因,一個在 app 端修,一個在 server 端(`/Users/andy/BeeCount-Cloud`,
另一個 git repo)修。

## 根因一:新增/改幣種帳戶不會立刻拉匯率(app 端)

**現象**:新建一個外幣帳戶(如 JPY 信用卡)後,帳戶頁淨資產卡 / 群組小計會把
它整條排除,即使該帳戶「納入總餘額」是開的、對應幣種的匯率其實抓得到——
重開 app 就會恢復正常。

**根因**:`effectiveRatesProvider`([lib/providers/currency_providers.dart](../../lib/providers/currency_providers.dart))
只有 `rateRefreshTickProvider` 被 bump 才會重算,而唯一會 bump 它的背景拉取
入口 `refreshExchangeRatesFromUi(ref)` 只在
[accounts_page.dart](../../lib/pages/account/accounts_page.dart) 的
`initState` 觸發一次(`WidgetsBinding.instance.addPostFrameCallback`),且
帶 `force: false`(24h 節流,節流 key 只認 base 幣種、不認 quote 集合)。若
使用者是在該頁第一次掛載「之後」才新增/改成某個外幣帳戶,整個 session 都
不會再有任何程式碼主動去拉那個新幣種的匯率(`account_edit_page.dart` 存檔
時原本完全沒有呼叫任何匯率刷新),直到重啟 app 讓 `initState` 重新跑一次。
`rate_math.dart` 的「缺匯率就是缺失,絕不靜默按 1.0」設計(README D5)本身
沒問題,問題是這個帳戶的匯率根本沒被主動抓過。

**修法**:[account_edit_page.dart](../../lib/pages/account/account_edit_page.dart)
存檔成功後、`Navigator.pop` 之前,若新增/改成的幣種不是主幣種且
`effectiveRatesProvider` 目前沒有它的匯率,`await refreshExchangeRatesFromUi(ref,
force: true, extraQuotes: {currency})`——跟 `transaction_entry_form.dart`/
`transfer_form.dart` 遇到新幣種時已經在用的既有模式對齊。刻意選在存檔當下
（widget 一定還掛載,不會有「頁面已關閉、WidgetRef 已失效」的競態)同步
`await` 完再 pop,而不是 fire-and-forget。

**取捨**:只覆蓋「之後新建/改幣種」的帳戶;已經存在、剛好卡在這個問題上的
舊帳戶不會自動修好,使用者仍需重開 app 一次或等 24h 節流自然過期。沒有做
更大的重構(例如把 `effectiveRatesProvider` 改成真正 reactive 的 DB
stream)——那能一併解決潛在的「WidgetRef 在背景刷新完成前被 dispose」的
理論競態,但範圍/風險比這次回報的問題大很多,故未動。

## 根因二:欠款/應收(借還款)server 端完全沒併入淨資產(server 端)

**現象**:app 端的「借還款」功能有一筆「對方欠我」(應收)且沒關「排除計入
總額」,app 端淨資產有把它算進總資產;BeeCount Cloud web 端的淨資產卡/
趨勢圖完全沒有這筆錢——不是過濾邏輯錯,是 web 端的淨資產聚合(
`AccountsPage.tsx` 的 `converted` useMemo,以及 `workspace_net_worth_history`
趨勢端點)壓根沒有查過 debts 表,兩個功能在 server 端是完全不相交的兩塊。

**修法**(`/Users/andy/BeeCount-Cloud`):
- 新增 `GET /workspace/debts` 端點(`src/routers/read/workspace.py`
  `list_workspace_debt_totals` + 共用 helper
  `_workspace_debt_currency_totals`):跨帳本彙總未結清(`closed_at is null`
  且 `remaining = principal - repaid > 0.01`)、未排除
  (`excluded_from_total is not True`)的欠款,按帳本幣種分桶回傳
  `{currency, receivable_total, payable_total}`,口徑對齊既有的
  `/ledgers/{id}/debts`(`remaining_amount` 而非 `principal_amount`,避免已
  還清部分重複計入)。
- `workspace_net_worth_history` 同一個 helper 算出的 debt 總額,折算到 base
  後當「目前未結清餘額」當常數疊加進 `_net()` 回傳的每一個月分桶,而不是
  真正逐月回放歷史欠款餘額(debt 沒有像 account 一樣的逐月交易流水可以
  replay)。**已知取捨**:早期月份的資產/負債會因此偏移(相當於把「現在」
  的欠款餘額投影回過去),只保證最新一個月會跟淨資產卡對上帳——比完全不算
  好,但不是精確的歷史。
- Web 前端(`frontend/apps/web/src/pages/sections/AccountsPage.tsx`)在
  `refresh()` 並行拉 `fetchWorkspaceDebtTotals`,`converted` useMemo 裡把
  receivable/payable 折算後加進頭部三個數字(`netWorth`/`assetTotal`/
  `liabilityTotal`),跟 accounts 同口徑「缺匯率整幣種剔除,絕不按 1 折
  入」。**已知取捨**:刻意沒有把欠款併入 `buckets`/`mergedGroups`(資產構成
  donut、「詳情」分幣種卡片)——跟 app 端「資產構成」圖本來就不含欠款分類
  對齊,只修頭部數字;分幣種詳情卡片暫時不會反映欠款金額,留待有需要時再
  擴充 `CurrencyAssetCard`。

**測試**:`tests/test_workspace_debt_totals.py`(新增,3 個案例:receivable/
payable 分幣種彙總、排除 excluded_from_total 與已結案、排除已還清)+
`tests/test_net_worth_history.py` 新增 2 個案例(應收併入淨值、
excluded_from_total 的欠款不併入)。跑過 `tests/`(除了兩個跟本次改動無關
的既有失敗案例——`test_i18n.test.ts` 的 zh-TW/en key parity、
`test_import_simple.py::test_accounts_parent_before_child_required`,在
`main` 分支未套用這次改動時就已經失敗,已用 `git stash` 驗證過)全綠。
