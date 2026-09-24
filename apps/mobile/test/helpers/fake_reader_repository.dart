import 'package:readme_ai/features/reader/domain/book_content.dart';
import 'package:readme_ai/features/reader/domain/bookmark.dart';
import 'package:readme_ai/features/reader/domain/content_format.dart';
import 'package:readme_ai/features/reader/domain/reader_repository.dart';
import 'package:readme_ai/features/reader/domain/reading_progress.dart';
import 'package:readme_ai/features/reader/domain/recent_read.dart';

/// In-memory [ReaderRepository] for widget and unit tests.
class FakeReaderRepository implements ReaderRepository {
  FakeReaderRepository({
    BookContent? content,
    ReadingProgress? progress,
    List<Bookmark>? bookmarks,
    List<RecentRead>? recent,
  }) : _content = content ?? textContent(),
       _progress = progress,
       _bookmarks = [...?bookmarks],
       recent = [...?recent];

  final BookContent _content;
  ReadingProgress? _progress;
  final List<Bookmark> _bookmarks;

  /// The most recently saved progress (for assertions).
  ReadingProgress? lastSaved;

  /// Returned by [listRecent].
  final List<RecentRead> recent;

  int listRecentCalls = 0;

  int getProgressCalls = 0;

  static BookContent textContent({
    String text =
        'It was a bright cold day in April, and the clocks were '
        'striking thirteen. Winston Smith walked through the glass doors.',
  }) => BookContent(
    bookId: 'b1',
    title: 'Nineteen Eighty-Four',
    format: ContentFormat.text,
    characterCount: text.length,
    text: text,
  );

  static BookContent unsupportedContent() => const BookContent(
    bookId: 'b1',
    title: 'Scanned Book',
    format: ContentFormat.unsupported,
    characterCount: 0,
  );

  @override
  Future<BookContent> getContent(String bookId) async => _content;

  @override
  Future<ReadingProgress?> getProgress(String bookId) async {
    getProgressCalls++;
    return _progress;
  }

  @override
  Future<ReadingProgress> saveProgress(
    String bookId, {
    required String currentPosition,
    required double progressPercentage,
    required int readingTimeSeconds,
  }) async {
    final previous = _progress?.totalReadingTimeSeconds ?? 0;
    final progress = ReadingProgress(
      currentPosition: currentPosition,
      progressPercentage: progressPercentage,
      totalReadingTimeSeconds: previous + readingTimeSeconds,
    );
    _progress = progress;
    lastSaved = progress;
    return progress;
  }

  @override
  Future<List<RecentRead>> listRecent() async {
    listRecentCalls++;
    return List.of(recent);
  }

  @override
  Future<List<Bookmark>> listBookmarks(String bookId) async =>
      List.of(_bookmarks);

  @override
  Future<Bookmark> createBookmark(
    String bookId, {
    required String anchor,
    String? label,
  }) async {
    final bookmark = Bookmark(
      id: 'bm-${_bookmarks.length + 1}',
      anchor: anchor,
      createdAt: DateTime(2026),
      label: label,
    );
    _bookmarks.insert(0, bookmark);
    return bookmark;
  }

  @override
  Future<void> deleteBookmark(String bookId, String bookmarkId) async {
    _bookmarks.removeWhere((bookmark) => bookmark.id == bookmarkId);
  }
}
