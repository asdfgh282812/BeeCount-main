import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';

import '../../ai/core/ai_project_assign_mode.dart';
import '../../ai/core/bill_info.dart';
import '../../data/db.dart';
import '../../data/repositories/base_repository.dart';
import '../../data/category_node.dart';
import '../../l10n/app_localizations.dart';
import '../currency/rate_math.dart';
import '../data/tag_seed_service.dart';
import '../system/logger_service.dart';
import 'category_matcher.dart';
import 'reward_rule_matcher.dart';

/// 账单交易创建服务。
///
/// 把 [BillInfo](AI 提取 + sanitize 后的统一表达)落库成 `transactions` 表
/// 记录,同时挂上分类/账户/标签。被以下渠道复用:
/// - [AiBookkeeper] 的 5 条路径(对话/图片/语音/自动截图/自动文本)
/// - 后续可能接入的手动录入(目前手动走 `repository.addTransaction` 直接落库)
/// 确保某币种 → 账本本位币的汇率在本地可用;返回是否可用。
///
/// 由 provider 层注入(见 `aiBookkeeperProvider` 装配),这样 service 层不必
/// 依赖 Riverpod,后台自动记账也能复用同一条汇率预拉路径(A6)。
typedef EnsureRate = Future<bool> Function(String currencyCode);

/// AI 記帳找不到帳戶時的攔截回調(對話/照片/語音三個有 UI 的渠道實作它,
/// 跳出帳戶選擇 sheet)。回傳 null = 使用者取消,這筆帳單視為主動放棄建立
/// (拋 [MissingAccountSkipped],不是「建立失敗」)。背景渠道不提供這個
/// callback,走 [needsAccountAssignment] 旗標,見 createFromBill 內的分支。
typedef ResolveMissingAccount = Future<int?> Function(BillInfo bill);

/// [BillCreationService.createFromBill] 在有 [ResolveMissingAccount] 回調、
/// 但使用者取消(回傳 null)時拋出——跟資料庫寫入失敗區分開,讓
/// `AiBookkeeper._persistAll` 能分別計數「已略過」vs.「失敗」。
class MissingAccountSkipped implements Exception {
  const MissingAccountSkipped();
}

/// AI 記帳「專案指定」ask 模式(或 aiDecide 配對不到時退回)的攔截回調
/// (design 2026-09-11)。回傳本地 project id,或 null 代表使用者主動選擇
/// 「不指定專案」——跟 [ResolveMissingAccount] 不同,這裡的 null **不是取消**,
/// 而是正常完成(專案是可選欄位),所以沒有對應的 `Skipped` 例外。呼叫端未
/// 提供回呼(背景渠道)時,視同下方 fallback,標記 [needsAccountAssignment]
/// 的姊妹旗標 `needsProjectAssignment`。
typedef ResolveMissingProject = Future<int?> Function(BillInfo bill);

/// AI 記帳信用卡回饋規則自動比對(design 2026-09-18)的 SwipeSmart 推薦查詢
/// 回調——由 provider 層注入,讓 service 層不必依賴 `flutter_cloud_sync`,
/// 比照 [EnsureRate] 的注入模式。回傳該帳戶目前最推薦的規則「名稱」文字
/// (不是本地 syncId——SwipeSmart 跟本地 `CardRewardRule` 是不同資料庫,沒有
/// ID 對應關係,呼叫端需再用 [matchUniqueRewardRuleByLabel] 模糊比對本地規
/// 則),查不到/例外一律回傳 null。
typedef RecommendRewardRuleName = Future<String?> Function({
  required int ledgerId,
  required int accountId,
  required double amount,
  required String merchant,
});

class BillCreationService {
  static const _tag = 'BillCreation';

  final BaseRepository repo;

  /// 见 [EnsureRate]。未注入(单测 / 老调用方)时跳过预拉,行为与改动前一致。
  final EnsureRate? ensureRate;

  /// 见 [RecommendRewardRuleName]。未注入(单测 / 老调用方)时跳过 SwipeSmart
  /// 推薦查詢,行为与改动前一致(只走本机学习快取,快取没有就没有回饋)。
  final RecommendRewardRuleName? recommendRewardRuleName;

  BillCreationService(this.repo,
      {this.ensureRate, this.recommendRewardRuleName});

