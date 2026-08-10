import 'character_anchor.dart';

/// A source of readable content addressed by canonical (Unicode scalar)
/// offsets — the same anchor space the backend, bookmarks, reading progress,
/// and the Explanation Engine already use.
///
/// The paginator and reading window depend only on this abstraction, never on a
/// raw [String]. Today the single implementation wraps in-memory text
/// ([StringPaginationSource]); Sprint 6.2's Document Model can add a structured
/// implementation (e.g. backed by chapters/paragraphs) without touching the
/// paginator, the reading window, or the widget layer.
abstract class PaginationSource {
  /// Total number of canonical scalar units in the document.
  int get length;

  /// The text for the canonical scalar range `[start, end)`.
  ///
  /// Implementations must clamp out-of-range indices and must never return a
  /// broken surrogate pair.
  String scalarSubstring(int start, int end);

  /// The single scalar at canonical offset [index] (empty at the boundary).
  String scalarAt(int index);
}

/// A [PaginationSource] backed by a single in-memory string.
///
/// UTF-16 ⇄ scalar boundary conversion is computed once at construction and
/// reused, so slicing by canonical offset is O(1) afterwards instead of the
/// O(n) rebuild the previous helpers performed on every call.
class StringPaginationSource implements PaginationSource {
  StringPaginationSource(this._text)
    : _boundaries = CharacterAnchor.codeUnitBoundaries(_text);

  final String _text;

  /// Maps a canonical scalar offset to its UTF-16 code-unit index. Always
  /// starts at 0 and ends at `_text.length`; its size is scalarLength + 1.
  final List<int> _boundaries;

  @override
  int get length => _boundaries.length - 1;

  @override
  String scalarSubstring(int start, int end) {
    final safeStart = start.clamp(0, length);
    final safeEnd = end.clamp(safeStart, length);
    return _text.substring(_boundaries[safeStart], _boundaries[safeEnd]);
  }

  @override
  String scalarAt(int index) {
    if (index < 0 || index >= length) return '';
    return _text.substring(_boundaries[index], _boundaries[index + 1]);
  }
}
