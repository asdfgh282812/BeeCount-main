import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// `category.icon` keys that currently have a bundled original SVG under
/// `assets/icons/categories_cute/`. Keep this in sync BY HAND
/// whenever an asset is added or removed — `CuteCategoryIcon.maybeBuild`
/// checks membership here before deciding whether to load `<key>.svg` or
/// the generic `_fallback.svg`, so a missing asset never throws at runtime.
///
/// 2026-09-12: expanded from the original 18 to cover every icon key used by
/// a *default* seed category (`SeedService.getDefaultIcon`, 127 distinct
/// values, 2 of which already overlapped the original 18) — 使用者反饋:cute
/// 模式下不該再看到任何 Material 圖示,連沒對應素材的分類也要顯示手繪風,見
/// `_fallbackAssetKey` 那個通用 fallback 圖示。
const Set<String> kCuteCategoryIconKeys = {
  // 原始 18 個(第一版)
  'restaurant',
  'bakery_dining',
  'directions_bus',
  'shopping_bag',
  'shopping_cart',
  'home',
  'flash_on',
  'sports_esports',
  'local_hospital',
  'menu_book',
  'smartphone',
  'checkroom',
  'card_travel',
  'laptop',
  'pets',
  'fitness_center',
  'account_balance_wallet',
  'trending_up',
  // 2026-09-12 追加:涵盖预设分类用到的其余 111 个 icon key
  'access_time',
  'accessibility',
  'account_balance',
  'apartment',
  'apple',
  'attach_money',
  'attractions',
  'auto_awesome',
  'back_hand',
  'bed',
  'biotech',
  'blender',
  'bubble_chart',
  'build',
  'business_center',
  'cake',
  'candy',
  'card_giftcard',
  'celebration',
  'child_care',
  'chocolate',
  'circle',
  'cleaning_services',
  'cloud',
  'coffee',
  'confirmation_number',
  'construction',
  'content_cut',
  'cookie',
  'delivery_dining',
  'description',
  'devices',
  'diamond',
  'dinner_dining',
  'directions_bike',
  'directions_car',
  'directions_subway',
  'eco',
  'edit',
  'emoji_events',
  'face',
  'face_retouching_natural',
  'family_restroom',
  'fastfood',
  'favorite',
  'flight',
  'free_breakfast',
  'grain',
  'group',
  'handyman',
  'health_and_safety',
  'hiking',
  'home_repair_service',
  'home_work',
  'icecream',
  'juice',
  'kitchen',
  'liquor',
  'local_bar',
  'local_cafe',
  'local_car_wash',
  'local_gas_station',
  'local_laundry_service',
  'local_parking',
  'local_shipping',
  'local_taxi',
  'lunch_dining',
  'medical_services',
  'medication',
  'mic',
  'military_tech',
  'model_training',
  'monetization_on',
  'money_off',
  'movie',
  'music_note',
  'palette',
  'payments',
  'pet_supplies',
  'phone',
  'pie_chart',
  'play_circle',
  'ramen_dining',
  'receipt',
  'receipt_long',
  'report_problem',
  'savings',
  'schedule',
  'school',
  'security',
  'sell',
  'set_meal',
  'show_chart',
  'shower',
  'sports',
  'sports_cricket',
  'sports_martial_arts',
  'star',
  'storefront',
  'subscriptions',
  'trending_down',
  'undo',
  'volunteer_activism',
  'wallet',
  'watch',
  'water_drop',
  'weekend',
  'work',
  'work_outline',
  'workspace_premium',
  'yard',
};

/// Generic hand-drawn placeholder used for any `category.icon` key with no
/// dedicated asset (custom/uncommon categories) — 2026-09-12 使用者反饋:cute
/// 模式下不该再退回 Material 图示,一律显示手绘风(专属的没有就显示这个通用款)。
const String _fallbackAssetKey = '_fallback';

/// Renders the bundled SVG for [iconKey], tinting its `currentColor` line
/// art with [lineColor] (pass `BeeTokens.iconCategory(context)` — the same
/// theme-aware ink token the rest of the app's category icons use). Each
/// icon's own baked accent shape is a literal hex color in the SVG file
/// itself and is unaffected by [lineColor].
///
/// Callers should go through [maybeBuild] rather than constructing this
/// directly.
class CuteCategoryIcon extends StatelessWidget {
  final String iconKey;
  final double size;
  final Color lineColor;

  const CuteCategoryIcon({
    super.key,
    required this.iconKey,
    required this.size,
    required this.lineColor,
  });

  /// Always returns a widget — [iconKey] with a bundled asset renders that
  /// SVG; anything else (unregistered key, or `null`) renders the generic
  /// `_fallback.svg` instead of ever falling back to a Material icon.
  static Widget maybeBuild({
    required String? iconKey,
    required double size,
    required Color lineColor,
  }) {
    final assetKey = (iconKey != null && kCuteCategoryIconKeys.contains(iconKey))
        ? iconKey
        : _fallbackAssetKey;
    return CuteCategoryIcon(iconKey: assetKey, size: size, lineColor: lineColor);
  }

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/categories_cute/$iconKey.svg',
      width: size,
      height: size,
      fit: BoxFit.contain,
      theme: SvgTheme(currentColor: lineColor),
    );
  }
}
