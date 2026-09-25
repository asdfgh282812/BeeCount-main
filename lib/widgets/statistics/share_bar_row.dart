import 'package:flutter/material.dart';

import '../../styles/tokens.dart';
import '../biz/amount_text.dart';

/// 統計報表維度分頁(帳戶/專案/商家…)的一列:圖示 + 名稱 + 金額 + 佔比條。
/// 樣式比照 `CategoryRankRow`,但不綁分類模型。
///
/// [leading] 為 null 時不顯示圖標(名稱/商家這類純文字維度);
/// [wrapLeading] = false 表示 [leading] 自己已經是完整頭像(例如帳戶 logo),
/// 不再套一層色底圓框。
class ShareBarRow extends StatelessWidget {
  final Widget? leading;
  final bool wrapLeading;
  final String title;
  final String? subtitle;
  final double amount;

  /// 0..1。
  final double percent;
  final Color color;

  /// 金額文字顏色(收入/支出色,見 `report_colors.dart`);null = 預設字色。
  final Color? amountColor;
  final VoidCallback? onTap;

  const ShareBarRow({
    super.key,
    this.leading,
    this.wrapLeading = true,
    required this.title,
    this.subtitle,
    required this.amount,
    required this.percent,
    required this.color,
    this.amountColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            if (leading != null) ...[
              if (wrapLeading)
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(child: leading),
                )
              else
                SizedBox(width: 40, height: 40, child: Center(child: leading)),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AmountText(
                        value: amount,
                        signed: false,
                        decimals: 0,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: amountColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${(percent * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontSize: 12,
                            color: BeeTokens.textTertiary(context)),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color: BeeTokens.textTertiary(context)),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        Container(
                            height: 6, color: color.withValues(alpha: 0.15)),
                        FractionallySizedBox(
                          widthFactor: percent.clamp(0, 1).toDouble(),
                          child: Container(
                              height: 6, color: color.withValues(alpha: 0.9)),
                        ),
                      ],
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
}