  /// 从 [BillInfo] 创建账单交易。入参的 [bill] 经过 sanitize,
  /// **保证 amount 非空且 abs > 0、time 非空**,内部无需再做兜底。
  ///
  /// 返回创建的交易 ID,失败(数据库异常)返回 null。
  Future<int?> createFromBill({
    required BillInfo bill,
    required int ledgerId,
    List<String>? billingTypes,
    List<String>? customTagNames,
    AppLocalizations? l10n,
    bool autoAddTags = true,
    ResolveMissingAccount? resolveMissingAccount,
    ResolveMissingProject? resolveMissingProject,
  }) async {
    final amount = bill.amount;
    if (amount == null || amount.abs() <= 0) {
      logger.warning(_tag, '[校验] amount 无效,跳过: ${bill.toJson()}');
      return null;
    }

    // 1. 确定交易类型
    final transactionType = _resolveType(bill);
    logger.debug(_tag,
        '[类型判断] type=${bill.type?.name} amount=$amount → $transactionType');

    // 2. 查询对应类型的所有可用分类
    final categories = await _loadUsableCategories(transactionType);

    // 3. 匹配分类(AI 名称 → 完全匹配 → 模糊匹配 → 规则匹配 → 兜底"其他")
    var categoryId =
        await _matchCategory(bill.category, bill.note ?? '', categories);
    if (categoryId == null && categories.isNotEmpty) {
      categoryId = _fallbackCategoryId(categories);
    }

    // 3.5 账本本位币 + AI 给的币种(.docs/multi-currency-ai A1/A2)
    final ledgerBase = await _ledgerCurrency(ledgerId);
    final requestedCurrency = bill.currency?.trim().toUpperCase();

    // 4. 匹配账户。**账户候选池按这笔的币种筛**(A3,与手动记账
    //    AccountSelector.filterCurrency 同构):AI 给了币种就只在该币种的账户
    //    里找;没给币种则全币种可选,由命中的账户反过来决定币种(L7)。
    int? accountId;
    int? toAccountId;
    if (transactionType == 'transfer') {
      final source = bill.fromAccount ?? bill.account;
      if (source != null && source.trim().isNotEmpty) {
        accountId = await _matchAccountByName(source, requestedCurrency);
      }
      if (bill.toAccount != null && bill.toAccount!.trim().isNotEmpty) {
        // **跨币种转账守卫**(.docs/multi-currency-ledger 01 §4.4):转入账户必须
        // 与这笔转账的币种一致。手动路径(transfer_form)会 toast 报错并重置转入
        // 账户;AI 是无人值守,所以退化成「匹配不到转入账户」—— 这与 AI 本来
        // 就没说转入账户时的落库形态一致,不会造出一笔币种错乱的转账。
        //
        // 这里**必须兜到 ledgerBase**,不能留 null:留 null 池就全币种开放,
        // 于是「转出账户没匹配上 + AI 没给币种」时,转入账户可能是 USD 账户而
        // 这笔按 CNY 落库(下面 4.5 算出的 txCurrency=ledgerBase)—— 账户余额读
        // 的是原币 amount,800 会当成 800 美元加到 USD 账户上,余额直接错。
        final fromCurrency = accountId == null
            ? null
            : (await repo.getAccount(accountId))?.currency.toUpperCase();
        final transferCurrency =
            fromCurrency ?? requestedCurrency ?? ledgerBase;
        toAccountId =
            await _matchAccountByName(bill.toAccount!, transferCurrency);
      }
      if (accountId != null && accountId == toAccountId) {
        toAccountId = null;
      }
    } else {
      accountId = await _matchAccount(
        bill.account,
        ledgerId,
        transactionType: transactionType,
        requestedCurrency: requestedCurrency,
        ledgerBase: ledgerBase,
      );
    }

    // 3.7 找不到帳戶時的攔截:有回調(對話/照片/語音,有 UI)就跳出選擇,
    // 使用者取消 → 這筆視為主動略過(不是失敗);沒有回調(背景截圖/通知
    // 監聽)→ 落到 4. needsAccountAssignment 旗標,交易照常建立。
    var needsAccountAssignment = false;
    if (transactionType != 'transfer' && accountId == null) {
      if (resolveMissingAccount != null) {
        accountId = await resolveMissingAccount(bill);
        if (accountId == null) {
          throw const MissingAccountSkipped();
        }
      } else {
        needsAccountAssignment = true;
      }
    }

    // 4.5 定交易币种:命中账户 → 随账户(账户内不混币,L7/L12 的不变量);
    //     否则用 AI 给的;都没有 → 账本本位币。
    final matchedAccount =
        accountId == null ? null : await repo.getAccount(accountId);
    final accountCurrency = (matchedAccount?.currency.isNotEmpty ?? false)
        ? matchedAccount!.currency.toUpperCase()
        : null;
    final txCurrency = accountCurrency ?? requestedCurrency ?? ledgerBase;

    // 4.6 AI 給的幣種跟命中帳戶的幣種不一致(#手動選帳戶,見下段):自動匹配
    // 池已按 requestedCurrency 篩過,正常不會走到這裡;唯一路徑是使用者透過
    // resolveMissingAccount(3.7)手動選了一個幣種不同的帳戶——例如收據是
    // JPY,手上沒有 JPY 帳戶,選了 TWD 帳戶記帳。帳戶幣種仍然贏(帳戶內不混
    // 幣的不變量不能破,見 4.5 開頭注解),但 AI 抓到的原始金額是
    // requestedCurrency 底下的數字,必須先換算成 accountCurrency 再落庫,否則
    // 會把「10230 日圓」原封不動記成「10230 台幣」(bug:少乘了匯率)。換算不到
    // 匯率時退化成不轉換並記警告,交易仍照常建立,不因為換算失敗而整筆放棄。
    var billAmount = amount.abs();
    if (requestedCurrency != null &&
        accountCurrency != null &&
        requestedCurrency != accountCurrency) {
      final converted = await _convertBetweenCurrencies(
        amount: billAmount,
        from: requestedCurrency,
        to: accountCurrency,
        ledgerBase: ledgerBase,
      );
      if (converted != null) {
        billAmount = converted;
      } else {
        logger.warning(_tag,
            '[币种] AI 给 $requestedCurrency 但選中帳戶是 $accountCurrency,匯率換算失敗,金額按原始數字記入 $accountCurrency(需事後手動修正)');
      }
    }
    // 外币且**本地还没有**有效汇率时才拉(A6)。本地已有就直接用 —— 否则
    // 多笔外币账单(一张图 10 笔)会各打一次 force 网络请求,后台自动记账
    // 同样受害;先查本地也让同一批里的后续账单命中第一笔刚落库的汇率。
    if (txCurrency != ledgerBase &&
        !await _hasLocalRate(ledgerBase, txCurrency)) {
      await _ensureRateAvailable(txCurrency);
    }

    // 4.8 專案指定(design 2026-09-11):三模式分流。none 略過;aiDecide 先按
    // BillInfo.project 名稱比對「目前有效專案」,配對成功直接寫入不詢問;
    // 配對不到(或 bill.project 為空)退回 ask 的行為;ask 直接呼叫回調。
    // 兩種情形都沒有回調可用(背景渠道)時,交易照常建立,只標記
    // needsProjectAssignment 讓使用者事後在「待確認專案」列表補選。
    final (projectSyncId, needsProjectAssignment) =
        await _resolveProject(bill, ledgerId, resolveMissingProject);

    // 4.9 信用卡回饋規則自動比對(design 2026-09-18):僅支出 + 帳戶為信用卡
    // 才進入,結果直接放進下面的 addTransaction 一次寫入,不擋流程。
    List<String>? rewardRuleIds;
    if (transactionType == 'expense' &&
        accountId != null &&
        matchedAccount?.type == 'credit_card') {
      rewardRuleIds = await _resolveRewardRuleIds(
        bill: bill,
        ledgerId: ledgerId,
        categoryId: categoryId,
        account: matchedAccount!,
        amount: billAmount,
      );
    }

    // 5. 落库。nativeAmount 不传 —— 交给 LocalRepository._resolveTxCurrency
    //    按有效汇率折算;缺汇率时它会退化成 =amount 并被 L11 检测捞回。
    final happenedAt = bill.time ?? DateTime.now();
    final transactionId = await repo.addTransaction(
      ledgerId: ledgerId,
      type: transactionType,
      amount: billAmount,
      categoryId: categoryId,
      accountId: accountId,
      toAccountId: toAccountId,
      happenedAt: happenedAt,
      note: bill.note,
      merchant: bill.merchant,
      currencyCode: txCurrency,
      needsAccountAssignment: needsAccountAssignment,
      projectSyncId: projectSyncId,
      needsProjectAssignment: needsProjectAssignment,
      rewardRuleIds: rewardRuleIds,
    );

    // 6. 自动标签:受「智能记账自动关联标签」开关控制(默认开启,关闭后不挂任何标签)。
    //    与账户功能开关一致直接读 prefs;入参 autoAddTags 作为代码级强制开关,二者取「与」。
    if (autoAddTags) {
      final prefs = await SharedPreferences.getInstance();
      final autoTagsEnabled = prefs.getBool('smartBillingAutoTags') ?? true;
      if (autoTagsEnabled) {
        await _addTags(
          transactionId,
          billingTypes: billingTypes,
          customTagNames: customTagNames ?? bill.tags,
          l10n: l10n,
        );
      }
    }

    // 7. 汇总日志
    String? categoryName;
    String? accountName;
    if (categoryId != null) {
      categoryName =
          categories.firstWhereOrNull((c) => c.id == categoryId)?.name;
    }
    if (accountId != null) {
      accountName = (await repo.getAccount(accountId))?.name;
    }
    final typeStr = transactionType == 'income'
        ? '收入'
        : (transactionType == 'transfer' ? '转账' : '支出');
    final tagSources = <String>[
      ...?billingTypes,
      ...?(customTagNames ?? bill.tags),
    ];
    logger.info(
      _tag,
      '[自动记账] 成功 | ID:$transactionId | $billAmount $txCurrency | $typeStr | '
      '分类:${categoryName ?? '未设置'} | 账户:${accountName ?? '未设置'} | '
      '时间:${_formatDateTime(happenedAt)} | 备注:${bill.note ?? '无'} | '
      '标签:${tagSources.isNotEmpty ? tagSources.join(',') : '无'}',
    );

    return transactionId;
  }

