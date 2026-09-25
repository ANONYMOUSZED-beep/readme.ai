import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/core/theme/theme_mode_controller.dart';
import 'package:readme_ai/features/reader/application/reader_settings.dart';
import 'package:readme_ai/features/reader/application/reader_settings_controller.dart';
import 'package:readme_ai/features/reader/domain/book_content.dart';
import 'package:readme_ai/features/reader/domain/chapter_mark.dart';
import 'package:readme_ai/features/reader/domain/content_format.dart';
import 'package:readme_ai/features/reader/domain/reading_progress.dart';
import 'package:readme_ai/features/reader/presentation/reader_screen.dart';
import 'package:readme_ai/l10n/generated/app_localizations.dart';

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

    expect(find.text("This book isn't ready to read."), findsOneWidget);
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

  testWidgets('leaving right after scrolling still saves the position', (
    tester,
  ) async {
    final repository = FakeReaderRepository(
      content: FakeReaderRepository.textContent(text: _longText),
    );
    await pumpReader(tester, repository: repository);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -600),
    );
    // Leave before the 1.2s save debounce fires.
    await tester.pump(const Duration(milliseconds: 200));
    expect(repository.lastSaved, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    // Let the final save finish refreshing the providers it touches.
    await tester.pumpAndSettle();

    final saved = repository.lastSaved;
    expect(saved, isNotNull);
    expect(saved!.progressPercentage, greaterThan(0));
    expect(int.parse(saved.currentPosition), greaterThan(0));
  });

  testWidgets('leaving before the saved position loads does not reset it', (
    tester,
  ) async {
    final repository = _SlowProgressRepository(
      content: FakeReaderRepository.textContent(text: _longText),
    );
    await pumpReader(tester, repository: repository);

    await tester.pumpWidget(const SizedBox.shrink());

    expect(repository.lastSaved, isNull);
    repository.release.complete();
  });
  testWidgets('contents lists chapters and jumps to the chosen one', (
    tester,
  ) async {
    await pumpReader(
      tester,
      repository: FakeReaderRepository(content: _chaptered()),
    );

    await tester.tap(find.byTooltip('Contents'));
    await tester.pumpAndSettle();

    expect(find.text('Beginnings'), findsOneWidget);
    expect(find.text('Chapter 2'), findsOneWidget);
    await tester.tap(find.text('Endings'));
    await tester.pumpAndSettle();

    expect(find.text('Beginnings'), findsNothing); // sheet closed
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.pixels, greaterThan(position.maxScrollExtent * 0.5));

    // Leaving saves the new position; let that save settle.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a book with a single chapter has no contents button', (
    tester,
  ) async {
    await pumpReader(tester, repository: FakeReaderRepository());

    expect(find.byTooltip('Contents'), findsNothing);
  });

  testWidgets('reopening a book fetches its latest saved position', (
    tester,
  ) async {
    final repository = FakeReaderRepository();
    final container = await pumpReader(tester, repository: repository);
    expect(repository.getProgressCalls, 1);

    // Leave the reader (the app's provider scope stays mounted) and return.
    Widget app(Widget home) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );
    await tester.pumpWidget(app(const SizedBox.shrink()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(const ReaderScreen(bookId: 'b1')));
    await tester.pumpAndSettle();

    expect(repository.getProgressCalls, 2);
  });

  testWidgets('the reader toolbar fits a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpReader(
      tester,
      repository: FakeReaderRepository(content: _chaptered()),
    );

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Contents'), findsOneWidget);
  });
}

BookContent _chaptered() {
  final one = List.filled(40, 'The first chapter goes on.').join('\n\n');
  final two = List.filled(40, 'The second one continues.').join('\n\n');
  final three = List.filled(40, 'And the third ends it.').join('\n\n');
  final text = '$one\n\n$two\n\n$three';
  return BookContent(
    bookId: 'b1',
    title: 'Chaptered',
    format: ContentFormat.text,
    characterCount: text.length,
    text: text,
    chapters: [
      const ChapterMark(startOffset: 0, title: 'Beginnings'),
      ChapterMark(startOffset: one.length + 2),
      ChapterMark(startOffset: one.length + two.length + 4, title: 'Endings'),
    ],
  );
}

final _longText = List.filled(
  120,
  'It was a bright cold day in April, and the clocks were striking thirteen.',
).join('\n\n');

/// A repository whose saved progress never arrives until released.
class _SlowProgressRepository extends FakeReaderRepository {
  _SlowProgressRepository({super.content});

  final Completer<void> release = Completer<void>();

  @override
  Future<ReadingProgress?> getProgress(String bookId) async {
    await release.future;
    return const ReadingProgress(
      currentPosition: '5000',
      progressPercentage: 60,
      totalReadingTimeSeconds: 120,
    );
  }
}
