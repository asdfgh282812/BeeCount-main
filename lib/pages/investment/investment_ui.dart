import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/theme_providers.dart';
import '../../services/investment/stock_trade_types.dart';
import '../../styles/tokens.dart';
import '../../utils/currencies.dart';

/// 股票持股 UI 共用的小工具(市場/交易類型文字、股數與金額格式、損益顏色)。

String stockMarketLabel(AppLocalizations l10n, String code) {
  switch (code.toUpperCase()) {
    case 'TW':
      return l10n.stockMarketTW;
    case 'TWO':
      return l10n.stockMarketTWO;
    case 'US':
      return l10n.stockMarketUS;
    case 'HK':
      return l10n.stockMarketHK;
    case 'JP':
      return l10n.stockMarketJP;
    case 'SS':
      return l10n.stockMarketSS;
    case 'SZ':
      return l10n.stockMarketSZ;
    case 'KS':
      return l10n.stockMarketKS;
    case 'KQ':
      return l10n.stockMarketKQ;
    case 'LSE':
      return l10n.stockMarketLSE;
    default:
      return code;
  }
}

String stockTradeTypeLabel(AppLocalizations l10n, String type) {
  switch (type) {
    case kStockTradeBuy:
      return l10n.stockTradeTypeBuy;
    case kStockTradeSell:
      return l10n.stockTradeTypeSell;
    case kStockTradeOpening:
      return l10n.stockTradeTypeOpening;
    case kStockTradeStockDividend:
      return l10n.stockTradeTypeStockDividend;
    case kStockTradeSplit:
      return l10n.stockTradeTypeSplit;
    case kStockTradeCashDividend:
      return l10n.stockTradeTypeCashDividend;
    case kStockTradeReinvest:
      return l10n.stockTradeTypeReinvest;
    default:
      return type;
  }
}

/// 股數:整數不帶小數,零碎股最多 4 位小數。
String formatShares(double shares) {
  if ((shares - shares.roundToDouble()).abs() < 1e-9) {
    return _groupDigits(shares.round().toString());
  }
  var text = shares.toStringAsFixed(4);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  final parts = text.split('.');
  return parts.length == 2
      ? '${_groupDigits(parts[0])}.${parts[1]}'
      : _groupDigits(parts[0]);
}

String _groupDigits(String digits) {
  final negative = digits.startsWith('-');
  final body = negative ? digits.substring(1) : digits;
  final buf = StringBuffer();
  for (var i = 0; i < body.length; i++) {
    if (i > 0 && (body.length - i) % 3 == 0) buf.write(',');
    buf.write(body[i]);
  }
  return negative ? '-$buf' : buf.toString();
}

/// 價格:最多 4 位小數、至少 2 位(台股 2475.00、美股 341.07、低價股 0.1234)。
String formatPrice(double price) {
  final parts = price.toStringAsFixed(4).split('.');
  var frac = parts.length > 1 ? parts[1].replaceFirst(RegExp(r'0+$'), '') : '';
  if (frac.length < 2) frac = frac.padRight(2, '0');
  return '${_groupDigits(parts[0])}.$frac';
}

/// 金額:依幣別小數位(TWD/JPY/KRW 0 位,其它 2 位),帶幣別符號。
String formatStockMoney(double value, String? currency, {bool signed = false}) {
  final code = (currency ?? '').toUpperCase();
  final decimals = (code == 'TWD' || code == 'JPY' || code == 'KRW') ? 0 : 2;
  final abs = value.abs();
  final fixed = abs.toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final body = parts.length == 2
      ? '${_groupDigits(parts[0])}.${parts[1]}'
      : _groupDigits(parts[0]);
  final symbol = code.isEmpty ? '' : getCurrencySymbol(code);
  final sign = value < 0 ? '-' : (signed && value > 0 ? '+' : '');
  return '$sign$symbol$body';
}

String formatPercent(double value, {bool signed = true}) {
  final sign = signed && value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(2)}%';
}

/// 損益顏色:依「股票漲跌顏色」設定(預設紅漲綠跌,台股慣例),
/// 與收支配色互相獨立,可在外觀設定切換並與 Web 同步。
Color pnlColor(BuildContext context, WidgetRef ref, double? value) {
  if (value == null || value.abs() < 1e-9)
    return BeeTokens.textSecondary(context);
  final upIsRed = ref.watch(stockUpIsRedProvider);
  final up = upIsRed ? BeeTokens.error(context) : BeeTokens.success(context);
  final down = upIsRed ? BeeTokens.success(context) : BeeTokens.error(context);
  return value > 0 ? up : down;
}

String formatQuoteTime(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.month}/${l.day} ${two(l.hour)}:${two(l.minute)}';
}

String formatTradeDate(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}

/// 報價 session 文字。
String quoteSessionLabel(AppLocalizations l10n, String? session) {
  switch (session) {
    case 'close':
      return l10n.stockQuoteClose;
    case 'manual':
      return l10n.stockQuoteManual;
    default:
      return l10n.stockQuoteIntraday;
  }
}
