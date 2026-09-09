import '../../utils/currencies.dart';
import '../../utils/currency_aliases.dart';
import 'ai_extraction_context.dart';

/// 模板占位符登记表的一项。
///
/// 存在的意义:自定义 prompt 是**整段替换**默认模板的(A7 方案 a,我们不覆盖
/// 用户模板),所以默认模板新增占位符时,老自定义模板拿不到对应能力。把占位符
/// 登记成数据,编辑页就能算出「用户模板缺哪些能力」并给出提示 —— 而不是每加
/// 一个占位符就写一遍 bespoke 检测 + bespoke 文案。
class PromptPlaceholder {
  /// 占位符本体,如 `{{CURRENCIES}}`。
  final String token;

  /// 缺失时是否值得提示用户。
  ///
  /// `false` 给**纯观感**的占位符:少了它 prompt 只是措辞怪一点,能力不受影响
  /// (`{{INPUT_SOURCE}}` 少个前缀、`{{CURRENT_DATE}}` 只出现在示例里)。
  /// 这条区分很重要 —— 把「不影响能力的差异」也报成警告,自定义模板用户就会
  /// 看到一条永远消不掉的黄条,然后学会无视它。
  final bool warnIfMissing;

  /// 可**安全追加到模板末尾**的补丁片段;`null` = 位置有语义,不能自动插入。
  ///
  /// 例:`{{BILL_GUARD}}` 必须在最前面、`{{OCR_TEXT}}` 要在「文本:」之后,
  /// 盲目追加会出错,这类只提示不代劳。
  final String? appendSnippet;

  const PromptPlaceholder(
    this.token, {
    this.warnIfMissing = true,
    this.appendSnippet,
  });
}

/// Prompt 模板拼装。纯函数,无副作用,易于单测。
///
/// 默认模板要求 AI 返回 JSON 数组(单笔也包成 `[{...}]`),通过占位符
/// `{{INPUT_SOURCE}}` / `{{CURRENT_TIME}}` / `{{OCR_TEXT}}` /
/// `{{BILL_GUARD}}` / `{{CATEGORIES}}` / `{{ACCOUNTS}}` 注入运行时变量。
class PromptBuilder {
  const PromptBuilder();

