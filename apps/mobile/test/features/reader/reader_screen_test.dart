import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/core/theme/theme_mode_controller.dart';
import 'package:readme_ai/features/reader/application/reader_settings.dart';
import 'package:readme_ai/features/reader/application/reader_settings_controller.dart';

import '../../helpers/fake_reader_repository.dart';
import '../../helpers/pump_reader.dart';

void main() {
  testWidgets('renders readable text content', (tester) async {
    await pumpReader(tester, repository: FakeReaderRepository());

    expect(find.textContaining('bright cold day in April'), findsOneWidget);
    expect(find.text('Nineteen Eighty-Four'), findsOneWidget);
  });

  testWidgets('shows a limitation message for unsupported formats', (
    tester,
  ) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(
        content: FakeReaderRepository.unsupportedContent(),
      ),
    );

    expect(
      find.text("Preview isn't available for this file format yet."),
      findsOneWidget,
    );
  });

  testWidgets('reader settings adjust font size', (tester) async {
    final container = await pumpReader(
      tester,
      repository: FakeReaderRepository(),
    );
    final initial = container.read(readerSettingsProvider).fontSize;

    await tester.tap(find.byTooltip('Reader settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Increase Font size'));
    await tester.pumpAndSettle();

    expect(container.read(readerSettingsProvider).fontSize, initial + 2);
  });

  testWidgets('choosing the Night page switches to dark mode', (tester) async {
    final container = await pumpReader(
      tester,
      repository: FakeReaderRepository(),
    );

    await tester.tap(find.byTooltip('Reader settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Night'));
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  testWidgets('choosing a page tone applies it in light mode', (tester) async {
    final container = await pumpReader(
      tester,
      repository: FakeReaderRepository(),
    );
    container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);

    await tester.tap(find.byTooltip('Reader settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sepia'));
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(
      container.read(readerSettingsProvider).pageTone,
      ReaderPageTone.sepia,
    );
  });

  testWidgets('reader settings switch the typeface', (tester) async {
    final container = await pumpReader(
      tester,
      repository: FakeReaderRepository(),
    );
    expect(
      container.read(readerSettingsProvider).typeface,
      ReaderTypeface.serif,
    );

    await tester.tap(find.byTooltip('Reader settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sans'));
    await tester.pumpAndSettle();

    expect(
      container.read(readerSettingsProvider).typeface,
      ReaderTypeface.sans,
    );
  });

  testWidgets('bookmarking a position lists the new bookmark', (tester) async {
    await pumpReader(tester, repository: FakeReaderRepository());

    await tester.tap(find.byTooltip('Bookmark this position'));
    await tester.pump();

    await tester.tap(find.byTooltip('Bookmarks'));
    await tester.pumpAndSettle();

    expect(find.text('Bookmark'), findsOneWidget);

    // Drain the confirmation snackbar's auto-dismiss timer.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
