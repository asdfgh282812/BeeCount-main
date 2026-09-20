import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/charts/overview_combo_chart.dart';
import '../../widgets/ui/ui.dart';

/// 資產管理頁「走勢」互動組合圖的全螢幕放大版：內容就是同一顆
/// [OverviewComboChart],資料來源／區間切換／拖曳互動邏輯與內嵌卡片版完全
/// 共用,不重複開發。只能從資產管理頁頭部「展開」圖示進入(內嵌卡片本身點擊
/// /拖曳是直接選點,不會跳頁,見 accounts_page.dart 的
/// `_buildNetWorthChartInline`)。
///
/// 強制橫向:長條+折線組合圖需要較寬的畫布才看得清楚,直向手機螢幕太窄。
/// 進頁鎖定橫向、離開時恢復自由旋轉,不影響 App 其它頁面(其它頁面都是直向
/// 設計,沒有另外鎖過方向)。
class AccountOverviewChartPage extends ConsumerStatefulWidget {
  const AccountOverviewChartPage({super.key});

  @override
  ConsumerState<AccountOverviewChartPage> createState() =>
      _AccountOverviewChartPageState();
}

class _AccountOverviewChartPageState
    extends ConsumerState<AccountOverviewChartPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.accountOverviewChartPageTitle,
            showBack: true,
            compact: true,
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(16.0.scaled(context, ref)),
              child: const OverviewComboChart(),
            ),
          ),
        ],
      ),
    );
  }
}
