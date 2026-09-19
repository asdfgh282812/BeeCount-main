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
  '多少', '幾多', '几多', '幾筆', '几笔', '幾次', '几次', '幾張', '几张',
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

/// 三層閘門的最終結果:true = 走本地記帳快路徑,false = 交給 [FreeChatRouter]。
bool isTransactionIntent(String input) {
  // Layer 0:查詢否決優先於一切。
  if (isQueryIntent(input)) return false;
  // Layer 1:必須同時有金額與記帳動詞(舊版是 OR,這是本次修正的核心)。
  return hasAmountToken(input) && hasBookkeepingVerb(input);
}
