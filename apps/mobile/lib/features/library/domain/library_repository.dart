import 'dart:typed_data';

import '../../../core/files/picked_book.dart';
import 'book.dart';
import 'processing_report.dart';

/// Contract for the user's book library.
///
/// The presentation/application layers depend on this interface; the Dio-backed
/// implementation lives in the data layer and is injected via Riverpod so a
/// fake can be used in tests.
abstract interface class LibraryRepository {
  /// Fetch all books belonging to the current user, newest first.
  Future<List<Book>> listBooks();

  /// Fetch a single book by id.
  Future<Book> getBook(String id);

  /// Upload a picked file and return the created book.
  Future<Book> uploadBook(PickedBook file);

  /// Delete a book by id.
  Future<void> deleteBook(String id);

  /// The latest processing outcome for a book, or `null` if it was never
  /// processed.
  Future<ProcessingReport?> getProcessingReport(String id);

  /// The book's cover image bytes, or `null` if it has none.
  Future<Uint8List?> getCover(String id);

  /// Re-run processing for a book (e.g. after a failure).
  Future<ProcessingReport> reprocessBook(String id);
}
