import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:beecount/widgets/biz/bee_icon.dart';

import '../../providers.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../styles/tokens.dart';
import '../../services/system/logger_service.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/ui_scale_extensions.dart';
import 'log_center_page.dart';

const _feedbackEmail = 'andy91011000@gmail.com';

/// 关于页面
class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  String _versionDisplay = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await _getAppInfo();
    final versionText = info.version.startsWith('dev-')
        ? '${info.version} (${info.buildNumber})'
        : info.version;
    setState(() {
      _versionDisplay = versionText;
    });
  }

  void _showDeveloperStory(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.aboutDeveloperStoryTitle),
        content: SingleChildScrollView(
          child: Text(
            l10n.aboutDeveloperStory,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: BeeTokens.textSecondary(context),
                  height: 1.7,
                ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primary = ref.watch(primaryColorProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.aboutPageTitle,
            subtitle: l10n.aboutPageSubtitle,
            showBack: true,
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16.0.scaled(context, ref),
                  8.0.scaled(context, ref),
                  16.0.scaled(context, ref),
                  16.0.scaled(context, ref),
                ),
                children: [
                  // ===== 顶部:图标 + 应用名 + 版本号(与原版一致)=====
                  Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: 24.0.scaled(context, ref),
                    ),
                    child: Column(
                      children: [
                        BeeIcon(
                          color: primary,
                          size: 80.0.scaled(context, ref),
                        ),
                        SizedBox(height: 16.0.scaled(context, ref)),
                        GestureDetector(
                          onTap: () => _showDeveloperStory(context),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l10n.appName,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: BeeTokens.textPrimary(context),
                                    ),
                              ),
                              SizedBox(width: 4.0.scaled(context, ref)),
                              Icon(
                                Icons.auto_stories_outlined,
                                size: 18.0.scaled(context, ref),
                                color: BeeTokens.textTertiary(context),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 8.0.scaled(context, ref)),
                        Text(
                          _versionDisplay.isEmpty
                              ? l10n.aboutPageLoadingVersion
                              : _versionDisplay,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: BeeTokens.textSecondary(context),
                                  ),
                        ),
                      ],
                    ),
                  ),
                  // ===== 圆形图标按钮行(真实品牌 logo)=====
                  Padding(
                    padding: EdgeInsets.only(bottom: 20.0.scaled(context, ref)),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 22.0.scaled(context, ref),
                      runSpacing: 14.0.scaled(context, ref),
                      children: [
                        _socialButton(
                          context,
                          svgAsset: 'assets/icons/social/github.svg',
                          label: 'GitHub',
                          onTap: () => _tryOpenUrl(Uri.parse(
                              'https://github.com/asdfgh282812/BeeCount-main')),
                        ),
                      ],
                    ),
                  ),
                  // ===== 功能卡 =====
                  SectionCard(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        AppListTile(
                          leading: Icons.feedback_outlined,
                          title: l10n.mineFeedback,
                          subtitle: l10n.mineFeedbackSubtitle,
                          onTap: () => _tryOpenUrl(
                              Uri(scheme: 'mailto', path: _feedbackEmail)),
                        ),
                        BeeTokens.cardDivider(context),
                        AppListTile(
                          leading: Icons.bug_report_outlined,
                          title: l10n.logCenterTitle,
                          subtitle: l10n.logCenterSubtitle,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LogCenterPage(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 8.0.scaled(context, ref)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 圆形图标社媒按钮 — 传 [svgAsset](品牌 logo)或 [icon](通用图标)之一。
  /// 图标统一用主题色(logo 形状本身已能辨识平台),和 app 整体视觉呼应。
  Widget _socialButton(
    BuildContext context, {
    String? svgAsset,
    IconData? icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final tint = ref.watch(primaryColorProvider);
    final size = 46.0.scaled(context, ref);
    final glyph = 22.0.scaled(context, ref);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: svgAsset != null
                ? SvgPicture.asset(
                    svgAsset,
                    width: glyph,
                    height: glyph,
                    colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
                  )
                : Icon(icon, color: tint, size: glyph),
          ),
          SizedBox(height: 6.0.scaled(context, ref)),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5.scaled(context, ref),
              color: BeeTokens.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }
}

// -------- 工具方法：关于与更新 --------
class _AppInfo {
  final String version;
  final String buildNumber;
  final String? commit;
  final String? buildTime;
  const _AppInfo(this.version, this.buildNumber, {this.commit, this.buildTime});
}

// 优先读取 CI 注入的 dart-define（CI_VERSION/GIT_COMMIT/BUILD_TIME），否则回退 PackageInfo
Future<_AppInfo> _getAppInfo() async {
  final p = await PackageInfo.fromPlatform();
  final commit = const String.fromEnvironment('GIT_COMMIT');
  final buildTime = const String.fromEnvironment('BUILD_TIME');
  final ciVersion = const String.fromEnvironment('CI_VERSION');

  // 版本号策略：CI版本优先，本地开发显示 "dev-{pubspec版本}"
  final version =
      ciVersion.isNotEmpty ? ciVersion : 'dev-${p.version}'; // 本地开发版本标识

  return _AppInfo(version, p.buildNumber,
      commit: commit.isEmpty ? null : commit,
      buildTime: buildTime.isEmpty ? null : buildTime);
}

/// 尝试使用多种方式打开URL，提供更好的兼容性
///
/// 直接依次尝试 launchUrl 而非先 canLaunchUrl 判断:mailto: 在 Android 上
/// canLaunchUrl 经常误报 false(package visibility 限制),但 launchUrl 实际能跳转。
Future<bool> _tryOpenUrl(Uri url) async {
  const modes = [
    LaunchMode.externalApplication,
    LaunchMode.externalNonBrowserApplication,
    LaunchMode.platformDefault,
  ];
  for (final mode in modes) {
    try {
      if (await launchUrl(url, mode: mode)) return true;
    } catch (e) {
      logger.warning('AboutPage', 'launchUrl mode=$mode 失败,继续: $e');
    }
  }
  logger.error('AboutPage', '无法打开URL: $url');
  return false;
}
