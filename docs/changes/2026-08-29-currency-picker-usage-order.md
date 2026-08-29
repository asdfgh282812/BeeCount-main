# 币种选择器按常用度排序

## 背景

所有选择币别的界面（账本本位币、账户币种、交易币种、外观设置主币种、汇率页）此前只是
「常用币种（`kCommonCurrencyCodes` 固定 11 个）置顶 + 其余按地区固定顺序」，与用户实际
使用情况无关——例如账本设成 TWD、账户里用了 JPY/USD，这两个仍然要滚很远才能找到。

## 改动

- [`lib/providers/currency_providers.dart`](../../lib/providers/currency_providers.dart) 新增
  `currencyPickerPriorityProvider`（`FutureProvider<List<String>>`）：排序 = 当前账本本位币
  （`currentLedgerCurrencyProvider`，恒居首）→ 按账户使用数量降序的币种（同数量按字母序）。
  watch `statsRefreshProvider`，账户增删改后自动重算。
- [`lib/widgets/currency/currency_picker_sheet.dart`](../../lib/widgets/currency/currency_picker_sheet.dart)
  的 `showCurrencyPickerSheet`：排序改为 `currencyPickerPriorityProvider` 结果 → 其余
  `kCommonCurrencyCodes` 补位 → 其余按地区原顺序。原先仅有的静态置顶逻辑保留作为兜底
  （provider 未就绪时退化为空列表，直接落到 `kCommonCurrencyCodes` 顺序，行为不比改动前差）。
- [`account_edit_page.dart`](../../lib/pages/account/account_edit_page.dart) 和
  [`ledgers_page_new.dart`](../../lib/pages/main/ledgers_page_new.dart) 里各自的
  `_showCurrencyPicker`（历史上复制的简化版弹窗：无排序、无汇率展示）改为直接调用共享的
  `showCurrencyPickerSheet`，而不是维护第二份 UI——顺带让账户/账本这两个入口也带上汇率展示
  和国旗图标，与其余选币界面外观统一。

## 未覆盖

- 排序信号只用「账户数量」，不是「交易频率」；一个只挂了一次的冷门币种账户和一个天天用的
  常用币种账户权重相同。账户表本身没有交易频率字段，做频率排序需要额外查询交易表按币种聚合，
  超出本次「让常用币种别再滚老远」的诉求，先用账户数量这个更便宜的信号。
- `currencyPickerPriorityProvider` 里的账户查询是全局的（`getAllAccounts()`，跟
  `AccountRepository.getUsedCurrencies()` 一样未按账本过滤，账户本身是 user-global 实体），
  多账本用户会看到「所有账本的账户币种」而非仅当前账本的。
