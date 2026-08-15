# 首页「明細」tab 改为日历视图，原列表挪到入口按钮后

## 背景

首页（底部 tab「明細」）原本是按日期分组的滚动交易列表；日历视图是从首页
头部一个日历图标按钮 `Navigator.push` 进去的独立页面
(`lib/pages/calendar/calendar_page.dart`)。本次改动按需求把两者的位置对调：
「明細」tab 现在直接显示日历（月历网格 + 选中日交易列表），原来的列表页
则挪到首页头部原「日历」按钮的位置，点击后以 push 页面的形式打开，并新增
与网页端一致的时间条件筛选（今日 / 七天内 / 一个月内 / 全部，默认今日）。

## 改动

- **`lib/pages/calendar/calendar_body.dart`（新增，取代 `calendar_page.dart`）**
  把原 `CalendarPage` 的月历网格 + 当日交易列表逻辑原样保留，但剥离外层
  `Scaffold`/`PrimaryHeader`（不再是独立页面，而是可嵌入 `HomePage` body 的
  `CalendarBody` widget）。原头部的「今天」跳转按钮改为放在日历卡片上方
  一个靠右的文字按钮。新增两个公开方法 `jumpToToday()` / `jumpToMonth()`
  （原来是 `_jumpToToday`/`_jumpToMonth` 私有方法），通过
  `GlobalKey<CalendarBodyState>` 暴露给 `HomePage`，用于「双击首页 tab 跳
  回今天」和「点头部年月摘要跳转指定月份」这两个原有交互。月份翻页/跳转时
  额外同步一份 `selectedMonthProvider`（原来由列表滚动可见性驱动），保持
  首页头部「收入/支出/结余」摘要随可见月份联动的行为不变。

- **`lib/pages/main/home_page.dart`（重写 body，头部改动一处图标）**
  - Body 由「StreamBuilder + TransactionList（FlutterListView 滚动列表）」
    换成 `Expanded(child: CalendarBody(key: _calendarKey))`。连带删除了
    只为支撑滚动列表存在的状态：`_isJumping`、可见性追踪
    (`_visibleHeaders`/`_onHeaderVisibilityChanged`/`_updateCurrentMonth`)、
    `FlutterListViewController`、tx stream 缓存 (`_txStream`/
    `_streamBuilderKey`/`_lastLedgerId`) 等。
  - 头部右上角原「日历」图标按钮（`Icons.calendar_month_outlined` →
    push `CalendarPage`）改为「明細」图标按钮
    （`Icons.receipt_long_outlined` → push 新的 `TransactionListPage`）。
  - 头部「年/月」点击（`_handleDateSelection`）原来是滚动列表跳转到目标
    月份，现在改为调用 `_calendarKey.currentState?.jumpToMonth(...)`。
  - `homeScrollToTopProvider`（双击首页 tab 触发）原语义是「滚动列表到
    顶部」，现改为「日历跳回今天」（`_calendarKey.currentState
    ?.jumpToToday()`），与列表页时代的用户习惯（双击回到默认视图）对齐。
  - 不再监听 `homeSwitchToStreamProvider` / `sharedResourceRefreshProvider`
    ——这两个信号原本是驱动 `TransactionList` 从预加载缓存切到实时 Stream
    用的，日历视图走的是 `FutureProvider` + `calendarRefreshProvider`
    的刷新链路（同步完成时已经在 `app.dart`/`sync_providers.dart` 里一并
    bump 了 `calendarRefreshProvider`，见 `PullCompleted`/自动同步两处），
    不需要额外处理。

- **`lib/pages/transaction/transaction_list_page.dart`（新增）**
  原首页的列表内容搬到这个新的 push 页面，同时按需求加上与网页端一致的
  时间条件筛选：今日 / 七天内 / 一个月内 / 全部（`_DateFilter` 枚举），
  默认「今日」。筛选直接对 `repo.transactionsWithCategoryAll` 的 Stream
  结果按 `happenedAt` 过滤后交给复用的 `TransactionList` 组件渲染，未使用
  首页那套「预加载缓存 + Stream 回退」的复杂 fallback ——因为这是用户主动
  点进来的页面，不像首页需要在冷启动瞬间就有数据可看，直接订阅 Stream 已
  经足够顺滑，没必要复制首页那套仅为首屏加速服务的缓存机制。

- **`test/widgets/calendar_month_jump_test.dart`**
  更新 import 与测试 host 从 `CalendarPage` 改为
  `Scaffold(body: CalendarBody())`，其余断言不变（月历下界/年月滚轮跳转
  行为完全保留）。

- **`lib/l10n/app_*.arb` + 生成的 `app_localizations*.dart`**
  新增 5 个 key：`transactionListTitle`、`transactionListFilterToday`、
  `transactionListFilterWeek`、`transactionListFilterMonth`、
  `transactionListFilterAll`，四语言（en/zh/zh_TW/ko）均已补上。

## 权衡 / 有意不做的事

- 「七天内」「一个月内」的具体口径：七天内 = 含今天在内最近 7 个自然日
  (`today - 6 days` 起)；一个月内 = 按月份数字回退一个月
  (`DateTime(year, month - 1, day)` 起，滚动窗口口径，不是日历自然月)。
  网页端截图未标注精确算法，这里采用最直观的“最近 N 天/最近 1 个月”滚动
  窗口解释，没有上界裁剪未来日期的交易（保留「全部」以外筛选下未来记账
  仍可见，避免用户手滑设了未来日期的交易凭空消失）。
- 未改动 `homeSwitchToStreamProvider`/`sharedResourceRefreshProvider` 这两
  个 provider 本身的定义和 `sync_providers.dart` 里的 bump 逻辑，只是
  `HomePage` 不再监听——`TransactionListPage` 目前也不需要，如果未来有别
  处需要这两个信号，保留定义不会有额外成本。