  /// 默认模板。强制 JSON 数组 + 完整字段说明 + 多笔示例。
  ///
  /// 调用方可通过 [build] 的 [billGuard] 参数决定是否注入前置过滤段
  /// （如 `[billGuardForImage]`），避免误伤聊天记账等主动输入路径。
  static const String defaultTemplate =
      '''{{BILL_GUARD}}{{INPUT_SOURCE}}擷取記帳資訊，回傳JSON陣列。

目前時間：{{CURRENT_TIME}}

{{OCR_TEXT}}

{{CATEGORIES}}{{ACCOUNTS}}{{CURRENCIES}}

輸出格式：
- 一律回傳 JSON 陣列，即使只有一筆，也包成 [{...}]
- 辨識到多筆獨立消費/收入/轉帳時，陣列中每筆一個物件，依時間先後順序排列
- 「拆開 AA」「拆開報銷」「合購」等情境，每筆獨立支付/收款都算一筆
- 同一商家的多件商品如果是一次付清，合併為一筆

欄位說明：
1. amount: 金額（支出為負數，收入為正數）
2. time: ISO8601 格式，盡量推斷時間：
   - 明確時間（如"14:30"、"2025-11-25"）→直接使用
   - 民國年（如台灣發票、收據常見的"115/09/20"、"民國115年9月20日"）→加1911換算為西元年（115+1911=2026，轉為"2026-09-20T12:00:00"）
   - 相對日期（昨天、前天、上週）→推算具體日期
   - 時間段（早上、中午、晚上）→使用合理時刻（早上09:00、中午12:00、晚上19:00）
   - 完全沒提到時間→使用目前時間
3. note: 備註（必須≤15字，超過則精簡），擷取優先順序：
   - 商家/店名（如"星巴克"、"肯德基"）
   - 商品名稱（長標題需簡化，如"2025春季新款黑色斜紋格紋半身裙"→"黑色半身裙"）
   - 使用者描述（如"給女兒買"）
   - 沒有則留空
4. category: 從分類清單選擇（轉帳可填"轉帳"）
5. type: income、expense 或 transfer
6. account: 支付帳戶（收入/支出可用）
7. from_account: 轉出帳戶（僅轉帳可用）
8. to_account: 轉入帳戶（僅轉帳可用）
9. tag/tags: 標籤（可選，單一字串或字串陣列）
$_currencyFieldSpec

範例：
單筆"昨天中午吃飯50" → [{"amount":-50,"time":"2025-11-24T12:00:00","category":"餐飲","type":"expense"}]
單筆"早上在星巴克買咖啡30" → [{"amount":-30,"time":"{{CURRENT_DATE}}T09:00:00","note":"星巴克","category":"咖啡","type":"expense"}]
單筆"商品:2025春季新款黑色半身裙 金額:NT\$299" → [{"amount":-299,"note":"黑色半身裙","category":"服裝","type":"expense"}]
轉帳"從台新轉800到街口" → [{"amount":800,"category":"轉帳","type":"transfer","from_account":"台新","to_account":"街口","tag":"自己"}]
外幣"花了45美元" → [{"amount":-45,"currency":"USD","type":"expense"}]
外幣"在東京吃拉麵1200日圓" → [{"amount":-1200,"currency":"JPY","note":"拉麵","category":"餐飲","type":"expense"}]
外幣"星巴克 \$6.5" → [{"amount":-6.5,"currency":"USD","note":"星巴克","category":"咖啡","type":"expense"}]
外幣"房租 1200 歐" → [{"amount":-1200,"currency":"EUR","note":"房租","category":"居家","type":"expense"}]
發票"統一發票 115/09/20 全聯 250元" → [{"amount":-250,"time":"2026-09-20T12:00:00","note":"全聯","category":"購物","type":"expense"}]
多筆"早上捷運5元，中午吃飯40元，晚上買水果35元" → [{"amount":-5,"time":"{{CURRENT_DATE}}T09:00:00","note":"捷運","category":"交通","type":"expense"},{"amount":-40,"time":"{{CURRENT_DATE}}T12:00:00","category":"餐飲","type":"expense"},{"amount":-35,"time":"{{CURRENT_DATE}}T19:00:00","note":"水果","category":"購物","type":"expense"}]

注意：只回傳 JSON 陣列（即使只有一筆也用陣列包裹），盡量推斷時間不要回傳 null，note 必須 ≤15 字（長標題要精簡）。外幣的 currency 一律填 ISO 代碼（USD，不是 \$ 或"美元"）''';

  /// 币种字段说明。**默认模板与「插入币种段落」补丁共用同一份**,避免两处漂移。
  ///
  /// 写法上刻意做了三件事(2026-08-12 实测「日元能识别、美元不行」后调整):
  /// 1. 显式列出中文名/符号 → ISO 代码的对应表 —— 只靠"填 ISO 代码"这句话,
  ///    模型对没见过样例的币种容易漏填
  /// 2. 明确禁止填符号或中文名 —— 原先字段说明里把 `\$45` 当输入例子写在紧邻
  ///    位置,模型会直接把 `\$` 当**字段值**回来
  /// 3. 强调"出现任何外币说法都要填",对冲其余示例(都没有 currency)带来的
  ///    few-shot 偏置
  static const String _currencyFieldSpec =
      '''10. currency: 幣別，必須是 3 位大寫 ISO 4217 代碼，**不要填貨幣符號，也不要填中文名稱**
    - 中文說法與代碼的對應見上面的「幣別對照」；符號同樣算外幣說法：
      \$ → USD，€ → EUR，£ → GBP，₩ → KRW，฿ → THB
    - 與帳本主要幣別相同時**省略此欄位**（主要幣別是 TWD 時，"花了50元"不要填 currency）
    - 原文出現任何外幣說法（中文名稱、符號、代碼都算）就必須填，別漏''';

  /// 币种段落(A7)。给**自定义模板用户**的「插入币种段落」一键补丁用 ——
  /// 我们不覆盖用户模板(方案 a),但让他们一次点击就能把这个能力补进自己的
  /// 模板。内容与默认模板共用 [_currencyFieldSpec],不会漂移。
  static const String currencySectionSnippet = '$_currencyFieldSpec\n{{CURRENCIES}}';

