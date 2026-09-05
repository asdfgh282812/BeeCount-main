import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/providers/theme_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('无本机存储时预设为 false(动画正常播放)', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(reduceMotionProvider), false);
  });

  test('reduceMotionInitProvider 从本机存储读回 true', () async {
    SharedPreferences.setMockInitialValues({'reduceMotion': true});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(reduceMotionInitProvider.future);
    expect(container.read(reduceMotionProvider), true);
  });

  test('变更后持久化到 SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(reduceMotionInitProvider.future);

    container.read(reduceMotionProvider.notifier).state = true;
    await pumpEventQueue();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('reduceMotion'), true);
  });
}
