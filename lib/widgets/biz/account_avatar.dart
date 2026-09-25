import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../services/custom_icon_service.dart';
import '../../utils/account_type_utils.dart';

/// 帳戶頭像圖片。avatarPath 是 custom_icons/ 下的相對路徑(帳戶頭像正常
/// 狀態一定是已落盤的相對路徑——臨時絕對路徑只在編輯頁存檔前那一刻存在),
/// 用 CustomIconService 解回絕對路徑顯示;解析失敗/檔案被清過快取就退回
/// [fallback](類型圖標)。資產頁、帳戶選擇器、統計報表共用。
class AccountAvatarImage extends StatelessWidget {
  final String avatarPath;
  final double size;
  final Widget fallback;

  const AccountAvatarImage({
    super.key,
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

/// 圓形帳戶頭像:有自訂頭像(例如銀行 logo)就顯示圖片,沒有就顯示帳戶類型
/// 圖標。樣式同資產頁/帳戶選擇器:類型色淡底 + 細框。
class AccountAvatar extends StatelessWidget {
  final Account account;
  final double size;

  /// 類型色的基準(`getColorForAccountType` 的 primaryColor)。
  final Color primaryColor;

  const AccountAvatar({
    super.key,
    required this.account,
    required this.primaryColor,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    final typeColor = getColorForAccountType(account.type, primaryColor);
    final typeIcon =
        AccountTypeIcon(type: account.type, size: size / 2, color: typeColor);
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
              child: AccountAvatarImage(
                avatarPath: account.avatarPath!,
                size: size,
                fallback: typeIcon,
              ),
            )
          : Center(child: typeIcon),
    );
  }
}
