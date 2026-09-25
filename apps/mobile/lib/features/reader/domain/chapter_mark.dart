import 'package:freezed_annotation/freezed_annotation.dart';

part 'chapter_mark.freezed.dart';

/// Where a chapter starts in a book's readable text (a contents entry).
@freezed
abstract class ChapterMark with _$ChapterMark {
  const factory ChapterMark({
    /// Character offset into the book's text.
    required int startOffset,

    /// The chapter's title, when the book provides one.
    String? title,
  }) = _ChapterMark;
}
