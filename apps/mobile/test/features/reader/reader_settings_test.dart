import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/core/storage/preferences_store.dart';
import 'package:readme_ai/core/theme/app_colors.dart';
import 'package:readme_ai/core/theme/theme_mode_controller.dart';
import 'package:readme_ai/features/reader/application/reader_settings.dart';
import 'package:readme_ai/features/reader/application/reader_settings_controller.dart';
import 'package:readme_ai/features/reader/presentation/widgets/explainable_text.dart';

import '../../helpers/fake_reader_repository.dart';
import '../../helpers/pump_reader.dart';

ProviderContainer _container(PreferencesStore store) {
  final container = ProviderContainer(
    overrides: [preferencesStoreProvider.overrideWithValue(store)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('reader settings survive a restart', () {
    final store = InMemoryPreferencesStore();
    final first = _container(store);
    first.read(readerSettingsProvider.notifier)
      ..increaseFontSize()
      ..increaseLineHeight()
      ..setFont(ReaderFont.sans)
      ..setSepia(enabled: true);

    // A fresh container stands in for the next launch.
    final restored = _container(store).read(readerSettingsProvider);

    expect(restored.fontSize, 20);
    expect(restored.lineHeight, 1.8);
    expect(restored.font, ReaderFont.sans);
    expect(restored.sepia, isTrue);
  });

  test('theme mode survives a restart', () {
    final store = InMemoryPreferencesStore();
    _container(store).read(themeModeProvider.notifier).setMode(ThemeMode.dark);

    expect(_container(store).read(themeModeProvider), ThemeMode.dark);
  });

  test('corrupt or out-of-range stored values fall back safely', () {
    final store = InMemoryPreferencesStore({
      'reader.font_size': '999',
      'reader.line_height': 'abc',
      'reader.font': 'comic-sans',
      'theme_mode': 'purple',
    });
    final container = _container(store);

    final settings = container.read(readerSettingsProvider);
    expect(settings.fontSize, ReaderSettings.maxFontSize);
    expect(settings.lineHeight, const ReaderSettings().lineHeight);
    expect(settings.font, ReaderFont.serif);
    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('line height steps do not accumulate floating-point drift', () {
    final controller = _container(
      InMemoryPreferencesStore(),
    ).read(readerSettingsProvider.notifier);
    for (var i = 0; i < 3; i++) {
      controller.increaseLineHeight();
    }

    expect(controller.state.lineHeight, 2.2);
  });

  testWidgets('choosing sepia warms the page and keeps the light theme', (
    tester,
  ) async {
    final container = await pumpReader(
      tester,
      repository: FakeReaderRepository(),
    );

    await tester.tap(find.byTooltip('Reader settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sepia'));
    await tester.pumpAndSettle();

    expect(container.read(readerSettingsProvider).sepia, isTrue);
    expect(container.read(themeModeProvider), ThemeMode.light);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, AppColors.sepiaCanvas);
  });

  testWidgets('book text uses the serif reading font by default', (
    tester,
  ) async {
    await pumpReader(tester, repository: FakeReaderRepository());

    final text = tester.widget<ExplainableText>(find.byType(ExplainableText));
    expect(text.style.fontFamily, 'Lora');
  });

  testWidgets('the settings sheet fits a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpReader(tester, repository: FakeReaderRepository());
    await tester.tap(find.byTooltip('Reader settings'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Sepia'), findsOneWidget);
  });
}
