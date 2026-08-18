import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../services/custom_icon_service.dart';
import '../../services/currency/rate_math.dart';
import '../../services/marketing/product_promos.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/amount_text.dart';
import '../../widgets/biz/format_money.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/biz/product_promo_card.dart';
import '../../data/db.dart' as db;
import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../utils/account_type_utils.dart';
import '../../utils/currencies.dart';
import '../../widgets/charts/asset_composition_chart.dart';
import '../../widgets/charts/line_chart.dart';
import '../../utils/net_worth_trend_utils.dart';
import '../currency/exchange_rate_page.dart';
import 'account_edit_page.dart';
import 'account_detail_page.dart';
import 'net_worth_trend_page.dart';

class AccountsPage extends ConsumerStatefulWidget {
  final bool asTab;
  const AccountsPage({super.key, this.asTab = false});

  @override
  ConsumerState<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends ConsumerState<AccountsPage> {
  /// 拖拽后临时保持本地排序，防止 stream rebuild 闪烁
  Map<String, List<db.Account>>? _reorderingGroups;

  @override
  void initState() {
    super.initState();
    // 进页静默刷新汇率:内部自带多币种总闸(D6)+ 24h 节流,单币种零请求。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      refreshExchangeRatesFromUi(ref);
    });
  }

  /// 按「展示類型」分組(而不是原始 account.type)——主帳戶(合併帳單分組,
  /// type='account_group')本身只是純管理容器,沒有自己的資產/負債分類,
  /// 要跟著它底下子帳戶的實際類型歸類,才能跟子帳戶落在同一個 typeOrder
  /// 分組裡讓樹狀巢狀渲染找得到彼此(否則主帳戶會被丟進「其它未知類型」
  /// 分組,子帳戶在信用卡分組裡找不到自己的主帳戶,全部降級成孤兒「隸屬於
  /// X」平鋪列表)。跟 web `resolveAccountGroupDisplayType` 同一份邏輯。
  Map<String, List<db.Account>> _groupAccounts(List<db.Account> accounts) {
    final childrenByParentSyncId = <String, List<db.Account>>{};
    for (final a in accounts) {
      final pid = a.parentAccountId;
      if (pid != null && pid.isNotEmpty) {
        childrenByParentSyncId.putIfAbsent(pid, () => []).add(a);
      }
    }
    final Map<String, List<db.Account>> grouped = {};
    for (final account in accounts) {
      final displayType = _resolveDisplayType(account, childrenByParentSyncId);
      grouped.putIfAbsent(displayType, () => []).add(account);
    }
    return grouped;
  }

  /// 主帳戶(account_group)的展示類型:底下子帳戶類型一致就跟著子帳戶;
  /// 子帳戶類型不一致時信用卡優先(合併帳單分組多半是信用卡場景);還沒有
  /// 任何子帳戶同步下來時,靠自己身上是否設了信用額度粗略判斷。非
  /// account_group 帳戶原樣返回自己的 type。
  String _resolveDisplayType(
    db.Account account,
    Map<String, List<db.Account>> childrenByParentSyncId,
  ) {
    if (account.type != 'account_group') return account.type;
    final syncId = account.syncId;
    final children = syncId != null ? childrenByParentSyncId[syncId] : null;
    if (children == null || children.isEmpty) {
      return account.creditLimit != null ? 'credit_card' : 'bank_card';
    }
    final childTypes = children.map((c) => c.type).toSet();
    if (childTypes.length == 1) return childTypes.first;
    return childTypes.contains('credit_card') ? 'credit_card' : 'bank_card';
  }

  void _onReorder(String type, List<db.Account> groupAccounts, int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    // 乐观更新：用本地状态锁住当前排序，防止 stream 刷新导致闪烁
    setState(() {
      _reorderingGroups ??= _groupAccounts(
        ref.read(allAccountsStreamProvider).asData?.value ?? [],
      );
      final list = _reorderingGroups![type]!;
      final item = list.removeAt(oldIndex);
      list.insert(newIndex, item);
    });

    // 构建批量更新
    final list = _reorderingGroups![type]!;
    final updates = <({int id, int sortOrder})>[];
    for (int i = 0; i < list.length; i++) {
      updates.add((id: list[i].id, sortOrder: i));
    }

    // 写入数据库，延迟清除本地状态让 stream 先到位
    ref.read(repositoryProvider).updateAccountSortOrders(updates).then((_) {
      // 账户拖拽排序也推到服务端。账户的 ChangeTracker 变更用的是 account.ledgerId
      // （非 0），走常规 push 路径即可。
      final activeLedgerId = ref.read(currentLedgerIdProvider);
      if (activeLedgerId > 0) {
        unawaited(PostProcessor.sync(ref, ledgerId: activeLedgerId));
      }
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _reorderingGroups = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final accountsAsync = ref.watch(allAccountsStreamProvider);
    final accountFeatureAsync = ref.watch(accountFeatureEnabledProvider);
    final primaryColor = ref.watch(primaryColorProvider);
    final allStatsAsync = ref.watch(allAccountStatsProvider);
    final netWorthByCurrencyAsync = ref.watch(netWorthBreakdownByCurrencyProvider);

    // 资产构成数据
    final compositionAsync = ref.watch(assetCompositionProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          // ======== 简洁 Header ========
          PrimaryHeader(
            title: l10n.accountsTitle,
            showBack: !widget.asTab,
            compact: true,
            // 顺序(左 → 右):加号 / 蜜蜂家当入口 / 设置。
            // 设置放最右边(Material 设计惯例,溢出 / 设置类放最右),
            // 蜜蜂家当放中间,顺手能点到但不抢主操作位。
            actions: [
              IconButton(
                onPressed: () => _addAccount(context, ref, ledgerId),
                icon: const Icon(Icons.add),
                tooltip: l10n.accountAddTooltip,
              ),
              // 蜜蜂家当 BeeAssets 入口 — 行为走 ProductPromoLauncher
              // (iOS 跳商店 / Android 弹窗)。
              _BeeAssetsHeaderEntry(),
              IconButton(
                onPressed: () => _showSettingsSheet(context, ref, accountFeatureAsync, accountsAsync),
                icon: const Icon(Icons.settings_outlined),
                tooltip: l10n.commonSettings,
              ),
            ],
          ),

          // ======== 主内容 ========
          Expanded(
            child: accountsAsync.when(
              skipLoadingOnReload: true,
              data: (accounts) {
                final groups = _reorderingGroups ?? _groupAccounts(accounts);

                return ListView(
                  padding: EdgeInsets.only(
                    left: 12.0.scaled(context, ref),
                    right: 12.0.scaled(context, ref),
                    top: 8.0.scaled(context, ref),
                    bottom: widget.asTab
                        ? 8.0.scaled(context, ref) + 56 + MediaQuery.of(context).padding.bottom + 24
                        : 8.0.scaled(context, ref),
                  ),
                  children: [
                    if (accounts.isEmpty)
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.4,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 64.0.scaled(context, ref),
                                color: primaryColor.withValues(alpha: 0.4),
                              ),
                              SizedBox(height: 16.0.scaled(context, ref)),
                              Text(
                                l10n.accountsEmptyMessage,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: BeeTokens.textSecondary(context),
                                ),
                              ),
                              SizedBox(height: 24.0.scaled(context, ref)),
                              ElevatedButton.icon(
                                onPressed: () => _addAccount(context, ref, ledgerId),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.add),
                                label: Text(l10n.accountAddButton),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      // 0. 净资产汇总 + 资产构成（合并卡片）
                      _buildNetWorthAndCompositionCard(
                        context, ref, netWorthByCurrencyAsync, compositionAsync, primaryColor,
                      ),

                      // 2. 资产账户分组
                      ..._buildClassificationSection(
                        context: context,
                        l10n: l10n,
                        title: l10n.assetAccounts,
                        icon: Icons.trending_up,
                        iconColor: BeeTokens.incomeColor(context, ref),
                        typeOrder: assetTypeOrder,
                        groups: groups,
                        allStats: allStatsAsync.valueOrNull,
                        primaryColor: primaryColor,
                        ledgerId: ledgerId,
                      ),

                      // 3. 负债账户分组
                      ..._buildClassificationSection(
                        context: context,
                        l10n: l10n,
                        title: l10n.liabilityAccounts,
                        icon: Icons.trending_down,
                        iconColor: BeeTokens.expenseColor(context, ref),
                        typeOrder: liabilityTypeOrder,
                        groups: groups,
                        allStats: allStatsAsync.valueOrNull,
                        primaryColor: primaryColor,
                        ledgerId: ledgerId,
                      ),

                      // 4. 其他未知类型(排除隐藏账户,账户隐藏 #240)
                      ...groups.keys
                          .where((type) =>
                              !accountTypeOrder.contains(type) &&
                              groups[type]!.any((a) => !a.hidden))
                          .map((type) {
                        final groupList =
                            groups[type]!.where((a) => !a.hidden).toList();
                        return _AccountTypeGroup(
                          type: type,
                          accounts: groupList,
                          primaryColor: primaryColor,
                          allStats: allStatsAsync.valueOrNull,
                          onReorder: (oldIndex, newIndex) =>
                              _onReorder(type, groupList, oldIndex, newIndex),
                          onTap: (account) =>
                              _viewAccountDetail(context, ref, account),
                          onEdit: (account) =>
                              _editAccount(context, ref, account, ledgerId),
                        );
                      }),

                      // 5. 已隐藏账户分区(账户隐藏 #240,D2:主列表退场,
                      // 分区头小计与净资产卡差额对账)
                      _HiddenAccountsSection(
                        accounts: accounts.where((a) => a.hidden).toList(),
                        allStats: allStatsAsync.valueOrNull,
                        primaryColor: primaryColor,
                        onTap: (account) =>
                            _viewAccountDetail(context, ref, account),
                        onEdit: (account) =>
                            _editAccount(context, ref, account, ledgerId),
                        onRestore: (account) =>
                            _restoreAccount(context, ref, account),
                      ),
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Text('${l10n.commonError}: $err'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 净资产汇总 + 资产构成合并卡片
  Widget _buildNetWorthAndCompositionCard(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Map<String, ({double totalAssets, double totalLiabilities, double netWorth})>> netWorthAsync,
    AsyncValue<List<({String type, double totalBalance})>> compositionAsync,
    Color primaryColor,
  ) {
    // reload 时 asData 会短暂变 null 致布局闪动,用 valueOrNull 保留上次结果
    final isSingleCurrency = (netWorthAsync.valueOrNull?.length ?? 1) <= 1;
    // 折算态:总闸开启时也展示饼图,数据换成折算后聚合(主币种口径)。
    final multiCurrencyActive = ref.watch(multiCurrencyActiveProvider);
    final showComposition = isSingleCurrency || multiCurrencyActive;
    // 折算 active 喂折算后构成;否则原币构成。组件入参类型相同。
    final effectiveCompositionAsync = multiCurrencyActive
        ? ref.watch(convertedAssetCompositionProvider)
        : compositionAsync;

    return SectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 净资产部分
          netWorthAsync.when(
            skipLoadingOnReload: true,
            data: (nwByCurrency) => _buildNetWorthContent(context, ref, nwByCurrency),
            loading: () => SizedBox(
              height: 80.0.scaled(context, ref),
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
          // 走势 / 构成 切换区:
          // - showComposition=true（单币种 或 折算态）：可在「净值走势」「资产构成」间切换，记住偏好；
          // - showComposition=false（多币种非折算，构成无法合并）：只展示走势（净值裸加）。
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.0.scaled(context, ref)),
            child: Divider(height: 1, color: BeeTokens.divider(context)),
          ),
          Builder(builder: (context) {
            final view = showComposition
                ? ref.watch(assetTrendViewProvider)
                : AssetTrendView.trend;
            return Column(
              children: [
                if (showComposition)
                  Padding(
                    padding: EdgeInsets.only(top: 10.0.scaled(context, ref)),
                    child:
                        _trendCompositionToggle(context, ref, view, primaryColor),
                  ),
                Padding(
                  padding: EdgeInsets.all(12.0.scaled(context, ref)),
                  child: view == AssetTrendView.composition
                      ? effectiveCompositionAsync.when(
                          skipLoadingOnReload: true,
                          data: (data) =>
                              AssetCompositionChart(data: data, embedded: true),
                          loading: () => SizedBox(
                            height: 180.0.scaled(context, ref),
                            child: const Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          ),
                          error: (_, __) => const SizedBox.shrink(),
                        )
                      : _buildNetWorthChartInline(context, ref),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  /// 净资产内容（不含外层 SectionCard）
  Widget _buildNetWorthContent(
    BuildContext context,
    WidgetRef ref,
    Map<String, ({double totalAssets, double totalLiabilities, double netWorth})> nwByCurrency,
  ) {
    final l10n = AppLocalizations.of(context);
    final useCompact = ref.watch(compactAmountProvider);

    // 多币种态总闸开启且折算结果就绪 → 走折算视图;否则原 per-currency 渲染原样回退。
    final multiCurrencyActive = ref.watch(multiCurrencyActiveProvider);
    final converted = ref.watch(convertedNetWorthProvider).valueOrNull;
    if (multiCurrencyActive && converted != null) {
      return _buildConvertedNetWorthContent(context, ref, converted, useCompact);
    }

    final isSingleCurrency = nwByCurrency.length <= 1;
    final singleNw = nwByCurrency.isEmpty
        ? (totalAssets: 0.0, totalLiabilities: 0.0, netWorth: 0.0)
        : nwByCurrency.values.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 净资产标签
        Text(
          l10n.accountTotalBalance,
          style: TextStyle(
            fontSize: 12,
            color: BeeTokens.textTertiary(context),
          ),
        ),
        SizedBox(height: 4.0.scaled(context, ref)),
        if (isSingleCurrency) ...[
          AmountText(
            value: singleNw.netWorth,
            signed: false,
            showCurrency: false,
            useCompactFormat: useCompact,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: singleNw.netWorth >= 0
                  ? BeeTokens.incomeColor(context, ref)
                  : BeeTokens.expenseColor(context, ref),
            ),
          ),
        ] else ...[
          ...nwByCurrency.entries.toList().asMap().entries.map((mapEntry) {
            final isFirst = mapEntry.key == 0;
            final currency = mapEntry.value.key;
            final nw = mapEntry.value.value;
            return Padding(
              padding: EdgeInsets.only(top: isFirst ? 0 : 2.0.scaled(context, ref)),
              child: AmountText(
                value: nw.netWorth,
                signed: false,
                showCurrency: true,
                currencyCode: currency,
                useCompactFormat: useCompact,
                style: TextStyle(
                  fontSize: isFirst ? 26 : 20,
                  fontWeight: FontWeight.bold,
                  color: nw.netWorth >= 0
                      ? BeeTokens.incomeColor(context, ref)
                      : BeeTokens.expenseColor(context, ref),
                ),
              ),
            );
          }),
        ],
        SizedBox(height: 12.0.scaled(context, ref)),
        // 总资产 | 总负债
        if (isSingleCurrency)
          Row(
            children: [
              Expanded(
                child: _StatCell(
                  label: l10n.totalAssets,
                  value: singleNw.totalAssets,
                  valueColor: BeeTokens.incomeColor(context, ref),
                ),
              ),
              Container(
                width: 1,
                height: 28.0.scaled(context, ref),
                color: BeeTokens.divider(context),
              ),
              Expanded(
                child: _StatCell(
                  label: l10n.totalLiabilities,
                  value: singleNw.totalLiabilities.abs(),
                  valueColor: BeeTokens.expenseColor(context, ref),
                ),
              ),
            ],
          )
        else
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        l10n.totalAssets,
                        style: TextStyle(
                          fontSize: 11,
                          color: BeeTokens.textTertiary(context),
                        ),
                      ),
                      SizedBox(height: 2.0.scaled(context, ref)),
                      _buildMultiCurrencyAmountRow(
                        context, ref,
                        entries: nwByCurrency.entries
                            .where((e) => e.value.totalAssets != 0)
                            .map((e) => (currency: e.key, value: e.value.totalAssets))
                            .toList(),
                        valueColor: BeeTokens.incomeColor(context, ref),
                        useCompact: useCompact,
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  color: BeeTokens.divider(context),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        l10n.totalLiabilities,
                        style: TextStyle(
                          fontSize: 11,
                          color: BeeTokens.textTertiary(context),
                        ),
                      ),
                      SizedBox(height: 2.0.scaled(context, ref)),
                      _buildMultiCurrencyAmountRow(
                        context, ref,
                        entries: nwByCurrency.entries
                            .where((e) => e.value.totalLiabilities != 0)
                            .map((e) => (currency: e.key, value: e.value.totalLiabilities.abs()))
                            .toList(),
                        valueColor: BeeTokens.expenseColor(context, ref),
                        useCompact: useCompact,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        // 总资产/总负债数字跟下面的 Divider 之间留出呼吸空间,不然视觉上紧贴着
        // 横线很挤。
        SizedBox(height: 20.0.scaled(context, ref)),
      ],
    );
  }

  /// 资产卡内嵌净值走势图（完整版：带网格 + 月份标签，非缩略 sparkline），点击进全屏
  /// 趋势页。interactive:false → LineChart 不吞 tap，把点击交给外层 InkWell。
  Widget _buildNetWorthChartInline(BuildContext context, WidgetRef ref) {
    final now = trendTodayAnchor();
    final start = DateTime(now.year, now.month - 11, 1);
    final seriesAsync = ref.watch(
        netWorthTrendSeriesProvider((startDate: start, endDate: now)));
    final hide = ref.watch(hideAmountsProvider);
    final primary = ref.watch(primaryColorProvider);
    final l10n = AppLocalizations.of(context);
    return seriesAsync.maybeWhen(
      data: (series) {
        final monthly = downsampleMonthly(series);
        if (monthly.length < 2) {
          return _inlineChartBox(
            context,
            ref,
            Text(l10n.commonEmpty,
                style: TextStyle(
                    fontSize: 12, color: BeeTokens.textTertiary(context))),
          );
        }
        return InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NetWorthTrendPage()),
          ),
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 180.0.scaled(context, ref),
            child: LineChart(
              values: monthly.map((e) => e.net).toList(),
              xLabels: monthly
                  .map((e) => '${e.date.year % 100}/${e.date.month}')
                  .toList(),
              highlightIndex: monthly.length - 1,
              onSwipeLeft: () {},
              onSwipeRight: () {},
              showHint: false,
              hideAmounts: hide,
              themeColor: primary,
              whiteBg: !BeeTokens.isDark(context),
              isDark: BeeTokens.isDark(context),
              showGrid: true,
              showDots: false,
              annotate: true,
              interactive: false, // 点击交给外层 InkWell 进全屏页
              minimal: true, // 去背景/Y轴/均线，避免嵌在 SectionCard 内暗黑模式「卡中卡」
            ),
          ),
        );
      },
      error: (_, __) => _inlineChartBox(
        context,
        ref,
        Text(l10n.commonError,
            style: TextStyle(
                fontSize: 12, color: BeeTokens.textTertiary(context))),
      ),
      orElse: () => _inlineChartBox(context, ref,
          const Center(child: CircularProgressIndicator(strokeWidth: 2))),
    );
  }

  Widget _inlineChartBox(BuildContext context, WidgetRef ref, Widget child) =>
      SizedBox(
        height: 180.0.scaled(context, ref),
        child: Center(child: child),
      );

  /// 走势 / 构成 切换控件（主题色分段胶囊）。
  Widget _trendCompositionToggle(BuildContext context, WidgetRef ref,
      AssetTrendView view, Color primary) {
    final l10n = AppLocalizations.of(context);
    Widget seg(AssetTrendView v, String label) {
      final on = view == v;
      return GestureDetector(
        onTap: () => ref.read(assetTrendViewProvider.notifier).select(v),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
              horizontal: 14.0.scaled(context, ref),
              vertical: 6.0.scaled(context, ref)),
          decoration: BoxDecoration(
            color: on ? primary.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: on ? primary : BeeTokens.border(context), width: 1),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 12,
                color: on ? primary : BeeTokens.textSecondary(context),
                fontWeight: on ? FontWeight.w600 : FontWeight.normal,
              )),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        seg(AssetTrendView.trend, l10n.netWorthTrendTitle),
        SizedBox(width: 8.0.scaled(context, ref)),
        seg(AssetTrendView.composition, l10n.assetComposition),
      ],
    );
  }

  /// 折算视图：净资产折算总额 + 每币种折算行 + 缺失标示 + 脚注入口 + 折算总资产/总负债。
  /// 仅在多币种总闸开启且 [convertedNetWorthProvider] 就绪时渲染（见 _buildNetWorthContent）。
  Widget _buildConvertedNetWorthContent(
    BuildContext context,
    WidgetRef ref,
    ConvertedNetWorth converted,
    bool useCompact,
  ) {
    final l10n = AppLocalizations.of(context);
    final base = ref.watch(baseCurrencyProvider).toUpperCase();
    final nwByCurrency = ref.watch(netWorthBreakdownByCurrencyProvider).valueOrNull ?? const {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 标题行：左 净资产(折X) 标签 + 右 详情入口
        Row(
          children: [
            const Spacer(),
            Text(
              l10n.convertedNetWorth(base),
              style: TextStyle(
                fontSize: 12,
                color: BeeTokens.textTertiary(context),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: () => _showNetWorthConversionDetail(
                    context, ref, converted, nwByCurrency, base, useCompact),
                  borderRadius: BorderRadius.circular(4.0.scaled(context, ref)),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 4.0.scaled(context, ref),
                      vertical: 2.0.scaled(context, ref),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.commonDetail,
                          style: TextStyle(
                            fontSize: 12,
                            color: BeeTokens.textTertiary(context),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 14.0.scaled(context, ref),
                          color: BeeTokens.iconTertiary(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 4.0.scaled(context, ref)),
        // 折算总额：≈(灰) + 折算净资产(主币种符号, 收支色)
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '≈ ',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: BeeTokens.textTertiary(context),
              ),
            ),
            Flexible(
              child: AmountText(
                value: converted.netWorth,
                signed: false,
                showCurrency: true,
                currencyCode: base,
                useCompactFormat: useCompact,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: converted.netWorth >= 0
                      ? BeeTokens.incomeColor(context, ref)
                      : BeeTokens.expenseColor(context, ref),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12.0.scaled(context, ref)),
        // 折算总资产 | 折算总负债(单行折算版)
        Row(
          children: [
            Expanded(
              child: _ConvertedStatCell(
                label: l10n.totalAssets,
                value: converted.totalAssets,
                currencyCode: base,
                valueColor: BeeTokens.incomeColor(context, ref),
                useCompact: useCompact,
              ),
            ),
            Container(
              width: 1,
              height: 28.0.scaled(context, ref),
              color: BeeTokens.divider(context),
            ),
            Expanded(
              child: _ConvertedStatCell(
                label: l10n.totalLiabilities,
                value: converted.totalLiabilities.abs(),
                currencyCode: base,
                valueColor: BeeTokens.expenseColor(context, ref),
                useCompact: useCompact,
              ),
            ),
          ],
        ),
        // 汇率折算脚注已折叠进「详情」弹窗(见 _showNetWorthConversionDetail），首屏不再展示。
        SizedBox(height: 8.0.scaled(context, ref)),
      ],
    );
  }

  /// 净资产折算明细弹窗:每币种原币净值 + 折算后/未折算。复用 _showConversionDetailSheet。
  void _showNetWorthConversionDetail(
    BuildContext context,
    WidgetRef ref,
    ConvertedNetWorth converted,
    Map<String, ({double totalAssets, double totalLiabilities, double netWorth})>
        nwByCurrency,
    String base,
    bool useCompact,
  ) {
    final l10n = AppLocalizations.of(context);
    final baseSymbol = getCurrencySymbol(base);
    final entries = nwByCurrency.entries.map((e) {
      final code = e.key.toUpperCase();
      return _ConversionDetailEntry(
        code: code,
        originalValue: e.value.netWorth,
        convertedValue: converted.netByCurrency[code],
        isBase: code == base,
        isMissing: converted.missingCurrencies.contains(code),
      );
    }).toList();
    // 汇率折算脚注（原在资产页首屏）折叠到这里:无缺失→折算日期(>7 天变橙),有缺失→
    // 缺失提示(橙),点击进汇率页管理。
    final hasMissing = converted.missingCurrencies.isNotEmpty;
    final rd = converted.oldestRateDate != null
        ? DateTime.tryParse(converted.oldestRateDate!)
        : null;
    final isStale = !hasMissing &&
        rd != null &&
        DateTime.now().difference(rd) > const Duration(days: 7);
    final footer = InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ExchangeRatePage()),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          hasMissing
              ? l10n.convertedPartialWarning(
                  converted.missingCurrencies.join('/'))
              : l10n.convertedFootnote(converted.oldestRateDate ?? '-'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: (hasMissing || isStale)
                ? Colors.orange
                : BeeTokens.textTertiary(context),
          ),
        ),
      ),
    );
    _showConversionDetailSheet(
      context,
      ref,
      title: l10n.conversionDetailTitle,
      entries: entries,
      baseSymbol: baseSymbol,
      useCompact: useCompact,
      footer: footer,
    );
  }

  /// 分组小计折算视图:≈ {symbol}{折算和}(有缺失加橙警示),整块点击 → 分组明细弹窗。
  /// 折算口径与净资产/构成图一致:缺汇率币种剔除,绝不按 1.0。
  Widget _buildGroupConvertedSubtotal(
    BuildContext context,
    WidgetRef ref, {
    required String groupTitle,
    required Map<String, double> subtotalByCurrency,
    required Map<String, EffectiveRate> rates,
    required String base,
    required Color iconColor,
    required bool useCompact,
  }) {
    final baseSymbol = getCurrencySymbol(base);
    final result = convertAmountsToBase(
      amounts: subtotalByCurrency,
      rates: rates,
      base: base,
    );
    final hasMissing = result.missingCurrencies.isNotEmpty;
    final hide = ref.watch(hideAmountsProvider);

    return InkWell(
      onTap: () => _showGroupConversionDetail(
        context, ref,
        groupTitle: groupTitle,
        subtotalByCurrency: subtotalByCurrency,
        result: result,
        baseSymbol: baseSymbol,
        base: base,
        useCompact: useCompact,
      ),
      borderRadius: BorderRadius.circular(4.0.scaled(context, ref)),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 4.0.scaled(context, ref),
          vertical: 2.0.scaled(context, ref),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (hasMissing) ...[
              Icon(
                Icons.warning_amber_rounded,
                size: 14.0.scaled(context, ref),
                color: Colors.orange,
              ),
              SizedBox(width: 4.0.scaled(context, ref)),
            ],
            Flexible(
              // abs 以沿用现状符号惯例:非折算时小计走 AmountText(signed:false) 即显绝对值,
              // 负债组同口径(折算值不带负号)。
              child: Text(
                hide
                    ? '≈ ****'
                    : '≈ $baseSymbol${result.total.abs().toStringAsFixed(2)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: iconColor,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 14.0.scaled(context, ref),
              color: BeeTokens.iconTertiary(context),
            ),
          ],
        ),
      ),
    );
  }

  /// 分组小计折算明细弹窗:每币种原币小计 + 折算后/未折算。复用 _showConversionDetailSheet。
  void _showGroupConversionDetail(
    BuildContext context,
    WidgetRef ref, {
    required String groupTitle,
    required Map<String, double> subtotalByCurrency,
    required ({double total, Map<String, double> convertedByCurrency, List<String> missingCurrencies}) result,
    required String baseSymbol,
    required String base,
    required bool useCompact,
  }) {
    final entries = subtotalByCurrency.entries.map((e) {
      final code = e.key.toUpperCase();
      return _ConversionDetailEntry(
        code: code,
        originalValue: e.value,
        convertedValue: result.convertedByCurrency[code],
        isBase: code == base,
        isMissing: result.missingCurrencies.contains(code),
      );
    }).toList();
    _showConversionDetailSheet(
      context,
      ref,
      title: groupTitle,
      entries: entries,
      baseSymbol: baseSymbol,
      useCompact: useCompact,
    );
  }

  /// 多货币金额横排（用 · 分隔）
  Widget _buildMultiCurrencyAmountRow(
    BuildContext context,
    WidgetRef ref, {
    required List<({String currency, double value})> entries,
    required Color valueColor,
    required bool useCompact,
  }) {
    if (entries.isEmpty) {
      return Text(
        '-',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: BeeTokens.textTertiary(context),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 4.0.scaled(context, ref)),
                child: Text(
                  '·',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: BeeTokens.textTertiary(context),
                  ),
                ),
              ),
            AmountText(
              value: entries[i].value,
              signed: false,
              showCurrency: true,
              currencyCode: entries[i].currency,
              useCompactFormat: useCompact,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建资产/负债分类区域
  List<Widget> _buildClassificationSection({
    required BuildContext context,
    required AppLocalizations l10n,
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<String> typeOrder,
    required Map<String, List<db.Account>> groups,
    required Map<int, ({double balance, double expense, double income})>? allStats,
    required Color primaryColor,
    required int ledgerId,
  }) {
    // 检查此分类下是否有在用(非隐藏)账户 —— 账户隐藏 #240:隐藏账户移入
    // 底部「已隐藏」分区(_HiddenAccountsSection),此处只看在用账户。
    final hasAccounts = typeOrder.any((type) =>
        groups.containsKey(type) && groups[type]!.any((a) => !a.hidden));
    if (!hasAccounts) return [];

    // 按币种分组计算小计(仅在用账户;隐藏账户的小计在「已隐藏」分区单独
    // 展示,两者相加与净资产汇总卡对账 —— 01 §4.1)
    final Map<String, double> subtotalByCurrency = {};
    for (final type in typeOrder) {
      if (groups.containsKey(type)) {
        for (final account in groups[type]!) {
          if (account.hidden) continue;
          final balance = allStats?[account.id]?.balance ?? 0;
          subtotalByCurrency.update(
            account.currency,
            (v) => v + balance,
            ifAbsent: () => balance,
          );
        }
      }
    }
    final useCompact = ref.watch(compactAmountProvider);
    final isSingleCurrency = subtotalByCurrency.length <= 1;

    // 折算态(总闸开启且汇率就绪)且组内多币种 → 小计折算并支持点击详情。
    final multiCurrencyActive = ref.watch(multiCurrencyActiveProvider);
    final rates = ref.watch(effectiveRatesProvider).valueOrNull;
    final base = ref.watch(baseCurrencyProvider).toUpperCase();
    final convertActive =
        multiCurrencyActive && rates != null && !isSingleCurrency;

    return [
      // 分类标题
      Padding(
        padding: EdgeInsets.only(
          top: 16.0.scaled(context, ref),
          bottom: 4.0.scaled(context, ref),
          left: 4.0.scaled(context, ref),
          right: 4.0.scaled(context, ref),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18.0.scaled(context, ref), color: iconColor),
            SizedBox(width: 6.0.scaled(context, ref)),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: BeeTokens.textPrimary(context),
              ),
            ),
            const Spacer(),
            if (convertActive)
              // 折算小计:≈ {symbol}{折算和}(有缺失加橙色警示),整块点击进详情。
              // Expanded+Align 保证贴右(Spacer+Flexible 会让内容在右半槽内左对齐,
              // 表头右侧出现空白),内部 Text 仍有 Flexible/ellipsis 兜长文本。
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _buildGroupConvertedSubtotal(
                    context, ref,
                    groupTitle: title,
                    subtotalByCurrency: subtotalByCurrency,
                    rates: rates,
                    base: base,
                    iconColor: iconColor,
                    useCompact: useCompact,
                  ),
                ),
              )
            else if (isSingleCurrency)
              AmountText(
                value: subtotalByCurrency.values.firstOrNull ?? 0,
                signed: false,
                showCurrency: false,
                useCompactFormat: useCompact,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: iconColor,
                ),
              )
            else
              Flexible(
                child: _buildMultiCurrencyAmountRow(
                  context, ref,
                  entries: subtotalByCurrency.entries
                      .map((e) => (currency: e.key, value: e.value))
                      .toList(),
                  valueColor: iconColor,
                  useCompact: useCompact,
                ),
              ),
          ],
        ),
      ),
      // 类型分组(排除隐藏账户,账户隐藏 #240)
      ...typeOrder
          .where((type) =>
              groups.containsKey(type) && groups[type]!.any((a) => !a.hidden))
          .map((type) {
        final groupList = groups[type]!.where((a) => !a.hidden).toList();
        return _AccountTypeGroup(
          type: type,
          accounts: groupList,
          primaryColor: primaryColor,
          allStats: allStats,
          onReorder: (oldIndex, newIndex) =>
              _onReorder(type, groupList, oldIndex, newIndex),
          onTap: (account) =>
              _viewAccountDetail(context, ref, account),
          onEdit: (account) =>
              _editAccount(context, ref, account, ledgerId),
        );
      }),
    ];
  }

  /// 设置底部弹窗
  void _showSettingsSheet(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<bool> accountFeatureAsync,
    AsyncValue<List<db.Account>> accountsAsync,
  ) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.read(primaryColorProvider);
    // 默认收/支账户选择器排除隐藏账户(账户隐藏 #240 §四):列表本身不出现,
    // 且若当前默认恰好指向隐藏账户,下方 _CompactDefaultAccount 找不到匹配项
    // 会自动显示「不设置」,兜底 E3。
    final accounts =
        (accountsAsync.asData?.value ?? const <db.Account>[])
            .where((a) => !a.hidden)
            .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: BeeTokens.surfaceSheet(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            final featureAsync = ref.watch(accountFeatureEnabledProvider);
            final enabled = featureAsync.asData?.value ?? false;

            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 拖拽条
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: BeeTokens.textTertiary(context).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // 标题
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      l10n.commonSettings,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: BeeTokens.textPrimary(context),
                      ),
                    ),
                  ),
                  // 功能开关
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: SwitchListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text(
                        l10n.accountsEnableFeature,
                        style: TextStyle(
                          fontSize: 14,
                          color: BeeTokens.textPrimary(context),
                        ),
                      ),
                      value: enabled,
                      activeColor: primaryColor,
                      onChanged: (value) async {
                        await ref
                            .read(accountFeatureSetterProvider)
                            .setEnabled(value);
                        ref.invalidate(accountFeatureEnabledProvider);
                      },
                    ),
                  ),
                  // 汇率管理入口:仅在使用中币种 ≥2 时出现。折算开关已下线
                  // (多币种恒折算,与 Web 端对齐),这里只保留汇率管理入口。
                  Consumer(
                    builder: (context, ref, _) {
                      final used = ref.watch(usedCurrenciesProvider).valueOrNull;
                      if (used == null || used.length < 2) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: BeeTokens.divider(context),
                          ),
                          ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            title: Text(
                              l10n.exchangeRatePageTitle,
                              style: TextStyle(
                                fontSize: 14,
                                color: BeeTokens.textPrimary(context),
                              ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right,
                              size: 18.0.scaled(context, ref),
                              color: BeeTokens.iconTertiary(context),
                            ),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const ExchangeRatePage()),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                  if (enabled && accounts.isNotEmpty) ...[
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: BeeTokens.divider(context),
                    ),
                    _CompactDefaultAccount(
                      accounts: accounts,
                      primaryColor: primaryColor,
                      type: 'expense',
                    ),
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: BeeTokens.divider(context),
                    ),
                    _CompactDefaultAccount(
                      accounts: accounts,
                      primaryColor: primaryColor,
                      type: 'income',
                    ),
                  ],
                  SizedBox(height: 16.0.scaled(context, ref)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _addAccount(BuildContext context, WidgetRef ref, int ledgerId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AccountEditPage(ledgerId: ledgerId),
      ),
    );

    // 只 bump tick:4 个 stats provider 都 ref.watch(statsRefreshProvider),
    // 自动重算且保留旧值,`when` 不会闪 loading。
    // `ref.invalidate` 会清掉 cached value 让 `.when` 走 loading 分支,资产
    // 页 spinner 闪烁 / 整页 reload 体感的根因。
    ref.read(statsRefreshProvider.notifier).state++;
  }

  Future<void> _editAccount(BuildContext context, WidgetRef ref,
      db.Account account, int ledgerId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AccountEditPage(
          account: account,
          ledgerId: ledgerId,
        ),
      ),
    );

    ref.read(statsRefreshProvider.notifier).state++;
  }

  void _viewAccountDetail(
      BuildContext context, WidgetRef ref, db.Account account) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AccountDetailPage(account: account),
      ),
    );
  }

  /// 「已隐藏」分区卡片上的「恢复」快捷入口(账户隐藏 #240)。恢复无需确认
  /// (低风险、可逆,产品设计 01 §3.2),即时生效并推送同步。
  Future<void> _restoreAccount(
      BuildContext context, WidgetRef ref, db.Account account) async {
    final l10n = AppLocalizations.of(context);
    await ref.read(repositoryProvider).setAccountHidden(account.id, false);

    // 账户变更推同步,同 _onReorder 的写法。
    final activeLedgerId = ref.read(currentLedgerIdProvider);
    if (activeLedgerId > 0) {
      unawaited(PostProcessor.sync(ref, ledgerId: activeLedgerId));
    }

    // 只 bump tick,不 invalidate,避免资产页整页 loading 闪烁(同 _addAccount)。
    ref.read(statsRefreshProvider.notifier).state++;

    if (context.mounted) showToast(context, l10n.accountRestoredToast);
  }
}

