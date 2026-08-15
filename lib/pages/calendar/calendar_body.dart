import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

import '../../widgets/ui/ui.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/biz/transaction_list_item.dart';
import '../../widgets/category_icon.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/transaction_detail_card.dart';
import '../../providers.dart';
import '../../providers/calendar_providers.dart';
import '../../l10n/app_localizations.dart';

/// 日历视图主体（月历网格 + 选中日交易列表），不含外层 Scaffold/Header ——
/// 直接嵌入首页(HomePage)的 body 中作为「明細」tab 的内容。
/// 通过 GlobalKey<CalendarBodyState> 暴露 jumpToToday()/jumpToMonth()
/// 给外层 Header（今天双击/年月选择器）驱动。
class CalendarBody extends ConsumerStatefulWidget {
  const CalendarBody({super.key});

  @override
  ConsumerState<CalendarBody> createState() => CalendarBodyState();
}

class CalendarBodyState extends ConsumerState<CalendarBody> {
  late DateTime _focusedMonth;
  DateTime? _selectedDay;
  // 月/週显示格式;由 TableCalendar 内置的上下滑动手势驱动切换
  // (availableGestures: all),不需要额外按钮。
  CalendarFormat _calendarFormat = CalendarFormat.month;

  // 日历可浏览范围。下界与 WheelDatePicker 默认 minDate 对齐(2000-01-01),
  // 导入了 2020 年前账单的用户也能翻到(#429:此前硬编码 2020-01-01);
  // 上界沿用「今天 + 1 年」以覆盖未来记账/周期记账。
  //
  // TableCalendar 与年月选择器必须绑同一份边界 —— focusedDay 落到界外会踩
  // table_calendar 内部 assert(table_calendar_base.dart:77)。
  static final DateTime _calFirstDay = DateTime(2000, 1, 1);

