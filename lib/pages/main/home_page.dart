import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../../providers/budget_providers.dart';
import '../project/project_overview_page.dart';
import '../../providers.dart';
import '../settings/personalize_page.dart' show headerStyleProvider;
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../widgets/biz/bee_icon.dart';
import '../../styles/tokens.dart';
import '../transaction/search_page.dart';
import '../transaction/transaction_list_page.dart';
import '../ai/ai_chat_page.dart';
import '../../widgets/biz/notification_bell_button.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/format_utils.dart';
import '../../utils/month_range.dart';
import '../../services/export/share_poster_service.dart';
import '../report/annual_report_page.dart';
import '../calendar/calendar_body.dart';
import '../../widgets/biz/ledger_picker_sheet.dart';
import '../../widgets/biz/home_budget_summary.dart';
import 'ledgers_page_new.dart';

// 首页 - 内嵌日历视图(CalendarBody)，「明細」列表挪到 TransactionListPage
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final GlobalKey<CalendarBodyState> _calendarKey =
      GlobalKey<CalendarBodyState>();

  // 月初提醒状态
  bool _showLastMonthReminder = false;
  static const String _reminderDismissedKey = 'last_month_reminder_dismissed';

  // 年度账单提醒状态（12月15日 - 次年1月31日显示）
  bool _showAnnualReportReminder = false;
  static const String _annualReportDismissedKey =
      'annual_report_reminder_dismissed';

  // 预算设置引导卡片状态
  bool _showBudgetSetupHint = false;
  static const String _budgetSetupHintDismissedKey =
      'budget_setup_hint_dismissed';

  @override
  void initState() {
    super.initState();
    _checkLastMonthReminder();
    _checkAnnualReportReminder();
    _checkBudgetSetupHint();
  }

  // 检查是否应该显示上月报告提醒
  Future<void> _checkLastMonthReminder() async {
    final now = DateTime.now();
    // 只在每月前7天显示提醒
    if (now.day > 7) return;

    final prefs = await SharedPreferences.getInstance();
    final dismissedMonth = prefs.getString(_reminderDismissedKey);
    final currentMonth = '${now.year}-${now.month}';

    // 如果当月已经关闭过，不再显示
    if (dismissedMonth == currentMonth) return;

    if (mounted) {
      setState(() {
        _showLastMonthReminder = true;
      });
    }
  }

  // 关闭上月报告提醒
  Future<void> _dismissLastMonthReminder() async {
    final now = DateTime.now();
    final currentMonth = '${now.year}-${now.month}';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_reminderDismissedKey, currentMonth);

    if (mounted) {
      setState(() {
        _showLastMonthReminder = false;
      });
    }
  }

  // 检查是否应该显示年度账单提醒（12月15日 - 次年1月31日）
  Future<void> _checkAnnualReportReminder() async {
    final now = DateTime.now();

    // 判断是否在提醒时间范围内：12月15日 - 次年1月31日
    final isInRange = (now.month == 12 && now.day >= 15) || now.month == 1;
    if (!isInRange) return;

    // 确定要展示的年度（12月展示当年，1月展示上一年）
    final reportYear = now.month == 1 ? now.year - 1 : now.year;

    final prefs = await SharedPreferences.getInstance();
    final dismissedYear = prefs.getInt(_annualReportDismissedKey);

    // 如果这个年度已经关闭过，不再显示
    if (dismissedYear == reportYear) return;

    if (mounted) {
      setState(() {
        _showAnnualReportReminder = true;
      });
    }
  }

  // 关闭年度账单提醒
  Future<void> _dismissAnnualReportReminder() async {
    final now = DateTime.now();
    final reportYear = now.month == 1 ? now.year - 1 : now.year;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_annualReportDismissedKey, reportYear);

    if (mounted) {
      setState(() {
        _showAnnualReportReminder = false;
      });
    }
  }

  // 检查是否应该显示预算设置引导卡片
  Future<void> _checkBudgetSetupHint() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_budgetSetupHintDismissedKey) ?? false;
    if (dismissed) return;

    if (mounted) {
      setState(() {
        _showBudgetSetupHint = true;
      });
    }
  }

  // 关闭预算设置引导卡片（永不再显示）
  Future<void> _dismissBudgetSetupHint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_budgetSetupHintDismissedKey, true);

    if (mounted) {
      setState(() {
        _showBudgetSetupHint = false;
      });
    }
  }

  // 日期选择处理 —— 现在驱动内嵌的日历(CalendarBody)跳转到目标年月，
  // 而不是滚动列表(明細列表已挪到 TransactionListPage)。
  Future<void> _handleDateSelection() async {
    final month = ref.read(selectedMonthProvider);
    final res = await showWheelDatePicker(
      context,
      initial: month,
      mode: WheelDatePickerMode.ym,
      maxDate: DateTime.now(),
    );

    if (res != null && mounted) {
      final targetMonth = DateTime(res.year, res.month, 1);
      _calendarKey.currentState?.jumpToMonth(targetMonth);
    }
  }

  // 构建月初提醒卡片
  Widget _buildLastMonthReminderCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final sd = ref.watch(currentMonthStartDayProvider);
    final currentLabel = labelForDate(now, sd);
    final lastMonth = DateTime(currentLabel.year, currentLabel.month - 1, 1);
    final monthFormat = DateFormat.MMMM(l10n.localeName);
    final primaryColor = ref.watch(primaryColorProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // 左侧装饰条
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4,
                color: primaryColor,
              ),
            ),
            // 主体内容
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  // 文案
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: primaryColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: monthFormat.format(lastMonth),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: primaryColor,
                                  ),
                                ),
                                TextSpan(
                                  text: ' ${l10n.homeLastMonthReportSubtitle}',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 查看按钮（查看后本次隐藏，下次打开app还会显示）
                  GestureDetector(
                    onTap: () {
                      SharePosterService.showPosterCarouselPreview(
                        context,
                        year: lastMonth.year,
                        month: lastMonth.month,
                      );
                      // 只临时隐藏，不保存到 prefs
                      setState(() {
                        _showLastMonthReminder = false;
                      });
                    },
                    child: Text(
                      l10n.homeLastMonthReportView,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 关闭按钮（关闭后当月不再显示）
                  GestureDetector(
                    onTap: _dismissLastMonthReminder,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: isDark ? Colors.white38 : Colors.black26,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 年度账单提醒卡片（样式与月初提醒一致）
  Widget _buildAnnualReportReminderCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final reportYear = now.month == 1 ? now.year - 1 : now.year;
    final primaryColor = ref.watch(primaryColorProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // 左侧装饰条
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4,
                color: primaryColor,
              ),
            ),
            // 主体内容
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  // 文案
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_graph_rounded,
                          color: primaryColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.homeAnnualReportReminder(reportYear),
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 查看按钮
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              AnnualReportPage(initialYear: reportYear),
                        ),
                      );
                      // 临时隐藏
                      setState(() {
                        _showAnnualReportReminder = false;
                      });
                    },
                    child: Text(
                      l10n.homeAnnualReportView,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 关闭按钮
                  GestureDetector(
                    onTap: _dismissAnnualReportReminder,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: isDark ? Colors.white38 : Colors.black26,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 预算设置引导卡片（无预算时显示，样式与月初提醒一致）
  Widget _buildBudgetSetupHintCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // 左侧装饰条
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4,
                color: primaryColor,
              ),
            ),
            // 主体内容
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  // 图标 + 文案
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.pie_chart_outline_rounded,
                          color: primaryColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.budgetSetupHint,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 去设置按钮
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ProjectOverviewPage()),
                      );
                    },
                    child: Text(
                      l10n.budgetSetupAction,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 关闭按钮
                  GestureDetector(
                    onTap: _dismissBudgetSetupHint,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: isDark ? Colors.white38 : Colors.black26,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(selectedMonthProvider);
    final aiEnabledAsync = ref.watch(aiAssistantEnabledProvider);
    final aiEnabled = aiEnabledAsync.asData?.value ?? true; // 默认开启

    // 双击首页 tab 时跳回今天(原「滚动到列表顶部」的等价行为，见 app.dart
    // onTabTap)。
    ref.listen<int>(homeScrollToTopProvider, (previous, next) {
      if (previous != next) {
        _calendarKey.currentState?.jumpToToday();
      }
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, // ⭐ 自适应背景色
      body: Column(
        children: [
          Consumer(builder: (context, ref, _) {
            ref.watch(headerStyleProvider);
            final hide = ref.watch(hideAmountsProvider);
            return PrimaryHeader(
              title: '',
              showTitleSection: false,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 头部 - 左: BeeIcon + 账本切换, 右: 操作按钮
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        // 左侧：BeeIcon + 标题 + 账本切换胶囊（用 Expanded 包住，
                        // 标题在空间富余时显示自然宽度，仅在不够时 ellipsis）
                        BeeIcon(
                          color: Theme.of(context).colorScheme.primary,
                          size: 28,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Row(
                            children: [
                              // 标题取自然宽度,溢出时优先压缩账本名而不是 app 名
                              Text(
                                AppLocalizations.of(context).homeAppTitle,
                                maxLines: 1,
                                softWrap: false,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.color,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Consumer(builder: (context, ref, _) {
                                    final currentLedger =
                                        ref.watch(currentLedgerProvider);
                                    return currentLedger.when(
                                      // invalidate(远端改名 / 改币种)期间继续
                                      // 显示旧值,避免账本名胶囊瞬间消失再出现 —
                                      // 用户感知"首页全量刷新"的主要来源。
                                      skipLoadingOnReload: true,
                                      data: (ledger) {
                                        // ledger == null:还没有账本(welcome 未勾默认账本
                                        // / 老用户导入配置不含账本),胶囊直接显示「新建账本」
                                        // + 加号图标,点击 push LedgersPage 并自动弹创建对
                                        // 话框,省两步点击。
                                        final isEmpty = ledger == null;
                                        return GestureDetector(
                                          onTap: () {
                                            if (isEmpty) {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      const LedgersPageNew(
                                                          autoOpenCreateDialog:
                                                              true),
                                                ),
                                              );
                                            } else {
                                              showLedgerPicker(context);
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                          .brightness ==
                                                      Brightness.dark
                                                  ? Colors.white
                                                      .withValues(alpha: 0.1)
                                                  : Colors.black
                                                      .withValues(alpha: 0.05),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (isEmpty) ...[
                                                  Icon(
                                                    Icons.add,
                                                    size: 16,
                                                    color: Theme.of(context)
                                                        .textTheme
                                                        .bodyLarge
                                                        ?.color,
                                                  ),
                                                  const SizedBox(width: 4),
                                                ],
                                                Flexible(
                                                  child: Text(
                                                    isEmpty
                                                        ? AppLocalizations.of(
                                                                context)
                                                            .ledgersNew
                                                        : translateLedgerName(
                                                            context,
                                                            ledger.name),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    softWrap: false,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: Theme.of(context)
                                                          .textTheme
                                                          .bodyLarge
                                                          ?.color,
                                                    ),
                                                  ),
                                                ),
                                                // v24 共享账本:header 也显示 🤝 角标 + 成员数
                                                if (!isEmpty &&
                                                    ledger.isShared) ...[
                                                  const SizedBox(width: 4),
                                                  Icon(
                                                    Icons.handshake,
                                                    size: 12,
                                                    color: Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.color
                                                        ?.withOpacity(0.7),
                                                  ),
                                                  const SizedBox(width: 1),
                                                  Text(
                                                    '${ledger.memberCount}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Theme.of(context)
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.color
                                                          ?.withOpacity(0.7),
                                                    ),
                                                  ),
                                                ],
                                                // 没账本时不显示下拉箭头(没东西可选)
                                                if (!isEmpty) ...[
                                                  const SizedBox(width: 2),
                                                  Icon(
                                                    Icons.keyboard_arrow_down,
                                                    size: 16,
                                                    color: Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.color
                                                        ?.withOpacity(0.5),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                      loading: () => const SizedBox.shrink(),
                                      error: (_, __) => const SizedBox.shrink(),
                                    );
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 右侧操作按钮
                        if (aiEnabled)
                          IconButton(
                            tooltip: AppLocalizations.of(context).aiChatTitle,
                            padding: const EdgeInsets.all(8),
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              minimumSize: Size.zero,
                            ),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const AIChatPage(),
                                ),
                              );
                            },
                            icon: Icon(
                              Icons.auto_awesome_outlined,
                              size: 20,
                              color: Theme.of(context).iconTheme.color,
                            ),
                          ),
                        const NotificationBellButton(),
                        IconButton(
                          tooltip:
                              AppLocalizations.of(context).transactionListTitle,
                          padding: const EdgeInsets.all(6),
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            minimumSize: Size.zero,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TransactionListPage(),
                              ),
                            );
                          },
                          icon: Icon(
                            Icons.receipt_long_outlined,
                            size: 20,
                            color: Theme.of(context).iconTheme.color,
                          ),
                        ),
                        IconButton(
                          tooltip: AppLocalizations.of(context).homeSearch,
                          padding: const EdgeInsets.all(6),
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            minimumSize: Size.zero,
                          ),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const SearchPage(),
                              ),
                            );
                          },
                          icon: Icon(
                            Icons.search,
                            size: 20,
                            color: Theme.of(context).iconTheme.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 第二行 - 月份显示和统计
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _handleDateSelection,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                AppLocalizations.of(context)
                                    .homeYear(month.year),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.color
                                            ?.withOpacity(0.6), // ⭐ 自适应次要文字颜色
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  AppLocalizations.of(context).homeMonth(
                                      month.month.toString().padLeft(2, '0')),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                          color: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.color, // ⭐ 自适应主文字颜色
                                          fontSize: 20,
                                          fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(width: 4),
                                // 月份旁边的向下三角形（日期选择）
                                Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 16,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color
                                      ?.withOpacity(0.6), // ⭐ 自适应次要颜色
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        width: 1,
                        height: 36,
                        color: Theme.of(context).dividerTheme.color ??
                            Theme.of(context).dividerColor, // ⭐ 自适应分割线颜色
                      ),
                      const Expanded(child: _HeaderCenterSummary()),
                    ],
                  ),
                ],
              ),
              bottom: const HomeBudgetSummary(),
            );
          }),
          const SizedBox(height: 0),
          // 月初提醒卡片
          if (_showLastMonthReminder) _buildLastMonthReminderCard(context),
          // 年度账单提醒卡片（12月15日 - 次年1月31日）
          if (_showAnnualReportReminder)
            _buildAnnualReportReminderCard(context),
          // 预算设置引导卡片（无预算 + 未关闭过）
          Consumer(builder: (context, ref, _) {
            final overviewAsync = ref.watch(budgetOverviewProvider);
            final hasBudget = overviewAsync.when(
              data: (overview) =>
                  overview != null && overview.totalBudget != null,
              loading: () => true, // loading 时不显示引导
              error: (_, __) => true, // 出错时不显示引导
            );
            if (!hasBudget && _showBudgetSetupHint) {
              return _buildBudgetSetupHintCard(context);
            }
            return const SizedBox.shrink();
          }),
          Expanded(
            child: CalendarBody(key: _calendarKey),
          ),
        ],
      ),
    );
  }
}

class _HeaderCenterSummary extends ConsumerWidget {
  const _HeaderCenterSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final month = ref.watch(selectedMonthProvider);
    final params = (ledgerId: ledgerId, month: month);

    ref.watch(monthlyTotalsProvider(params));
    final cachedTotals = ref.watch(lastMonthlyTotalsProvider(params));
    final (income, expense) = cachedTotals ?? (0.0, 0.0);
    final balance = income - expense;

    final amountStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).textTheme.bodyLarge?.color,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ) ??
        TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        );

    Widget item(String title, double value) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                textAlign: TextAlign.left, style: BeeTextTokens.label(context)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AmountText(
                value: value,
                signed: false,
                decimals: 2,
                style: amountStyle,
              ),
            ),
          ],
        );
    return Row(
      children: [
        Expanded(child: item(AppLocalizations.of(context).homeIncome, income)),
        const SizedBox(width: 4),
        Expanded(
            child: item(AppLocalizations.of(context).homeExpense, expense)),
        const SizedBox(width: 4),
        Expanded(
            child: item(AppLocalizations.of(context).homeBalance, balance)),
      ],
    );
  }
}
