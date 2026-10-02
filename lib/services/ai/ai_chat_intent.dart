/// 對話輸入的意圖判定(純函式,無任何 I/O,方便單測)。
///
/// 三層閘門,依序判斷:
///
/// - **Layer 0 查詢否決**:命中查詢標記就直接走自由對話,不管句子裡有沒有金額、
///   有沒有記帳動詞。這一層是本模組存在的理由 —— 舊版 `_isTransactionIntent` 用
///   `hasAmount || hasKeyword`,而關鍵字表裡的「花 / 付 / 收入」正好是中文查詢句
///   的主要動詞,導致「我復健科至今為止花了多少錢」被判成記帳意圖,提取不到金額
///   就回一段固定的記帳教學,**完全沒機會走到查詢工具**。
/// - **Layer 1 記帳快路徑**:`hasAmount && hasVerb`(注意是 AND)。命中就走本地
///   提取流程,LLM 往返次數與舊版相同,記帳延遲不退化。
/// - **Layer 2**:其餘全部交給 `FreeChatRouter`,由 routing 模型自己判斷。
///
/// 誤判的代價是**不對稱**的:誤判成記帳 → 使用者收到固定文案,完全碰不到查詢工具;
/// 誤判成查詢 → router 還有 `record_transaction` 決策可以救回來。所以閘門刻意偏向
/// 放行查詢。
library;

/// Layer 0:只要出現這些片語,一律視為查詢。
///
/// 刻意**不收**單字「查」「幾」「哪」—— 它們會出現在正常的記帳句裡
/// (健康檢**查**花了2000 / 花了**幾**百塊),誤攔的代價比漏攔高。需要這些語意時
/// 一律用更長的片語(查詢 / 查一下 / 哪些)。
const List<String> kQueryVetoKeywords = [
  // 數量/金額詢問
  '多少', '幾多', '几多', '幾筆', '几笔', '幾次', '几次', '幾張', '几张', '幾股', '几股',
  // 查詢動作
  '查詢', '查询', '查一下', '查查', '查看', '查帳', '查账', '看一下',
  '列出', '告訴我', '告诉我', '幫我看', '帮我看', '明細', '明细', '清單', '清单',
  // 統計/彙總
  '統計', '统计', '總共', '总共', '一共', '合計', '合计', '累計', '累计',
  '總額', '总额', '總計', '总计', '平均', '佔比', '占比', '排行', '排名', '排序',
  '分析', '比較', '比较', '對比', '对比', '最多', '最少',
  // 餘額/預算/趨勢
  '剩下', '還剩', '还剩', '剩餘', '剩余', '預算', '预算', '趨勢', '趋势',
  // 疑問句式
  '有沒有', '有没有', '是不是', '什麼', '什么', '怎麼', '怎么', '為什麼', '为什么',
  '哪些', '哪個', '哪个', '哪類', '哪类', '哪天',
  // 全期間語意(「至今為止」這類問法本身就是查詢)
  '至今', '到現在', '到现在', '一直以來', '一直以来', '以來', '以来',
];

/// Layer 0:單字元疑問標記。這些字不會出現在陳述式的記帳句裡,單獨收是安全的。
const List<String> kQueryVetoChars = ['嗎', '吗', '呢', '?', '？'];

/// Layer 0:英文查詢片語(比對前會先轉小寫)。
const List<String> kQueryVetoEnglish = [
  'how much',
  'how many',
  'how often',
  'total',
  'list ',
  'show me',
  'what ',
  'which ',
  'why ',
  'when did',
  'compare',
  'summar',
  'average',
  'breakdown',
  'so far',
  'overall',
  'all time',
  'this month i spent',
];

/// Layer 1:記帳動詞。
///
/// 舊版只有簡體(`买/花/消费/支付/记账/付/收入/赚/工资`),繁中使用者的
/// 「買/記帳/賺/工資」反而不匹配 —— 真正在觸發的只有「花/付/收入」這幾個簡繁同形
/// 的字,而那三個恰好又是查詢動詞。這裡補齊繁體與英文。
const List<String> kBookkeepingVerbs = [
  // 支出
  '買', '买', '花', '消費', '消费', '支付', '付款', '付', '刷卡', '買單', '买单',
  '繳', '缴', '儲值', '储值', '加值', '充值', '報帳', '报帐', '報銷', '报销',
  '吃', '喝', '搭', '坐', '加油', '訂', '订',
  // 收入
  '收入', '賺', '赚', '工資', '工资', '薪水', '薪資', '薪资', '獎金', '奖金',
  '收到', '領到', '领到', '退款',
  // 記帳動作本身
  '記帳', '记账', '記賬', '记帐', '記一筆', '记一笔',
];

/// Layer 1:英文記帳動詞(比對前會先轉小寫)。
const List<String> kBookkeepingVerbsEnglish = [
  'bought',
  'buy',
  'spent',
  'spend',
  'paid',
  'pay ',
  'cost',
  'salary',
  'income',
  'earned',
  'received',
  'refund',
];

final RegExp _amountPattern = RegExp(r'\d+(?:\.\d+)?');

