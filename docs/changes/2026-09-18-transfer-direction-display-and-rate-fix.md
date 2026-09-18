# 转账:补齐「转出→转入」帐户显示 + 修正跨币别折算金额

用户反馈(2026-09-18):转账在多个列表/明细页面看不出转到哪个帐户;跨币别转
账的「≈折算金额」跟使用者实际换到的金额对不上(截图案例:玉山外币户 JPY
9,016 手动转入台币户 1,828,但列表/明细显示「≈1841.92」)。

## 问题一:转帐没有显示转出/转入帐户

主页交易列表(`lib/widgets/biz/transaction_list.dart`)本来就有正确处理——它
查的记录自带 `account`(转出)+ `toAccount`(转入),拼成
`'$accountName → $toAccountName'` 传给 `TransactionListItem.accountName`。但
以下几处入口各自维护自己的查询/拼装逻辑,当初新增时漏了转入帐户这一段:

- [`lib/widgets/biz/transaction_detail_card.dart`](../../lib/widgets/biz/transaction_detail_card.dart) ——交易明细卡片。
  `_loadBundle()` 原本只查 `tx.accountId` 对应的帐户,现在同样查
  `tx.toAccountId`(含 `toAccountSyncIdOverride` 的共享帐本兜底,镜像
  `accountFuture` 的处理),存进新增的 `_DetailBundle.toAccount` 字段;
  `_buildDetailRows` 转帐时把帐户行文字换成 `'转出户名 → 转入户名'`。
- [`lib/pages/calendar/calendar_body.dart`](../../lib/pages/calendar/calendar_body.dart) ——日历当日交易列表。底层查询
  `getTransactionsByDate`(`lib/data/repositories/local/local_transaction_repository.dart`)
  原本的返回记录只带 `account`,现新增 `toAccount` 字段(批量查帐户时把
  `toAccountId` 也并进同一次查询;`_hydrateSharedOverridesFull` 共享帐本兜底
  同步补上 `toAccountSyncIdOverride` 反查)。为了保持记录形状(record 是结构
  化类型)一致,`getTransactionsByDateRange`(目前没有 UI 调用方,只在接口/
  实现里存在)一并加了同名字段,否则两者共用的 `_hydrateSharedOverridesFull`
  没法编译。
- [`lib/pages/transaction/search_page.dart`](../../lib/pages/transaction/search_page.dart) ——搜索结果列表本来就是走
  `repo.transactionsWithCategoryAll`(跟主页同一个三连 join,早就有
  `toAccount`),只是调用 `TransactionListItem` 时忘了传 `accountName`/
  `isTransfer`,现在补上。
- [`lib/pages/project/project_detail_page.dart`](../../lib/pages/project/project_detail_page.dart)、
  [`lib/pages/tag/tag_detail_page.dart`](../../lib/pages/tag/tag_detail_page.dart)、
  [`lib/pages/transaction/category_detail_page.dart`](../../lib/pages/transaction/category_detail_page.dart) ——这三个页面底层查询
  (`getTransactionsByProject`/`watchTransactionsByTag`/
  `watchTransactionsByCategory`)另有其他调用方共用,不适合改返回形状。改成
  页面内部用 `accountsStreamProvider`/`allAccountsStreamProvider` 建一份
  `Map<int, Account>`,按 `t.accountId`/`t.toAccountId` 查名字拼接。

  已知限制(刻意不处理,风险/收益不成比例):这三个页面对共享帐本
  `accountSyncIdOverride`/`toAccountSyncIdOverride` 的 synthetic 帐户完全没
  有反查——本来就没有,不是这次引入的退化。真要补,需要额外一轮
  `getSharedAccountBySyncId` 批量查询,留给之后有需要再做。

## 问题二:跨币别转账「≈折算金额」跟实际转入金额对不上

根因在 [`lib/widgets/transaction/transfer_form.dart`](../../lib/widgets/transaction/transfer_form.dart) 的 `_submit()`——它一直
没有把 `currencyCode`/`nativeAmount` 传给 `repo.addTransaction`/
`updateTransaction`,导致两者都落到
`LocalRepository._resolveTxCurrency`(`lib/data/repositories/local/local_repository.dart`)
的兜底逻辑:用「转出金额 × 转出币别对本位币的即时/全域汇率」重新算一次
`nativeAmount`。这跟这里实际使用的转入金额(可能是使用者手动填的、或是关掉
「采用线上汇率」时自订的汇率)完全脱钩——`toAmount` 字段虽然存了正确的转入
金额,但列表卡片/明细页的「≈」小字读的是 `nativeAmount`,不是 `toAmount`。

