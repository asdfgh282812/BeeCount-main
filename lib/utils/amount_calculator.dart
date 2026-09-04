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

/// 支出/收入手續費/折扣淨額公式(對齐 BeeCount Cloud
/// `_compute_fee_discount_amount`,`routers/write/_shared.py`——App/Cloud
/// 兩邊要用同一份公式,不要各自發明):
///   expense: amount = baseAmount + feeAmount − discountAmount
///   income:  amount = baseAmount − feeAmount + discountAmount
/// `type` 只接受 `'expense'`/`'income'`(轉帳的手續費/折損是疊加在餘額計算
/// 上的獨立 delta,不套這條公式,見 `LocalAccountRepository`
/// `_transferOutEffect`/`_transferInEffect`)。結果四捨五入到兩位小數,不額外
/// 擋淨額變負數——比照 Cloud,折扣金額大於本金+手續費時 amount 就是會變負值。
double computeFeeDiscountNetAmount({
  required String type,
  required double baseAmount,
  required double feeAmount,
  required double discountAmount,
}) {
  assert(type == 'expense' || type == 'income');
  final base = Decimal.parse(baseAmount.toStringAsFixed(2));
  final fee = Decimal.parse(feeAmount.toStringAsFixed(2));
  final discount = Decimal.parse(discountAmount.toStringAsFixed(2));
  final r = type == 'expense' ? base + fee - discount : base - fee + discount;
  return r.round(scale: 2).toDouble();
}

/// [computeFeeDiscountNetAmount] 的反函数:已知淨額 `amount`(必然正確,
/// 任何時候都會被寫入/同步)跟 `feeAmount`/`discountAmount`,反推
/// `baseAmount`。
///
/// 用途:sync pull 自愈(见 `lib/cloud/sync/sync_engine_apply.dart`
/// `_applyTransactionChange` 的 v51 段落)——某些歷史 SyncChange 的 payload
/// 只帶了 feeAmount/discountAmount 卻漏了 baseAmount 鍵,「缺鍵不覆蓋」語意
/// 下 baseAmount 會永遠停留在 null,使用者只能一筆一筆手動觸發重新同步才
/// 能補回來。改用這裡反推,不依賴對端把 baseAmount 鍵送齊。
double computeBaseAmountFromNet({
  required String type,
  required double amount,
  required double feeAmount,
  required double discountAmount,
}) {
  assert(type == 'expense' || type == 'income');
  final a = Decimal.parse(amount.toStringAsFixed(2));
  final fee = Decimal.parse(feeAmount.toStringAsFixed(2));
  final discount = Decimal.parse(discountAmount.toStringAsFixed(2));
  final r = type == 'expense' ? a - fee + discount : a + fee - discount;
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
