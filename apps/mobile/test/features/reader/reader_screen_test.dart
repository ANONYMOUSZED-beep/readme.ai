import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/core/theme/theme_mode_controller.dart';
import 'package:readme_ai/features/reader/application/reader_settings_controller.dart';
import 'package:readme_ai/features/reader/domain/reading_progress.dart';

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

  testWidgets('reader settings toggle dark mode', (tester) async {
    final container = await pumpReader(
      tester,
      repository: FakeReaderRepository(),
    );

    await tester.tap(find.byTooltip('Reader settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.dark);
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
