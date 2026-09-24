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
class LibraryController extends AsyncNotifier<List<Book>> {
  LibraryRepository get _repository => ref.read(libraryRepositoryProvider);

  @override
  Future<List<Book>> build() => _repository.listBooks();

  /// Re-fetch the library. The RefreshIndicator shows its own spinner, so the
  /// current list stays visible until the new result arrives.
  Future<void> refresh() async {
    state = await AsyncValue.guard(_repository.listBooks);
  }

  /// Upload a picked file, then refresh the list. Rethrows on failure.
  Future<void> uploadBook(PickedBook file) async {
    await _repository.uploadBook(file);
    state = AsyncData(await _repository.listBooks());
  }

  /// Re-run processing for a book, then refresh everything that shows its
  /// status. Rethrows on failure.
  Future<void> reprocessBook(String id) async {
    await _repository.reprocessBook(id);
    ref
      ..invalidate(bookProvider(id))
      ..invalidate(processingReportProvider(id));
    state = AsyncData(await _repository.listBooks());
  }

  /// Delete a book and remove it from the list. Rethrows on failure.
  Future<void> deleteBook(String id) async {
    await _repository.deleteBook(id);
    final current = state.value ?? const [];
    state = AsyncData([
      for (final book in current)
        if (book.id != id) book,
    ]);
  }
}

/// Exposes the [LibraryController] and the current library list.
final libraryControllerProvider =
    AsyncNotifierProvider<LibraryController, List<Book>>(LibraryController.new);
