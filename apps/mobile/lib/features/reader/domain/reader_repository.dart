import 'book_content.dart';
import 'bookmark.dart';
import 'element_window.dart';
import 'reading_progress.dart';
import 'recent_read.dart';

/// Contract for the reading experience: content, position, and bookmarks.
///
/// The presentation/application layers depend on this interface; the Dio-backed
/// implementation lives in the data layer and is injected via Riverpod so a
/// fake can be used in tests.
abstract interface class ReaderRepository {
  /// Fetch the readable content for a book.
  Future<BookContent> getContent(String bookId);

  /// Fetch the document elements covering a canonical offset range.
  ///
  /// A pure read. Implementations decode tolerantly: unknown element types and
  /// individually malformed elements never fail the window, so the Reader can
  /// always render something.
  Future<ElementWindow> getElements(
    String bookId, {
    required int start,
    required int end,
  });

  /// Fetch saved reading progress, or `null` if the book is unstarted.
  Future<ReadingProgress?> getProgress(String bookId);

  /// Persist the current reading position.
  Future<ReadingProgress> saveProgress(
    String bookId, {
    required String currentPosition,
    required double progressPercentage,
    required int readingTimeSeconds,
  });

  /// Books the user has been reading, most recently read first.
  Future<List<RecentRead>> listRecent();

  /// List the book's bookmarks, newest first.
  Future<List<Bookmark>> listBookmarks(String bookId);

  /// Create a bookmark at a stable position anchor.
  Future<Bookmark> createBookmark(
    String bookId, {
    required String anchor,
    String? label,
  });

  /// Delete a bookmark.
  Future<void> deleteBookmark(String bookId, String bookmarkId);
}
