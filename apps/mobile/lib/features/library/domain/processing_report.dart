import 'package:freezed_annotation/freezed_annotation.dart';

part 'processing_report.freezed.dart';

/// The outcome of preparing a book for reading (server-side processing).
@freezed
abstract class ProcessingReport with _$ProcessingReport {
  const factory ProcessingReport({
    /// Whether the book was turned into readable text.
    required bool completed,

    /// Why processing failed, in words suitable for the reader.
    String? errorMessage,
  }) = _ProcessingReport;
}
