import '../../../core/files/picked_book.dart';
import 'book.dart';
import 'book_processing.dart';

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
  ///
  /// The book comes back while its content is still being prepared
  /// ([Book.status] is processing). [onProgress] reports the fraction of the
  /// file sent, from 0 to 1.
  Future<Book> uploadBook(
    PickedBook file, {
    void Function(double progress)? onProgress,
  });

  /// Fetch how the book's content was prepared, or `null` if it never was.
  Future<BookProcessing?> getProcessing(String id);

  /// Prepare the book's content again (e.g. after a transient failure).
  Future<void> retryProcessing(String id);

  /// Delete a book by id.
  Future<void> deleteBook(String id);
}