/// Header 内统计项（白色文字）
class _StatCell extends ConsumerWidget {
  final String label;
  final double value;
  final Color? valueColor;

  const _StatCell({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: BeeTokens.textTertiary(context),
          ),
        ),
        SizedBox(height: 2.0.scaled(context, ref)),
        AmountText(
          value: value,
          signed: false,
          showCurrency: false,
          useCompactFormat: ref.watch(compactAmountProvider),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: valueColor ?? BeeTokens.textPrimary(context),
          ),
        ),
      ],
    );
  }
}

/// 折算视图里「≈ 符号+数值」的灰色小字（每币种折算行尾随）。
/// 这是派生金额文本，需跟 AmountText 一样响应隐藏金额开关。
class _ApproxConvertedText extends ConsumerWidget {
  final String text;

  const _ApproxConvertedText({required this.text});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hide = ref.watch(hideAmountsProvider);
    return Text(
      hide ? '≈ ****' : text,
      style: TextStyle(
        fontSize: 12,
        color: BeeTokens.textTertiary(context),
      ),
    );
  }
}

/// 折算详情弹窗的一行数据：原币 + 折算后/缺失标示。
/// 净资产明细弹窗与分组小计明细弹窗共用同一渲染(redline:两处一份代码)。
class _ConversionDetailEntry {
  final String code; // 大写币种码
  final double originalValue; // 原币金额(符号保持调用方口径)
  final double? convertedValue; // 折算后(base 自身/可折算才有);缺失为 null
  final bool isBase;
  final bool isMissing;
  const _ConversionDetailEntry({
    required this.code,
    required this.originalValue,
    required this.convertedValue,
    required this.isBase,
    required this.isMissing,
  });
}

