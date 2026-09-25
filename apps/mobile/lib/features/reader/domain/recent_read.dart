import 'package:freezed_annotation/freezed_annotation.dart';

part 'recent_read.freezed.dart';

/// A book the user has been reading, for the "Continue reading" shelf.
@freezed
abstract class RecentRead with _$RecentRead {
  const factory RecentRead({
    required String bookId,
    required double progressPercentage,
    required DateTime lastReadAt,
  }) = _RecentRead;

  const RecentRead._();

  /// Whether the book has effectively been finished.
  bool get isFinished => progressPercentage >= 99.5;
}
