import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../data/library_repository_impl.dart';
import '../domain/book.dart';
import '../domain/library_repository.dart';
import '../domain/processing_report.dart';

/// Provides the [LibraryRepository]. Overridden in tests with a fake.
final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepositoryImpl(ref.watch(dioProvider));
});

/// Fetches a single book by id (used by the detail screen).
final bookProvider = FutureProvider.family<Book, String>((ref, id) {
  return ref.watch(libraryRepositoryProvider).getBook(id);
});

/// The latest processing outcome for a book (used to explain failures).
final processingReportProvider = FutureProvider.autoDispose
    .family<ProcessingReport?, String>((ref, id) {
      return ref.watch(libraryRepositoryProvider).getProcessingReport(id);
    });
