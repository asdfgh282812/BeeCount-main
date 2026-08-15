import 'package:decimal/decimal.dart';

/// 用 Decimal 精确运算(避免浮点漂移,如 0.1+0.2),左到右无运算符优先级,
/// 除零保护;结果四舍五入到最多两位小数(金额精度)。
double computeAmountOp(double a, String op, double b) {
  final da = Decimal.parse(a.toStringAsFixed(2));
  final db = Decimal.parse(b.toStringAsFixed(2));
  final Decimal r;
  switch (op) {
    case '+':
      r = da + db;
      break;
    case '-':
      r = da - db;
      break;
    case '×':
      r = da * db;
      break;
    case '÷':
      if (db == Decimal.zero) return a; // 除零保护:保持被除数不变
      r = (da.toRational() / db.toRational())
          .toDecimal(scaleOnInfinitePrecision: 12);
      break;
    default:
      return b;
  }
  return r.round(scale: 2).toDouble();
}

/// 运算符显示字形(减号用真减号 −,而非连字符 -)。
String amountOpGlyph(String op) {
  switch (op) {
    case '-':
      return '−';
    case '×':
      return '×';
    case '÷':
      return '÷';
    default:
      return '+';
  }
}
