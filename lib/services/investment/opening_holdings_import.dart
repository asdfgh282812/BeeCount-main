import '../../models/investment_settings.dart';

/// 批次期初持股(docs/changes/2026-09-30-dca-sync-opening-holdings.md)。
///
/// 開始記帳前就持有的股票不用逐筆補記過去的買進:照券商「庫存」頁每一檔填
/// 股數 + 平均成本(或總成本)一筆期初持股就好,持股成本/未實現損益完全一樣,
/// 差別只有看不到記帳前的個別買進日期跟已實現損益。對齊 Web
/// `lib/investment.ts::parseOpeningHoldingsText` / `openingTradeFromCost`,
/// 兩邊測試用同一組字串。

/// 貼上的一行解析結果。[cost] 依使用者選的模式是平均成本或總成本。
class OpeningHoldingLine {
  final String symbol;
  final String? name;
  final double shares;
  final double cost;

  const OpeningHoldingLine({
    required this.symbol,
    this.name,
    required this.shares,
    required this.cost,
  });
}

class OpeningHoldingsParseResult {
  final List<OpeningHoldingLine> lines;

  /// 有內容但解析不出「代號 + 股數 + 成本」的行數(標題列、備註等)。
  final int skipped;

  const OpeningHoldingsParseResult(this.lines, this.skipped);
}

final RegExp _symbolPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9.\-]*$');

/// 數字欄位:去掉千分位、貨幣符號、「股」「元」這類單位。
double? _parseNumber(String token) {
  final cleaned = token
      .replaceAll(RegExp(r'[,，\s]'), '')
      .replaceAll(RegExp(r'^(NT\$|US\$|HK\$|\$|¥|￥)'), '')
      .replaceAll(RegExp(r'(股|元|TWD|USD)$', caseSensitive: false), '');
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(cleaned)) return null;
  return double.tryParse(cleaned);
}

List<String> _splitLine(String line) {
  // Excel / Google 試算表複製出來是 tab 分隔,數字可能帶千分位,所以有 tab
  // 就只用 tab 切;空白切得出 3 欄以上(`0050 1,000 120.5`)用空白,逗號只當
  // 千分位/欄尾;否則當 CSV(`2330,台積電,50,580`)。
  if (line.contains('\t')) return line.split('\t');
  final bySpace = line
      .split(RegExp(r'\s+'))
      .map((t) => t.replaceAll(RegExp(r'^[,，]+|[,，]+$'), ''))
      .where((t) => t.isNotEmpty)
      .toList();
  if (bySpace.length >= 3) return bySpace;
  return line.split(RegExp(r'[,，]'));
}

/// 一行一檔:「代號 股數 成本」,可夾名稱,例如
/// `0050	1,000	120.5`、`2330,台積電,50,580`、`VOO 3.5 412.3`。
/// 代號 = 第一個看起來像代號(英數字)的欄位,它後面的前兩個數字依序是
/// 股數、成本;其它非數字欄位當名稱。
OpeningHoldingsParseResult parseOpeningHoldingsText(String text) {
  final lines = <OpeningHoldingLine>[];
  var skipped = 0;
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final tokens = _splitLine(line)
        .map((t) => t.trim().replaceAll(RegExp(r'^"|"$'), '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
    String? symbol;
    final names = <String>[];
    final numbers = <double>[];
    for (final t in tokens) {
      if (symbol == null) {
        if (_symbolPattern.hasMatch(t)) {
          symbol = t.toUpperCase();
        } else if (_parseNumber(t) == null) {
          names.add(t);
        }
        continue;
      }
      final n = _parseNumber(t);
      if (n != null) {
        numbers.add(n);
      } else {
        names.add(t);
      }
    }
    if (symbol == null ||
        numbers.length < 2 ||
        numbers[0] <= 0 ||
        numbers[1] <= 0) {
      skipped++;
      continue;
    }
    lines.add(OpeningHoldingLine(
      symbol: symbol,
      name: names.isEmpty ? null : names.join(' '),
      shares: numbers[0],
      cost: numbers[1],
    ));
  }
  return OpeningHoldingsParseResult(lines, skipped);
}

/// 期初持股要存成的(成交價, 手續費)。
///
/// - 平均成本模式:價格 = 平均成本,手續費 0(券商庫存的成本均價通常已含
///   手續費)。
/// - 總成本模式:價格 = 總成本 ÷ 股數(4 位小數),差額(台幣價金無條件捨去
///   造成的零頭)放手續費,讓存下來的成本剛好等於輸入的總成本。
({double price, double fee}) openingTradeFromCost({
  required double shares,
  required double cost,
  required bool costIsTotal,
  required String? currency,
}) {
  if (!costIsTotal || shares <= 0) return (price: cost, fee: 0);
  final price = double.parse((cost / shares).toStringAsFixed(4));
  final gross = InvestmentSettings.gross(shares, price, currency);
  final fee = InvestmentSettings.roundMoney(cost - gross, currency);
  return (price: price, fee: fee > 0 ? fee : 0);
}

/// 這一行存下去的總成本(顯示用)。
double openingTotalCost({
  required double shares,
  required double cost,
  required bool costIsTotal,
  required String? currency,
}) {
  final t = openingTradeFromCost(
      shares: shares, cost: cost, costIsTotal: costIsTotal, currency: currency);
  return InvestmentSettings.gross(shares, t.price, currency) + t.fee;
}
