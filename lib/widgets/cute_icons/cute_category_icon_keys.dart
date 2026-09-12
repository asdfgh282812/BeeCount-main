import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// `category.icon` keys that currently have a bundled original SVG under
/// `assets/icons/categories_cute/`. Keep this in sync BY HAND
/// whenever an asset is added or removed — `CategoryIconWidget` checks
/// membership here before attempting to load the file, so a missing asset
/// never throws at runtime; it just falls back to the Material icon.
const Set<String> kCuteCategoryIconKeys = {
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
};

/// Renders the bundled SVG for [iconKey], tinting its `currentColor` line
/// art with [lineColor] (pass `BeeTokens.iconCategory(context)` — the same
/// theme-aware ink token the rest of the app's category icons use). Each
/// icon's own baked accent shape is a literal hex color in the SVG file
/// itself and is unaffected by [lineColor].
///
/// Callers should go through [maybeBuild] rather than constructing this
/// directly, so a key with no asset falls back cleanly to the Material icon.
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

  /// Returns null when [iconKey] has no bundled asset, so the caller can
  /// fall back to its own Material icon rendering.
  static Widget? maybeBuild({
    required String? iconKey,
    required double size,
    required Color lineColor,
  }) {
    if (iconKey == null || !kCuteCategoryIconKeys.contains(iconKey))
      return null;
    return CuteCategoryIcon(iconKey: iconKey, size: size, lineColor: lineColor);
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