  /// 获取按类型过滤的可用分类(排除有子分类的父分类)。公开给业务复用。
  Future<List<Category>> getCategoriesByType(String type) async {
    final top = await repo.getTopLevelCategories(type);
    final all = <Category>[...top];
    for (final c in top) {
      all.addAll(await repo.getSubCategories(c.id));
    }
    return all;
  }

  // ============================================================
  // 内部实现
  // ============================================================

  /// 决定 transaction.type:
  /// 1. BillInfo.type 显式 → 直接用
  /// 2. category 是「转账」字样 → transfer
  /// 3. 默认 expense(AI 模式下 amount 负值代表支出,prompt 已要求 AI 自行标
  ///    type;若 type 漏了我们保守按 expense 处理,避免误记成收入)
  String _resolveType(BillInfo bill) {
    if (bill.type == BillType.transfer) return 'transfer';
    if (bill.type == BillType.expense) return 'expense';
    if (bill.type == BillType.income) return 'income';
    final cat = bill.category?.trim();
    if (cat == '转账' || cat == '轉帳' || cat?.toLowerCase() == 'transfer') {
      return 'transfer';
    }
    return 'expense';
  }

  Future<List<Category>> _loadUsableCategories(String type) async {
    final top = await repo.getTopLevelCategories(type);
    final all = <Category>[...top];
    for (final c in top) {
      all.addAll(await repo.getSubCategories(c.id));
    }
    return CategoryHierarchy.getUsableCategories(all);
  }