/// 折算详情弹窗的单行:左 币种码+本地化名 / 中 原币值 / 右 base 空·缺失 badge·≈折算灰字。
class _ConversionDetailRow extends ConsumerWidget {
  final _ConversionDetailEntry entry;
  final String baseSymbol;
  final bool useCompact;

  const _ConversionDetailRow({
    required this.entry,
    required this.baseSymbol,
    required this.useCompact,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16.0.scaled(context, ref),
        vertical: 10.0.scaled(context, ref),
      ),
      child: Row(
        children: [
          // 左:币种码 + 本地化名
          Expanded(
            child: Row(
              children: [
                Text(
                  entry.code,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
                SizedBox(width: 6.0.scaled(context, ref)),
                Flexible(
                  child: Text(
                    getCurrencyName(entry.code, context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: BeeTokens.textTertiary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.0.scaled(context, ref)),
          // 中:原币净值
          AmountText(
            value: entry.originalValue,
            signed: false,
            showCurrency: true,
            currencyCode: entry.code,
            useCompactFormat: useCompact,
            style: TextStyle(
              fontSize: 14,
              color: BeeTokens.textSecondary(context),
            ),
          ),
          SizedBox(width: 8.0.scaled(context, ref)),
          // 右:base 自身空 / 缺失橙 badge / ≈ 折算 灰字
          if (entry.isBase)
            const SizedBox.shrink()
          else if (entry.isMissing)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: 6.0.scaled(context, ref),
                vertical: 1.0.scaled(context, ref),
              ),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.orange, width: 1),
                borderRadius: BorderRadius.circular(4.0.scaled(context, ref)),
              ),
              child: Text(
                l10n.unconvertedBadge,
                style: const TextStyle(fontSize: 11, color: Colors.orange),
              ),
            )
          else if (entry.convertedValue != null)
            // abs:与同行原币 AmountText(signed:false) 的绝对值口径一致(负债不带负号)。
            _ApproxConvertedText(
              text: '≈ $baseSymbol${entry.convertedValue!.abs().toStringAsFixed(2)}',
            ),
        ],
      ),
    );
  }
}

/// 折算详情弹窗(骨架照 _showSettingsSheet:拖拽条 + 标题 + SafeArea)。
/// 净资产明细 / 分组小计明细共用;[entries] 已是 UI 所需的每币种行数据。
void _showConversionDetailSheet(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required List<_ConversionDetailEntry> entries,
  required String baseSymbol,
  required bool useCompact,
  Widget? footer,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: BeeTokens.surfaceSheet(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽条
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: BeeTokens.textTertiary(sheetContext)
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: BeeTokens.textPrimary(sheetContext),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in entries)
                      _ConversionDetailRow(
                        entry: e,
                        baseSymbol: baseSymbol,
                        useCompact: useCompact,
                      ),
                    if (footer != null) footer,
                  ],
                ),
              ),
            ),
            SizedBox(height: 8.0.scaled(sheetContext, ref)),
          ],
        ),
      );
    },
  );
}