  // 取整到「日」:同一天内多次读取结果恒等,避免 TableCalendar 与选择器
  // 各自 DateTime.now() 差出微秒级不一致。
  DateTime get _calLastDay {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 365));
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month, 1);
    _selectedDay = now;

    // 同步到 Provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(calendarSelectedMonthProvider.notifier).state = _focusedMonth;
      ref.read(calendarSelectedDateProvider.notifier).state = _selectedDay;
    });
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      _selectedDay = selectedDay;
    });
    ref.read(calendarSelectedDateProvider.notifier).state = selectedDay;
  }

  void _onPageChanged(DateTime focusedMonth) {
    setState(() {
      _focusedMonth = focusedMonth;
      // 切换月份时，清空选中日期
      _selectedDay = null;
    });
    ref.read(calendarSelectedMonthProvider.notifier).state = focusedMonth;
    ref.read(calendarSelectedDateProvider.notifier).state = null;
    // 与首页头部「年/月 + 收支结余」摘要联动 —— 之前该摘要靠列表滚动可见性
    // 驱动 selectedMonthProvider,现在改由日历翻页/跳转驱动,保持同一契约。
    ref.read(selectedMonthProvider.notifier).state = focusedMonth;
  }

  /// 跳转到今天。暴露给外层 Header 的「今天」入口(双击首页 tab)调用。
  void jumpToToday() {
    final now = DateTime.now();
    setState(() {
      _focusedMonth = DateTime(now.year, now.month, 1);
      _selectedDay = now;
    });
    ref.read(calendarSelectedMonthProvider.notifier).state = _focusedMonth;
    ref.read(calendarSelectedDateProvider.notifier).state = _selectedDay;
    ref.read(selectedMonthProvider.notifier).state = _focusedMonth;
  }

  // 点头部「20xx年xx月 ▾」跳转指定年月(#429)。复用全 App 通用的年月滚轮,
  // 与首页(home_page.dart)、统计页(analytics_page.dart)同一范式。
  Future<void> _showMonthJumpPicker() async {
    // 上界故意跟随日历的 _calLastDay 而非 DateTime.now():日历本身能横滑到
    // 未来一年,若选择器卡在今天就会出现「手能滑到、选择器跳不到」的割裂。
    final picked = await showWheelDatePicker(
      context,
      initial: _focusedMonth,
      mode: WheelDatePickerMode.ym,
      minDate: _calFirstDay,
      maxDate: _calLastDay,
    );
    if (picked == null || !mounted) return;
    jumpToMonth(picked);
  }

  /// 跳转到指定年月。暴露给外层 Header 的年月选择器调用。
  void jumpToMonth(DateTime target) {
    // 选择器已按 min/max 限制返回值,这里只是兜底,防止将来改动边界后越界崩溃。
    // 钳制同样落到月初 —— _focusedMonth 恒为月初是本页各处共同的前置假设。
    var month = DateTime(target.year, target.month, 1);
    if (month.isBefore(_calFirstDay)) {
      month = DateTime(_calFirstDay.year, _calFirstDay.month, 1);
    }
    final lastDay = _calLastDay;
    if (month.isAfter(lastDay)) {
      month = DateTime(lastDay.year, lastDay.month, 1);
    }

    setState(() {
      _focusedMonth = month;
      // 与滑动切月(_onPageChanged)保持同一语义:清空选中日,下方当日列表收起
      _selectedDay = null;
    });
    // 程序化跳转时 table_calendar 会置 _pageCallbackDisabled(table_calendar_
    // base.dart:165),onPageChanged 不会回调,provider 必须手动同步
    ref.read(calendarSelectedMonthProvider.notifier).state = month;
    ref.read(calendarSelectedDateProvider.notifier).state = null;
    ref.read(selectedMonthProvider.notifier).state = month;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final primaryColor = ref.watch(primaryColorProvider);

    // 监听数据刷新
    ref.watch(calendarRefreshProvider);

    // 交易资讯卡的删除/退款/复制/编辑都会在变更真正完成时 bump
    // statsRefreshProvider(见 transaction_detail_card.dart /
    // transaction_editor_page.dart _handleSubmit)。日历用的是 FutureProvider
    // (不会因 Drift 写入自动重算),借这个信号驱动 calendarRefreshProvider。
    ref.listen<int>(statsRefreshProvider, (previous, next) {
      if (previous != next) {
        ref.read(calendarRefreshProvider.notifier).state++;
      }
    });

    // 获取当月统计数据
    final dailyTotalsAsync = ref.watch(
      dailyTotalsByMonthProvider((ledgerId: ledgerId, month: _focusedMonth)),
    );

    final horizontalPadding = 12.0.scaled(context, ref);
    final verticalPadding = 8.0.scaled(context, ref);

    // 月历格与「选中日交易列表」拆成上下两块:月历固定高度不滚动,
    // 交易列表单独用 Expanded+SingleChildScrollView 承接滚动。
    // 这样天数记录少时列表在自己的区域内就完整可见,不需要把整页往下滑
    // 划过月历才能看到(此前两者同在一个 ListView 里,月历本身就快 500px)。
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              horizontalPadding, verticalPadding, horizontalPadding, 0),
          child: Column(
            children: [
              // 回到今天
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: jumpToToday,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    l10n.calendarToday,
                    style: TextStyle(
                      color: BeeTokens.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              // 日历视图
              SectionCard(
                margin: EdgeInsets.zero,
                // 比默认 all(12) 更紧凑：格子本身已经很小，四周留白没必要
                // 跟随同样的间距，避免看起来"卡片比日历内容还占地方"。
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: dailyTotalsAsync.when(
                  // 记账等触发 calendarRefreshProvider 时不切到 loading,
                  // 旧统计保留,等新数据来无缝替换 — 避免日历整页 spinner 闪烁
                  skipLoadingOnReload: true,
                  data: (dailyTotals) =>
                      _buildCalendar(context, dailyTotals, primaryColor),
                  loading: () => _buildCalendarSkeleton(context),
                  error: (err, stack) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('Error: $err'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 选中日期的交易列表（无日期标题和统计）—— 独立滚动区域
        Expanded(
          child: _selectedDay == null
              ? const SizedBox.shrink()
              : SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    12.0.scaled(context, ref),
                    horizontalPadding,
                    verticalPadding,
                  ),
                  child: _buildDateTransactionsList(
                      context, ledgerId, _selectedDay!),
                ),
        ),
      ],
    );
  }

  Widget _buildCalendar(
    BuildContext context,
    Map<String, (double, double)> dailyTotals,
    Color primaryColor,
  ) {
    final locale = Localizations.localeOf(context);
    // 头部标题样式:headerStyle 与自定义 headerTitleBuilder 共用同一份,避免走样
    final titleTextStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: BeeTokens.textPrimary(context),
    );

    return TableCalendar(
      locale: locale.toString(),
      firstDay: _calFirstDay,
      lastDay: _calLastDay,
      focusedDay: _focusedMonth,
      selectedDayPredicate: (day) {
        return _selectedDay != null && isSameDay(_selectedDay, day);
      },
      onDaySelected: _onDaySelected,
      onPageChanged: _onPageChanged,
      calendarFormat: _calendarFormat,
      // 只在 月/週 两种格式间切换（跳过内置的 twoWeeks），
      // 上滑收起成一週、下滑展开回整月。
      availableCalendarFormats: const {
        CalendarFormat.month: '月',
        CalendarFormat.week: '週',
      },
      onFormatChanged: (format) {
        if (_calendarFormat != format) {
          setState(() => _calendarFormat = format);
        }
      },
      startingDayOfWeek: StartingDayOfWeek.monday,
      // all = 横滑翻页 + 纵滑切换 月/週 格式（原先只开横滑，纵滑收起成一週的
      // 功能一直没接上手势，现补上）。
      availableGestures: AvailableGestures.all,

      // 设置行高以适应内容（每格已改成只显示一行净额，不再需要两行收支的
      // 空间，行高可以进一步收紧）
      rowHeight: 44,
      daysOfWeekHeight: 20,

      // Header 样式
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        leftChevronIcon: Icon(Icons.chevron_left, color: primaryColor),
        rightChevronIcon: Icon(Icons.chevron_right, color: primaryColor),
        titleTextStyle: titleTextStyle,
      ),

      // 日历样式
      calendarStyle: CalendarStyle(
        // 今天样式
        todayDecoration: BoxDecoration(
          color: primaryColor.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        todayTextStyle: TextStyle(
          color: primaryColor,
          fontWeight: FontWeight.bold,
        ),

        // 选中样式
        selectedDecoration: BoxDecoration(
          color: primaryColor,
          shape: BoxShape.circle,
        ),
        selectedTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),

        // 日期文字样式
        defaultTextStyle: TextStyle(
          color: BeeTokens.textPrimary(context),
        ),
        outsideTextStyle: TextStyle(
          color: BeeTokens.textTertiary(context).withOpacity(0.3),
        ),

        // 周末样式
        weekendTextStyle: TextStyle(
          color: BeeTokens.textPrimary(context),
        ),

        // 标记样式
        markersAlignment: Alignment.bottomCenter,
        markerDecoration: BoxDecoration(
          color: primaryColor,
          shape: BoxShape.circle,
        ),
      ),

      // 星期标题样式
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: TextStyle(
          color: BeeTokens.textSecondary(context),
          fontSize: 12,
        ),
        weekendStyle: TextStyle(
          color: BeeTokens.textSecondary(context),
          fontSize: 12,
        ),
      ),

      // 日期标记构建器
      calendarBuilders: CalendarBuilders(
        // 头部标题改为「20xx年xx月 ▾」可点入口(#429)。
        // 注意:headerTitleBuilder 会整体替换掉 table_calendar 内置那层
        // GestureDetector(calendar_header.dart:58),onHeaderTapped 因此不会
        // 回调 —— 点击手势必须挂在这里。
        headerTitleBuilder: (context, month) {
          // SectionCard 是纯 Container,不提供 Material —— 水波纹会画到
          // Scaffold 那层 Material 上、被卡片背景挡住。补一层透明 Material,
          // 与本文件下方「在该日记账」按钮同一处理。
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showMonthJumpPicker,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Flexible + ellipsis:标题字号是固定 16,系统「更大字体」放大后
                    // 纯 Text 会先吃满整行、把 20pt 的箭头挤出去触发 RenderFlex
                    // overflow(改造前是裸 Text,靠软换行不会横向溢出)
                    Flexible(
                      child: Text(
                        // 与内置实现同格式(calendar_header.dart:42),
                        // 中/繁/英/韩四语显示与改造前完全一致
                        DateFormat.yMMMM(locale.toString()).format(month),
                        style: titleTextStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 20,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        // 自定义默认日期单元格
        defaultBuilder: (context, day, focusedDay) {
          return _buildDateCell(
              context, day, dailyTotals, primaryColor, false, false, false);
        },
        // 自定义今天日期单元格
        todayBuilder: (context, day, focusedDay) {
          return _buildDateCell(
              context, day, dailyTotals, primaryColor, true, false, false);
        },
        // 自定义选中日期单元格
        selectedBuilder: (context, day, focusedDay) {
          return _buildDateCell(
              context, day, dailyTotals, primaryColor, false, true, false);
        },
        // 自定义非当前月日期
        outsideBuilder: (context, day, focusedDay) {
          return _buildDateCell(
              context, day, dailyTotals, primaryColor, false, false, true);
        },
      ),
    );
  }

  Widget _buildDateCell(
    BuildContext context,
    DateTime day,
    Map<String, (double, double)> dailyTotals,
    Color primaryColor,
    bool isToday,
    bool isSelected,
    bool isOutside,
  ) {
    final dateKey = _formatDate(day);
    final totals = dailyTotals[dateKey];
    final (income, expense) = totals ?? (0.0, 0.0);
    final hasTransaction = income > 0 || expense > 0;
    final netAmount = income - expense;

    // 文字颜色
    Color textColor;
    if (isSelected) {
      textColor = Colors.white;
    } else if (isToday) {
      textColor = primaryColor;
    } else if (isOutside) {
      textColor = BeeTokens.textTertiary(context).withOpacity(0.3);
    } else {
      textColor = BeeTokens.textPrimary(context);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 1),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 日期数字（带圆形背景）
          Container(
            width: 24,
            height: 24,
            decoration: isSelected
                ? BoxDecoration(
                    color: primaryColor,
                    shape: BoxShape.circle,
                  )
                : isToday
                    ? BoxDecoration(
                        color: primaryColor.withOpacity(0.15),
                        shape: BoxShape.circle,
                      )
                    : null,
            alignment: Alignment.center,
            child: Text(
              '${day.day}',
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight:
                    isToday || isSelected ? FontWeight.bold : FontWeight.normal,
                height: 1.0,
              ),
            ),
          ),
          // 净额（收入-支出），只占一行，不再分两行显示收入/支出
          if (!isOutside && hasTransaction) ...[
            const SizedBox(height: 1),
            Text(
              _formatNetAmount(netAmount),
              style: TextStyle(
                color: netAmount >= 0
                    ? BeeTokens.incomeColor(context, ref)
                    : BeeTokens.expenseColor(context, ref),
                fontSize: 9,
                fontWeight: FontWeight.w600,
                height: 1.0,
              ),
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ],
        ],
      ),
    );
  }

  // 净额格式化：正数带 +、负数带 -，超过千/万位简写成 k/w。
  String _formatNetAmount(double net) {
    final sign = net < 0 ? '-' : '+';
    final abs = net.abs();
    final value = abs >= 10000
        ? '${(abs / 10000).toStringAsFixed(1)}w'
        : abs >= 1000
            ? '${(abs / 1000).toStringAsFixed(1)}k'
            : abs.toInt().toString();
    return '$sign$value';
  }

  // 构建选中日期的交易列表
  Widget _buildDateTransactionsList(
      BuildContext context, int ledgerId, DateTime date) {
    final l10n = AppLocalizations.of(context);

    final transactionsAsync = ref.watch(
      transactionsByDateProvider((ledgerId: ledgerId, date: date)),
    );

    final card = SectionCard(
      margin: EdgeInsets.zero,
      child: transactionsAsync.when(
        // 同上:bump 刷新触发的 reload 不切到 loading 分支,旧列表保持显示
        skipLoadingOnReload: true,
        data: (transactions) {
          if (transactions.isEmpty) {
            return Padding(
              padding: EdgeInsets.all(24.0.scaled(context, ref)),
              child: Center(
                child: Text(
                  l10n.calendarNoTransactions,
                  style: TextStyle(
                    color: BeeTokens.textTertiary(context),
                  ),
                ),
              ),
            );
          }

          // 直接显示交易列表
          return ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              final item = transactions[index];
              final category = item.category;
              final isExpense = item.t.type == 'expense';
              final isTransfer = item.t.type == 'transfer';

              // 分类名称
              final categoryName = category?.name ?? l10n.commonUncategorized;

              // 备注作为副标题
              final subtitle = item.t.note ?? '';

              // 标签列表
              final tagsList = item.tags
                  .map((tag) => (id: tag.id, name: tag.name, color: tag.color))
                  .toList();

              return TransactionListItem(
                icon: getCategoryIconData(
                    category: category, categoryName: categoryName),
                category: category,
                title: isTransfer
                    ? (subtitle.isNotEmpty ? subtitle : l10n.transferTitle)
                    : (subtitle.isNotEmpty ? subtitle : categoryName),
                categoryName: isTransfer
                    ? null
                    : (subtitle.isNotEmpty ? categoryName : null),
                amount: item.t.amount,
                currencyCode: item.t.currencyCode,
                nativeAmount: item.t.nativeAmount,
                isExpense: isExpense,
                isTransfer: isTransfer,
                happenedAt: item.t.happenedAt,
                accountName: item.account?.name,
                tags: tagsList.isNotEmpty ? tagsList : null,
                attachmentCount: item.attachments.length,
                onTap: () async {
                  await showTransactionDetailCard(
                    context,
                    ref,
                    item.t,
                    item.category,
                  );
                },
              );
            },
          );
        },
        loading: () => _buildTransactionsSkeleton(context),
        error: (err, stack) => Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text('Error: $err')),
        ),
      ),
    );

    return card;
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // 日历整页骨架(模拟 6 周 × 7 天 的灰格,接近真实日历高度)
  // 占位等高:rowHeight 44 × 6 + daysOfWeekHeight 20 + header 50 ≈ 334
  Widget _buildCalendarSkeleton(BuildContext context) {
    return DelayedSkeleton(
      placeholder: const SizedBox(height: 334),
      child: PulseSkeleton(
        child: SizedBox(
          height: 334,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                const SkeletonBar(height: 18, widthFactor: 0.4),
                const SizedBox(height: 10),
                for (int row = 0; row < 6; row++)
                  Row(
                    children: List.generate(
                      7,
                      (_) => const Expanded(
                        child: Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                          child: SkeletonBar(height: 32),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 当日交易列表骨架(3 条 ListTile 风格占位)
  Widget _buildTransactionsSkeleton(BuildContext context) {
    return const DelayedSkeleton(
      placeholder: SizedBox(height: 200),
      child: PulseSkeleton(
        child: Column(
          children: [
            SkeletonListTile(),
            SkeletonListTile(),
            SkeletonListTile(),
          ],
        ),
      ),
    );
  }
}
