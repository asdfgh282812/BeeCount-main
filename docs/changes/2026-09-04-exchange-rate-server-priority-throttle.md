# 已登入 server 端时汇率节流应优先信任 server 源

## 问题

用户反馈:登入 BeeCount Cloud 后,App 端换算显示的资产总额(如 accounts_page 的
"≈TWD ..." 净资产)与 server/web 端算出的数字对不上。

## 根因

`_refreshExchangeRatesImpl`([lib/providers/currency_providers.dart](../../lib/providers/currency_providers.dart))
的拉取顺序本身没问题——`_fetchAndStoreRatesForBase` 已经是「先试 server
(`beecountCloudProviderInstance.fetchExchangeRates`),失败才降级公网 CDN 链」。
问题出在**节流层**:`force=false` 时只要本地 `getLastFetchedAt(base)` 在 24h 内,
无论当前缓存的 `source` 是不是 `'server'`,都直接跳过、不会尝试改拉 server。

于是常见的触发序列是:

1. 未登入 / 登入前用公网源(`frankfurter`/`fawazahmed0`)拉过一次汇率并落库缓存;
2. 用户登入 BeeCount Cloud,`beecountCloudProviderInstance` 变为非 null;
3. `accounts_page.dart` `initState` 静默调用 `refreshExchangeRatesFromUi()`
   (force=false),但因为 24h 节流命中,直接判定"无需拉取",**从未真正尝试过
   server 源**;
4. App 端继续用登入前缓存的公网汇率算总额,与 server/web 面板(永远用
   `/read/exchange-rates`)的数值不一致,且要等本地缓存过期(最长 24h)才会
   自然纠正。

再叠加 `ExchangeRateService`(`lib/services/currency/exchange_rate_service.dart`)
的公网源"粘性索引"(`SharedPreferences` 记住上次成功的 CDN,下次优先复用)——
App 与 server 即使都在同一天走公网兜底,也可能各自停在不同上游、数值不同。
这部分暂不动(server 已可用时 App 会优先用 server,不再触发这条路径),仅记录
备查。

## 修复

`lib/providers/currency_providers.dart`:

- 新增纯逻辑函数 `shouldSkipThrottledRefresh({cloudLoggedIn, cachedSource})`:
  未登入 server 端维持原节流行为;已登入但当前缓存 `source != 'server'` 时返回
  `false`(放行,不跳过)。
- `_refreshExchangeRatesImpl` 在「本来会被 24h 节流跳过」的分支里,追加读一次
  `beecountCloudProviderInstance` 和 `repo.getLatestAutoRates(base)`,把结果交给
  `shouldSkipThrottledRefresh` 判定是否真的跳过。未登入、或已登入但缓存已经是
  `'server'` 源时,行为与之前完全一致(不额外拉网)。
- 一旦某次刷新把缓存换成 `'server'` 源,后续 24h 内的节流判断会因为
  `cachedSource == 'server'` 而正常跳过——不会每次打开页面都重复打 server。

刻意没有改动的部分(超出本次范围):

- server 端 `stale` 标记仍不消费(注释在原地保留,MVP 既有取舍,见
  `_fetchAndStoreRatesForBase` 里的注释)。
- 未新增"登入成功后立即触发一次汇率刷新"的钩子——`accounts_page.dart` /
  `exchange_rate_page.dart` 本来就在 `initState` 里静默刷新一次,登入后用户
  重进这些页面即会命中新逻辑并纠正到 server 源,不需要额外挂钩子。

## 测试

`test/providers/currency_providers_test.dart` 新增
`shouldSkipThrottledRefresh` 分组,覆盖未登入/已登入+server源/已登入+公网源/
已登入+无缓存四种组合(纯逻辑单测,不打网络,与既有"拉取链走 IO 不在此测"的
约定一致)。