/// 句子裡是否出現阿拉伯數字金額。
bool hasAmountToken(String input) => _amountPattern.hasMatch(input);

/// Layer 0:是否命中查詢標記。
bool isQueryIntent(String input) {
  final lower = input.toLowerCase();
  for (final k in kQueryVetoKeywords) {
    if (input.contains(k)) return true;
  }
  for (final c in kQueryVetoChars) {
    if (input.contains(c)) return true;
  }
  for (final k in kQueryVetoEnglish) {
    if (lower.contains(k)) return true;
  }
  return false;
}

/// Layer 1:是否出現記帳動詞。
bool hasBookkeepingVerb(String input) {
  final lower = input.toLowerCase();
  for (final v in kBookkeepingVerbs) {
    if (input.contains(v)) return true;
  }
  for (final v in kBookkeepingVerbsEnglish) {
    if (lower.contains(v)) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// 股票(2026-10-03)
// ---------------------------------------------------------------------------

/// 含「股」字但不是股票的詞,比對股票標記前先剔除。
const List<String> _nonStockWords = [
  '股東', '股东', '股份', '股市', '股價', '股价', '股神', '一股腦', '一股脑', '股長', '股长',
];

/// 買賣動詞(股票買賣意圖用,刻意比 [kBookkeepingVerbs] 窄:只有買進/賣出語意)。
const List<String> _stockTradeVerbs = [
  '買', '买', '賣', '卖', '加碼', '加码', '減碼', '减码', '認購', '申購', '申购',
];

const List<String> _stockTradeVerbsEnglish = ['buy', 'bought', 'sell', 'sold'];

final RegExp _enShares = RegExp(r'\d+\s*shares?\b', caseSensitive: false);

/// 句子裡是否出現股票標記:「股」(剔除股東/股份/股市…)、股票、ETF、零股、
/// 英文 shares / stock。刻意**不收**「張」(買了3張電影票),「N 張」的買賣由
/// routing 模型依 prompt 規則判斷。
bool hasStockMarker(String input) {
  var cleaned = input;
  for (final w in _nonStockWords) {
    cleaned = cleaned.replaceAll(w, '');
  }
  if (cleaned.contains('股')) return true;
  final lower = input.toLowerCase();
  return lower.contains('etf') ||
      lower.contains('stock') ||
      _enShares.hasMatch(lower);
}

/// 「買了 2330 十股」「賣出 0050 100 股」這類是要**新增股票交易**的句子。
///
/// 買股票是「轉帳到投資理財帳戶 + 記股數」,不是支出記帳,走記帳快路徑會被
/// 記成一筆莫名其妙的支出,所以這種句子不進記帳、改回覆做法。查詢句
/// (「我買了幾股」「賣股賺多少」)先被 [isQueryIntent] 擋掉,走查詢工具。
bool isStockTradeIntent(String input) {
  if (isQueryIntent(input)) return false;
  if (!hasStockMarker(input)) return false;
  final lower = input.toLowerCase();
  for (final v in _stockTradeVerbs) {
    if (input.contains(v)) return true;
  }
  for (final v in _stockTradeVerbsEnglish) {
    if (RegExp('\\b$v\\b').hasMatch(lower)) return true;
  }
  return false;
}

const List<String> _adviceWords = [
  '建議', '建议', '該不該', '该不该', '要不要', '值不值得', '適合', '适合', '風險', '风险',
  '集中', '分散', '配置', '調整', '调整', '買還是賣', '买还是卖', '賣還是買', '该买', '該買',
  '該賣', '该卖', '加碼', '加码', '減碼', '减码', '停損', '停损', '停利', '看好', '推薦', '推荐',
  '怎麼辦', '怎么办',
];

const List<String> _adviceWordsEnglish = [
  'advice', 'advise', 'should i', 'recommend', 'risk', 'diversif', 'allocation',
  'rebalanc', 'worth buying', 'worth selling',
];

const List<String> _investTerms = [
  '投資', '投资', '持股', '股票', '基金', 'portfolio', 'holdings', 'invest',
];

/// 使用者是不是在問投資建議/風險類問題(要附免責聲明)。要求「股票/投資詞」與
/// 「建議/風險詞」同時出現,避免一般記帳問答被誤加。
bool isStockAdviceQuestion(String input) {
  final lower = input.toLowerCase();
  final stockish = hasStockMarker(input) ||
      _investTerms.any((t) => input.contains(t) || lower.contains(t));
  if (!stockish) return false;
  return _adviceWords.any(input.contains) ||
      _adviceWordsEnglish.any(lower.contains);
}

/// 三層閘門的最終結果:true = 走本地記帳快路徑,false = 交給 [FreeChatRouter]。
bool isTransactionIntent(String input) {
  // Layer 0:查詢否決優先於一切。
  if (isQueryIntent(input)) return false;
  // 買賣股票不是支出記帳(是轉帳到投資理財帳戶),不進記帳快路徑。
  if (isStockTradeIntent(input)) return false;
  // Layer 1:必須同時有金額與記帳動詞(舊版是 OR,這是本次修正的核心)。
  return hasAmountToken(input) && hasBookkeepingVerb(input);
}
