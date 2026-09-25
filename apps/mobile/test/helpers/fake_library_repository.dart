import 'dart:async';
import 'dart:typed_data';

import 'package:readme_ai/core/files/picked_book.dart';
import 'package:readme_ai/features/library/domain/book.dart';
import 'package:readme_ai/features/library/domain/book_processing.dart';
import 'package:readme_ai/features/library/domain/book_status.dart';
import 'package:readme_ai/features/library/domain/library_repository.dart';

/// In-memory [LibraryRepository] for widget and unit tests.
class FakeLibraryRepository implements LibraryRepository {
  FakeLibraryRepository({List<Book>? initial}) : _books = [...?initial];

  final List<Book> _books;

  /// When set, [listBooks] throws this.
  Object? listError;

  /// When set, [uploadBook] throws this.
  Object? uploadError;

  /// When set, [listBooks] awaits this before returning (to test loading).
  Completer<void>? releaseList;

  /// When set, [uploadBook] reports half progress, then awaits this.
  Completer<void>? releaseUpload;

  /// Status given to uploaded books (the real server answers "processing").
  BookStatus uploadStatus = BookStatus.uploaded;

  /// When set, books still processing become ready once [listBooks] has been
  /// called this many times — simulating the server finishing in between.
  int? readyAfterListCalls;

  /// Returned by [getProcessing], keyed by book id.
  final Map<String, BookProcessing> processing = {};

  final List<String> retried = [];

  /// Cover images returned by [getCover], by book id.
  final Map<String, Uint8List> covers = {};

  int listCalls = 0;

  @override
  Future<List<Book>> listBooks() async {
    listCalls++;
    if (releaseList != null) {
      await releaseList!.future;
    }
    if (listError != null) {
      throw listError!;
    }
    final readyAfter = readyAfterListCalls;
    if (readyAfter != null && listCalls > readyAfter) {
      for (var i = 0; i < _books.length; i++) {
        if (_books[i].status.isPreparing) {
          _books[i] = _books[i].copyWith(status: BookStatus.ready);
        }
      }
    }
    return List.of(_books);
  }

  @override
  Future<Book> getBook(String id) async =>
      _books.firstWhere((book) => book.id == id);

  @override
  Future<Book> uploadBook(
    PickedBook file, {
    void Function(double progress)? onProgress,
  }) async {
    if (uploadError != null) {
      throw uploadError!;
    }
    if (releaseUpload != null) {
      onProgress?.call(0.5);
      await releaseUpload!.future;
    }
    onProgress?.call(1);
    final book = Book(
      id: 'id-${_books.length + 1}',
      title: file.filename,
      originalFilename: file.filename,
      mimeType: file.mimeType ?? 'application/pdf',
      fileSize: file.size,
      status: uploadStatus,
      uploadedAt: DateTime(2026),
    );
    _books.insert(0, book);
    return book;
  }

  @override
  Future<BookProcessing?> getProcessing(String id) async => processing[id];

  @override
  Future<void> retryProcessing(String id) async {
    retried.add(id);
    final index = _books.indexWhere((book) => book.id == id);
    _books[index] = _books[index].copyWith(status: BookStatus.ready);
  }

  @override
  Future<void> deleteBook(String id) async {
    _books.removeWhere((book) => book.id == id);
  }

  @override
  Future<Uint8List?> getCover(String id) async => covers[id];
}
