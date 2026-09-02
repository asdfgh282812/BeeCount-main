import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/db.dart';
import '../../data/repositories/base_repository.dart';
import '../../providers/database_providers.dart';
import '../automation/auto_billing_service.dart';
import '../billing/post_processor.dart';
import '../system/logger_service.dart';

/// AppLink 动作类型
enum AppLinkAction {
  /// 语音记账
  voice,

  /// 图片记账（从相册选择）
  image,

  /// 拍照记账
  camera,

  /// AI 小助手
  aiChat,

  /// 自动记账（带参数）
  add,

  /// 自动记账（从文本）
  autoBilling,

  /// 快速记账（从相册）
  quickBilling,

  /// 手动记账（从小组件快捷入口）
  newTransaction,

  /// 打开指定页面（净资产/预算/最近交易明细），配合小组件点击深链使用：
  /// `beecount://open?page=assets|budget|detail`
  open,

  /// SwipeSmart「一键记账」快速记账：`beecount://quick-add?merchant=..&
  /// amount=..&category=..&cardId=..&bankName=..&cardName=..&reward=..&
  /// rate=..`。只反查账户/分类、打开预填好的新增交易表单，不落地写入
  /// 交易——与 [add] 唯一的本质差异，见 [_handleQuickAdd] 文档。
  quickAdd,

  /// SSO 登录回调：`beecount://auth-callback#access_token=...`（或失败时
  /// `?sso_error=...`）。由 main.dart 在 isAppReady 判断之前提前拦截，
  /// 不会真的走到 handleUrl 的这个 case（见 AppLinkService 顶部文档）。
  ssoCallback,

  /// 未知
  unknown,
}

/// 自动记账参数
///
/// 同时也是 [AppLinkService.onNavigate] 回调的通用参数载体——
/// [AppLinkAction.newTransaction] / [AppLinkAction.open] 两个 action 复用本类
/// 只取用其中与自己相关的字段（前者用 [type]/[categoryId]，后者用 [page]），
/// 不为它们各开一个专门的参数类。
class AddTransactionParams {
  /// [AppLinkAction.add]/[AppLinkAction.quickAdd] 才可能为 null——前者构造前
  /// 已校验非空正数（见 [_handleAddTransaction]）,后者(quick-add)允许金额
  /// 解析失败/缺失时留空,由用户在表单里自己输入,不挡流程。
  final double? amount;
  final String type; // expense, income, transfer
  final String? category;
  final String? note;
  final String? account;
  final String? toAccount;
  final List<String>? tags;
  final DateTime? date;
  final bool silent;

  /// 快速记账预填的分类 id（仅 [AppLinkAction.newTransaction] 使用，来自
  /// `beecount://new?type=...&category=<id>` 中的 int id）。
  ///
  /// 与上面的 [category] 字段语义不同——那个是 [AppLinkAction.add] 自动记账
  /// 场景下按分类**名称**匹配用的字符串，这里是小组件「快速记账」点击某个
  /// 分类格后直接携带的分类 **id**，两者不复用同一字段，避免 int id 与 name
  /// 混淆。
  final int? categoryId;

  /// [AppLinkAction.open] 深链的目标页面标识（`assets`/`budget`/`detail`），
  /// 仅该 action 使用。
  final String? page;

  /// SwipeSmart「一键记账」带来的商家名（仅 [AppLinkAction.quickAdd] 使用）。
  final String? merchant;

  /// [AppLinkAction.quickAdd] 用 `swipesmartCardId` 反查到的信用卡账户 id
  /// （仅该 action 使用；反查不到则为 null，由用户自己在表单里选账户）。
  final int? accountId;

  const AddTransactionParams({
    this.amount,
    this.type = 'expense',
    this.category,
    this.note,
    this.account,
    this.toAccount,
    this.tags,
    this.date,
    this.silent = false,
    this.categoryId,
    this.page,
    this.merchant,
    this.accountId,
  });

  factory AddTransactionParams.fromQueryParams(Map<String, String> params) {
    final amountStr = params['amount'];
    if (amountStr == null || amountStr.isEmpty) {
      throw ArgumentError('amount is required');
    }

    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      throw ArgumentError('amount must be a positive number');
    }

