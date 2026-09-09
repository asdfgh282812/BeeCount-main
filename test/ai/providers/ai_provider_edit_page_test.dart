import 'package:beecount/ai/providers/ai_provider_config.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/ai/ai_provider_manage_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpEditor(
    WidgetTester tester, {
    AIServiceProviderConfig? provider,
  }) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AIProviderEditPage(provider: provider),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Gemini selection fills native base and updates all model hints',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpEditor(tester);
    await tester.tap(find.text('Gemini 原生體系'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final base = find.byWidgetPredicate((widget) =>
        widget is TextField && widget.decoration?.labelText == 'Base URL');
    expect(tester.widget<TextField>(base).controller!.text,
        'https://generativelanguage.googleapis.com/v1beta');
    final models = find.byWidgetPredicate((widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'gemini-3.5-flash');
    expect(models, findsNWidgets(3));
    expect(
        tester
            .widgetList<TextField>(models)
            .every((field) => field.controller!.text.isEmpty),
        isTrue);

    await tester.tap(find.text('OpenAI 體系'));
    await tester.pumpAndSettle();
    expect(models, findsNothing);
  });

  testWidgets('editing preserves family and user-provided URL and models',
      (tester) async {
    final config = AIServiceProviderConfig(
      id: 'custom',
      name: 'Custom',
      apiFamily: 'gemini',
      baseUrl: 'https://proxy.example/v1beta',
      audioModel: 'custom-model',
      createdAt: DateTime(2026),
    );
    await pumpEditor(tester, provider: config);
    expect(
        tester
            .widget<SegmentedButton<String>>(
                find.byType(SegmentedButton<String>))
            .selected,
        {'gemini'});
    await tester.tap(find.text('OpenAI 體系'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gemini 原生體系'));
    await tester.pumpAndSettle();
    expect(find.text('https://proxy.example/v1beta'), findsOneWidget);
    expect(find.text('custom-model'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('built-in provider does not expose API family switch',
      (tester) async {
    await pumpEditor(tester, provider: AIServiceProviderConfig.zhipuDefault);
    expect(find.byType(SegmentedButton<String>), findsNothing);
  });
}