  /// 按 AI 给的 category 名称匹配本地分类。完全匹配 → 模糊匹配 → 规则匹配。
  Future<int?> _matchCategory(
    String? aiCategoryName,
    String note,
    List<Category> categories,
  ) async {
    if (categories.isEmpty) return null;

    if (aiCategoryName != null && aiCategoryName.isNotEmpty) {
      // 完全匹配
      final exact =
          categories.firstWhereOrNull((c) => c.name == aiCategoryName);
      if (exact != null) {
        logger.debug(_tag,
            '[分类匹配-完全] AI 分类"$aiCategoryName" → ${exact.name}(ID:${exact.id})');
        return exact.id;
      }

      // 模糊匹配:分类名包含 AI 名,或 AI 名包含分类名(取匹配长度最长的)
      Category? best;
      var bestScore = 0;
      for (final c in categories) {
        var score = 0;
        if (c.name.contains(aiCategoryName)) {
          score = aiCategoryName.length;
        } else if (aiCategoryName.contains(c.name)) {
          score = c.name.length;
        }
        if (score > bestScore) {
          bestScore = score;
          best = c;
        }
      }
      if (best != null) {
        logger.debug(_tag,
            '[分类匹配-模糊] AI 分类"$aiCategoryName" → ${best.name}(ID:${best.id})');
        return best.id;
      }
      logger.debug(_tag, '[分类匹配] AI 分类"$aiCategoryName" 未匹配,降级规则匹配');
    }

    return CategoryMatcher.smartMatch(
      merchant: note,
      fullText: note,
      categories: categories,
    );
  }