    // 解析日期
    DateTime? date;
    final dateStr = params['date'];
    if (dateStr != null && dateStr.isNotEmpty) {
      date = DateTime.tryParse(dateStr);
    }

    // 解析标签
    List<String>? tags;
    final tagsStr = params['tags'];
    if (tagsStr != null && tagsStr.isNotEmpty) {
      tags = tagsStr.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    }

    return AddTransactionParams(
      amount: amount,
      type: params['type'] ?? 'expense',
      category: params['category'],
      note: params['note'],
      account: params['account'],
      toAccount: params['to_account'],
      tags: tags,
      date: date,
      silent: params['silent'] == '1' || params['silent'] == 'true',
    );
  }
}

/// AppLink 处理结果
class AppLinkResult {
  final bool success;
  final String? message;
  final int? transactionId;

  const AppLinkResult({
    required this.success,
    this.message,
    this.transactionId,
  });

  factory AppLinkResult.success({String? message, int? transactionId}) =>
      AppLinkResult(success: true, message: message, transactionId: transactionId);

  factory AppLinkResult.failure(String message) =>
      AppLinkResult(success: false, message: message);
}

/// AppLink 服务
///
/// 处理所有 beecount:// 开头的链接
///
/// 支持的链接格式:
/// - beecount://voice - 语音记账
/// - beecount://image - 图片记账（从相册）
/// - beecount://camera - 拍照记账
/// - beecount://ai-chat - AI 小助手
/// - beecount://new?type=expense - 手动记账（支出/收入）
/// - beecount://new?type=expense&category=12 - 手动记账并预填分类（小组件
///   「快速记账」点分类格用，category 为分类 id）
/// - beecount://add?amount=100&type=expense&category=餐饮 - 自动记账
/// - beecount://open?page=assets|budget|detail - 打开指定页面（小组件点击
///   净资产/预算/最近交易卡片用）
/// - beecount://quick-add?merchant=..&amount=..&category=..&cardId=..&
///   bankName=..&cardName=..&reward=..&rate=.. - SwipeSmart「一键记账」，
///   反查信用卡账户/分类后打开预填新增交易表单（不自动存档）
/// - beecount://auto-billing?text=... - 文本自动记账（兼容旧版）
/// - beecount://quick-billing - 快速记账（兼容旧版）
///
/// 同时监听 iOS AppIntents EventChannel 处理快捷指令传入的图片
class AppLinkService {
  final ProviderContainer _container;
  late final AutoBillingService _autoBillingService;

  /// iOS AppIntents 事件通道（用于接收快捷指令传入的图片路径）
  static const EventChannel _eventChannel =
      EventChannel('com.beecount.app_intents/events');

  /// iOS AppIntents 方法通道(回调 Swift,告知后台处理已完成可以放 perform 返回)
  static const MethodChannel _methodChannel =
      MethodChannel('com.beecount.app_intents');

  /// AppIntents 事件订阅
  StreamSubscription<dynamic>? _appIntentSubscription;

  /// 导航回调，由外部设置
  void Function(AppLinkAction action, {AddTransactionParams? params})? onNavigate;

  /// Toast 回调，由外部设置
  void Function(String message)? onShowToast;

  AppLinkService(this._container) {
    _autoBillingService = AutoBillingService(_container);
    _initAppIntentsListener();
  }

