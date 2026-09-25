import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../data/reader_repository_impl.dart';
import '../domain/book_content.dart';
import '../domain/bookmark.dart';
import '../domain/reader_repository.dart';
import '../domain/reading_progress.dart';
import '../domain/recent_read.dart';

/// Provides the [ReaderRepository]. Overridden in tests with a fake.
final readerRepositoryProvider = Provider<ReaderRepository>((ref) {
  return ReaderRepositoryImpl(ref.watch(dioProvider));
});

/// Loads a book's readable content.
///
/// Auto-disposed so each visit to the reader fetches fresh content (e.g. a
/// book that was re-processed after a failure becomes readable).
final bookContentProvider = FutureProvider.autoDispose
    .family<BookContent, String>((ref, bookId) {
      return ref.watch(readerRepositoryProvider).getContent(bookId);
    });

/// Loads the saved reading position for resume (null if unstarted).
///
/// Auto-disposed: a cached value would resume the *previous* visit's
/// position when a book is reopened in the same session.
final readingProgressProvider = FutureProvider.autoDispose
    .family<ReadingProgress?, String>((ref, bookId) {
      return ref.watch(readerRepositoryProvider).getProgress(bookId);
    });

/// Loads the book's bookmarks; invalidated by the controller on change.
final bookmarksProvider = FutureProvider.family<List<Bookmark>, String>((
  ref,
  bookId,
) {
  return ref.watch(readerRepositoryProvider).listBookmarks(bookId);
});

/// Books the user has been reading, most recent first ("Continue reading").
///
/// Invalidated whenever progress is saved, so returning from the reader
/// shows up-to-date positions.
final recentReadingProvider = FutureProvider<List<RecentRead>>((ref) {
  return ref.watch(readerRepositoryProvider).listRecent();
});

/// Creates the stopwatch that times a reading session (for streaks and goals).
///
/// Tests replace it with one that never advances, so what gets saved can't
/// depend on how long the test itself took to run.
final readingStopwatchProvider = Provider<Stopwatch Function()>(
  (ref) =>
      () => Stopwatch()..start(),
);
