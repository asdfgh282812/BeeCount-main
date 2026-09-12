import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:beecount/providers/theme_providers.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('categoryIconStyleProvider defaults to material', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(categoryIconStyleProvider), CategoryIconStyle.material);
  });

  test('select(cute) updates state and persists across a fresh container', () async {
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
