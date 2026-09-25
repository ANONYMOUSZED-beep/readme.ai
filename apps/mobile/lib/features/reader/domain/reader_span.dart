import 'package:flutter/foundation.dart';

/// A half-open range `[start, end)` in canonical scalar offsets.
///
/// Canonical offsets count Unicode scalar values and are the only anchor space
/// ReadMe.ai persists: reading progress, bookmarks, and explanation selections
/// all address content this way. A span therefore means the same thing on every
/// device, at every font size, and for every source format.
@immutable
class ReaderSpan {
  const ReaderSpan(this.start, this.end)
    : assert(start >= 0, 'span start cannot be negative'),
      assert(end >= start, 'span end cannot precede its start');

  /// An empty span at [offset], useful as a neutral value.
  const ReaderSpan.empty(int offset) : this(offset, offset);

  final int start;
  final int end;

  int get length => end - start;

  bool get isEmpty => end <= start;

  bool get isNotEmpty => !isEmpty;

  /// Whether [offset] falls inside this span. The end bound is exclusive.
  bool contains(int offset) => offset >= start && offset < end;

  /// Whether this span shares at least one offset with [other].
  bool overlaps(ReaderSpan other) => start < other.end && end > other.start;

  /// The overlapping part of two spans, or `null` when they do not overlap.
  ///
  /// Used to clip an element to the page currently being rendered, so an element
  /// crossing a page boundary contributes its visible part to each page with
  /// correct offsets.
  ReaderSpan? intersect(ReaderSpan other) {
    final clippedStart = start > other.start ? start : other.start;
    final clippedEnd = end < other.end ? end : other.end;
    if (clippedEnd <= clippedStart) return null;
    return ReaderSpan(clippedStart, clippedEnd);
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'ReaderSpan($start, $end)';
}
