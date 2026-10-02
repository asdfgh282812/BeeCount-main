// 股票相關的意圖閘門(2026-10-03):買賣股票不是支出記帳,要回覆操作說明;
// 查詢句走查詢工具;原本的記帳快路徑不受影響。
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/ai/core/ai_extraction_context.dart';
import 'package:beecount/ai/core/ai_extraction_engine.dart';
import 'package:beecount/ai/core/bill_info.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/ai/ai_bookkeeper.dart';
import 'package:beecount/services/ai/ai_chat_intent.dart';
import 'package:beecount/services/ai/ai_chat_service.dart';
import 'package:beecount/services/ai/free_chat_router.dart';
import 'package:beecount/services/billing/bill_creation_service.dart';

class _SpyEngine implements AiExtractionEngine {
  bool called = false;

  @override
  Future<List<BillInfo>> extractFromText(String text, AiExtractionContext ctx,
      {String billGuard = ''}) async {
    called = true;
    return const [];
  }

  @override
  Future<List<BillInfo>> extractFromImage(File image, AiExtractionContext ctx,
      {String billGuard = ''}) async {
    called = true;
    return const [];
  }

  @override
  Future<AudioExtractionResult> extractFromAudio(
      File audio, AiExtractionContext ctx) async {
    called = true;
    return const AudioExtractionResult();
  }

  @override
  Future<String?> speechToText(File audio) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isStockTradeIntent', () {
    test('買進/賣出股票的陳述句', () {
      for (final s in [
        '買了 2330 十股',
        '賣出0050 100股',
        '今天買進台積電 5 股',
        '加碼 00878 一千股',
        'bought 10 shares of AAPL',
        'sold 5 shares AAPL',
        'buy 3 shares of VOO',
        '我買了零股 20 股',
      ]) {
        expect(isStockTradeIntent(s), isTrue, reason: s);
        expect(isTransactionIntent(s), isFalse, reason: '$s 不該走記帳快路徑');
      }
    });

    test('不是股票交易的句子不誤判', () {
      for (final s in [
        '買了杯咖啡 50',
        '午餐花了 120',
        '買了3張電影票 500',
        '股東大會買了便當 100',
        '買了一股腦的零食 300',
        '收到股利 5000', // 沒有買賣動詞(而且股利不是這個意圖要處理的)
      ]) {
        expect(isStockTradeIntent(s), isFalse, reason: s);
      }
    });

    test('查詢句先被查詢閘門擋掉,不算「要新增交易」', () {
      for (final s in [
        '我買了幾股台積電',
        '賣股賺多少',
        '今年買了哪些股票?',
        'how many shares did I buy',
      ]) {
        expect(isStockTradeIntent(s), isFalse, reason: s);
      }
    });

    test('一般記帳句仍走快路徑(迴歸)', () {
      expect(isTransactionIntent('買了杯奶茶 28'), isTrue);
      expect(isTransactionIntent('今天午餐花了 50'), isTrue);
    });
  });

  group('isStockAdviceQuestion', () {
    test('股票/投資詞 + 建議/風險詞同時出現才算', () {
      expect(isStockAdviceQuestion('我的股票要不要加碼'), isTrue);
      expect(isStockAdviceQuestion('幫我分析持股有什麼風險'), isTrue);
      expect(isStockAdviceQuestion('投資組合太集中嗎'), isTrue);
      expect(isStockAdviceQuestion('should I sell my stocks'), isTrue);
      expect(isStockAdviceQuestion('any advice on my portfolio'), isTrue);
    });

    test('一般問題不算', () {
      expect(isStockAdviceQuestion('我有幾股台積電'), isFalse);
      expect(isStockAdviceQuestion('這個月花多少'), isFalse);
      expect(isStockAdviceQuestion('有什麼建議可以省錢'), isFalse);
      expect(isStockAdviceQuestion('哈囉'), isFalse);
    });
  });

  group('AIChatService:買賣股票說明', () {
    late BeeDatabase db;
    late LocalRepository repo;
    late _SpyEngine engine;
    late int ledgerId;
    var routerCalls = 0;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = BeeDatabase.forTesting(NativeDatabase.memory());
      repo = LocalRepository(db);
      ledgerId = await repo.createLedger(name: 't');
      engine = _SpyEngine();
      routerCalls = 0;
    });

    tearDown(() async => db.close());

    AIChatService service(ChatFn chatFn) => AIChatService(
          repo: repo,
          bookkeeper: AiBookkeeper(
            repository: repo,
            engine: engine,
            persister: BillCreationService(repo),
          ),
          freeChatRouter: FreeChatRouter(
            repo: repo,
            chatFn: (p, {systemPrompt}) {
              routerCalls++;
              return chatFn(p, systemPrompt: systemPrompt);
            },
            now: () => DateTime(2026, 10, 3),
          ),
        );

    test('「買了 2330 十股」:不記帳、不呼叫 LLM,直接回做法', () async {
      final s = service((p, {systemPrompt}) async => 'should not be called');
      final r = await s.processMessage('買了 2330 十股', ledgerId: ledgerId);
      expect(r.type, 'text');
      expect(r.text, contains('不是支出記帳'));
      expect(r.text, contains('新增股票交易'));
      expect(r.text, contains('轉帳'));
      expect(engine.called, isFalse);
      expect(routerCalls, 0);
    });

    test('英文使用者回英文說明', () async {
      final s = service((p, {systemPrompt}) async => 'x');
      final r = await s.processMessage('bought 10 shares of AAPL',
          ledgerId: ledgerId, languageCode: 'en');
      expect(r.text, contains('not an expense'));
      expect(r.text, contains('investment account'));
      expect(engine.called, isFalse);
    });

    test('forceChat 時照舊交給 router(routing prompt 有同樣的規則)', () async {
      final s = service((p, {systemPrompt}) async =>
          '{"type":"answer","text":"買股票不是支出,請到投資頁新增"}');
      final r = await s.processMessage('買了 2330 十股',
          ledgerId: ledgerId, forceChat: true);
      expect(r.text, contains('不是支出'));
      expect(routerCalls, 1);
      expect(engine.called, isFalse);
    });

    test('查詢句仍進 router 走股票工具', () async {
      var n = 0;
      final s = service((p, {systemPrompt}) async {
        n++;
        if (n == 1) {
          return '{"type":"tool_call","tool":"stock_trades","params":{"limit":1}}';
        }
        return '目前沒有股票交易';
      });
      final r = await s.processMessage('我最近買了哪些股票', ledgerId: ledgerId);
      expect(r.text, '目前沒有股票交易');
      expect(routerCalls, 2);
    });
  });
}
