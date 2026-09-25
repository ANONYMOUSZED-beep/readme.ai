import 'package:freezed_annotation/freezed_annotation.dart';

import 'book_status.dart';

part 'book.freezed.dart';

/// A book in the user's library (domain representation).
@freezed
abstract class Book with _$Book {
  const factory Book({
    required String id,
    required String title,
    required String originalFilename,
    required String mimeType,
    required int fileSize,
    required BookStatus status,
    required DateTime uploadedAt,
    int? totalPages,
    String? coverImageUrl,

    /// Whether the server has a cover picture for this book (EPUB covers).
    @Default(false) bool hasCover,
  }) = _Book;
}