  /// 初始化 iOS AppIntents 监听器
  void _initAppIntentsListener() {
    if (!Platform.isIOS) return;

    logger.info('AppLink', '初始化 AppIntents 监听器');

    _appIntentSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is String) {
          logger.info('AppLink', '收到 AppIntent 事件: $event');
          _handleAppIntent(event);
        }
      },
      onError: (error) {
        logger.error('AppLink', 'AppIntent 事件监听错误', error);
      },
      onDone: () {
        logger.info('AppLink', 'AppIntent 事件流关闭');
      },
    );
  }

  /// 处理 AppIntent 事件
  Future<void> _handleAppIntent(String event) async {
    try {
      final data = jsonDecode(event) as Map<String, dynamic>;
      final action = data['action'] as String?;

      logger.info('AppLink', 'AppIntent action: $action');

      if (action == 'auto-billing') {
        final imagePath = data['imagePath'] as String?;
        if (imagePath != null && imagePath.isNotEmpty) {
          logger.info('AppLink', '处理快捷指令图片: $imagePath');
          await _handleScreenshotBilling(imagePath);
        } else {
          logger.warning('AppLink', 'auto-billing 未提供图片路径');
        }
      } else {
        logger.warning('AppLink', '未知的 AppIntent action: $action');
      }
    } catch (e, st) {
      logger.error('AppLink', '解析 AppIntent 事件失败', e, st);
    }
  }

  /// 处理快捷指令截图记账
  Future<void> _handleScreenshotBilling(String imagePath) async {
    try {
      await _autoBillingService.processScreenshot(
        imagePath,
        showNotification: true,
      );
      logger.info('AppLink', '快捷指令截图记账完成');
    } catch (e, st) {
      logger.error('AppLink', '快捷指令截图记账失败', e, st);
    } finally {
      // iOS: 通知 Swift AppIntent 处理完成,可以放 perform() 返回了。
      // 不发这个信号的话 perform() 会一直 await(直到 25s 超时),iOS 在 30s
      // 后台窗口内会 kill 进程,「成功」通知发不出去。
      if (Platform.isIOS) {
        try {
          await _methodChannel.invokeMethod('notifyBillingComplete');
        } catch (e) {
          logger.warning('AppLink', '通知 Swift 完成信号失败: $e');
        }
      }
    }
  }

  /// 解析 URI 获取动作类型
  static AppLinkAction parseAction(Uri uri) {
    final host = uri.host.toLowerCase();
    switch (host) {
      case 'voice':
        return AppLinkAction.voice;
      case 'image':
        return AppLinkAction.image;
      case 'camera':
        return AppLinkAction.camera;
      case 'ai-chat':
      case 'aichat':
      case 'ai':
        return AppLinkAction.aiChat;
      case 'add':
        return AppLinkAction.add;
      case 'new':
        return AppLinkAction.newTransaction;
      case 'open':
        return AppLinkAction.open;
      case 'quick-add':
        return AppLinkAction.quickAdd;
      case 'auth-callback':
        return AppLinkAction.ssoCallback;
      case 'auto-billing':
        return AppLinkAction.autoBilling;
      case 'quick-billing':
        return AppLinkAction.quickBilling;
      default:
        return AppLinkAction.unknown;
    }
  }

  /// 处理 URL
  Future<AppLinkResult> handleUrl(Uri uri) async {
    logger.info('AppLink', '收到URL: $uri');

    final action = parseAction(uri);
    final queryParams = uri.queryParameters;

    switch (action) {
      case AppLinkAction.voice:
        logger.info('AppLink', '打开语音记账');
        onNavigate?.call(AppLinkAction.voice);
        return AppLinkResult.success(message: '打开语音记账');

      case AppLinkAction.image:
        logger.info('AppLink', '打开图片记账');
        onNavigate?.call(AppLinkAction.image);
        return AppLinkResult.success(message: '打开图片记账');

      case AppLinkAction.camera:
        logger.info('AppLink', '打开拍照记账');
        onNavigate?.call(AppLinkAction.camera);
        return AppLinkResult.success(message: '打开拍照记账');

      case AppLinkAction.aiChat:
        logger.info('AppLink', '打开AI小助手');
        onNavigate?.call(AppLinkAction.aiChat);
        return AppLinkResult.success(message: '打开AI小助手');

      case AppLinkAction.add:
        logger.info('AppLink', '自动记账: $queryParams');
        return await _handleAddTransaction(queryParams);

      case AppLinkAction.newTransaction:
        final type = queryParams['type'] ?? 'expense';
        // 小组件「快速记账」点分类格携带的分类 id（int），与 add action 的
        // 分类名称参数是两个不同概念，见 AddTransactionParams.categoryId 文档。
        final categoryIdStr = queryParams['category'];
        final categoryId = categoryIdStr != null ? int.tryParse(categoryIdStr) : null;
        logger.info('AppLink',
            '打开手动记账: type=$type${categoryId != null ? ', categoryId=$categoryId' : ''}');
        onNavigate?.call(
          AppLinkAction.newTransaction,
          params: AddTransactionParams(amount: 0, type: type, categoryId: categoryId),
        );
        return AppLinkResult.success(message: '打开手动记账');

      case AppLinkAction.open:
        final page = queryParams['page'] ?? '';
        logger.info('AppLink', '打开页面: page=$page');
        if (page.isEmpty) {
          logger.warning('AppLink', 'open 未提供 page 参数');
          return AppLinkResult.failure('未提供目标页面');
        }
        onNavigate?.call(AppLinkAction.open, params: AddTransactionParams(amount: 0, page: page));
        return AppLinkResult.success(message: '打开页面: $page');

      case AppLinkAction.quickAdd:
        logger.info('AppLink', 'SwipeSmart 一键记账: $queryParams');
        return await _handleQuickAdd(queryParams);

      case AppLinkAction.ssoCallback:
        // 正常流程下 main.dart 的 dispatch() 会在 isAppReady 判断之前就
        // 拦截掉这个 host，不会走到这里。留这个 case 只是兜底（比如未来
        // 有别的入口直接调 handleUrl），避免 switch 漏 case。
        logger.warning('AppLink', 'ssoCallback 未被 main.dart 提前拦截，忽略');
        return AppLinkResult.failure('SSO 回调未被处理');

      case AppLinkAction.autoBilling:
        // 兼容旧版
        return await _handleAutoBilling(queryParams);

      case AppLinkAction.quickBilling:
        // 兼容旧版，等同于图片记账
        onNavigate?.call(AppLinkAction.image);
        return AppLinkResult.success(message: '打开图片记账');

      case AppLinkAction.unknown:
        logger.warning('AppLink', '未知的action: ${uri.host}');
        return AppLinkResult.failure('未知的操作: ${uri.host}');
    }
  }

  /// 处理自动记账（带参数）
  Future<AppLinkResult> _handleAddTransaction(Map<String, String> params) async {
    try {
      final repo = _container.read(repositoryProvider);

      // 冷启动早期 _currentLedgerPersist 可能还没把上次选中的账本从
      // SharedPreferences 恢复出来,currentLedgerId 还是默认值 1 —— 先显式
      // 校准一次,避免 deep-link 把交易记到错误账本。
      await _restoreCurrentLedgerId();

      // 必须 await .future:冷启动时 currentLedgerProvider 还在 loading,
      // 用 .valueOrNull 会拿到 null 而误判"无账本"导致静默失败(issue #162)。
      final currentLedger = await _container.read(currentLedgerProvider.future);

      if (currentLedger == null) {
        logger.warning('AppLink',
            '自动记账失败:未找到当前账本 (ledgerId=${_container.read(currentLedgerIdProvider)})');
        return AppLinkResult.failure('请先选择账本');
      }

      final ledgerId = currentLedger.id;
      final type = params['type'] ?? 'expense';

      // —— 完整性校验 —— 金额无效 / 缺分类 / 分类不存在 → 不记账,返回具体原因
      // (由上层用 toast 提醒用户)。转账没有分类概念,只校验金额。
      final parsedAmount = double.tryParse(params['amount'] ?? '');
      if (parsedAmount == null || parsedAmount <= 0) {
        logger.warning('AppLink', '已拦截:金额无效 (amount=${params['amount']})');
        return AppLinkResult.failure('未记账:请填写有效金额');
      }
      if (type != 'transfer') {
        final categoryName = params['category'];
        if (categoryName == null || categoryName.isEmpty) {
          logger.warning('AppLink', '已拦截:缺少分类');
          return AppLinkResult.failure('未记账:请指定分类');
        }
        final matched = await _findCategoryId(
            repo, categoryName, type == 'income' ? 'income' : 'expense');
        if (matched == null) {
          logger.warning('AppLink', '已拦截:分类「$categoryName」不存在');
          return AppLinkResult.failure('未记账:分类「$categoryName」不存在');
        }
      }

      // —— 参数齐全:自动记账(原逻辑)——
      final txParams = AddTransactionParams.fromQueryParams(params);

      // 解析分类
      int? categoryId;
      if (txParams.category != null) {
        categoryId = await _findCategoryId(
          repo,
          txParams.category!,
          txParams.type == 'income' ? 'income' : 'expense',
        );
      }

      // 解析账户（不存在则自动创建）
      int? accountId;
      if (txParams.account != null) {
        accountId = await _findOrCreateAccountId(repo, txParams.account!, ledgerId);
      }

      // 解析转入账户（不存在则自动创建）
      int? toAccountId;
      if (txParams.type == 'transfer' && txParams.toAccount != null) {
        toAccountId = await _findOrCreateAccountId(repo, txParams.toAccount!, ledgerId);
      }

      // 创建交易
      final transactionId = await repo.addTransaction(
        ledgerId: ledgerId,
        type: txParams.type,
        amount: txParams.amount!.abs(),
        categoryId: categoryId,
        accountId: accountId,
        toAccountId: toAccountId,
        happenedAt: txParams.date ?? DateTime.now(),
        note: txParams.note,
      );

      // 关联标签
      if (txParams.tags != null && txParams.tags!.isNotEmpty) {
        final tagIds = <int>[];
        for (final tagName in txParams.tags!) {
          final tag = await repo.getTagByName(tagName);
          if (tag != null) {
            tagIds.add(tag.id);
          } else {
            // 创建新标签
            final newTagId = await repo.createTag(name: tagName);
            tagIds.add(newTagId);
          }
        }
        if (tagIds.isNotEmpty) {
          await repo.updateTransactionTags(
            transactionId: transactionId,
            tagIds: tagIds,
          );
        }
      }

      logger.info('AppLink', '自动记账成功: id=$transactionId, amount=${txParams.amount}');

      // 统一后处理：刷新UI + 触发云同步
      final hasTags = txParams.tags != null && txParams.tags!.isNotEmpty;
      await PostProcessor.runC(_container, ledgerId: ledgerId, tags: hasTags);

      if (!txParams.silent) {
        final typeText = txParams.type == 'income' ? '收入' : (txParams.type == 'transfer' ? '转账' : '支出');
        onShowToast?.call('已记录 $typeText ${txParams.amount!.toStringAsFixed(2)} 元');
      }

      return AppLinkResult.success(
        message: '记账成功',
        transactionId: transactionId,
      );
    } on ArgumentError catch (e) {
      logger.warning('AppLink', '参数错误: $e');
      return AppLinkResult.failure('参数错误: ${e.message}');
    } catch (e, st) {
      logger.error('AppLink', '自动记账失败', e, st);
      return AppLinkResult.failure('记账失败: $e');
    }
  }

  /// 从持久化恢复上次选中的账本 id。
  ///
  /// 冷启动通过 deep-link 触发记账时,Splash 的 `_currentLedgerPersist` 恢复
  /// 逻辑可能还没跑完(它是 fire-and-forget,不被 await),currentLedgerId 还
  /// 停在默认值 1。这里显式、幂等地校准一次,确保记到用户真正选中的账本。
  Future<void> _restoreCurrentLedgerId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt('current_ledger_id');
      if (saved != null &&
          _container.read(currentLedgerIdProvider) != saved) {
        _container.read(currentLedgerIdProvider.notifier).state = saved;
      }
    } catch (_) {
      // 恢复失败不致命,退回当前(可能为默认)账本。
    }
  }

  /// 处理 SwipeSmart「一键记账」深链（quick-add）
  ///
  /// 与 [_handleAddTransaction] 唯一的本质差异：只反查信用卡账户/分类、打开
  /// 预填好的新增交易表单（通过 [onNavigate] 回调），**不**调用
  /// `repo.addTransaction`——quick-add 只开表单不落地写入，由用户确认后自己
  /// 按存。详见设计文档
  /// `docs/superpowers/specs/2026-09-02-swipesmart-quickadd-deeplink-design.md`。
  Future<AppLinkResult> _handleQuickAdd(Map<String, String> params) async {
    // 冷启动早期账本可能还没从 SharedPreferences 恢复,比照 _handleAddTransaction
    // 先显式校准一次。
    await _restoreCurrentLedgerId();
    final currentLedger = await _container.read(currentLedgerProvider.future);
    if (currentLedger == null) {
      logger.warning('AppLink', 'quick-add 失败: 未找到当前账本');
      return AppLinkResult.failure('请先选择账本');
    }

    final repo = _container.read(repositoryProvider);

    final merchant = params['merchant'];
    final categoryRaw = params['category'];
    final cardId = params['cardId'] ?? '';
    final bankName = params['bankName'] ?? '';
    final cardName = params['cardName'] ?? '';

    // 金额:能解析且 > 0 才带入,否则留空由用户自己输入,不挡流程(比照网页版
    // Number.isFinite(amountNum) && amountNum > 0 的宽容处理)。
    double? amount;
    final parsedAmount = double.tryParse(params['amount'] ?? '');
    if (parsedAmount != null && parsedAmount > 0) {
      amount = parsedAmount;
    }

    // 账户反查(比照网页版 findAccountBySwipesmartCardId):swipesmartCardId
    // 精确比对,只在信用卡、未隐藏账户里找。cardId 为空字符串时直接视为没对到。
    Account? account;
    if (cardId.isNotEmpty) {
      final accounts = await repo.getAllAccounts();
      for (final acc in accounts) {
        if (acc.type == 'credit_card' &&
            !acc.hidden &&
            acc.swipesmartCardId == cardId) {
          account = acc;
          break;
        }
      }
    }

    // 分类反查(比照网页版 matchCategoryByName,不沿用 _findCategoryId 的精确
    // 比对):只在支出分类里模糊比对,刚好一笔命中才采用。
    int? categoryId;
    if (categoryRaw != null && categoryRaw.isNotEmpty) {
      categoryId = await _findCategoryIdFuzzy(repo, categoryRaw);
    }

    // note:只在账户没对到时才组,依序拼接分类提示/预估回馈/回馈率/绑定引导。
    String? note;
    if (account == null) {
      final clauses = <String>[];
      if (categoryId == null && categoryRaw != null && categoryRaw.isNotEmpty) {
        clauses.add('分类:$categoryRaw');
      }
      final rewardNum = double.tryParse(params['reward'] ?? '');
      if (rewardNum != null && rewardNum > 0) {
        clauses.add('预估回馈 ${rewardNum.toStringAsFixed(0)}');
      }
      final rateNum = double.tryParse(params['rate'] ?? '');
      if (rateNum != null && rateNum > 0) {
        clauses.add('回馈率 ${(rateNum * 100).toStringAsFixed(1)}%');
      }
      clauses.add('尚未绑定 BeeCount 账户，可至设置 → SwipeSmart 卡片对照手动绑定');
      note = 'SwipeSmart 建议刷:$bankName $cardName（${clauses.join('，')}）';
    }

    logger.info('AppLink',
        'quick-add: merchant=$merchant amount=$amount categoryId=$categoryId accountId=${account?.id}');

    onNavigate?.call(
      AppLinkAction.quickAdd,
      params: AddTransactionParams(
        amount: amount,
        merchant: merchant,
        categoryId: categoryId,
        accountId: account?.id,
        note: note,
      ),
    );
    return AppLinkResult.success(message: '打开预填记账表单');
  }

  /// 分类模糊比对(比照 SwipeSmart 网页版 matchCategoryByName):只在**支出**
  /// 分类里找(顶层 + 两层遍历子分类),名称正规化(trim + 小写 + 去空白)后用
  /// 「互相包含」比对,收集所有命中分类,刚好一笔才采用,0 笔或多笔都当没对到。
  Future<int?> _findCategoryIdFuzzy(BaseRepository repo, String rawName) async {
    String normalize(String s) =>
        s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

    final target = normalize(rawName);
    if (target.isEmpty) return null;

    final matches = <int>[];
    final topCats = await repo.getTopLevelCategories('expense');
    for (final cat in topCats) {
      final name = normalize(cat.name);
      if (name.isNotEmpty && (name.contains(target) || target.contains(name))) {
        matches.add(cat.id);
      }
      final subCats = await repo.getSubCategories(cat.id);
      for (final sub in subCats) {
        final subName = normalize(sub.name);
        if (subName.isNotEmpty &&
            (subName.contains(target) || target.contains(subName))) {
          matches.add(sub.id);
        }
      }
    }
    return matches.length == 1 ? matches.first : null;
  }

  /// 处理旧版文本自动记账
  Future<AppLinkResult> _handleAutoBilling(Map<String, String> params) async {
    String? text = params['text'];

    if (text != null && text.isNotEmpty) {
      // 将逗号还原为换行符
      text = text.replaceAll(',', '\n');
      logger.info('AppLink', '从URL参数读取文本，长度: ${text.length}');

      try {
        await _autoBillingService.processText(
          text,
          showNotification: true,
        );
        return AppLinkResult.success(message: '文本处理完成');
      } catch (e, st) {
        logger.error('AppLink', '文本记账失败', e, st);
        return AppLinkResult.failure('文本记账失败: $e');
      }
    } else {
      logger.warning('AppLink', 'auto-billing 未提供文本');
      return AppLinkResult.failure('未提供文本内容');
    }
  }

  /// 根据名称查找分类ID
  Future<int?> _findCategoryId(BaseRepository repo, String name, String kind) async {
    final categories = kind == 'income'
        ? await repo.getTopLevelCategories('income')
        : await repo.getTopLevelCategories('expense');

    for (final cat in categories) {
      if (cat.name == name) {
        return cat.id;
      }
      // 检查子分类
      final subCats = await repo.getSubCategories(cat.id);
      for (final sub in subCats) {
        if (sub.name == name) {
          return sub.id;
        }
      }
    }
    return null;
  }

  /// 根据名称查找账户ID，不存在则创建
  Future<int?> _findOrCreateAccountId(BaseRepository repo, String name, int ledgerId) async {
    final accounts = await repo.getAllAccounts();
    for (final acc in accounts) {
      if (acc.name == name) {
        return acc.id;
      }
    }
    // 账户不存在，自动创建
    logger.info('AppLink', '账户 "$name" 不存在，自动创建');
    final newAccountId = await repo.createAccount(
      ledgerId: ledgerId,
      name: name,
    );
    return newAccountId;
  }

  /// 释放资源
  void dispose() {
    _appIntentSubscription?.cancel();
    _appIntentSubscription = null;
    _autoBillingService.dispose();
  }
}

