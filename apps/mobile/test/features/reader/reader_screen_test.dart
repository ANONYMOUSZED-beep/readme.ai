import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/core/theme/theme_mode_controller.dart';
import 'package:readme_ai/features/reader/application/reader_settings.dart';
import 'package:readme_ai/features/reader/application/reader_settings_controller.dart';
import 'package:readme_ai/features/reader/domain/book_content.dart';
import 'package:readme_ai/features/reader/domain/bookmark.dart';
import 'package:readme_ai/features/reader/domain/chapter_mark.dart';
import 'package:readme_ai/features/reader/domain/content_format.dart';
import 'package:readme_ai/features/reader/domain/reading_progress.dart';
import 'package:readme_ai/features/reader/presentation/reader_screen.dart';
import 'package:readme_ai/features/reader/presentation/widgets/bookmarks_sheet.dart';
import 'package:readme_ai/features/reader/presentation/widgets/page_turn_view.dart';
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

  testWidgets('turning a logical page saves its stable character anchor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final text = List.generate(
      180,
      (index) =>
          'Concept $index builds understanding through careful reading. ',
    ).join();
    final repository = FakeReaderRepository(
      content: FakeReaderRepository.textContent(text: text),
    );

    await pumpReader(tester, repository: repository);

    expect(find.byType(PageTurnView), findsOneWidget);
    expect(find.textContaining('Page 1 of '), findsOneWidget);

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Page 2 of '), findsOneWidget);
    expect(repository.lastSaved, isNotNull);
    expect(int.parse(repository.lastSaved!.currentPosition), greaterThan(0));
  });

  testWidgets('restores a nonzero scalar anchor to its logical page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final text = List.generate(
      240,
      (index) => '😀 Chapter $index preserves the reader position. ',
    ).join();
    final repository = FakeReaderRepository(
      content: FakeReaderRepository.textContent(text: text),
      progress: const ReadingProgress(
        currentPosition: '1800',
        progressPercentage: 20,
        totalReadingTimeSeconds: 0,
      ),
    );

    await pumpReader(tester, repository: repository);

    expect(find.textContaining('Page 1 of '), findsNothing);
    expect(find.textContaining('Page '), findsWidgets);
  });

  testWidgets('typography reflow retains the exact global scalar anchor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final text = List.generate(
      240,
      (index) => '😀 Chapter $index preserves the reader position. ',
    ).join();
    final repository = FakeReaderRepository(
      content: FakeReaderRepository.textContent(text: text),
      progress: const ReadingProgress(
        currentPosition: '1800',
        progressPercentage: 20,
        totalReadingTimeSeconds: 0,
      ),
    );
    await pumpReader(tester, repository: repository);

    await tester.tap(find.byTooltip('Reader settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Increase Font size'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 100));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bookmark this position'));
    await tester.pump();

    expect(repository.lastCreatedBookmarkAnchor, '1800');
  });

  testWidgets('bookmark jump immediately persists the target anchor', (
    tester,
  ) async {
    final text = List.generate(
      240,
      (index) => 'Chapter $index preserves the reader position. ',
    ).join();
    final repository = FakeReaderRepository(
      content: FakeReaderRepository.textContent(text: text),
      bookmarks: [
        Bookmark(
          id: 'bm-jump',
          anchor: '1800',
          createdAt: DateTime(2026),
          label: 'Jump target',
        ),
      ],
    );
    await pumpReader(tester, repository: repository);

    await tester.tap(find.byTooltip('Bookmarks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jump target'));
    await tester.pumpAndSettle();

    expect(repository.lastSaved?.currentPosition, '1800');
  });

  testWidgets('bookmarking a position lists contextual information', (
    tester,
  ) async {
    await pumpReader(tester, repository: FakeReaderRepository());

    await tester.tap(find.byTooltip('Bookmark this position'));
    await tester.pump();
    await tester.tap(find.byTooltip('Bookmarks'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(BookmarksSheet),
        matching: find.textContaining('bright cold day'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('% through'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('bookmark fallback preview uses Unicode scalar anchors', (
    tester,
  ) async {
    const text = '😀😀Target passage starts here.';
    final repository = FakeReaderRepository(
      content: FakeReaderRepository.textContent(text: text),
      bookmarks: [
        Bookmark(id: 'bm-unicode', anchor: '2', createdAt: DateTime(2026)),
      ],
    );
    await pumpReader(tester, repository: repository);

    await tester.tap(find.byTooltip('Bookmarks'));
    await tester.pumpAndSettle();

    expect(find.text('Target passage starts here.'), findsOneWidget);
  });

  testWidgets('created bookmark labels truncate on Unicode scalar boundaries', (
    tester,
  ) async {
    final prefix = List.filled(70, 'a').join();
    final text = '$prefix😀 trailing text';
    final repository = FakeReaderRepository(
      content: FakeReaderRepository.textContent(text: text),
    );
    await pumpReader(tester, repository: repository);

    await tester.tap(find.byTooltip('Bookmark this position'));
    await tester.pump();

    final label = repository.lastCreatedBookmarkLabel!;
    expect(label.runes.length, 72);
    expect(label, '$prefix😀…');
    expect(label.runes, isNot(contains(0xFFFD)));
  });

  testWidgets('Explain is persistently discoverable on phone and desktop', (
    tester,
  ) async {
    for (final size in [const Size(390, 844), const Size(1280, 900)]) {
      await tester.binding.setSurfaceSize(size);
      await pumpReader(tester, repository: FakeReaderRepository());

      expect(find.widgetWithText(FilledButton, 'Explain'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    // Unmount the reader and let its providers' scheduled cleanup run.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('bookmark deletion offers undo and restores the bookmark', (
    tester,
  ) async {
    final repository = FakeReaderRepository(
      bookmarks: [
        Bookmark(
          id: 'bm-1',
          anchor: '12',
          createdAt: DateTime(2026),
          label: 'bright cold day in April',
        ),
      ],
    );
    await pumpReader(tester, repository: repository);

    await tester.tap(find.byTooltip('Bookmarks'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete bookmark'));
    await tester.pumpAndSettle();

    expect(find.text('Bookmark deleted'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('bright cold day in April'), findsOneWidget);
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
    final repository = FakeReaderRepository(content: _chaptered());
    await pumpReader(tester, repository: repository);

    await tester.tap(find.byTooltip('Contents'));
    await tester.pumpAndSettle();

    expect(find.text('Beginnings'), findsOneWidget);
    expect(find.text('Chapter 2'), findsOneWidget);
    await tester.tap(find.text('Endings'));
    await tester.pumpAndSettle();

    expect(find.text('Beginnings'), findsNothing); // sheet closed
    // The jump lands on the chapter's first character and is saved there.
    final endings = _chaptered().chapters.last.startOffset;
    expect(repository.lastSaved?.currentPosition, '$endings');

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
