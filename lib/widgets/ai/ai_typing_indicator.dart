import 'package:flutter/material.dart';

/// AI 思考中的三點脈動動畫(取代原本的轉圈圈),樣式與 AI 氣泡一致。
class AiTypingIndicator extends StatefulWidget {
  final Color color;
  final double dotSize;

  const AiTypingIndicator({
    super.key,
    required this.color,
    this.dotSize = 7,
  });

  @override
  State<AiTypingIndicator> createState() => _AiTypingIndicatorState();
}

class _AiTypingIndicatorState extends State<AiTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // 三顆點錯開 0.2 個週期,形成波浪
            final t = (_controller.value - i * 0.2) % 1.0;
            final wave = t < 0.5 ? t * 2 : (1 - t) * 2; // 0→1→0
            final eased = Curves.easeInOut.transform(wave);
            return Container(
              width: widget.dotSize,
              height: widget.dotSize,
              margin: EdgeInsets.symmetric(horizontal: widget.dotSize * 0.3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withOpacity(0.35 + 0.65 * eased),
              ),
              transform: Matrix4.translationValues(
                0,
                -widget.dotSize * 0.6 * eased,
                0,
              ),
            );
          }),
        );
      },
    );
  }
}
