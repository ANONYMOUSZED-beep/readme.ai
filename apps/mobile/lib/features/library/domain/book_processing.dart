import 'package:freezed_annotation/freezed_annotation.dart';

part 'book_processing.freezed.dart';

/// Why preparing a book's content failed, mirroring the backend codes.
enum ProcessingError {
  unsupportedFormat,
  malformedFile,
  emptyDocument,
  tooLarge,
  timeout,
  internal;

  /// Parse the backend's error code, defaulting to [internal].
  static ProcessingError fromApi(String value) => switch (value) {
    'unsupported_format' => ProcessingError.unsupportedFormat,
    'malformed_file' => ProcessingError.malformedFile,
    'empty_document' => ProcessingError.emptyDocument,
    'too_large' => ProcessingError.tooLarge,
    'timeout' => ProcessingError.timeout,
    _ => ProcessingError.internal,
  };

  /// Whether trying again could succeed (the file itself isn't the problem).
  bool get isRetryable =>
      this == ProcessingError.timeout || this == ProcessingError.internal;
}

/// How a book's content was prepared for reading.
@freezed
abstract class BookProcessing with _$BookProcessing {
  const factory BookProcessing({
    required int wordCount,
    int? estimatedReadingMinutes,
    ProcessingError? error,
  }) = _BookProcessing;
}
