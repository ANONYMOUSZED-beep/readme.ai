import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/reader_repository.dart';
import 'reader_providers.dart';

/// Orchestrates reader mutations (save position, bookmark add/delete) and keeps
/// the relevant providers fresh.
///
/// Reads are served by the `FutureProvider`s in `reader_providers.dart`; this
/// controller owns the side-effecting actions so widgets stay declarative.
class ReaderController {
  ReaderController(this._ref);

  final Ref _ref;

  ReaderRepository get _repository => _ref.read(readerRepositoryProvider);

  /// Persist the current reading position for [bookId], then refresh the
  /// cached progress so the library and book detail show the new position.
  Future<void> saveProgress(
    String bookId, {
    required String currentPosition,
    required double progressPercentage,
    required int readingTimeSeconds,
  }) async {
    await _repository.saveProgress(
      bookId,
      currentPosition: currentPosition,
      progressPercentage: progressPercentage,
      readingTimeSeconds: readingTimeSeconds,
    );
    _ref.invalidate(readingProgressProvider(bookId));
  }

  /// Create a bookmark and refresh the bookmark list.
  Future<void> addBookmark(
    String bookId, {
    required String anchor,
    String? label,
  }) async {
    await _repository.createBookmark(bookId, anchor: anchor, label: label);
    _ref.invalidate(bookmarksProvider(bookId));
  }

  /// Delete a bookmark and refresh the bookmark list.
  Future<void> deleteBookmark(String bookId, String bookmarkId) async {
    await _repository.deleteBookmark(bookId, bookmarkId);
    _ref.invalidate(bookmarksProvider(bookId));
  }
}

/// Exposes the [ReaderController].
final readerControllerProvider = Provider<ReaderController>(
  ReaderController.new,
);