  /// 获取兜底分类("其他"系列或最后一个)
  int? _fallbackCategoryId(List<Category> categories) {
    if (categories.isEmpty) return null;
    const keywords = ['其他', 'other', '其它', '杂项', 'misc'];
    for (final k in keywords) {
      final hit = categories.firstWhereOrNull(
        (c) => c.name.toLowerCase().contains(k.toLowerCase()),
      );
      if (hit != null) {
        logger.debug(_tag, '[分类兜底] 使用"${hit.name}"(ID:${hit.id})');
        return hit.id;
      }
    }
    final last = categories.last;
    logger.debug(_tag, '[分类兜底] 使用"${last.name}"(ID:${last.id})');
    return last.id;
  }

  /// 收入/支出场景的账户匹配。
  Future<int?> _matchAccount(
    String? aiAccountName,
    int ledgerId, {
    required String transactionType,
    required String? requestedCurrency,
    required String ledgerBase,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('account_feature_enabled') ?? true;
    if (!enabled) {
      logger.debug(_tag, '[账户匹配] 账户功能未启用,跳过');
      return null;
    }

    if (aiAccountName == null || aiAccountName.isEmpty) {
      logger.debug(_tag, '[账户匹配] AI 未识别账户,使用默认账户');
      return _getDefaultAccountId(
          transactionType, prefs, requestedCurrency ?? ledgerBase);
    }

    final matched = await _matchAccountByName(aiAccountName, requestedCurrency);
    if (matched != null) return matched;

    logger.debug(_tag, '[账户匹配] "$aiAccountName" 未匹配,尝试默认账户');
    return _getDefaultAccountId(
        transactionType, prefs, requestedCurrency ?? ledgerBase);
  }

  /// 按名称匹配账户。完全 → 模糊 → 类型映射。
  ///
  /// [currency] 非空时只在该币种的账户里找(AI 明确说了外币,就不该匹配到本位
  /// 币账户 —— 45 美元记成 45 元是比「没匹配到账户」严重得多的错);为空则全
  /// 币种可选,命中的账户反过来决定这笔的币种(L7)。
  Future<int?> _matchAccountByName(String accountName, String? currency) async {
    final allAccounts = await repo.getAllAccounts();
    // 账户隐藏(#240):AI 自动记账不匹配隐藏账户(隐藏 = 不再作为新交易记账
    // 目标,与手动选择器 / Web AI 候选一致);未匹配则回落默认账户。
    final wanted = currency?.toUpperCase();
    final pool = allAccounts
        .where((a) =>
            !a.hidden &&
            // 主帳戶(合併帳單分組,type=='account_group')是純管理容器,不能直接
            // 入帳——即使 AI 提示詞候選清單已排除,自訂模板/幻覺仍可能回傳其
            // 名稱,這裡是最後一道防線,與手動選擇器一致。
            a.type != 'account_group' &&
            (wanted == null || a.currency.toUpperCase() == wanted))
        .toList();
    final target = accountName.toLowerCase().trim();

    // 完全匹配
    for (final a in pool) {
      if (a.name.toLowerCase().trim() == target) {
        logger.debug(_tag, '[账户匹配-完全] "$accountName" → ${a.name}(ID:${a.id})');
        return a.id;
      }
    }
    // 模糊匹配
    for (final a in pool) {
      final n = a.name.toLowerCase().trim();
      if (n.contains(target) || target.contains(n)) {
        logger.debug(_tag, '[账户匹配-模糊] "$accountName" → ${a.name}(ID:${a.id})');
        return a.id;
      }
    }
    // 类型映射(余额宝 → 支付宝 等)
    const typeMap = {
      '余额宝': ['支付宝', 'alipay'],
      '花呗': ['支付宝', 'alipay'],
      '微信支付': ['微信', 'wechat'],
      '微信钱包': ['微信', 'wechat'],
      '零钱': ['微信', 'wechat'],
      '零钱通': ['微信', 'wechat'],
    };
    final related = typeMap[target] ?? const [];
    for (final a in pool) {
      final n = a.name.toLowerCase().trim();
      for (final r in related) {
        if (n.contains(r.toLowerCase())) {
          logger.debug(
              _tag, '[账户匹配-类型] "$accountName" → ${a.name}(ID:${a.id})');
          return a.id;
        }
      }
    }
    return null;
  }

  /// 專案指定(design 2026-09-11)三模式分流。回傳 (projectSyncId, 是否標記
  /// needsProjectAssignment)。
  Future<(String?, bool)> _resolveProject(
    BillInfo bill,
    int ledgerId,
    ResolveMissingProject? resolveMissingProject,
  ) async {
    final mode = await _projectAssignMode();
    if (mode == AiProjectAssignMode.none) return (null, false);

    int? matchedProjectId;
    if (mode == AiProjectAssignMode.aiDecide) {
      final aiProjectName = bill.project?.trim();
      if (aiProjectName != null && aiProjectName.isNotEmpty) {
        matchedProjectId = await _matchProjectByName(aiProjectName, ledgerId);
      }
    }

    if (matchedProjectId != null) {
      final syncId = (await repo.getProject(matchedProjectId))?.syncId;
      logger.debug(_tag, '[專案匹配] "${bill.project}" → 專案ID:$matchedProjectId');
      return (syncId, false);
    }

    // aiDecide 配對不到(或本來就是 ask 模式)→ 退回 ask 的行為。
    if (resolveMissingProject != null) {
      final pickedId = await resolveMissingProject(bill);
      if (pickedId == null) {
        // 使用者主動選擇「不指定專案」,是正常完成,不是取消。
        return (null, false);
      }
      final syncId = (await repo.getProject(pickedId))?.syncId;
      return (syncId, false);
    }

    // 背景渠道(無回呼可用):交易照常建立,標記待確認。
    return (null, true);
  }

  /// 目前設定的 [AiProjectAssignMode],直接讀 SharedPreferences(同
  /// [_matchAccount] 讀 `account_feature_enabled` 的慣例,service 層不依賴
  /// Riverpod)。解析失敗(未設定/髒值)一律當作 [AiProjectAssignMode.none]。
  Future<AiProjectAssignMode> _projectAssignMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kAiProjectAssignModeKey);
    return AiProjectAssignMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => AiProjectAssignMode.none,
    );
  }

  /// 按名稱匹配「目前有效(enabled=true)」的專案。完全匹配 → 模糊匹配,
  /// 邏輯結構同 [_matchAccountByName]。
  Future<int?> _matchProjectByName(String projectName, int ledgerId) async {
    final projects = await repo.getAllProjects(ledgerId);
    final target = projectName.toLowerCase().trim();

    for (final p in projects) {
      if (p.name.toLowerCase().trim() == target) return p.id;
    }
    for (final p in projects) {
      final n = p.name.toLowerCase().trim();
      if (n.contains(target) || target.contains(n)) return p.id;
    }
    return null;
  }

  /// 信用卡回饋規則自動比對(design 2026-09-18 §5.2)。
  ///
  /// 1. [categoryId] 非 null 時先查「同帳戶+同分類」學習快取(跟手動表單共用
  ///    同一份資料,**只讀不寫**——見 [RewardChoiceCacheRepository] 文件注
  ///    釋)。快取存在的 syncId 可能已經被刪了,過濾掉不在
  ///    [CardRewardRuleRepository.getCardRewardRulesForAccount] 清單裡的。
  ///    過濾後非空就直接採用。
  /// 2. 快取沒有可用結果時,只在帳戶已對照 SwipeSmart 卡片、AI 有辨識出商
  ///    家、且注入了 [recommendRewardRuleName] 時才查 SwipeSmart 推薦,模糊
  ///    比對本地目前生效中的規則,剛好一筆命中才採用。
  ///
  /// 任何一步沒有結果都回傳 null——交易照常建立,只是沒有回饋,不擋流程。
  /// 自動比對的結果**不寫回**學習快取(§8:維持「只有使用者手動選才寫入」
  /// 的既有不變量)。
  Future<List<String>?> _resolveRewardRuleIds({
    required BillInfo bill,
    required int ledgerId,
    required int? categoryId,
    required Account account,
    required double amount,
  }) async {
    final accountId = account.id;

    if (categoryId != null) {
      final cached = await repo.getCachedRewardRuleIds(
        ledgerId: ledgerId,
        categoryId: categoryId,
        accountId: accountId,
      );
      if (cached != null && cached.isNotEmpty) {
        final rules = await repo.getCardRewardRulesForAccount(accountId);
        final validIds = rules.map((r) => r.syncId).whereType<String>().toSet();
        final filtered = cached.where(validIds.contains).toList();
        if (filtered.isNotEmpty) {
          logger.debug(
              _tag, '[回饋] 快取命中(帳戶$accountId+分類$categoryId): $filtered');
          return filtered;
        }
      }
    }

    final recommend = recommendRewardRuleName;
    final swipesmartCardId = account.swipesmartCardId;
    final merchant = bill.merchant?.trim();
    if (recommend == null ||
        swipesmartCardId == null ||
        swipesmartCardId.isEmpty ||
        merchant == null ||
        merchant.isEmpty) {
      return null;
    }

    try {
      final ruleName = await recommend(
        ledgerId: ledgerId,
        accountId: accountId,
        amount: amount,
        merchant: merchant,
      );
      if (ruleName == null || ruleName.isEmpty) return null;

      final rules = await repo.getCardRewardRulesForAccount(accountId);
      final matched =
          matchUniqueRewardRuleByLabel(ruleName, effectiveRewardRules(rules));
      if (matched?.syncId == null) return null;
      logger.debug(
          _tag, '[回饋] SwipeSmart 推薦"$ruleName" 唯一命中本地規則"${matched!.label}"');
      return [matched.syncId!];
    } catch (e, st) {
      logger.warning(_tag, '[回饋] SwipeSmart 推薦查詢失敗,略過', st);
      return null;
    }
  }

  /// 默认账户。[txCurrency] 是这笔的币种(AI 给的,没给就是账本本位币)——
  /// 记外币时本位币的默认账户**不适用**,返回 null 让这笔不挂账户(Q3),
  /// 而不是硬塞一个币种不符的账户进去。
  Future<int?> _getDefaultAccountId(
    String transactionType,
    SharedPreferences prefs,
    String txCurrency,
  ) async {
    if (transactionType == 'transfer') return null;
    final key = transactionType == 'income'
        ? 'default_income_account_id'
        : 'default_expense_account_id';
    final defaultId = prefs.getInt(key);
    if (defaultId == null) return null;

    final account = await repo.getAccount(defaultId);
    if (account == null) return null;
    if (account.currency.toUpperCase() != txCurrency.toUpperCase()) {
      logger.debug(_tag, '[默认账户] 币种不匹配: ${account.currency} vs $txCurrency');
      return null;
    }
    logger.debug(_tag, '[默认账户] → ${account.name}(ID:${account.id})');
    return defaultId;
  }

  /// 账本本位币(空/查不到兜底 CNY)。
  Future<String> _ledgerCurrency(int ledgerId) async {
    final ledger = await repo.getLedgerById(ledgerId);
    final c = ledger?.currency;
    return (c == null || c.isEmpty) ? 'CNY' : c.toUpperCase();
  }

  /// 本地是否已有 [quote] → [base] 的有效汇率(手动 override 或最新自动源)。
  /// 判定口径与 `mergeEffectiveRates` 一致:rate 能解析成正数才算有效。
  Future<bool> _hasLocalRate(String base, String quote) async {
    bool valid(String rate) => (double.tryParse(rate) ?? 0) > 0;
    try {
      final overrides = await repo.getOverrides(base);
      if (overrides.any(
          (o) => o.quoteCurrency.toUpperCase() == quote && valid(o.rate))) {
        return true;
      }
      final autos = await repo.getLatestAutoRates(base);
      return autos
          .any((r) => r.quoteCurrency.toUpperCase() == quote && valid(r.rate));
    } catch (e) {
      // 查不了就当没有,交给 _ensureRateAvailable 兜(它自己也吞异常)
      logger.debug(_tag, '[汇率] 本地汇率检查失败,按「无」处理: $e');
      return false;
    }
  }

  /// 用「[from] → 帳本本位幣 → [to]」三角換算(對齊 transfer_form.dart
  /// `_convertCrossCurrency` 同一套邏輯):本地匯率表一律以帳本本位幣為 base,
  /// 沒有兩個外幣之間的直接匯率,所以兩段都要轉。任一段查不到有效匯率就回傳
  /// null,呼叫端自行決定退化行為(這裡選擇金額原樣落庫,而不是擋住整筆建立)。
  Future<double?> _convertBetweenCurrencies({
    required double amount,
    required String from,
    required String to,
    required String ledgerBase,
  }) async {
    if (from == to) return amount;
    if (from != ledgerBase && !await _hasLocalRate(ledgerBase, from)) {
      await _ensureRateAvailable(from);
    }
    if (to != ledgerBase && !await _hasLocalRate(ledgerBase, to)) {
      await _ensureRateAvailable(to);
    }
    final rates = await _effectiveRates(ledgerBase);
    final inBase = computeNativeAmount(
      amount: amount,
      accountCurrency: from,
      ledgerBase: ledgerBase,
      rates: rates,
    );
    if (inBase == null) return null;
    if (to == ledgerBase) return inBase;
    final toEff = rates[to];
    if (toEff == null) return null;
    final r = double.tryParse(toEff.rate);
    if (r == null || r <= 0) return null;
    return inBase / r;
  }

  /// [base] 的有效匯率表(手動 override 優先於最新自動源),同
  /// `LocalRepository._effectiveRatesFor` 的口徑。
  Future<Map<String, EffectiveRate>> _effectiveRates(String base) async {
    final autos = await repo.getLatestAutoRates(base);
    final overrides = await repo.getOverrides(base);
    return mergeEffectiveRates(
      autoRates: [
        for (final r in autos)
          (quote: r.quoteCurrency, rate: r.rate, rateDate: r.rateDate)
      ],
      overrides: [
        for (final o in overrides) (quote: o.quoteCurrency, rate: o.rate)
      ],
    );
  }

  /// 尽力把 [code] → 账本本位币的汇率拉到本地(A6)。
  ///
  /// 拉不到**不阻断**:自动截图/通知记账是无人值守的,阻断等于丢账。落库时
  /// repo 会退化成 `nativeAmount = amount`,恰好命中 L11 检测条件,用户在统计
  /// 页点一次「补折算」即可修正。手动记账那条路径仍然是阻断的(L8)。
  Future<void> _ensureRateAvailable(String code) async {
    final fn = ensureRate;
    if (fn == null) return;
    try {
      final ok = await fn(code);
      if (!ok) {
        logger.info(_tag, '[汇率] $code 拉取未成功,本笔按 1:1 暂记(L11 可补折算)');
      }
    } catch (e, st) {
      logger.warning(_tag, '[汇率] $code 拉取异常,本笔按 1:1 暂记', st);
      logger.debug(_tag, '[汇率] 异常详情: $e');
    }
  }

  /// 自动添加标签(记账方式 + 自定义)
  Future<void> _addTags(
    int transactionId, {
    List<String>? billingTypes,
    List<String>? customTagNames,
    AppLocalizations? l10n,
  }) async {
    try {
      final names = <String>{};
      if (billingTypes != null && billingTypes.isNotEmpty && l10n != null) {
        names.addAll(TagSeedService.getBillingTagNames(billingTypes, l10n));
      }
      if (customTagNames != null && customTagNames.isNotEmpty) {
        names.addAll(
            customTagNames.map((n) => n.trim()).where((n) => n.isNotEmpty));
      }
      if (names.isEmpty) return;

      final tagIds = <int>[];
      for (final name in names) {
        var tag = await repo.getTagByName(name);
        if (tag == null) {
          final color = TagSeedService.getRandomColor();
          final id = await repo.createTag(name: name, color: color);
          tagIds.add(id);
        } else {
          tagIds.add(tag.id);
        }
      }
      if (tagIds.isNotEmpty) {
        await repo.addTagsToTransaction(
            transactionId: transactionId, tagIds: tagIds);
      }
    } catch (e, st) {
      logger.error(_tag, '[标签] 添加失败', e, st);
    }
  }

  String _formatDateTime(DateTime dt) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} ${pad(dt.hour)}:${pad(dt.minute)}';
  }
}
