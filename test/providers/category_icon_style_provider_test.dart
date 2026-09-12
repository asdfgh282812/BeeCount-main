import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:beecount/providers/theme_providers.dart';

void main() {
  // select() 现在会尝试推播到云端(见 theme_providers.dart),推播路径会碰
  // logger 单例的原生桥接初始化,没有这行会在纯 test() 环境下断言失败——
  // 跟 reduce_motion_provider_test.dart 的写法保持一致。
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('categoryIconStyleProvider defaults to material', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
        container.read(categoryIconStyleProvider), CategoryIconStyle.material);
  });

  test('select(cute) updates state and persists across a fresh container',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(categoryIconStyleProvider.notifier)
        .select(CategoryIconStyle.cute);
    expect(container.read(categoryIconStyleProvider), CategoryIconStyle.cute);

    // Simulate app relaunch: a fresh container should load the persisted value.
    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    // Riverpod providers are lazy — reading once instantiates the notifier
    // (and kicks off its async _load()); only then is there anything to wait on.
    container2.read(categoryIconStyleProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container2.read(categoryIconStyleProvider), CategoryIconStyle.cute);
  });
}