修正:在 `_submit()` 里,跨币别转账时直接用使用者实际使用的转入金额
(`resolvedToAmount`,转入帐户自己的币别)换算到帐本本位币当作
`nativeAmount`：
- 转入帐户币别刚好等于本位币时(最常见,例如外币户转回台币户)——直接等于
  `resolvedToAmount`,免查表,一定精确。
- 转入帐户币别也不是本位币时——才需要再查一次
  `effectiveRatesForLedgerProvider` 转一手(`computeNativeAmount`,
  `lib/services/currency/rate_math.dart`)。查不到汇率就放弃,不传
  `currencyCode`/`nativeAmount`,退回原本的兜底逻辑(不强行带入不可靠的值,
  也不会比修正前更差)。

`updateTransaction`/`addTransaction` 两处调用都补了这两个参数;同币别转账
路径完全不受影响(`resolvedCurrencyCode`/`resolvedNativeAmount` 仍是
`null`,跟旧行为一致)。

## 修复一提交后的追加修正:文字溢出 + 既有资料回填

第一轮修好帐户方向显示后,使用者截图回报两个新问题:

1. **`RIGHT OVERFLOWED BY x PIXELS`**——`'$accountName → $toAccountName'`
   拼出来的字串比单一帐户名长很多(例如「永豐日幣 → 永豐大戶」),
   [`transaction_list_item.dart`](../../lib/widgets/biz/transaction_list_item.dart) 的
   `_buildSecondaryInfo()` 原本用一个裸 `Text`(没有 `maxLines`/`overflow`)
   塞进 `Row(mainAxisSize: MainAxisSize.min)`,遇到超出可用宽度的长字串就直接
   撑爆版面。修正:把这个 `Text` 包一层 `Flexible` + `maxLines: 1` +
   `overflow: TextOverflow.ellipsis`,超长时改成省略号截断,不影响原本较短
   帐户名的显示。

2. **既有转帐记录的「≈折算金额」还是没变**——这是预期中的资料层问题,不是
   `transfer_form.dart` 那个修正没生效:`nativeAmount` 是存档当下的快照
   字段,修 code 只影响之后新增/编辑的转帐,不会回头改已经存在 DB 里的旧
   记录。使用者截图用的是同一笔在第一轮修复前就已经存在的转帐(JPY 9,016 →
   TWD 1,828),自然还是显示旧的 `nativeAmount`(1841.92)。

   修正方式:在 [`lib/data/db.dart`](../../lib/data/db.dart) 加一个 v62 迁移
   (`schemaVersion` 61→62),一次性回填所有既有转帐记录——只处理「转入帐户
   币别 = 帐本本位币」这个免查表、保证精确的情况(直接 `native_amount =
   to_amount`),这正好是使用者回报的案例(JPY 帐户转回 TWD 帐户,帐本本位币
   也是 TWD)。转入帐户也不是本位币的情况缺乏「当时汇率」可回溯,维持原样,
   跟 `transfer_form.dart` 那边查不到汇率时的降级行为一致。纯资料 UPDATE,
   不改 schema DDL,新增测试见
   [`test/data/migration_v62_test.dart`](../../test/data/migration_v62_test.dart)
   (直接对这段 UPDATE SQL 的逻辑做验证:本位币案例回填、非本位币案例不动、
   非转帐交易不受影响、重跑一次确认冪等)。

   使用者下次打开 App 触发一次 DB 升级(`schemaVersion` 从 61 升到 62)后,
   这笔既有记录的「≈」就会自动变成 1828,不需要手动编辑重存。

## 未涉及范围

- `account_detail_page.dart` 的 `TransactionTile`(帐户详情页自己的交易列表)
  本来就正确处理了转出/转入帐户显示(`isTransferOut`/`isTransferIn` +
  `displaySubtitle`),而且该组件本来就故意把转帐排除在「≈折算金额」显示之外
  (它的假设是转帐没有可靠的 `nativeAmount`)。这次修正后 `nativeAmount` 对
  跨币别转帐已经准确,但没有改动这个组件去启用显示——维持原样,避免超出这次
  修复范围。
- `getTransactionsByDateRange` 目前在 UI 侧没有任何调用方,只是为了跟
  `getTransactionsByDate` 共用同一个 hydration helper 而同步加了 `toAccount`
  字段,行为本身没有新增用途。