  /// 默认模板用到的全部占位符。**新增占位符必须在此登记** ——
  /// [placeholdersMatchDefaultTemplate] 会双向校验,漏登记或登记了模板里没有的
  /// 都会让单测红。
  static const List<PromptPlaceholder> placeholders = [
    // 位置有语义(必须在最前),不能自动插入
    PromptPlaceholder('{{BILL_GUARD}}'),
    // 纯观感:少了只是少个「从以下支付账单文本中」前缀
    PromptPlaceholder('{{INPUT_SOURCE}}', warnIfMissing: false),
    // 时间锚点:少了「昨天」「上周」这类相对日期会算错
    PromptPlaceholder('{{CURRENT_TIME}}'),
    // 只出现在示例里,少了不影响能力
    PromptPlaceholder('{{CURRENT_DATE}}', warnIfMissing: false),
    // 待识别文本本体:文本类路径少了它 AI 根本看不到内容
    PromptPlaceholder('{{OCR_TEXT}}'),
    PromptPlaceholder('{{CATEGORIES}}'),
    PromptPlaceholder('{{ACCOUNTS}}'),
    PromptPlaceholder('{{CURRENCIES}}', appendSnippet: currencySectionSnippet),
  ];

  /// [template] 里缺失的、**值得提示**的占位符(即能力会失效的那些)。
  /// 用默认模板调用应恒为空。
  static List<PromptPlaceholder> missingPlaceholdersIn(String template) =>
      placeholders
          .where((p) => p.warnIfMissing && !template.contains(p.token))
          .toList();

  /// 登记表与默认模板是否一致(双向)。给单测当锁用。
  static bool get placeholdersMatchDefaultTemplate {
    final inTemplate = RegExp(r'\{\{[A-Z_]+\}\}')
        .allMatches(defaultTemplate)
        .map((m) => m.group(0)!)
        .toSet();
    final registered = placeholders.map((p) => p.token).toSet();
    return inTemplate.difference(registered).isEmpty &&
        registered.difference(inTemplate).isEmpty;
  }

  /// 截图/自动路径使用的账单过滤段。
  ///
  /// 拼在默认模板最前面，让 AI 先判断输入是否为真实账单，非账单直接返回 []。
  /// 聊天记账、语音记账等主动输入路径不应注入此段（传空字符串即可）。
  static const String billGuardForImage = '請先判斷輸入圖片是否為帳單。'
      '以下情況通常不屬於帳單（僅供參考，不僅限於此）：\n'
      '- 電腦/手機桌面截圖\n'
      '- 聊天紀錄、社群動態、社群網站等頁面\n'
      '- 新聞、文章、網頁瀏覽頁\n'
      '- 照片、自拍、風景圖\n'
      '- 應用程式主畫面、設定頁面\n'
      '\n'
      '判斷後，不是帳單則回傳JSON空陣列[]，是帳單則繼續。\n';

  /// Hardcoded fallback 分类(context 不提供时使用)
  static const String _hardcodedCategoryHint = '分類清單：\n'
      '支出：餐飲、交通、購物、娛樂、居家、通訊、水電、醫療、教育\n'
      '收入：工資、理財、收紅包、獎金、報銷、兼職';

  /// 拼装最终 prompt。
  ///
  /// [inputSource] 输入源描述(如 "从以下支付账单文本中" / "分析支付账单截图，从中")
  /// [billGuard] 前置过滤段，截图/自动路径传入 [billGuardForImage]，聊天等主动输入传空字符串。
  /// [ocrText] 文本输入(图片场景留空)
  /// [now] 时间锚点,默认 `DateTime.now()` (测试可注入固定时间)
  String build({
    required AiExtractionContext context,
    required String inputSource,
    String billGuard = '',
    String ocrText = '',
    DateTime? now,
  }) {
    final ts = now ?? DateTime.now();
    final currentDate = '${ts.year}-${_pad(ts.month)}-${_pad(ts.day)}';
    final currentTime = '$currentDate ${_pad(ts.hour)}:${_pad(ts.minute)}';

    final template = (context.customPromptTemplate != null &&
            context.customPromptTemplate!.trim().isNotEmpty)
        ? context.customPromptTemplate!
        : defaultTemplate;

    return template
        .replaceAll('{{BILL_GUARD}}', billGuard)
        .replaceAll('{{INPUT_SOURCE}}', inputSource)
        .replaceAll('{{CURRENT_TIME}}', currentTime)
        .replaceAll('{{CURRENT_DATE}}', currentDate)
        .replaceAll('{{OCR_TEXT}}', ocrText)
        .replaceAll('{{CATEGORIES}}', _buildCategoryHint(context))
        .replaceAll('{{ACCOUNTS}}', _buildAccountHint(context))
        .replaceAll('{{CURRENCIES}}', _buildCurrencyHint(context));
  }

