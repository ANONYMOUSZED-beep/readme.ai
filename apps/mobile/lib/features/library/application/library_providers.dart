import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../data/library_repository_impl.dart';
import '../domain/book.dart';
import '../domain/book_processing.dart';
import '../domain/library_repository.dart';

/// Provides the [LibraryRepository]. Overridden in tests with a fake.
final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepositoryImpl(ref.watch(dioProvider));
});

/// Fetches a single book by id (used by the detail screen).
final bookProvider = FutureProvider.family<Book, String>((ref, id) {
  return ref.watch(libraryRepositoryProvider).getBook(id);
});

/// How a book's content was prepared: size, reading time, or failure reason.
final bookProcessingProvider = FutureProvider.family<BookProcessing?, String>((
  ref,
  id,
) {
  return ref.watch(libraryRepositoryProvider).getProcessing(id);
});
