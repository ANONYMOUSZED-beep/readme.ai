/// Converts between canonical document anchors and Dart string offsets.
///
/// ReadMe.ai anchors count Unicode scalar values, matching Python's `len(str)`
/// and remaining stable across clients. Flutter text selection and `substring`
/// use UTF-16 code-unit offsets, so conversion happens only at presentation
/// boundaries.
abstract final class CharacterAnchor {
  /// Number of canonical anchor units in [text].
  static int length(String text) => text.runes.length;

  /// UTF-16 boundaries for every Unicode scalar in [text].
  ///
  /// The result always starts with 0 and ends with `text.length`.
  static List<int> codeUnitBoundaries(String text) {
    final boundaries = <int>[0];
    var codeUnits = 0;
    for (final scalar in text.runes) {
      codeUnits += scalar > 0xFFFF ? 2 : 1;
      boundaries.add(codeUnits);
    }
    return boundaries;
  }

  /// Converts a canonical scalar offset to a UTF-16 code-unit offset.
  static int toCodeUnit(String text, int scalarOffset) {
    final boundaries = codeUnitBoundaries(text);
    return boundaries[scalarOffset.clamp(0, boundaries.length - 1)];
  }

  /// Converts a UTF-16 offset to the canonical scalar offset.
  ///
  /// If [codeUnitOffset] falls inside a surrogate pair, it resolves to the
  /// scalar's leading boundary rather than creating an invalid anchor.
  static int fromCodeUnit(String text, int codeUnitOffset) {
    final safeOffset = codeUnitOffset.clamp(0, text.length);
    final boundaries = codeUnitBoundaries(text);
    var low = 0;
    var high = boundaries.length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (boundaries[middle] <= safeOffset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  /// Extracts a range expressed in canonical scalar offsets.
  static String substring(String text, int start, [int? end]) {
    final boundaries = codeUnitBoundaries(text);
    final safeStart = start.clamp(0, boundaries.length - 1);
    final safeEnd = (end ?? boundaries.length - 1).clamp(
      safeStart,
      boundaries.length - 1,
    );
    return text.substring(boundaries[safeStart], boundaries[safeEnd]);
  }
}
