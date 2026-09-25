import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/picked_book.dart';
import '../domain/book.dart';
import '../domain/library_repository.dart';
import 'library_providers.dart';

/// Owns the library list state and the upload/delete actions.
///
/// The initial load and refresh expose loading/error via [AsyncValue];
/// upload and delete rethrow failures so the UI can surface them while the
/// existing list is preserved.
///
/// Uploads return before the server has finished preparing a book, so while
/// any book is still preparing the list is re-fetched quietly every
/// [pollInterval] until it settles.
class LibraryController extends AsyncNotifier<List<Book>> {
  /// How often to check on books that are still being prepared.
  static const pollInterval = Duration(seconds: 2);

  Timer? _poll;

  LibraryRepository get _repository => ref.read(libraryRepositoryProvider);

  @override
  Future<List<Book>> build() async {
    ref.onDispose(() => _poll?.cancel());
    return _settle(await _repository.listBooks());
  }

  /// Re-fetch the library. The RefreshIndicator shows its own spinner, so the
  /// current list stays visible until the new result arrives.
  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      return _settle(await _repository.listBooks());
    });
  }

  /// Upload a picked file, then refresh the list. Rethrows on failure.
  Future<void> uploadBook(
    PickedBook file, {
    void Function(double progress)? onProgress,
  }) async {
    await _repository.uploadBook(file, onProgress: onProgress);
    state = AsyncData(_settle(await _repository.listBooks()));
  }

  /// Delete a book and remove it from the list. Rethrows on failure.
  Future<void> deleteBook(String id) async {
    await _repository.deleteBook(id);
    final current = state.value ?? const [];
    state = AsyncData(
      _settle([
        for (final book in current)
          if (book.id != id) book,
      ]),
    );
  }

  /// Ask the server to prepare a book again, then follow it until it settles.
  Future<void> retryProcessing(String id) async {
    await _repository.retryProcessing(id);
    ref
      ..invalidate(bookProvider(id))
      ..invalidate(bookProcessingProvider(id))
      ..invalidate(bookCoverProvider(id));
    state = AsyncData(_settle(await _repository.listBooks()));
  }

  /// Schedule a quiet re-fetch while any book is still being prepared.
  List<Book> _settle(List<Book> books) {
    _poll?.cancel();
    _poll = books.any((book) => book.status.isPreparing)
        ? Timer(pollInterval, () => unawaited(_pollOnce(books)))
        : null;
    return books;
  }

  Future<void> _pollOnce(List<Book> previous) async {
    try {
      final books = await _repository.listBooks();
      if (!ref.mounted) return;
      // Books whose status moved on need their detail views refreshed too.
      final before = {for (final book in previous) book.id: book.status};
      for (final book in books) {
        if (before[book.id] != book.status) {
          ref
            ..invalidate(bookProvider(book.id))
            ..invalidate(bookProcessingProvider(book.id));
        }
      }
      state = AsyncData(_settle(books));
    } on Object {
      // Keep the list on screen and try again a little later.
      _poll = Timer(pollInterval * 2, () => unawaited(_pollOnce(previous)));
    }
  }
}

/// Exposes the [LibraryController] and the current library list.
final libraryControllerProvider =
    AsyncNotifierProvider<LibraryController, List<Book>>(LibraryController.new);