/// 生成 AppLink URL
class AppLinkBuilder {
  static const String scheme = 'beecount';

  /// 语音记账链接
  static String voice() => '$scheme://voice';

  /// 图片记账链接
  static String image() => '$scheme://image';

  /// 拍照记账链接
  static String camera() => '$scheme://camera';

  /// AI 小助手链接
  static String aiChat() => '$scheme://ai-chat';

  /// 新建支出记账链接
  static String newExpense() => '$scheme://new?type=expense';

  /// 新建收入记账链接
  static String newIncome() => '$scheme://new?type=income';

  /// 新建转账记账链接
  static String newTransfer() => '$scheme://new?type=transfer';

  /// 新建支出记账并预填分类链接（小组件「快速记账」点分类格用）
  static String newExpenseWithCategory(int categoryId) =>
      '$scheme://new?type=expense&category=$categoryId';

  /// 打开净资产（资产页）链接（小组件「净资产」卡片点击用）
  static String openAssets() => '$scheme://open?page=assets';

  /// 打开预算页链接（小组件「预算进度」卡片点击用）
  static String openBudget() => '$scheme://open?page=budget';

  /// 打开明细页链接（小组件「最近交易」卡片点击用）
  static String openDetail() => '$scheme://open?page=detail';

  /// 自动记账链接
  static String add({
    required double amount,
    String type = 'expense',
    String? category,
    String? note,
    String? account,
    String? toAccount,
    List<String>? tags,
    DateTime? date,
    bool silent = false,
  }) {
    final params = <String, String>{
      'amount': amount.toString(),
      'type': type,
    };

    if (category != null) params['category'] = category;
    if (note != null) params['note'] = note;
    if (account != null) params['account'] = account;
    if (toAccount != null) params['to_account'] = toAccount;
    if (tags != null && tags.isNotEmpty) params['tags'] = tags.join(',');
    if (date != null) params['date'] = date.toIso8601String();
    if (silent) params['silent'] = '1';

    final query = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return '$scheme://add?$query';
  }
}
