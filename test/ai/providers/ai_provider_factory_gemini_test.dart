import 'dart:convert';
import 'dart:io';

import 'package:beecount/ai/providers/ai_provider_config.dart';
import 'package:beecount/ai/providers/ai_provider_factory.dart';
import 'package:beecount/ai/providers/ai_provider_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  HttpOverrides.global = null;

  late HttpServer server;
  late AIServiceProviderConfig config;
  late List<Uri> requests;
  late List<Map<String, dynamic>> payloads;
  late List<String?> apiKeys;
  late Map<String, dynamic> responseBody;
  late int statusCode;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    requests = [];
    payloads = [];
    apiKeys = [];
    statusCode = 200;
    responseBody = {
      'candidates': [
        {
          'content': <String, dynamic>{
            'parts': [
              {'text': 'hello'},
            ],
          },
          'finishReason': 'STOP',
        },
      ],
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request.uri);
      apiKeys.add(request.headers.value('x-goog-api-key'));
      final body = await utf8.decoder.bind(request).join();
      payloads.add(jsonDecode(body) as Map<String, dynamic>);
      request.response.statusCode = statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(responseBody));
      await request.response.close();
    });
    config = AIServiceProviderConfig(
      id: 'gemini',
      name: 'Gemini',
      apiKey: 'test-key',
      apiFamily: 'gemini',
      baseUrl: 'http://127.0.0.1:${server.port}/v1beta//openai///',
      textModel: 'gemini-text',
      visionModel: 'gemini-vision',
      audioModel: 'gemini-audio',
      createdAt: DateTime(2026),
    );
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('all capability validations use native Gemini with header-only auth',
      () async {
    expect(
        await AIProviderFactory.validateTextCapability(config), (true, null));
    expect(
        await AIProviderFactory.validateVisionCapability(config), (true, null));
    expect(
        await AIProviderFactory.validateSpeechCapability(config), (true, null));

    expect(requests.map((uri) => uri.path), [
      '/v1beta/models/gemini-text:generateContent',
      '/v1beta/models/gemini-vision:generateContent',
      '/v1beta/models/gemini-audio:generateContent',
    ]);
    expect(requests.every((uri) => !uri.hasQuery), isTrue);
    expect(apiKeys, everyElement('test-key'));
    expect(payloads.every((body) => !body.containsKey('messages')), isTrue);
    final image = payloads[1]['contents'][0]['parts'][1]['inlineData'];
    final audio = payloads[2]['contents'][0]['parts'][1]['inlineData'];
    expect(image['mimeType'], 'image/jpeg');
    expect(audio['mimeType'], 'audio/wav');
    expect(base64Decode(image['data'] as String), isNotEmpty);
    expect(base64Decode(audio['data'] as String).take(4), [82, 73, 70, 70]);
    expect(payloads[2]['generationConfig']['temperature'], 0.0);
  });

  test('bound runtime calls persist Gemini family and send native payloads',
      () async {
    final saved = await AIProviderManager.addProvider(
      name: config.name,
      apiKey: config.apiKey,
      baseUrl: config.baseUrl,
      apiFamily: config.apiFamily,
      textModel: config.textModel,
      visionModel: config.visionModel,
      audioModel: config.audioModel,
    );
    expect(
        (await AIProviderManager.getProvider(saved.id))!.apiFamily, 'gemini');
    await AIProviderManager.saveCapabilityBinding(AICapabilityBinding(
      textProviderId: saved.id,
      visionProviderId: saved.id,
      speechProviderId: saved.id,
    ));
    final directory = await Directory.systemTemp.createTemp('gemini_test_');
    addTearDown(() => directory.delete(recursive: true));
    final image =
        await File('${directory.path}/image.png').writeAsBytes([1, 2]);
    final audio =
        await File('${directory.path}/audio.wav').writeAsBytes([3, 4]);
    responseBody['candidates'][0]['content']['parts'] = [
      {'text': 'internal', 'thought': true},
      {'text': 'hello'},
      {'text': ' world'},
    ];

    expect(
      await AIProviderFactory.chat('prompt',
          systemPrompt: 'system', temperature: 0.4),
      'hello world',
    );
    expect(
        await AIProviderFactory.vision(image, 'image prompt'), 'hello world');
    expect(await AIProviderFactory.speechToText(audio), 'hello world');
    expect(payloads[0]['systemInstruction'], {
      'parts': [
        {'text': 'system'}
      ],
    });
    expect(payloads[0]['generationConfig']['temperature'], 0.4);
    expect(payloads[1].containsKey('systemInstruction'), isFalse);
    expect(payloads[1]['contents'][0]['parts'][1]['inlineData'], {
      'mimeType': 'image/png',
      'data': base64Encode([1, 2]),
    });
    expect(
        requests.every((uri) => uri.path.endsWith(':generateContent')), isTrue);
  });

  for (final parts in <List<Map<String, dynamic>>?>[
    null,
    [],
    [
      {'text': ''}
    ],
    [
      {
        'inlineData': {'mimeType': 'audio/wav', 'data': ''}
      }
    ],
  ]) {
    test('silent audio accepts empty or non-text parts: $parts', () async {
      responseBody['candidates'][0]['content'] = {
        if (parts != null) 'parts': parts,
      };
      expect(await AIProviderFactory.validateSpeechCapability(config),
          (true, null));
      expect(
          (await AIProviderFactory.validateTextCapability(config)).$1, isFalse);
      expect((await AIProviderFactory.validateVisionCapability(config)).$1,
          isFalse);
    });
  }

  test('empty candidates are safe and silent audio remains valid', () async {
    responseBody = {'candidates': []};
    expect(
        await AIProviderFactory.validateSpeechCapability(config), (true, null));
    expect(
        (await AIProviderFactory.validateTextCapability(config)).$1, isFalse);
  });

  test('blocked candidate is not treated as silent audio', () async {
    responseBody['candidates'][0]['finishReason'] = 'SAFETY';
    final result = await AIProviderFactory.validateSpeechCapability(config);
    expect(result.$1, isFalse);
    expect(result.$2, contains('SAFETY'));
  });

  test('blocked prompt without candidates is reported safely', () async {
    responseBody = {
      'promptFeedback': {'blockReason': 'SAFETY'}
    };
    final result = await AIProviderFactory.validateSpeechCapability(config);
    expect(result.$1, isFalse);
    expect(result.$2, contains('SAFETY'));
  });

  test('malformed success body is not accepted as silent audio', () async {
    responseBody = {};
    expect(
        (await AIProviderFactory.validateSpeechCapability(config)).$1, isFalse);
  });

  test('Google error code, status and message are preserved', () async {
    statusCode = 400;
    responseBody = {
      'error': {
        'code': 400,
        'message': 'Unsupported audio format',
        'status': 'INVALID_ARGUMENT',
      },
    };
    final result = await AIProviderFactory.validateSpeechCapability(config);
    expect(result, (false, '[400] INVALID_ARGUMENT: Unsupported audio format'));
  });

  test('normalizes native models base, model prefix and removes URL secrets',
      () async {
    final result =
        await AIProviderFactory.validateTextCapability(config.copyWith(
      baseUrl:
          'http://127.0.0.1:${server.port}/v1beta/models/?key=old-key#fragment',
      textModel: 'models/gemini-text',
    ));
    expect(result, (true, null));
    expect(requests.single.toString(),
        '/v1beta/models/gemini-text:generateContent');
    expect(apiKeys.single, 'test-key');
  });

  test('OpenAI family retains chat completions and Bearer authentication',
      () async {
    responseBody = {
      'choices': [
        {
          'message': {'content': 'hello'}
        },
      ],
    };
    final result =
        await AIProviderFactory.validateTextCapability(config.copyWith(
      apiFamily: 'openai',
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
    ));
    expect(result, (true, null));
    expect(requests.single.path, '/v1/chat/completions');
    expect(apiKeys.single, isNull);
    expect(payloads.single['model'], config.textModel);
    expect(payloads.single['messages'][0]['content'], 'hi');
  });
}
