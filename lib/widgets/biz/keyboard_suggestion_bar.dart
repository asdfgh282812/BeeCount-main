import 'package:flutter/material.dart';

import '../../styles/tokens.dart';

/// 貼在系統鍵盤正上方的建議 chip 列(比照 moze 的設計)——用來取代舊版
/// 「點時鐘圖示彈出視窗」的歷史備註/歷史商家選擇方式。呼叫端只要把這個
/// widget 當作 `Column` 裡系統鍵盤前的最後一個子元件(欄位聚焦、鍵盤打開時
/// 才 render),就會自然貼齊鍵盤上緣,不需要另外用 `Stack`/`MediaQuery`
/// 手動算位置。不顯示使用次數數字——單純的候選字列表。
class KeyboardSuggestionBar extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onSelected;

  const KeyboardSuggestionBar({
    super.key,
    required this.suggestions,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          return InkWell(
            onTap: () => onSelected(suggestion),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: BeeTokens.surfaceChip(context),
                borderRadius: BorderRadius.circular(16),
                border: BeeTokens.isDark(context)
                    ? Border.all(color: BeeTokens.border(context))
                    : null,
              ),
              child: Text(
                suggestion,
                style: TextStyle(
                  fontSize: 13,
                  color: BeeTokens.textSecondary(context),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