/// 折算视图的总资产/总负债单元格：≈(灰) 前缀 + 折算后金额(主币种)。
class _ConvertedStatCell extends ConsumerWidget {
  final String label;
  final double value;
  final String currencyCode;
  final Color valueColor;
  final bool useCompact;

  const _ConvertedStatCell({
    required this.label,
    required this.value,
    required this.currencyCode,
    required this.valueColor,
    required this.useCompact,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: BeeTokens.textTertiary(context),
          ),
        ),
        SizedBox(height: 2.0.scaled(context, ref)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '≈ ',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: BeeTokens.textTertiary(context),
              ),
            ),
            Flexible(
              child: AmountText(
                value: value,
                signed: false,
                showCurrency: true,
                currencyCode: currencyCode,
                useCompactFormat: useCompact,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 账户类型分组（可折叠，默认展开）
class _AccountTypeGroup extends ConsumerStatefulWidget {
  final String type;
  final List<db.Account> accounts;
  final Color primaryColor;
  final Map<int, ({double balance, double expense, double income})>? allStats;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(db.Account account) onTap;
  final void Function(db.Account account) onEdit;

  const _AccountTypeGroup({
    required this.type,
    required this.accounts,
    required this.primaryColor,
    this.allStats,
    required this.onReorder,
    required this.onTap,
    required this.onEdit,
  });

  @override
  ConsumerState<_AccountTypeGroup> createState() => _AccountTypeGroupState();
}

class _AccountTypeGroupState extends ConsumerState<_AccountTypeGroup> {
  bool _expanded = true;
  /// 主帳戶(合併帳單分組)收合狀態:記錄「已收合」的主帳戶 id,預設全部展開。
  final Set<int> _collapsedParentIds = {};

  @override
  Widget build(BuildContext context) {
    final typeColor = getColorForAccountType(widget.type, widget.primaryColor);
    // 折算外幣子帳戶用:跟頁面其它折算口徑（净资产卡/分组小计）同一組
    // effectiveRatesProvider + baseCurrencyProvider。
    final rates = ref.watch(effectiveRatesProvider).valueOrNull;
    final base = ref.watch(baseCurrencyProvider).toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 类型标题栏（点击展开/折叠）
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.only(
              top: 12.0.scaled(context, ref),
              bottom: 6.0.scaled(context, ref),
              left: 4.0.scaled(context, ref),
              right: 4.0.scaled(context, ref),
            ),
            child: Row(
              children: [
                Container(
                  width: 28.0.scaled(context, ref),
                  height: 28.0.scaled(context, ref),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7.0.scaled(context, ref)),
                  ),
                  child: Center(
                    child: AccountTypeIcon(
                      type: widget.type,
                      size: 16.0.scaled(context, ref),
                      color: typeColor,
                    ),
                  ),
                ),
                SizedBox(width: 8.0.scaled(context, ref)),
                Text(
                  getAccountTypeLabel(context, widget.type),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
                SizedBox(width: 6.0.scaled(context, ref)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 5.0.scaled(context, ref),
                    vertical: 1.0.scaled(context, ref),
                  ),
                  decoration: BoxDecoration(
                    color: BeeTokens.textTertiary(context).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8.0.scaled(context, ref)),
                  ),
                  child: Text(
                    '${widget.accounts.length}',
                    style: TextStyle(
                      fontSize: 11,
                      color: BeeTokens.textTertiary(context),
                    ),
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right,
                    size: 18.0.scaled(context, ref),
                    color: BeeTokens.iconTertiary(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 账户清单(主帳戶/子帳戶樹狀分組,帳戶總覽 #主子帳戶改版):對齊 web
        // AccountListRow 的緊湊清單樣式 —— 整組帳戶包在同一個帶邊框的清單
        // 容器裡,行與行之間用細分隔線隔開,不再是各自獨立的漸層卡片。
        if (_expanded)
          Container(
            decoration: BoxDecoration(
              color: BeeTokens.surfaceElevated(context),
              borderRadius: BorderRadius.circular(14.0.scaled(context, ref)),
              border: Border.all(color: BeeTokens.cardOuterBorderColor(context)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final entry in _buildAccountBlocks(context, typeColor, rates, base).indexed) ...[
                  if (entry.$1 > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: BeeTokens.cardInnerDividerColor(context),
                    ),
                  entry.$2,
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// 按 parentAccountId 把本類型的帳戶分成「主帳戶+子帳戶」樹狀結構跟獨立
  /// 帳戶,每個頂層帳戶(含它底下展開的子帳戶)算一個 block,block 之間由
  /// 呼叫端插入分隔線。子帳戶找不到同組主帳戶(主帳戶被隱藏/不同類型/尚未
  /// 同步下來)時降級成獨立 block,不丟資料。
  List<Widget> _buildAccountBlocks(
    BuildContext context,
    Color typeColor,
    Map<String, EffectiveRate>? rates,
    String base,
  ) {
    final childrenByParent = <String, List<db.Account>>{};
    for (final a in widget.accounts) {
      final pid = a.parentAccountId;
      if (pid != null && pid.isNotEmpty) {
        childrenByParent.putIfAbsent(pid, () => []).add(a);
      }
    }
    final topLevel =
        widget.accounts.where((a) => a.parentAccountId == null || a.parentAccountId!.isEmpty).toList();
    final topLevelSyncIds = topLevel.map((a) => a.syncId).whereType<String>().toSet();

    final blocks = <Widget>[];
    for (final account in topLevel) {
      final children = (account.syncId != null)
          ? (childrenByParent[account.syncId] ?? const <db.Account>[])
          : const <db.Account>[];
      if (children.isEmpty) {
        blocks.add(_AccountCard(
          key: ValueKey(account.id),
          account: account,
          primaryColor: widget.primaryColor,
          typeColor: typeColor,
          effectiveType: widget.type,
          stats: widget.allStats?[account.id],
          onTap: () => widget.onTap(account),
          onEdit: () => widget.onEdit(account),
        ));
        continue;
      }

      final collapsed = _collapsedParentIds.contains(account.id);
      final rows = <Widget>[
        _AccountCard(
          key: ValueKey(account.id),
          account: account,
          primaryColor: widget.primaryColor,
          typeColor: typeColor,
          effectiveType: widget.type,
          stats: _aggregateParentStats(account, children, widget.allStats, rates, base),
          childCount: children.length,
          expanded: !collapsed,
          onToggleExpand: () => setState(() {
            if (collapsed) {
              _collapsedParentIds.remove(account.id);
            } else {
              _collapsedParentIds.add(account.id);
            }
          }),
          onTap: () => widget.onTap(account),
          onEdit: () => widget.onEdit(account),
        ),
      ];
      if (!collapsed) {
        for (var i = 0; i < children.length; i++) {
          final child = children[i];
          rows.add(_ChildAccountRow(
            key: ValueKey('child_${child.id}'),
            account: child,
            parentCurrency: account.currency,
            isLast: i == children.length - 1,
            stats: widget.allStats?[child.id],
            onTap: () => widget.onTap(child),
            onEdit: () => widget.onEdit(child),
          ));
        }
      }
      blocks.add(Column(children: rows));
    }

    // 孤儿子卡(主帳戶不在同一類型分組裡):降級成獨立 block,避免漏掉。
    for (final a in widget.accounts) {
      final pid = a.parentAccountId;
      if (pid != null && pid.isNotEmpty && !topLevelSyncIds.contains(pid)) {
        blocks.add(_AccountCard(
          key: ValueKey(a.id),
          account: a,
          primaryColor: widget.primaryColor,
          typeColor: typeColor,
          effectiveType: widget.type,
          stats: widget.allStats?[a.id],
          onTap: () => widget.onTap(a),
          onEdit: () => widget.onEdit(a),
        ));
      }
    }

    return blocks;
  }

  /// 主帳戶表頭聚合餘額:自己的 stats + 全部子帳戶 stats 加總,幣種不同的
  /// 子帳戶按 [rates] 折算成主帳戶幣種再併入(跟 web 端「主帳戶合計＝子帳戶
  /// 折算後加總」對齊);缺有效匯率時該子帳戶跳過不併入合計,不靜默按 1.0
  /// 折算(README D5)。
  ({double balance, double expense, double income})? _aggregateParentStats(
    db.Account parent,
    List<db.Account> children,
    Map<int, ({double balance, double expense, double income})>? allStats,
    Map<String, EffectiveRate>? rates,
    String base,
  ) {
    if (allStats == null) return null;
    final own = allStats[parent.id];
    double balance = own?.balance ?? 0;
    double expense = own?.expense ?? 0;
    double income = own?.income ?? 0;
    for (final c in children) {
      final s = allStats[c.id];
      if (s == null) continue;
      if (c.currency == parent.currency) {
        balance += s.balance;
        expense += s.expense;
        income += s.income;
        continue;
      }
      final convertedBalance = convertBetweenCurrencies(
          amount: s.balance, from: c.currency, to: parent.currency, rates: rates, base: base);
      final convertedExpense = convertBetweenCurrencies(
          amount: s.expense, from: c.currency, to: parent.currency, rates: rates, base: base);
      final convertedIncome = convertBetweenCurrencies(
          amount: s.income, from: c.currency, to: parent.currency, rates: rates, base: base);
      if (convertedBalance != null) balance += convertedBalance;
      if (convertedExpense != null) expense += convertedExpense;
      if (convertedIncome != null) income += convertedIncome;
    }
    return (balance: balance, expense: expense, income: income);
  }
}

/// 幣種互轉:通過 [rates](以 [base] 為錨的「1 quote = rate base」有效匯率表)
/// 做「from → base → to」兩段換算。from/to 等於 base 時對應段 rate=1,免查表。
/// 任一段缺有效匯率 → 回傳 null(README D5,絕不靜默按 1.0 折算)。
double? convertBetweenCurrencies({
  required double amount,
  required String from,
  required String to,
  required Map<String, EffectiveRate>? rates,
  required String base,
}) {
  final fromCode = from.toUpperCase();
  final toCode = to.toUpperCase();
  if (fromCode == toCode) return amount;
  double? rateToBase(String code) {
    if (code == base) return 1.0;
    final eff = rates?[code];
    if (eff == null) return null;
    final r = double.tryParse(eff.rate);
    if (r == null || r <= 0) return null;
    return r;
  }

  final fromRate = rateToBase(fromCode);
  final toRate = rateToBase(toCode);
  if (fromRate == null || toRate == null) return null;
  return amount * fromRate / toRate;
}

/// 子帳戶樹狀列表行(帳戶總覽 #主子帳戶改版):樹狀連接線 + 小圖標 + 名稱 +
/// 餘額,點擊進子帳戶明細、長按編輯(跟 _AccountCard 手勢一致)。幣種跟主
/// 帳戶不同時,金額前綴幣種代碼並帶一個 ⇌ 折算切換鈕(對齊 web 端行為):
/// 預設顯示原幣金額,點一下切成折算成主帳戶幣種後的金額,再點一下切回去。
class _ChildAccountRow extends ConsumerStatefulWidget {
  final db.Account account;
  final String parentCurrency;
  final bool isLast;
  final ({double balance, double expense, double income})? stats;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _ChildAccountRow({
    super.key,
    required this.account,
    required this.parentCurrency,
    required this.isLast,
    required this.stats,
    required this.onTap,
    required this.onEdit,
  });

  @override
  ConsumerState<_ChildAccountRow> createState() => _ChildAccountRowState();
}

class _ChildAccountRowState extends ConsumerState<_ChildAccountRow> {
  bool _showConverted = false;

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final isLast = widget.isLast;
    final onTap = widget.onTap;
    final onEdit = widget.onEdit;
    final balance = widget.stats?.balance ?? 0;
    final useCompact = ref.watch(compactAmountProvider);

    final isForeign = account.currency.toUpperCase() != widget.parentCurrency.toUpperCase();
    double? converted;
    if (isForeign) {
      final rates = ref.watch(effectiveRatesProvider).valueOrNull;
      final base = ref.watch(baseCurrencyProvider).toUpperCase();
      converted = convertBetweenCurrencies(
        amount: balance,
        from: account.currency,
        to: widget.parentCurrency,
        rates: rates,
        base: base,
      );
    }
    final showingConverted = isForeign && _showConverted && converted != null;
    final displayValue = showingConverted ? converted : balance;
    final displayCurrency = showingConverted ? widget.parentCurrency : account.currency;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onEdit,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.only(
          left: 14.0.scaled(context, ref),
          right: 14.0.scaled(context, ref),
          top: 4.0.scaled(context, ref),
          bottom: 4.0.scaled(context, ref),
        ),
        child: Row(
          children: [
            _TreeConnector(
              isLast: isLast,
              color: BeeTokens.divider(context),
            ),
            Container(
              width: 26.0.scaled(context, ref),
              height: 26.0.scaled(context, ref),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BeeTokens.surfaceCategoryIcon(context),
              ),
              child: account.avatarPath != null
                  ? ClipOval(
                      child: _AccountAvatarImage(
                        avatarPath: account.avatarPath!,
                        size: 26.0.scaled(context, ref),
                        fallback: AccountTypeIcon(
                          type: account.type,
                          size: 14.0.scaled(context, ref),
                        ),
                      ),
                    )
                  : Center(
                      child: AccountTypeIcon(
                        type: account.type,
                        size: 14.0.scaled(context, ref),
                      ),
                    ),
            ),
            SizedBox(width: 8.0.scaled(context, ref)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    account.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                  if ((account.cardLastFour ?? '').isNotEmpty)
                    Text(
                      '•••• ${account.cardLastFour}',
                      style: TextStyle(
                        fontSize: 11,
                        color: BeeTokens.textTertiary(context),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: 8.0.scaled(context, ref)),
            if (isForeign)
              Padding(
                padding: EdgeInsets.only(right: 4.0.scaled(context, ref)),
                child: Text(
                  displayCurrency.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: BeeTokens.textTertiary(context),
                  ),
                ),
              ),
            AmountText(
              value: displayValue,
              signed: false,
              showCurrency: false,
              useCompactFormat: useCompact,
              currencyCode: displayCurrency,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                // 信用卡类子帳戶:欠款(負)紅、繳清或溢繳(≥0)綠,跟主帳戶
                // 聚合列同一套配色(_AccountCard);其它類型子帳戶維持中性
                // 文字色,只在真的欠款時標紅。
                color: isLiabilityType(account.type)
                    ? (displayValue < 0
                        ? BeeTokens.expenseColor(context, ref)
                        : BeeTokens.incomeColor(context, ref))
                    : (displayValue < 0
                        ? BeeTokens.expenseColor(context, ref)
                        : BeeTokens.textPrimary(context)),
              ),
            ),
            // 幣種折算切換鈕(對齊 web「⇌」):只在能算出折算值(匯率齊全)
            // 時才顯示,缺匯率就不給切換入口,避免點了沒反應。
            if (isForeign && converted != null)
              GestureDetector(
                onTap: () => setState(() => _showConverted = !_showConverted),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.only(left: 4.0.scaled(context, ref)),
                  child: Icon(
                    Icons.sync_alt,
                    size: 14.0.scaled(context, ref),
                    color: showingConverted
                        ? BeeTokens.primary(context)
                        : BeeTokens.iconTertiary(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 子帳戶樹狀連接線:垂直主幹(從上方接續) + 水平分支接到圖標,非最後一個
/// 子帳戶時主幹繼續往下延伸接下一行(視覺上就是 ├/└ 的效果)。
class _TreeConnector extends StatelessWidget {
  final bool isLast;
  final Color color;

  const _TreeConnector({required this.isLast, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 34,
      child: CustomPaint(
        painter: _TreeConnectorPainter(isLast: isLast, color: color),
      ),
    );
  }
}

class _TreeConnectorPainter extends CustomPainter {
  final bool isLast;
  final Color color;

  _TreeConnectorPainter({required this.isLast, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final midX = size.width * 0.4;
    final midY = size.height / 2;
    canvas.drawLine(
      Offset(midX, 0),
      Offset(midX, isLast ? midY : size.height),
      paint,
    );
    canvas.drawLine(Offset(midX, midY), Offset(size.width, midY), paint);
  }

  @override
  bool shouldRepaint(covariant _TreeConnectorPainter oldDelegate) =>
      oldDelegate.isLast != isLast || oldDelegate.color != color;
}

/// 「已隐藏」账户分区(账户隐藏 #240,产品设计 01 §4.1)。置于所有在用分组
/// 之后,默认折叠;分区头显示「已隐藏(N)· 合计 ¥x」(小计口径同净资产卡:
/// 多币种折算跳过缺汇率币种,复用 [convertAmountsToBase],与资产/负债分组
/// 小计同一函数,保证与净资产汇总卡的差额天然对上账)。隐藏卡复用
/// [_AccountCard],传入中性灰 typeColor 弱化视觉权重 + onRestore 回调。
class _HiddenAccountsSection extends ConsumerStatefulWidget {
  final List<db.Account> accounts;
  final Map<int, ({double balance, double expense, double income})>? allStats;
  final Color primaryColor;
  final void Function(db.Account account) onTap;
  final void Function(db.Account account) onEdit;
  final void Function(db.Account account) onRestore;

  const _HiddenAccountsSection({
    required this.accounts,
    required this.allStats,
    required this.primaryColor,
    required this.onTap,
    required this.onEdit,
    required this.onRestore,
  });

  @override
  ConsumerState<_HiddenAccountsSection> createState() =>
      _HiddenAccountsSectionState();
}

class _HiddenAccountsSectionState
    extends ConsumerState<_HiddenAccountsSection> {
  // 默认折叠(产品设计 01 §4.1)。
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.accounts.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final isDark = BeeTokens.isDark(context);
    // 中性灰(暗黑/明亮各一档),弱化隐藏卡视觉权重,不用账户类型主题色
    // (0xFF48484A 沿用 tokens.dart 里同款暗黑中性灰,见 surfaceCategoryIcon)。
    final mutedColor = isDark ? const Color(0xFF48484A) : Colors.grey.shade400;

    // 按币种分组计算小计,口径同 _buildClassificationSection(仅隐藏账户)。
    final Map<String, double> subtotalByCurrency = {};
    for (final account in widget.accounts) {
      final balance = widget.allStats?[account.id]?.balance ?? 0;
      subtotalByCurrency.update(
        account.currency,
        (v) => v + balance,
        ifAbsent: () => balance,
      );
    }
    final multiCurrencyActive = ref.watch(multiCurrencyActiveProvider);
    final rates = ref.watch(effectiveRatesProvider).valueOrNull;
    final base = ref.watch(baseCurrencyProvider).toUpperCase();
    final hide = ref.watch(hideAmountsProvider);

    final totalText = hide
        ? '****'
        : _subtotalText(subtotalByCurrency, multiCurrencyActive, rates, base);
    final summary =
        l10n.accountHiddenSectionSummary(widget.accounts.length, totalText);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.only(
              top: 16.0.scaled(context, ref),
              bottom: 4.0.scaled(context, ref),
              left: 4.0.scaled(context, ref),
              right: 4.0.scaled(context, ref),
            ),
            child: Row(
              children: [
                Icon(Icons.visibility_off_outlined,
                    size: 18.0.scaled(context, ref),
                    color: BeeTokens.textTertiary(context)),
                SizedBox(width: 6.0.scaled(context, ref)),
                Expanded(
                  child: Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: BeeTokens.textSecondary(context),
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.chevron_right,
                      size: 18.0.scaled(context, ref),
                      color: BeeTokens.iconTertiary(context)),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            decoration: BoxDecoration(
              color: BeeTokens.surfaceElevated(context),
              borderRadius: BorderRadius.circular(14.0.scaled(context, ref)),
              border: Border.all(color: BeeTokens.cardOuterBorderColor(context)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final entry in widget.accounts.indexed) ...[
                  if (entry.$1 > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: BeeTokens.cardInnerDividerColor(context),
                    ),
                  _AccountCard(
                    key: ValueKey('hidden_${entry.$2.id}'),
                    account: entry.$2,
                    primaryColor: widget.primaryColor,
                    typeColor: mutedColor,
                    stats: widget.allStats?[entry.$2.id],
                    onTap: () => widget.onTap(entry.$2),
                    onEdit: () => widget.onEdit(entry.$2),
                    onRestore: () => widget.onRestore(entry.$2),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// 小计文本:与净资产卡同口径。单币种直接格式化;跨币种且折算态就绪时,
  /// 折到主币种(与 _buildGroupConvertedSubtotal 同一个 convertAmountsToBase)。
  String _subtotalText(
    Map<String, double> subtotalByCurrency,
    bool multiCurrencyActive,
    Map<String, EffectiveRate>? rates,
    String base,
  ) {
    final isSingleCurrency = subtotalByCurrency.length <= 1;
    if (multiCurrencyActive && rates != null && !isSingleCurrency) {
      final result = convertAmountsToBase(
        amounts: subtotalByCurrency,
        rates: rates,
        base: base,
      );
      return '${getCurrencySymbol(base)}${result.total.abs().toStringAsFixed(2)}';
    }
    final currency = subtotalByCurrency.keys.firstOrNull ?? base;
    final value = subtotalByCurrency.values.firstOrNull ?? 0;
    return '${getCurrencySymbol(currency)}${formatMoneyCompact(value, maxDecimals: 2, signed: false)}';
  }
}

/// 账户卡片
/// 账户清单行(帳戶總覽 #主子帳戶改版):緊湊清單樣式,對齊 web
/// AccountListRow —— 圖示 + 名稱(+子卡數量徽章)+ 副標(可用額度 / 卡號末
/// 四碼 / 隸屬於 X)+ 金額(+ 展開箭頭),取代舊版漸層促銷卡片。主帳戶跟
/// 子帳戶(_ChildAccountRow)共用同一種視覺語言,只差圖示大小跟樹狀連接線。
class _AccountCard extends ConsumerWidget {
  final db.Account account;
  final Color primaryColor;
  final Color typeColor;
  final ({double balance, double expense, double income})? stats;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  /// 「已隐藏」分区卡片的恢复回调(账户隐藏 #240)。非空时才渲染「已隐藏」
  /// 灰标 + 恢复按钮;在用卡片(account.hidden==false)不受影响。
  final VoidCallback? onRestore;
  /// 主帳戶(合併帳單分組)子卡數量。非空時在名稱旁渲染數量徽章,配合
  /// [onToggleExpand] 顯示展開/收合箭頭。
  final int? childCount;
  final bool expanded;
  final VoidCallback? onToggleExpand;
  /// 資產/負債分類要用的「展示類型」——主帳戶(account_group)自己的
  /// account.type 不在 isLiabilityType 白名單裡,要用它被歸類到的分組
  /// type(呼叫端 [_AccountTypeGroupState.widget.type],已按子帳戶類型
  /// 解析過,見 [_AccountsPageState._resolveDisplayType])才能正確判斷是不是
  /// 該用信用卡的欠款紅/繳清綠配色。不傳則退回 account.type 自己。
  final String? effectiveType;

  const _AccountCard({
    super.key,
    required this.account,
    required this.primaryColor,
    required this.typeColor,
    this.stats,
    required this.onTap,
    required this.onEdit,
    this.onRestore,
    this.childCount,
    this.expanded = true,
    this.onToggleExpand,
    this.effectiveType,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final balance = stats?.balance ?? 0;
    final isLiability = isLiabilityType(effectiveType ?? account.type);
    final creditLimit = account.creditLimit;
    final used = balance < 0 ? -balance : 0.0;
    final primaryValue = isLiability ? used : balance;
    final Color amountColor = isLiability
        ? (used > 0
            ? BeeTokens.expenseColor(context, ref)
            : BeeTokens.incomeColor(context, ref))
        : (balance < 0
            ? BeeTokens.expenseColor(context, ref)
            : BeeTokens.textPrimary(context));

    return GestureDetector(
      onTap: onTap,
      onLongPress: onEdit,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 14.0.scaled(context, ref),
          vertical: 10.0.scaled(context, ref),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildAvatar(context, ref),
            SizedBox(width: 10.0.scaled(context, ref)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: BeeTokens.textPrimary(context),
                          ),
                        ),
                      ),
                      if (childCount != null) ...[
                        SizedBox(width: 6.0.scaled(context, ref)),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 5.0.scaled(context, ref),
                            vertical: 1.0.scaled(context, ref),
                          ),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8.0.scaled(context, ref)),
                          ),
                          child: Text(
                            '$childCount',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: typeColor,
                            ),
                          ),
                        ),
                      ],
                      if (account.hidden) ...[
                        SizedBox(width: 6.0.scaled(context, ref)),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 5.0.scaled(context, ref),
                            vertical: 1.0.scaled(context, ref),
                          ),
                          decoration: BoxDecoration(
                            color: BeeTokens.textTertiary(context).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(4.0.scaled(context, ref)),
                          ),
                          child: Text(
                            l10n.accountHiddenTag,
                            style: TextStyle(
                              fontSize: 10,
                              color: BeeTokens.textTertiary(context),
                            ),
                          ),
                        ),
                      ],
                      _buildBillingDueBadge(context, ref, l10n),
                    ],
                  ),
                  SizedBox(height: 2.0.scaled(context, ref)),
                  _buildSubtitle(context, ref, l10n, creditLimit, used),
                ],
              ),
            ),
            SizedBox(width: 8.0.scaled(context, ref)),
            if (stats == null)
              SizedBox(
                width: 14.0.scaled(context, ref),
                height: 14.0.scaled(context, ref),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(BeeTokens.iconTertiary(context)),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AmountText(
                    value: primaryValue,
                    signed: false,
                    showCurrency: false,
                    useCompactFormat: ref.watch(compactAmountProvider),
                    currencyCode: account.currency,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: amountColor,
                    ),
                  ),
                  if (onRestore != null) ...[
                    SizedBox(height: 4.0.scaled(context, ref)),
                    GestureDetector(
                      onTap: onRestore,
                      child: Text(
                        l10n.accountRestore,
                        style: TextStyle(
                          fontSize: 11,
                          color: primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            if (onToggleExpand != null)
              GestureDetector(
                onTap: onToggleExpand,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.only(left: 4.0.scaled(context, ref)),
                  child: AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right,
                      size: 18.0.scaled(context, ref),
                      color: BeeTokens.iconTertiary(context),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, WidgetRef ref) {
    final size = 36.0.scaled(context, ref);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: typeColor.withValues(alpha: 0.14),
        border: Border.all(color: typeColor.withValues(alpha: 0.35)),
      ),
      child: account.avatarPath != null
          ? ClipOval(
              child: _AccountAvatarImage(
                avatarPath: account.avatarPath!,
                size: size,
                fallback: AccountTypeIcon(
                  type: account.type,
                  size: 18.0.scaled(context, ref),
                  color: typeColor,
                ),
              ),
            )
          : Center(
              child: AccountTypeIcon(
                type: account.type,
                size: 18.0.scaled(context, ref),
                color: typeColor,
              ),
            ),
    );
  }

  /// 「可繳款」徽章(MOZE 對標,2026-08-18):鏡射 Cloud
  /// `routers/read/workspace.py::list_workspace_accounts` 的
  /// `billing_due_date`/`billing_remaining_due`——只在 billing-root(獨立信用
  /// 卡,或合併帳單主帳戶 account_group)且「最近一次已結帳週期」仍有應繳
  /// 金額時才顯示,沒有額外的「N 天內」時間窗口限制。掛靠某個主帳戶的子卡
  /// (`parentAccountId != null`)不重複顯示——避免主帳戶跟子卡各自顯示一次
  /// 造成混淆,對齊 Cloud 只在 root 帳戶上附加這兩個欄位的做法。
  Widget _buildBillingDueBadge(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    if (account.parentAccountId != null) return const SizedBox.shrink();
    if (account.type != 'credit_card' && account.type != 'account_group') {
      return const SizedBox.shrink();
    }
    if (account.billingDay == null || account.paymentDueDay == null) {
      return const SizedBox.shrink();
    }
    final allAccounts = ref.watch(allAccountsStreamProvider).valueOrNull ?? const [];
    final syncId = account.syncId;
    final childIds = (syncId == null || syncId.isEmpty)
        ? <int>[]
        : allAccounts
            .where((a) => a.parentAccountId == syncId)
            .map((a) => a.id)
            .toList();
    childIds.sort();
    final badgeAsync = ref.watch(creditCardBillingBadgeProvider((
      accountId: account.id,
      extraIdsKey: childIds.join(','),
      billingDay: account.billingDay,
      paymentDueDay: account.paymentDueDay,
    )));
    final badge = badgeAsync.valueOrNull;
    if (badge == null) return const SizedBox.shrink();
    final dateLabel =
        '${badge.dueDate.month.toString().padLeft(2, '0')}/${badge.dueDate.day.toString().padLeft(2, '0')}';
    return Padding(
      padding: EdgeInsets.only(left: 6.0.scaled(context, ref)),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 5.0.scaled(context, ref),
          vertical: 1.0.scaled(context, ref),
        ),
        decoration: BoxDecoration(
          color: BeeTokens.error(context).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4.0.scaled(context, ref)),
        ),
        child: Text(
          l10n.creditCardBillingDueBadge(dateLabel),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: BeeTokens.error(context),
          ),
        ),
      ),
    );
  }

  /// 副標優先序:掛靠主帳戶的子卡顯示「隸屬於 X」→ 有子卡且設了額度的主
  /// 帳戶顯示「可用額度 $X」→ 有卡號末四碼顯示「•••• 1234」→ 都沒有就不
  /// 顯示副標。跟 web AccountListRow 的 showAvailableCredit/showLastFour
  /// 互斥邏輯對齊。
  Widget _buildSubtitle(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    double? creditLimit,
    double used,
  ) {
    final subtitleStyle = TextStyle(
      fontSize: 11,
      color: BeeTokens.textTertiary(context),
    );

    if (account.parentAccountId != null) {
      final allAccounts = ref.watch(allAccountsStreamProvider).valueOrNull ?? [];
      final parentName = allAccounts
          .where((a) => a.syncId == account.parentAccountId)
          .map((a) => a.name)
          .firstOrNull;
      if (parentName == null) return const SizedBox.shrink();
      return Text(
        l10n.accountParentBadge(parentName),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: subtitleStyle,
      );
    }

    if (childCount != null && creditLimit != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${l10n.creditAvailable} ', style: subtitleStyle),
          AmountText(
            value: creditLimit - used,
            signed: false,
            showCurrency: false,
            useCompactFormat: ref.watch(compactAmountProvider),
            currencyCode: account.currency,
            style: subtitleStyle,
          ),
        ],
      );
    }

    if ((account.cardLastFour ?? '').isNotEmpty) {
      return Text('•••• ${account.cardLastFour}', style: subtitleStyle);
    }

    return const SizedBox.shrink();
  }
}

/// 账户头像图片。avatarPath 是 custom_icons/ 下的相对路径(账户头像正常
/// 状态一定是已落盘的相对路径 —— 临时绝对路径只在编辑页保存前那一刻存在,
/// 不会进到这张已保存的卡片里),用 CustomIconService 解回绝对路径显示;
/// 解析失败 / 文件被清过缓存就退回调用方传入的 [fallback](类型图标)。
class _AccountAvatarImage extends StatelessWidget {
  final String avatarPath;
  final double size;
  final Widget fallback;

  const _AccountAvatarImage({
    required this.avatarPath,
    required this.size,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: CustomIconService().resolveIconPath(avatarPath),
      builder: (context, snapshot) {
        final abs = snapshot.data;
        if (abs == null) return Center(child: fallback);
        final file = File(abs);
        if (!file.existsSync()) return Center(child: fallback);
        return Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Center(child: fallback),
        );
      },
    );
  }
}

/// 紧凑默认账户选择行
class _CompactDefaultAccount extends ConsumerWidget {
  final List<db.Account> accounts;
  final Color primaryColor;
  final String type;

  const _CompactDefaultAccount({
    required this.accounts,
    required this.primaryColor,
    required this.type,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isIncome = type == 'income';
    final defaultAccountIdAsync = isIncome
        ? ref.watch(defaultIncomeAccountIdProvider)
        : ref.watch(defaultExpenseAccountIdProvider);

    return defaultAccountIdAsync.when(
      data: (defaultAccountId) {
        db.Account? defaultAccount;
        if (defaultAccountId != null) {
          defaultAccount = accounts.where((a) => a.id == defaultAccountId).firstOrNull;
        }

        final title = isIncome
            ? l10n.accountDefaultIncomeTitle
            : l10n.accountDefaultExpenseTitle;

        return InkWell(
          onTap: () => _showPicker(context, ref, accounts, defaultAccountId),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 16.0.scaled(context, ref),
              vertical: 10.0.scaled(context, ref),
            ),
            child: Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
                const Spacer(),
                Text(
                  defaultAccount?.name ?? l10n.accountDefaultNone,
                  style: TextStyle(
                    fontSize: 13,
                    color: BeeTokens.textTertiary(context),
                  ),
                ),
                SizedBox(width: 2.0.scaled(context, ref)),
                Icon(
                  Icons.chevron_right,
                  size: 16.0.scaled(context, ref),
                  color: BeeTokens.iconTertiary(context),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  void _showPicker(BuildContext context, WidgetRef ref, List<db.Account> accounts, int? currentDefaultId) {
    final l10n = AppLocalizations.of(context);
    final isIncome = type == 'income';
    final title = isIncome ? l10n.accountDefaultIncomeTitle : l10n.accountDefaultExpenseTitle;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BeeTokens.surfaceElevated(context),
        title: Text(title, style: TextStyle(color: BeeTokens.textPrimary(context))),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                dense: true,
                leading: Icon(Icons.block, color: BeeTokens.iconSecondary(context)),
                title: Text(
                  l10n.accountDefaultNone,
                  style: TextStyle(
                    color: currentDefaultId == null ? primaryColor : BeeTokens.textPrimary(context),
                    fontWeight: currentDefaultId == null ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                trailing: currentDefaultId == null ? Icon(Icons.check, color: primaryColor) : null,
                onTap: () async {
                  if (isIncome) {
                    await ref.read(defaultAccountSetterProvider).setDefaultIncomeAccountId(null);
                    ref.invalidate(defaultIncomeAccountIdProvider);
                  } else {
                    await ref.read(defaultAccountSetterProvider).setDefaultExpenseAccountId(null);
                    ref.invalidate(defaultExpenseAccountIdProvider);
                  }
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              ...accounts.map((account) {
                final isSelected = account.id == currentDefaultId;
                return ListTile(
                  dense: true,
                  leading: AccountTypeIcon(
                    type: account.type,
                    size: 24,
                  ),
                  title: Text(
                    account.name,
                    style: TextStyle(
                      color: isSelected ? primaryColor : BeeTokens.textPrimary(context),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected ? Icon(Icons.check, color: primaryColor) : null,
                  onTap: () async {
                    if (isIncome) {
                      await ref.read(defaultAccountSetterProvider).setDefaultIncomeAccountId(account.id);
                      ref.invalidate(defaultIncomeAccountIdProvider);
                    } else {
                      await ref.read(defaultAccountSetterProvider).setDefaultExpenseAccountId(account.id);
                      ref.invalidate(defaultExpenseAccountIdProvider);
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

/// 资产管理页 header 右上角的「蜜蜂家当」入口。
///
/// 用 Material 标准的 Premium / 进阶版图标(`workspace_premium_outlined`),
/// 跟 setting / add 等 outlined 图标视觉重量完全一致;语义上暗示「升级 /
/// 进阶版本」,鼓励点击。颜色自适应 header 背景。点击进入介绍弹窗。
class _BeeAssetsHeaderEntry extends StatelessWidget {
  const _BeeAssetsHeaderEntry();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final info = beeAssetsPromo(context);
    final texts = buildPromoTexts(context, l10n.aboutBeeAssets);

    return IconButton(
      onPressed: () => ProductPromoLauncher.open(context, info, texts),
      tooltip: info.title,
      icon: const Icon(Icons.auto_awesome_outlined),
    );
  }
}