  String _buildCategoryHint(AiExtractionContext ctx) {
    if (ctx.expenseCategories.isEmpty && ctx.incomeCategories.isEmpty) {
      return _hardcodedCategoryHint;
    }
    final parts = <String>[];
    if (ctx.expenseCategories.isNotEmpty) {
      parts.add('支出：${ctx.expenseCategories.join('、')}');
    }
    if (ctx.incomeCategories.isNotEmpty) {
      parts.add('收入：${ctx.incomeCategories.join('、')}');
    }
    return '分類清單：\n${parts.join('\n')}';
  }

  /// 账户清单。**只有币种 ≠ 账本本位币的账户才标注币种** —— 单币种账本渲染出
  /// 的字符串与加多币种之前逐字相同(零噪声、零回归)。
  String _buildAccountHint(AiExtractionContext ctx) {
    if (ctx.accounts.isEmpty) return '';
    final base = ctx.ledgerCurrency.toUpperCase();
    final parts = ctx.accounts.map((a) {
      final code = a.currency.toUpperCase();
      return (code.isEmpty || code == base) ? a.name : '${a.name}($code)';
    });
    return '\n帳戶清單：${parts.join('、')}';
  }

  /// 币种提示 = 主币种 + 账本内的外币账户币种 + **「中文说法 → ISO 代码」对照表**。
  ///
  /// 对照表从 [zhAliasesForCode] 生成(与解析器同一份别名表),覆盖:
  /// ① 账本自己在用的币种 —— 哪怕是 KES 这种长尾也带上,它对这个用户最相关;
  /// ② [kCommonCurrencyCodes] 常用币种 —— 用户在单币种账本里说「花了 45 美元」
  ///    同样要认得,所以不按「有没有外币账户」裁剪。
  ///
  /// 只靠一句「填 ISO 代码」是不够的:实测「日元」能识别而「美元」漏填,就是
  /// 因为示例里只有 JPY 一个样例、模型没有可套的模式(见 [_currencyFieldSpec])。
  String _buildCurrencyHint(AiExtractionContext ctx) {
    final base = ctx.ledgerCurrency.toUpperCase();
    final ledgerOthers = ctx.availableCurrencies
        .map((c) => c.toUpperCase())
        .where((c) => c.isNotEmpty && c != base)
        .toSet()
        .toList()
      ..sort();

    final buf = StringBuffer('\n帳本主要幣別：$base');
    if (ledgerOthers.isNotEmpty) {
      buf.write('；帳本內已有外幣帳戶：${ledgerOthers.join('、')}');
    }

    // 账本在用的排前面(更相关),再补常用币种;主币种不需要(相同就省略字段)
    final codes = <String>{
      ...ledgerOthers,
      ...kCommonCurrencyCodes.map((c) => c.toUpperCase()),
    }..remove(base);
    final rows = <String>[];
    for (final code in codes) {
      // limit:1 —— 对照表只给**一个规范名**。别名表里还登记了繁体变体(歐元/
      // 港幣)和口语(美金/美刀),那些是给**解析**用的,写进 prompt 只是白烧
      // token:模型自己就知道美金=美元,输出的都是 code。
      final names = zhAliasesForCode(code, limit: 1);
      rows.add(names.isEmpty ? code : '${names.first}=$code');
    }
    if (rows.isNotEmpty) {
      buf.write('\n幣別對照（原文出現左邊說法時，currency 填右邊代碼）：'
          '${rows.join('、')}');
    }
    return buf.toString();
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
