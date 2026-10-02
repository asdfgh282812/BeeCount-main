// FreeChatRouter 的股票面向(2026-10-03):工具解析、routing/answer prompt 規則、
// 免責聲明、工具結果截斷、context 帶入投資帳戶與持有標的。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/base_repository.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/ai/free_chat_context.dart';
import 'package:beecount/services/ai/free_chat_router.dart';
import 'package:beecount/services/ai/free_chat_stock_tools.dart';
import 'package:beecount/services/ai/free_chat_tools.dart';

/// 不管叫什麼工具都回一個超大結果,驗證 router 的 payload 截斷保險。
class _HugeExecutor extends FreeChatToolExecutor {
  const _HugeExecutor();

  @override
  Future<Map<String, dynamic>> execute(
    String toolName,
    Map<String, dynamic> params, {
    required BaseRepository repo,
    required int ledgerId,
    DateTime Function()? now,
    StockPendingDividendsLoader? pendingDividends,
  }) async =>
      {'blob': 'x' * 100000};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;
  final fixedNow = DateTime(2026, 10, 3, 12);

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency, sync_id) VALUES (1, 'L', 'TWD', 'lg1')");
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, type, currency, sync_id) VALUES "
        "(1, 1, '交割戶', 'bank_card', 'TWD', 'acc_bank'), "
        "(2, 1, '永豐證券', 'investment', 'TWD', 'acc_inv')");
  });

  tearDown(() async => db.close());

  Future<void> seedTsmc() async {
    await repo.createStockTrade(
      ledgerId: 1,
      accountId: 2,
      tradeType: 'buy',
      market: 'TW',
      symbol: '2330',
      securityName: '台積電',
      shares: 1000,
      price: 600,
      fee: 855,
      tradeDate: DateTime(2026, 1, 10, 12),
      settlementAccountId: 1,
    );
  }

  FreeChatRouter routerWith(ChatFn chatFn,
          {FreeChatToolExecutor executor = const FreeChatToolExecutor(),
          StockPendingDividendsLoader? pending}) =>
      FreeChatRouter(
        repo: repo,
        chatFn: chatFn,
        executor: executor,
        now: () => fixedNow,
        pendingDividends: pending,
      );

  String text(FreeChatOutcome o) {
    expect(o, isA<FreeChatAnswer>());
    return (o as FreeChatAnswer).text;
  }

  test('stock_holdings tool_call:工具結果(含報價與口徑)進 answer prompt', () async {
    await seedTsmc();
    final prompts = <String>[];
    final systems = <String?>[];
    final router = routerWith((prompt, {systemPrompt}) async {
      prompts.add(prompt);
      systems.add(systemPrompt);
      if (prompts.length == 1) {
        return '{"type":"tool_call","tool":"stock_holdings","params":{"symbol":"台積電"}}';
      }
      return '你持有台積電 1,000 股';
    });

    final out = text(await router.route('我有幾股台積電', ledgerId: 1));

    expect(out, '你持有台積電 1,000 股');
    expect(prompts, hasLength(2));
    expect(prompts[1], contains('"holdingCount":1'));
    expect(prompts[1], contains('"symbol":"2330"'));
    expect(prompts[1], contains('"available":false')); // 沒有報價也要明講
    // answer 階段帶股票回答規則
    expect(systems[1], contains('股票回答規則'));
    expect(systems[1], contains('各幣別分開'));
    expect(systems[1], contains('不要編造'));
  });

  test('只呼叫記帳工具時 answer prompt 不帶股票規則(省 token)', () async {
    final systems = <String?>[];
    var n = 0;
    final router = routerWith((prompt, {systemPrompt}) async {
      systems.add(systemPrompt);
      n++;
      if (n == 1) {
        return '{"type":"tool_call","tool":"get_spending_summary","params":{}}';
      }
      return '共花 0 元';
    });
    await router.route('這個月花多少', ledgerId: 1);
    expect(systems[1], isNot(contains('股票回答規則')));
  });

  test('tools 陣列同時跑多個股票工具,也受 maxToolsPerTurn 限制', () async {
    await seedTsmc();
    final prompts = <String>[];
    final router = routerWith((prompt, {systemPrompt}) async {
      prompts.add(prompt);
      if (prompts.length == 1) {
        return '{"type":"tool_call","tools":['
            '{"tool":"stock_performance","params":{}},'
            '{"tool":"stock_holdings","params":{}},'
            '{"tool":"stock_trades","params":{"limit":1}},'
            '{"tool":"stock_settings","params":{}}]}';
      }
      return '好';
    });
    await router.route('我股票賺還是賠', ledgerId: 1);
    expect(prompts[1], contains('"tool":"stock_performance"'));
    expect(prompts[1], contains('"tool":"stock_holdings"'));
    expect(prompts[1], contains('"tool":"stock_trades"'));
    expect(prompts[1], isNot(contains('"tool":"stock_settings"')));
  });

  test('股票工具參數錯誤(日期格式)→ 該工具帶 error,全部失敗才降級', () async {
    await seedTsmc();
    final prompts = <String>[];
    final router = routerWith((prompt, {systemPrompt}) async {
      prompts.add(prompt);
      if (prompts.length == 1) {
        return '{"type":"tool_call","tools":['
            '{"tool":"stock_trades","params":{"startDate":"昨天"}},'
            '{"tool":"stock_holdings","params":{}}]}';
      }
      return '持股如下';
    });
    final out = text(await router.route('看一下', ledgerId: 1));
    expect(out, '持股如下');
    expect(prompts[1], contains('"error"'));
    expect(prompts[1], contains('"holdingCount":1'));

    final router2 = routerWith((prompt, {systemPrompt}) async =>
        '{"type":"tool_call","tool":"stock_trades","params":{"tradeType":"gift"}}');
    expect(text(await router2.route('x', ledgerId: 1)), contains('暫時處理不了'));
  });

  test('routing prompt:列出全部股票工具、股票規則、買賣意圖說明', () async {
    String? system;
    final router = routerWith((prompt, {systemPrompt}) async {
      system ??= systemPrompt;
      return '{"type":"answer","text":"好"}';
    });
    await router.route('嗨', ledgerId: 1);
    for (final tool in [
      'stock_holdings',
      'stock_trades',
      'stock_realized_pnl',
      'stock_dividends',
      'stock_settings',
      'stock_dca_plans',
      'stock_performance',
      'stock_portfolio_analysis',
    ]) {
      expect(system, contains('- $tool:'));
    }
    expect(system, contains('股票相關規則'));
    expect(system, contains('不要用 query_transactions'));
    expect(system, contains('不要用 record_transaction'));
    expect(system, contains('新增股票交易'));
    expect(system, contains('stock_portfolio_analysis'));
    expect(system, contains('"year":2026')); // 範例帶入今年
  });

  test('routing prompt 英文版也帶股票規則', () async {
    String? system;
    final router = routerWith((prompt, {systemPrompt}) async {
      system ??= systemPrompt;
      return '{"type":"answer","text":"ok"}';
    });
    await router.route('hi', ledgerId: 1, languageCode: 'en');
    expect(system, contains('Stock rules'));
    expect(system, contains('NEVER use query_transactions'));
  });

  test('routing prompt 帶入投資帳戶與交易過的股票(持有中的在前)', () async {
    await seedTsmc();
    await repo.createStockTrade(
      ledgerId: 1,
      accountId: 2,
      tradeType: 'opening',
      market: 'TW',
      symbol: '0050',
      securityName: '元大台灣50',
      shares: 10,
      price: 100,
      tradeDate: DateTime(2026, 1, 1, 12),
    );
    await repo.createStockTrade(
      ledgerId: 1,
      accountId: 2,
      tradeType: 'opening',
      market: 'TW',
      symbol: '1101',
      securityName: '台泥',
      shares: 10,
      price: 40,
      tradeDate: DateTime(2026, 1, 1, 12),
    );
    await repo.createStockTrade(
      ledgerId: 1,
      accountId: 2,
      tradeType: 'sell',
      market: 'TW',
      symbol: '1101',
      shares: 10,
      price: 45,
      tradeDate: DateTime(2026, 2, 1, 12),
      settlementAccountId: 1,
    );
    String? system;
    final router = routerWith((prompt, {systemPrompt}) async {
      system ??= systemPrompt;
      return '{"type":"answer","text":"好"}';
    });
    await router.route('嗨', ledgerId: 1);
    expect(system, contains('投資理財帳戶(股票工具用):永豐證券'));
    expect(system, contains('2330 台積電'));
    expect(system, contains('0050 元大台灣50'));
    // 已出清的 1101 排在持有中的後面
    final line = system!
        .split('\n')
        .firstWhere((l) => l.startsWith('交易過的股票'));
    expect(line.indexOf('1101'), greaterThan(line.indexOf('2330')));
  });

  test('FreeChatContext:沒有投資帳戶時不讀股票明細、不加兩行', () async {
    await db.customStatement("DELETE FROM accounts WHERE type = 'investment'");
    final ctx = await FreeChatContext.forLedger(repo: repo);
    expect(ctx.investmentAccountNames, isEmpty);
    expect(ctx.securities, isEmpty);
    expect(ctx.toPromptSection(isEn: false), isNot(contains('投資理財帳戶')));
  });

  test('FreeChatContext:標的清單最多 maxSecurities 檔', () async {
    for (var i = 0; i < FreeChatContext.maxSecurities + 5; i++) {
      await repo.createStockTrade(
        ledgerId: 1,
        accountId: 2,
        tradeType: 'opening',
        market: 'TW',
        symbol: '${4000 + i}',
        shares: 1,
        price: 10,
        tradeDate: DateTime(2026, 1, 1, 12),
      );
    }
    final ctx = await FreeChatContext.forLedger(repo: repo);
    expect(ctx.securities.length, FreeChatContext.maxSecurities + 5);
    final section = ctx.toPromptSection(isEn: false);
    final line =
        section.split('\n').firstWhere((l) => l.startsWith('交易過的股票'));
    expect(line, endsWith('…'));
    expect('、'.allMatches(line).length, FreeChatContext.maxSecurities - 1);
  });

  group('免責聲明', () {
    test('stock_portfolio_analysis:模型漏寫時 router 補上', () async {
      await seedTsmc();
      var n = 0;
      final router = routerWith((prompt, {systemPrompt}) async {
        n++;
        if (n == 1) {
          return '{"type":"tool_call","tool":"stock_portfolio_analysis","params":{}}';
        }
        return '你的持股集中在台積電。';
      });
      final out = text(await router.route('幫我看看持股', ledgerId: 1));
      expect(out, startsWith('你的持股集中在台積電。'));
      expect(out, endsWith(FreeChatRouter.stockDisclaimerZh));
    });

    test('模型已寫免責聲明就不重複', () async {
      await seedTsmc();
      var n = 0;
      final router = routerWith((prompt, {systemPrompt}) async {
        n++;
        if (n == 1) {
          return '{"type":"tool_call","tool":"stock_portfolio_analysis","params":{}}';
        }
        return '集中度偏高。以上內容僅供參考,非投資建議,不構成任何買賣推薦。';
      });
      final out = text(await router.route('幫我分析持股', ledgerId: 1));
      expect('非投資建議'.allMatches(out).length, 1);
    });

    test('英文使用者補英文聲明', () async {
      await seedTsmc();
      var n = 0;
      final router = routerWith((prompt, {systemPrompt}) async {
        n++;
        if (n == 1) {
          return '{"type":"tool_call","tool":"stock_portfolio_analysis","params":{}}';
        }
        return 'Your holdings are concentrated.';
      });
      final out = text(await router.route('analyze my portfolio',
          ledgerId: 1, languageCode: 'en'));
      expect(out, endsWith(FreeChatRouter.stockDisclaimerEn));
    });

    test('routing 階段直接 answer 的投資建議問題也補聲明;一般問題不補', () async {
      final router = routerWith((prompt, {systemPrompt}) async =>
          '{"type":"answer","text":"我無法替你決定,但可以看你的持股結構。"}');
      var out = text(await router.route('我的股票要不要加碼', ledgerId: 1));
      expect(out, endsWith(FreeChatRouter.stockDisclaimerZh));

      out = text(await router.route('哈囉', ledgerId: 1));
      expect(out, isNot(contains('非投資建議')));
    });

    test('非建議類的股票查詢(只查持股)不附聲明', () async {
      await seedTsmc();
      var n = 0;
      final router = routerWith((prompt, {systemPrompt}) async {
        n++;
        if (n == 1) {
          return '{"type":"tool_call","tool":"stock_holdings","params":{}}';
        }
        return '你持有台積電 1,000 股';
      });
      final out = text(await router.route('我有哪些股票', ledgerId: 1));
      expect(out, '你持有台積電 1,000 股');
    });
  });

  test('工具結果超過上限時截斷並註明', () async {
    final prompts = <String>[];
    final router = routerWith(
      (prompt, {systemPrompt}) async {
        prompts.add(prompt);
        if (prompts.length == 1) {
          return '{"type":"tool_call","tool":"stock_holdings","params":{}}';
        }
        return '好';
      },
      executor: const _HugeExecutor(),
    );
    await router.route('持股', ledgerId: 1);
    expect(prompts[1].length, lessThan(FreeChatRouter.maxPayloadChars + 500));
    expect(prompts[1], contains('已截斷'));
  });

  test('待確認股利 loader 一路傳到 stock_dividends', () async {
    await seedTsmc();
    final prompts = <String>[];
    final router = routerWith(
      (prompt, {systemPrompt}) async {
        prompts.add(prompt);
        if (prompts.length == 1) {
          return '{"type":"tool_call","tool":"stock_dividends","params":{}}';
        }
        return '有一筆待確認';
      },
      pending: () async => [
        {
          'accountName': '永豐證券',
          'market': 'TW',
          'symbol': '2330',
          'exDate': '2026-09-18',
          'estNet': 3000.0,
          'status': 'pending',
        },
      ],
    );
    await router.route('有沒有待確認的股利', ledgerId: 1);
    expect(prompts[1], contains('"available":true'));
    expect(prompts[1], contains('"estNet":3000.0'));
  });
}
